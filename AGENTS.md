# AGENTS.md

This file gives future coding agents the project context and working rules needed to keep MenuBarLyrics easy to iterate.

## Project Overview

MenuBarLyrics is a lightweight macOS menu bar app written as a Swift Package. It reads the currently playing track from Music.app, resolves one lyric line from local `lyrics` metadata or the visible Music.app lyrics panel, and displays that line as text in the macOS menu bar status item.

The app is an early but runnable prototype. Favor small, well-tested changes that preserve the current simplicity unless the user explicitly asks for a larger product direction.

## Repository Layout

- `Package.swift`: Swift package definition. Requires Swift 6.0 and macOS 14.
- `Sources/MenuBarLyrics/MenuBarLyricsApp.swift`: app entry point, menu bar status item, polling loop, lyric title updates, and menu commands.
- `Sources/MenuBarLyrics/MusicLyricsReader.swift`: AppleScript bridge for Music.app and conversion into `NowPlaying`.
- `Sources/MenuBarLyrics/MusicLyricsAccessibilityReader.swift`: Accessibility bridge for reading the visible Music.app lyrics panel when local metadata is empty.
- `Sources/MenuBarLyrics/LyricsLineResolver.swift`: pure lyric selection logic. This is the safest place to extend parsing behavior.
- `Sources/MenuBarLyrics/PreferencesWindowController.swift`: AppKit preferences window for user-facing settings.
- `Tests/MenuBarLyricsTests/LyricsLineResolverTests.swift`: Swift Testing coverage for lyric resolution.
- `README.md`: user-facing description, requirements, usage, and limitations.

## Build And Test Commands

Use these from the repository root:

```bash
swift test
Scripts/build-app.sh
swift run
```

Run `swift test` before finishing changes that touch lyric parsing, data modeling, or other testable logic. After any code or app-facing behavior change, run `Scripts/build-app.sh` so the latest build is copied into `dist/MenuBarLyrics.app` for direct manual checking. `swift run` launches a real macOS app and may require Music.app plus Automation permissions, so use it only when interactive verification is useful.

## Runtime And Permission Notes

- The app targets macOS 14 or newer.
- It depends on Music.app being installed and running.
- It reads local Music library lyric metadata through AppleScript. Apple Music live synced lyrics are not available through a public macOS API.
- When local lyric metadata is empty, it can read the visible Music.app lyrics panel through macOS Accessibility. This requires the user to grant Accessibility permission, and the Music.app lyrics panel must be open.
- First launch may trigger macOS Automation permission prompts for Music.app and System Events.
- AppleScript failures should be shown as user-readable messages through `MusicLyricsError`.

## Architecture Guidelines

- Keep Music.app access isolated in `MusicLyricsReader`.
- Keep Music.app Accessibility UI scraping isolated in `MusicLyricsAccessibilityReader`.
- Keep lyric parsing and line selection pure in `LyricsLineResolver` so behavior is easy to test without launching AppKit or Music.app.
- Keep menu bar display, app lifecycle, menu commands, and polling in `MenuBarLyricsApp`.
- Keep preferences UI and control wiring in `PreferencesWindowController`.
- Avoid mixing AppleScript, UI layout, and parsing logic in the same type.

## Development Guidelines

- Prefer conservative, focused changes over broad rewrites.
- Preserve the lightweight menu bar app model unless a task explicitly calls for a full app window or preferences UI.
- When adding lyric parsing features, add or update `LyricsLineResolverTests`.
- Treat `NowPlaying.trackID` as a lightweight identity for the current track. If behavior starts caching by track, account for title, artist, and album changes.
- Keep persisted preferences explicit and stable in `UserDefaults`. If a key changes, handle migration or preserve the old behavior.
- Be careful with string separators used by AppleScript output. The current implementation uses the unit separator (`\u{1F}`) to reduce collisions with normal lyric text.
- Keep polling work cheap. The app currently polls Music.app once per second and only updates the menu bar title when the displayed line changes.
- Keep user-facing error text short and direct; menu bar space is limited.
- Avoid adding external dependencies unless they clearly solve a real project need.
- Unless the user says otherwise, finish app changes by rebuilding the app bundle with `Scripts/build-app.sh` so the user's next manual check opens the latest code from `dist/MenuBarLyrics.app`.

## UI Guidelines

- The lyric display should stay inside the macOS menu bar status item rather than a floating desktop overlay.
- macOS public APIs only allow status item text in the menu bar status area; do not assume the app can reserve an arbitrary fixed position in the middle of the menu bar.
- Keep lyric text short enough for the menu bar. If changing truncation behavior, consider narrow screens and crowded status areas.
- Preserve a clear collapsed state when lyrics are hidden: the menu bar item should still provide access to settings and quit.

## Testing Guidance

The current reliable automated coverage is lyric resolution. Add tests for:

- LRC timestamp parsing changes.
- Untimed lyric fallback behavior.
- Empty or whitespace-only lyric input.
- Boundary positions such as negative playback time, zero duration, and end-of-track progress.
- Multiple timestamps on one lyric line.

AppKit status item behavior and Music.app AppleScript behavior are harder to automate in this package. For those, document manual verification in the final response when relevant.

## Useful Manual Checks

For app-facing changes, verify as much of this as practical:

- `swift run` launches a menu bar status item.
- The menu bar visibility toggle, preferences window, and quit command work.
- The lyrics visibility preference persists across app launches.
- When Music.app is not running, the menu bar item shows a readable error while lyrics are enabled.
- When Music.app is paused or stopped, the menu bar item shows a readable error while lyrics are enabled.
- When a streaming Apple Music song has no local lyric metadata, opening Music.app's lyrics panel lets the menu bar item pick up a visible lyric line after Accessibility permission is granted.
- A track with timestamped lyrics advances to the expected line.
- A track without timestamped lyrics falls back by playback progress.
- Long lyric lines are truncated without crowding the menu bar excessively.

## Documentation Expectations

Update `README.md` when changing:

- User-visible behavior.
- System requirements.
- Launch, build, or test commands.
- Known limitations around Music.app, permissions, or lyric sources.
- Packaging or release workflow.

Keep this `AGENTS.md` updated when project structure, commands, test strategy, or core architectural boundaries change.
