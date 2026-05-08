# MenuBarLyrics

MenuBarLyrics 是一个轻量的 macOS 菜单栏歌词工具。它会读取 Music.app 当前播放的歌曲信息和本地歌词元数据；如果本地没有歌词，会尝试从 Music.app 的歌词面板读取 Apple Music 当前显示的歌词，并在 macOS 顶部菜单栏显示当前歌词。

## 功能

- 常驻 macOS 菜单栏，可从菜单或设置窗口显示、隐藏歌词或退出应用。
- 将当前歌词作为菜单栏文字展示，关闭歌词后只保留菜单栏图标。
- 每秒轮询一次 Music.app 当前播放状态。
- 通过 AppleScript 读取歌曲名、艺人、播放进度、时长和 `lyrics` 元数据。
- 当本地 `lyrics` 元数据为空时，通过 macOS Accessibility 读取 Music.app 歌词面板中当前可见的歌词行。
- 支持解析 LRC 风格时间戳，例如 `[00:12.50]`。
- 当歌词没有时间戳时，根据播放进度估算当前歌词行。
- 首次打开会显示设置窗口，可控制是否展示菜单栏歌词，并会记住开关状态。

## 系统要求

- macOS 14 或更新版本
- Swift 6.0 或更新版本（从源码运行或测试时需要）
- Music.app
- 当前歌曲需要在本地音乐资料库元数据中包含可读取的歌词，或 Music.app 正在显示 Apple Music 歌词面板
- 辅助功能权限（用于读取 Music.app 歌词面板）

## 生成可双击的 App

```bash
Scripts/build-app.sh
```

生成完成后，Finder 中打开项目的 `dist` 目录，双击 `MenuBarLyrics.app` 即可启动。启动后它会常驻顶部菜单栏，不会出现在 Dock 中。

如果 macOS 提示该应用来自未识别开发者，可以在 Finder 中右键点击 `MenuBarLyrics.app`，选择“打开”，再在系统提示中确认打开。首次读取 Music.app 时，macOS 可能会请求“自动化”权限，用于允许 MenuBarLyrics 控制 Music.app 和 System Events。读取 Music.app 歌词面板还需要在“系统设置 > 隐私与安全性 > 辅助功能”中允许 MenuBarLyrics。

## 从源码启动应用

```bash
swift run
```

这会启动 MenuBarLyrics 菜单栏应用。启动后，顶部菜单栏会出现一个音乐图标；如果歌词显示已开启，图标旁会显示当前歌词行。

首次启动时，macOS 可能会请求“自动化”权限，用于允许 MenuBarLyrics 控制 Music.app 和 System Events。没有该权限时，应用无法读取当前播放信息。读取 Music.app 歌词面板还需要辅助功能权限。

## 使用

1. 打开 Music.app，并播放歌曲。
2. 双击 `dist/MenuBarLyrics.app`，或在项目目录运行 `swift run` 启动 MenuBarLyrics。
3. 通过菜单栏图标打开菜单，可显示或隐藏菜单栏歌词、打开设置窗口或退出应用。
4. 设置窗口中的歌词显示开关会被记住，下次启动时沿用上一次的状态。

## 测试

```bash
swift test
```

## 使用限制

Apple Music 的实时同步歌词目前没有公开的 macOS API 可供第三方应用直接读取。本项目优先读取 Music.app 本地资料库中的 `lyrics` 元数据；如果为空，会在 Music.app 歌词面板已打开时，通过辅助功能读取面板里当前显示的歌词行。

如果 Music.app 没有打开歌词面板，或当前歌曲没有 Apple Music 歌词，菜单栏会显示相应提示。辅助功能读取依赖 Music.app 的界面结构，macOS 或 Music.app 更新后可能需要调整匹配逻辑。

macOS 公开 API 只允许应用把文字放在右侧状态栏区域，无法强制占用菜单栏中间某个固定位置。MenuBarLyrics 会尽量以菜单栏文字项的形式展示当前歌词。

## 项目状态

这是一个早期版本，当前已经是可运行的 macOS 菜单栏应用，并提供本地 `.app` 生成脚本。后续可以考虑补充：

- DMG、release 和正式签名公证流程
- 菜单栏歌词长度、刷新频率等偏好设置
- 开机启动选项
- 更完善的错误提示和权限引导
- 更稳定的 Music.app 歌词面板识别

## AI 生成声明

本项目由 AI 生成，并经过人工需求描述、运行验证和后续维护。代码、文档和行为仍可能存在疏漏，使用前请自行审阅并测试。

## 许可证

本项目使用 MIT License，详见 [LICENSE](LICENSE)。
