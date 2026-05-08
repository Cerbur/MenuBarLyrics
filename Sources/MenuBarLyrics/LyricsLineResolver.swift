import Foundation

final class LyricsLineResolver: @unchecked Sendable {
    private struct CacheKey: Equatable {
        let trackID: String
        let lyrics: String
    }

    private struct TimedLine {
        let time: Double
        let text: String
    }

    private struct ParsedLyrics {
        let fallbackLines: [String]
        let timedLines: [TimedLine]
    }

    private var cachedKey: CacheKey?
    private var cachedLyrics: ParsedLyrics?

    func displayLine(for nowPlaying: NowPlaying) -> String {
        let parsedLyrics = parsedLyrics(for: nowPlaying)
        let cleanLines = parsedLyrics.fallbackLines

        if cleanLines.isEmpty {
            return "\(nowPlaying.title) - \(nowPlaying.artist)\nMusic 元数据中没有歌词。"
        }

        let timedLines = parsedLyrics.timedLines
        if !timedLines.isEmpty {
            return line(at: nowPlaying.playerPosition, from: timedLines)
        }

        guard nowPlaying.duration > 0 else {
            return cleanLines.first ?? "\(nowPlaying.title) - \(nowPlaying.artist)"
        }

        let progress = min(max(nowPlaying.playerPosition / nowPlaying.duration, 0), 0.999)
        let index = Int(progress * Double(cleanLines.count))
        return cleanLines[min(index, cleanLines.count - 1)]
    }

    private func parsedLyrics(for nowPlaying: NowPlaying) -> ParsedLyrics {
        let key = CacheKey(trackID: nowPlaying.trackID, lyrics: nowPlaying.lyrics)
        if cachedKey == key, let cachedLyrics {
            return cachedLyrics
        }

        let parsedLyrics = parseLyrics(nowPlaying.lyrics)
        cachedKey = key
        cachedLyrics = parsedLyrics
        return parsedLyrics
    }

    private func line(at playerPosition: Double, from lines: [TimedLine]) -> String {
        let position = max(playerPosition, 0)
        var selected = lines[0]

        for line in lines where line.time <= position {
            selected = line
        }

        return selected.text
    }

    private func parseLyrics(_ lyrics: String) -> ParsedLyrics {
        let cleanLines = lyrics
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let offset = parseOffset(from: cleanLines)
        let timedLines = cleanLines
            .flatMap { parseTimedLine($0, offset: offset) }
            .sorted { $0.time < $1.time }

        let fallbackLines = cleanLines.filter { !isMetadataLine($0) }
        return ParsedLyrics(fallbackLines: fallbackLines, timedLines: timedLines)
    }

    private func parseTimedLine(_ line: String, offset: Double) -> [TimedLine] {
        var remaining = line[...]
        var timestamps: [Double] = []

        while remaining.first == "[", let end = remaining.firstIndex(of: "]") {
            let token = String(remaining[remaining.index(after: remaining.startIndex)..<end])
            guard let timestamp = parseTimestamp(token) else {
                break
            }

            timestamps.append(timestamp)
            remaining = remaining[remaining.index(after: end)...]
        }

        let text = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !timestamps.isEmpty, !text.isEmpty else {
            return []
        }

        return timestamps.map { TimedLine(time: $0 + offset, text: text) }
    }

    private func parseTimestamp(_ token: String) -> Double? {
        let parts = token.split(separator: ":", maxSplits: 1)
        guard parts.count == 2,
              let minutes = Int(parts[0]),
              minutes >= 0,
              let seconds = Double(parts[1]),
              seconds >= 0,
              seconds < 60
        else {
            return nil
        }

        return Double(minutes * 60) + seconds
    }

    private func parseOffset(from lines: [String]) -> Double {
        for line in lines {
            guard let value = lrcTagValue(named: "offset", in: line),
                  let milliseconds = Double(value) else {
                continue
            }

            return milliseconds / 1_000
        }

        return 0
    }

    private func isMetadataLine(_ line: String) -> Bool {
        guard line.first == "[", line.last == "]" else {
            return false
        }

        let token = String(line.dropFirst().dropLast())
        guard lrcMetadataKey(from: token) != nil else {
            return false
        }

        return parseTimestamp(token) == nil
    }

    private func lrcTagValue(named expectedKey: String, in line: String) -> String? {
        guard line.first == "[", let end = line.firstIndex(of: "]") else {
            return nil
        }

        let token = String(line[line.index(after: line.startIndex)..<end])
        guard let key = lrcMetadataKey(from: token),
              key == expectedKey
        else {
            return nil
        }

        return token.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            .dropFirst()
            .first
            .map(String.init)
    }

    private func lrcMetadataKey(from token: String) -> String? {
        let parts = token.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              let key = parts.first?.lowercased(),
              ["al", "ar", "au", "by", "length", "offset", "re", "ti", "tool", "ve"].contains(key)
        else {
            return nil
        }

        return key
    }
}
