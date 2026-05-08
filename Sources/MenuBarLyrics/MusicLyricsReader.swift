import Foundation

// Snapshot of the Music.app track fields needed to resolve and display a lyric line.
// Music.app 当前歌曲信息快照，包含解析和显示歌词所需的字段。
struct NowPlaying: Sendable {
    let trackID: String
    let title: String
    let artist: String
    let album: String
    let lyrics: String
    let playerPosition: Double
    let duration: Double

    // Convenience resolver for callers that already have a complete NowPlaying value.
    // 便捷解析入口，供已经拿到完整 NowPlaying 值的调用方直接使用。
    var displayLine: String {
        LyricsLineResolver().displayLine(for: self)
    }
}

// User-facing failures from the AppleScript bridge.
// AppleScript 桥接层产生的用户可读错误。
enum MusicLyricsError: LocalizedError, Sendable {
    case musicNotRunning
    case notPlaying
    case missingResult
    case scriptFailure(String)

    var errorDescription: String? {
        switch self {
        case .musicNotRunning:
            return "Music.app 未运行。"
        case .notPlaying:
            return "Music.app 未在播放。"
        case .missingResult:
            return "无法读取 Music.app 当前歌曲。"
        case .scriptFailure(let message):
            return message
        }
    }
}

// Reads Music.app state through AppleScript, keeping all scripting details behind one boundary.
// 通过 AppleScript 读取 Music.app 状态，并把脚本细节隔离在单一边界内。
final class MusicLyricsReader: @unchecked Sendable {
    // Unit Separator is unlikely to appear in normal lyrics, unlike commas or newlines.
    // 单元分隔符很少出现在普通歌词里，比逗号或换行更适合作为字段分隔。
    private let separator = "\u{1F}"

    func readNowPlaying() -> Result<NowPlaying, MusicLyricsError> {
        // AppleScript returns sentinel strings for expected app/player states, and a separated
        // payload only when Music.app is actively playing a track.
        // AppleScript 会为常见应用/播放器状态返回哨兵字符串，仅在 Music.app 正在播放时返回分隔后的字段。
        let source = """
        tell application "System Events"
          set musicIsRunning to exists process "Music"
        end tell

        if musicIsRunning is false then
          return "NOT_RUNNING"
        end if

        tell application "Music"
          if player state is not playing then
            return "NOT_PLAYING"
          end if

          set currentTrack to current track
          set trackName to name of currentTrack
          set artistName to artist of currentTrack
          set albumName to album of currentTrack
          set trackLyrics to lyrics of currentTrack
          set trackDuration to duration of currentTrack
          set trackPosition to player position
          return trackName & "\(separator)" & artistName & "\(separator)" & albumName & "\(separator)" & trackLyrics & "\(separator)" & trackDuration & "\(separator)" & trackPosition
        end tell
        """

        // NSAppleScript reports execution errors through an NSDictionary instead of throwing.
        // NSAppleScript 通过 NSDictionary 返回执行错误，而不是用 throw 抛出。
        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            return .failure(.scriptFailure("无法创建 AppleScript。"))
        }

        let output = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "AppleScript 执行失败。"
            return .failure(.scriptFailure(message))
        }

        guard let raw = output.stringValue else {
            return .failure(.missingResult)
        }

        if raw == "NOT_RUNNING" {
            return .failure(.musicNotRunning)
        }

        if raw == "NOT_PLAYING" {
            return .failure(.notPlaying)
        }

        let parts = raw.components(separatedBy: separator)
        guard parts.count == 6 else {
            return .failure(.missingResult)
        }

        // Track identity is deliberately lightweight; it is stable enough for lyric cache invalidation.
        // 歌曲身份刻意保持轻量，用于歌词缓存失效已经足够稳定。
        let title = parts[0]
        let artist = parts[1]
        let album = parts[2]
        let lyrics = parts[3]
        let duration = Double(parts[4]) ?? 0
        let playerPosition = Double(parts[5]) ?? 0

        return .success(
            NowPlaying(
                trackID: "\(title)|\(artist)|\(album)",
                title: title,
                artist: artist,
                album: album,
                lyrics: lyrics,
                playerPosition: playerPosition,
                duration: duration
            )
        )
    }
}
