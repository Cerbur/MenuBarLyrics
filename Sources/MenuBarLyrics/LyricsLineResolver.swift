import Foundation

struct LyricsLineResolver {
    private struct TimedLine {
        let time: Double
        let text: String
    }

    func displayLine(for nowPlaying: NowPlaying) -> String {
        let cleanLines = nowPlaying.lyrics
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if cleanLines.isEmpty {
            return "\(nowPlaying.title) - \(nowPlaying.artist)\nNo lyrics found in Music library metadata."
        }

        let timedLines = parseTimedLines(from: cleanLines)
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

    private func line(at playerPosition: Double, from lines: [TimedLine]) -> String {
        let position = max(playerPosition, 0)
        var selected = lines[0]

        for line in lines where line.time <= position {
            selected = line
        }

        return selected.text
    }

    private func parseTimedLines(from lines: [String]) -> [TimedLine] {
        lines.flatMap(parseTimedLine)
            .sorted { $0.time < $1.time }
    }

    private func parseTimedLine(_ line: String) -> [TimedLine] {
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

        return timestamps.map { TimedLine(time: $0, text: text) }
    }

    private func parseTimestamp(_ token: String) -> Double? {
        let parts = token.split(separator: ":", maxSplits: 1)
        guard parts.count == 2,
              let minutes = Double(parts[0]),
              let seconds = Double(parts[1]),
              seconds >= 0,
              seconds < 60
        else {
            return nil
        }

        return minutes * 60 + seconds
    }
}
