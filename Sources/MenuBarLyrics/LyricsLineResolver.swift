import Foundation

// Resolves one short menu-bar line from either timed LRC lyrics or plain lyric text.
// 从带时间戳的 LRC 歌词或普通歌词文本中解析出一行适合菜单栏显示的歌词。
final class LyricsLineResolver: @unchecked Sendable {
    // The parsed result is tied to both the track identity and the raw lyric payload.
    // 解析缓存同时依赖歌曲身份和原始歌词内容，避免同名字段变化时复用旧结果。
    private struct CacheKey: Equatable {
        let trackID: String
        let lyrics: String
    }

    // A lyric line with its playback timestamp in seconds.
    // 一条带播放时间点的歌词，时间单位为秒。
    private struct TimedLine {
        let time: Double
        let text: String
    }

    // Keeps both display fallbacks and parsed timed lines so callers can prefer precise timing.
    // 同时保留兜底显示行和已解析的时间戳行，调用方可以优先使用精确时间。
    private struct ParsedLyrics {
        let fallbackLines: [String]
        let timedLines: [TimedLine]
    }

    private var cachedKey: CacheKey?
    private var cachedLyrics: ParsedLyrics?

    // Prefer LRC timestamps when present; otherwise approximate the line by track progress.
    // 优先使用 LRC 时间戳；没有时间戳时按歌曲播放进度粗略选择歌词行。
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

        // Clamp to just below 1.0 so end-of-track progress still maps to the last valid index.
        // 将进度限制在略小于 1.0，确保歌曲结束附近仍映射到最后一条有效歌词。
        let progress = min(max(nowPlaying.playerPosition / nowPlaying.duration, 0), 0.999)
        let index = Int(progress * Double(cleanLines.count))
        return cleanLines[min(index, cleanLines.count - 1)]
    }

    // Cache parsing because Music.app is polled every second and lyrics rarely change mid-track.
    // 缓存解析结果，因为应用每秒轮询 Music.app，而同一首歌的歌词通常不会中途变化。
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

    // Walk the sorted timed lines and keep the latest line at or before the current position.
    // 遍历已排序的时间戳歌词，保留当前播放时间之前或正好命中的最后一行。
    private func line(at playerPosition: Double, from lines: [TimedLine]) -> String {
        let position = max(playerPosition, 0)
        var selected = lines[0]

        for line in lines where line.time <= position {
            selected = line
        }

        return selected.text
    }

    // Normalize the source once, then derive both timed and untimed views from the same lines.
    // 先统一清理原始文本，再从同一组行里派生时间戳歌词和普通歌词视图。
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

    // Supports repeated LRC timestamps on one line, such as "[00:05][00:30]Chorus".
    // 支持同一行出现多个 LRC 时间戳，例如 “[00:05][00:30]副歌”。
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

    // Accepts mm:ss, mm:ss.S, mm:ss.SS, and similar Double-compatible second precision.
    // 支持 mm:ss、mm:ss.S、mm:ss.SS 以及 Swift Double 可解析的秒数精度。
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

    // LRC offset is stored in milliseconds and shifts every parsed timestamp.
    // LRC offset 的单位是毫秒，会整体平移所有已解析的时间戳。
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

    // Metadata-only LRC tags should not appear as fallback lyrics.
    // 纯元数据 LRC 标签不应作为普通歌词兜底显示。
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

    // Reads a single bracketed LRC tag value when the key matches the requested metadata name.
    // 当方括号内的 LRC 标签键名匹配时，读取该元数据标签的值。
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

    // Only known LRC metadata keys are treated as metadata; unknown tags stay available as text.
    // 只有已知 LRC 元数据键会被当作元数据；未知标签仍保留为可显示文本。
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
