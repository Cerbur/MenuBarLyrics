import Foundation

struct NowPlaying: Sendable {
    let trackID: String
    let title: String
    let artist: String
    let album: String
    let lyrics: String
    let playerPosition: Double
    let duration: Double

    var displayLine: String {
        LyricsLineResolver().displayLine(for: self)
    }
}

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

final class MusicLyricsReader: @unchecked Sendable {
    private let separator = "\u{1F}"

    func readNowPlaying() -> Result<NowPlaying, MusicLyricsError> {
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
