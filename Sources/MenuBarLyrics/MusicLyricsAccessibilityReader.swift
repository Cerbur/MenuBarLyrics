import ApplicationServices
import AppKit
import Foundation

enum MusicLyricsAccessibilityError: LocalizedError, Sendable {
    case permissionRequired
    case musicNotRunning
    case lyricsPanelUnavailable

    var errorDescription: String? {
        switch self {
        case .permissionRequired:
            return "Enable Accessibility permission for MenuBarLyrics."
        case .musicNotRunning:
            return "Music.app is not running."
        case .lyricsPanelUnavailable:
            return "Open the Lyrics panel in Music.app."
        }
    }
}

final class MusicLyricsAccessibilityReader: @unchecked Sendable {
    private struct TextCandidate {
        let text: String
        let frame: CGRect?
        let isSelected: Bool
        let isFocused: Bool
    }

    private let maximumTraversalDepth = 12
    private let maximumTraversalNodes = 1_500
    private let accessibilityMessagingTimeout: Float = 0.2

    var isPermissionGranted: Bool {
        AXIsProcessTrusted()
    }

    func requestPermissionIfNeeded() {
        guard !isPermissionGranted else {
            return
        }

        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func readCurrentVisibleLyricLine(for nowPlaying: NowPlaying) -> Result<String, MusicLyricsAccessibilityError> {
        guard AXIsProcessTrusted() else {
            return .failure(.permissionRequired)
        }

        guard let musicApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").first else {
            return .failure(.musicNotRunning)
        }

        let appElement = AXUIElementCreateApplication(musicApp.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, accessibilityMessagingTimeout)
        let roots = windows(in: appElement)
        var candidates: [TextCandidate] = []
        var visitedElements = Set<CFHashCode>()
        var remainingNodeBudget = maximumTraversalNodes

        for root in roots {
            candidates.append(
                contentsOf: collectTextCandidates(
                    from: root,
                    depth: 0,
                    inheritedSelection: false,
                    inheritedFocus: false,
                    visitedElements: &visitedElements,
                    remainingNodeBudget: &remainingNodeBudget
                )
            )
        }

        guard let selectedLine = selectBestCandidate(from: candidates, for: nowPlaying) else {
            return .failure(.lyricsPanelUnavailable)
        }

        return .success(selectedLine)
    }

    private func windows(in appElement: AXUIElement) -> [AXUIElement] {
        if let windows = elementArrayAttribute(kAXWindowsAttribute, from: appElement), !windows.isEmpty {
            return windows
        }

        return [appElement]
    }

    private func collectTextCandidates(
        from element: AXUIElement,
        depth: Int,
        inheritedSelection: Bool,
        inheritedFocus: Bool,
        visitedElements: inout Set<CFHashCode>,
        remainingNodeBudget: inout Int
    ) -> [TextCandidate] {
        guard depth < maximumTraversalDepth, remainingNodeBudget > 0 else {
            return []
        }

        let elementID = CFHash(element)
        guard visitedElements.insert(elementID).inserted else {
            return []
        }

        remainingNodeBudget -= 1
        AXUIElementSetMessagingTimeout(element, accessibilityMessagingTimeout)

        var candidates: [TextCandidate] = []
        let role = stringAttribute(kAXRoleAttribute, from: element) ?? ""
        let isSelected = inheritedSelection || (boolAttribute(kAXSelectedAttribute, from: element) ?? false)
        let isFocused = inheritedFocus || (boolAttribute(kAXFocusedAttribute, from: element) ?? false)
        let text = bestTextValue(from: element, role: role)

        if let text, isPotentialLyricText(text) {
            candidates.append(
                TextCandidate(
                    text: text,
                    frame: frame(of: element),
                    isSelected: isSelected,
                    isFocused: isFocused
                )
            )
        }

        let children = uniqueElements(
            (elementArrayAttribute(kAXVisibleChildrenAttribute, from: element) ?? [])
                + (elementArrayAttribute(kAXChildrenAttribute, from: element) ?? [])
        )

        for child in children {
            candidates.append(
                contentsOf: collectTextCandidates(
                    from: child,
                    depth: depth + 1,
                    inheritedSelection: isSelected,
                    inheritedFocus: isFocused,
                    visitedElements: &visitedElements,
                    remainingNodeBudget: &remainingNodeBudget
                )
            )
        }

        return candidates
    }

    private func bestTextValue(from element: AXUIElement, role: String) -> String? {
        let textRoles = [
            kAXStaticTextRole,
            kAXTextAreaRole,
            kAXTextFieldRole,
            kAXButtonRole,
            kAXGroupRole
        ].map { $0 as String }

        guard textRoles.contains(role) else {
            return nil
        }

        return stringAttribute(kAXValueAttribute, from: element)
            ?? stringAttribute(kAXTitleAttribute, from: element)
            ?? stringAttribute(kAXDescriptionAttribute, from: element)
    }

