import Testing
@testable import MenuBarLyrics

// Covers pure lyric selection behavior without launching Music.app or AppKit.
// 覆盖纯歌词选择逻辑，不需要启动 Music.app 或 AppKit。
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

    @Test func supportsTimestampPrecisionVariants() {
        let nowPlaying = makeNowPlaying(
            lyrics: """
            [00:01]One
            [00:02.3]Two
            [00:03.345]Three
            """,
            playerPosition: 2.4,
            duration: 10
        )

        #expect(resolver.displayLine(for: nowPlaying) == "Two")
    }

    @Test func skipsLRCMetadataWhenSelectingTimedLyrics() {
        let nowPlaying = makeNowPlaying(
            lyrics: """
            [ti:Song]
            [ar:Artist]
            [al:Album]
            [00:00.00]Intro
            [00:10.00]Verse
            """,
            playerPosition: 12,
            duration: 60
        )

        #expect(resolver.displayLine(for: nowPlaying) == "Verse")
    }

    @Test func appliesLRCOffsetToTimestamps() {
        let nowPlaying = makeNowPlaying(
            lyrics: """
            [offset:1000]
            [00:00.00]Intro
            [00:10.00]Verse
            """,
            playerPosition: 10.5,
            duration: 60
        )

        #expect(resolver.displayLine(for: nowPlaying) == "Intro")
    }

    @Test func supportsNegativeLRCOffset() {
        let nowPlaying = makeNowPlaying(
            lyrics: """
            [offset:-1000]
            [00:10.00]Verse
            [00:20.00]Chorus
            """,
            playerPosition: 9.5,
            duration: 60
        )

        #expect(resolver.displayLine(for: nowPlaying) == "Verse")
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

    @Test func skipsLRCMetadataWhenFallingBackToUntimedLyrics() {
        let nowPlaying = makeNowPlaying(
            lyrics: """
            [ti:Song]
            First line
            Second line
            """,
            playerPosition: 0,
            duration: 10
        )

        #expect(resolver.displayLine(for: nowPlaying) == "First line")
    }

    @Test func clampsNegativePlaybackPositionForUntimedLyrics() {
        let nowPlaying = makeNowPlaying(
            lyrics: """
            One
            Two
            """,
            playerPosition: -5,
            duration: 10
        )

        #expect(resolver.displayLine(for: nowPlaying) == "One")
    }

    @Test func fallsBackToFirstUntimedLyricWhenDurationIsZero() {
        let nowPlaying = makeNowPlaying(
            lyrics: """
            One
            Two
            """,
            playerPosition: 5,
            duration: 0
        )

        #expect(resolver.displayLine(for: nowPlaying) == "One")
    }

    @Test func reportsMissingLyricsWhenOnlyLRCMetadataExists() {
        let nowPlaying = makeNowPlaying(
            lyrics: """
            [ti:Song]
            [ar:Artist]
            """,
            playerPosition: 0,
            duration: 0
        )

        #expect(resolver.displayLine(for: nowPlaying) == "Song - Artist\nMusic 元数据中没有歌词。")
    }

    @Test func reportsMissingLyrics() {
        let nowPlaying = makeNowPlaying(lyrics: "", playerPosition: 0, duration: 0)

        #expect(resolver.displayLine(for: nowPlaying) == "Song - Artist\nMusic 元数据中没有歌词。")
    }

    // Keep fixture creation explicit so each test only varies the lyric timing inputs it cares about.
    // 保持测试数据创建清晰，让每个测试只改变自己关心的歌词时间输入。
    private func makeNowPlaying(
        lyrics: String,
        playerPosition: Double,
        duration: Double
    ) -> NowPlaying {
        NowPlaying(
            trackID: "song|artist|album",
            title: "Song",
            artist: "Artist",
            album: "Album",
            lyrics: lyrics,
            playerPosition: playerPosition,
            duration: duration
        )
    }
}
