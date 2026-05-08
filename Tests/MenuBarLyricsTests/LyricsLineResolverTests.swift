import Testing
@testable import MenuBarLyrics

struct LyricsLineResolverTests {
    private let resolver = LyricsLineResolver()

    @Test func selectsTimestampedLineByPlaybackPosition() {
        let nowPlaying = makeNowPlaying(
            lyrics: """
            [00:00.00]Intro
            [00:12.50]First line
            [00:25.00]Second line
            """,
            playerPosition: 13,
            duration: 180
        )

        #expect(resolver.displayLine(for: nowPlaying) == "First line")
    }

    @Test func supportsMultipleTimestampsForSameLyricText() {
        let nowPlaying = makeNowPlaying(
            lyrics: """
            [00:05.00][00:30.00]Repeated line
            [00:45.00]Outro
            """,
            playerPosition: 32,
            duration: 60
        )

        #expect(resolver.displayLine(for: nowPlaying) == "Repeated line")
    }

    @Test func fallsBackToProgressWhenLyricsHaveNoTimestamps() {
        let nowPlaying = makeNowPlaying(
            lyrics: """
            One
            Two
            Three
            Four
            """,
            playerPosition: 31,
            duration: 40
        )

        #expect(resolver.displayLine(for: nowPlaying) == "Four")
    }

    @Test func reportsMissingLyrics() {
        let nowPlaying = makeNowPlaying(lyrics: "", playerPosition: 0, duration: 0)

        #expect(resolver.displayLine(for: nowPlaying) == "Song - Artist\nNo lyrics found in Music library metadata.")
    }

    private func makeNowPlaying(
        lyrics: String,
        playerPosition: Double,
        duration: Double
    ) -> NowPlaying {
        NowPlaying(
            trackID: "song|artist|album",
            title: "Song",
            artist: "Artist",
            lyrics: lyrics,
            playerPosition: playerPosition,
            duration: duration
        )
    }
}
