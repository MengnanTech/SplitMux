# SplitMux

A native macOS terminal multiplexer built with SwiftUI and SwiftTerm. Split panes, tabs, SSH, and more — keyboard-driven and lightweight.

## Features

- **Split Panes** — Split horizontally or vertically, drag to resize, zoom into any pane
- **Tabs** — Multiple tabs per session with session persistence across relaunches
- **SSH** — Saved hosts + auto-parse `~/.ssh/config`, one-click connect from command palette
- **Command Palette** (⌘P) — Fuzzy search across sessions, tabs, commands, and SSH hosts
- **Terminal Search** (⌘F) — Floating search bar with match navigation
- **Terminal History** (⇧⌘H) — Browse, search, and export terminal output
- **Claude Code Integration** — Agent dashboard for monitoring Claude Code agents
- **Auto-Update** — Built-in Sparkle updates

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘N | New Session |
| ⌘T | New Tab |
| ⌘D | Split Right |
| ⇧⌘D | Split Down |
| ⌘F | Find in Terminal |
| ⌘P | Command Palette |
| ⇧⌘A | Agent Dashboard |
| ⇧⌘H | Terminal History |
| ⌘+/⌘- | Font Size |

## Requirements

- macOS 15.0+
- Apple Silicon or Intel

## Build from Source

```bash
# Install dependencies
brew install xcodegen create-dmg

# Generate Xcode project
xcodegen generate

# Build
xcodebuild -project SplitMux.xcodeproj -scheme SplitMux -configuration Release build
```

## Tech Stack

- **SwiftUI** + **Swift 6.0** — UI and concurrency
- **[SwiftTerm](https://github.com/migueldeicaza/SwiftTerm)** — Terminal emulation
- **[Sparkle](https://sparkle-project.org/)** — Auto-update

## Download

Get the latest release from the [Releases](https://github.com/MengnanTech/SplitMux/releases) page.

## License

[MIT](LICENSE)