    private func selectBestCandidate(from candidates: [TextCandidate], for nowPlaying: NowPlaying) -> String? {
        let uniqueCandidates = unique(candidates)
            .filter { !isTrackMetadata($0.text, nowPlaying: nowPlaying) }

        if let selected = uniqueCandidates
            .filter({ $0.isSelected || $0.isFocused })
            .max(by: { candidateScore($0) < candidateScore($1) }) {
            return selected.text
        }

        let framedCandidates = uniqueCandidates.filter { $0.frame != nil }
        guard !framedCandidates.isEmpty else {
            return uniqueCandidates.first?.text
        }

        let maxX = framedCandidates.compactMap(\.frame?.maxX).max() ?? 0
        let minY = framedCandidates.compactMap(\.frame?.minY).min() ?? 0
        let maxY = framedCandidates.compactMap(\.frame?.maxY).max() ?? 0
        let verticalCenter = (minY + maxY) / 2

        return framedCandidates
            .filter { candidate in
                guard let frame = candidate.frame else {
                    return false
                }

                return frame.midX >= maxX * 0.65
            }
            .max { lhs, rhs in
                candidateScore(lhs, verticalCenter: verticalCenter) < candidateScore(rhs, verticalCenter: verticalCenter)
            }?
            .text
            ?? framedCandidates.first?.text
    }

    private func candidateScore(_ candidate: TextCandidate, verticalCenter: CGFloat? = nil) -> Double {
        var score = 0.0

        if candidate.isSelected {
            score += 1_000
        }

        if candidate.isFocused {
            score += 100
        }

        if let frame = candidate.frame {
            score += min(Double(frame.minX), 3_000) / 10
            score += min(Double(frame.width), 400) / 40

            if let verticalCenter {
                score -= abs(Double(frame.midY - verticalCenter)) / 100
            }
        }

        return score
    }

    private func unique(_ candidates: [TextCandidate]) -> [TextCandidate] {
        var seen = Set<String>()
        var result: [TextCandidate] = []

        for candidate in candidates {
            guard !seen.contains(candidate.text) else {
                continue
            }

            seen.insert(candidate.text)
            result.append(candidate)
        }

        return result
    }

    private func uniqueElements(_ elements: [AXUIElement]) -> [AXUIElement] {
        var seen = Set<CFHashCode>()
        var result: [AXUIElement] = []

        for element in elements {
            guard seen.insert(CFHash(element)).inserted else {
                continue
            }

            result.append(element)
        }

        return result
    }

    private func isPotentialLyricText(_ text: String) -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedText.count >= 2, trimmedText.count <= 180 else {
            return false
        }

        let ignoredValues = [
            "Music",
            "Lyrics",
            "歌词",
            "翻译",
            "Playing Next",
            "待播清单",
            "Listen Now",
            "Browse",
            "Radio",
            "Library",
            "Recently Added",
            "Artists",
            "Albums",
            "Songs",
            "歌曲排行",
            "Made for You"
        ]

        return !ignoredValues.contains(trimmedText)
    }

    private func isTrackMetadata(_ text: String, nowPlaying: NowPlaying) -> Bool {
        let normalizedText = normalized(text)
        let metadata = [
            nowPlaying.title,
            nowPlaying.artist,
            nowPlaying.album
        ].map(normalized)

        return metadata.contains(normalizedText)
    }

    private func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private func stringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }

        return (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func boolAttribute(_ attribute: String, from element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }

        return value as? Bool
    }

    private func elementArrayAttribute(_ attribute: String, from element: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }

        return value as? [AXUIElement]
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        guard let position = pointAttribute(kAXPositionAttribute, from: element),
              let size = sizeAttribute(kAXSizeAttribute, from: element)
        else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }

    private func pointAttribute(_ attribute: String, from element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID()
        else {
            return nil
        }

        let axValue = value as! AXValue
        guard
              AXValueGetType(axValue) == .cgPoint
        else {
            return nil
        }

        var point = CGPoint.zero
        AXValueGetValue(axValue, .cgPoint, &point)
        return point
    }

    private func sizeAttribute(_ attribute: String, from element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID()
        else {
            return nil
        }

        let axValue = value as! AXValue
        guard
              AXValueGetType(axValue) == .cgSize
        else {
            return nil
        }

        var size = CGSize.zero
        AXValueGetValue(axValue, .cgSize, &size)
        return size
    }
}
