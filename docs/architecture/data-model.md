# SplitMux — 数据模型

## 核心数据结构

### AppState（根状态）

```swift
@MainActor @Observable class AppState {
    var sessions: [Session]             // 所有会话
    var selectedSessionID: UUID?        // 当前激活会话
    var defaultWorkingDirectory: String // 全局默认工作目录（UserDefaults 持久化）
}
```

### Session（会话）

```swift
@MainActor @Observable class Session: Identifiable, Hashable {
    let id: UUID
    var customName: String?             // 用户自定义名称（nil = 使用目录名）
    var icon: String                    // SF Symbol 名称（默认 "terminal"）
    var tabs: [Tab]
    var activeTabID: UUID?
    var splitRoot: SplitNode?           // nil = 单 Tab 模式
    var zoomedTabID: UUID?              // tmux 风格放大
    var tabDragState: TabDragState?     // 拖拽共享状态
    var workingDirectory: String
    var gitBranch: String?              // 3 秒轮询，nil = 非 git 目录
}
```

### Tab（标签页）

```swift
@Observable class Tab: Identifiable, Hashable {
    let id: UUID
    var title: String
    var icon: String
    var content: TabContent             // 内容类型枚举
    var hasNotification: Bool
    var lastNotificationMessage: String?
    var claudeStatus: ClaudeStatus?     // running / idle / needsInput / unknown / nil
    var terminalView: NSView?           // 强引用：防止 SwiftUI 重建时 PTY 进程丢失
    var sshHostID: UUID?
}

enum TabContent: Hashable {
    case text(String)
    case webURL(URL)
    case notes(String)
    case terminal                       // 本地终端
    case sshTerminal(hostID: UUID)      // SSH 终端
}
```

### SplitNode（分屏布局树）

```swift
indirect enum SplitNode: Equatable {
    case tab(UUID)                                              // 叶节点
    case horizontal(SplitNode, SplitNode, ratio: Double)       // 左|右，ratio = 左侧占比
    case vertical(SplitNode, SplitNode, ratio: Double)         // 上/下，ratio = 上方占比
}
```

ratio 范围：拖动时限制在 0.15~0.85，防止分屏过窄。

### SSHHost（SSH 主机）

```swift
@Observable class SSHHost: Identifiable, Codable {
    // 持久化字段
    let id: UUID
    var name: String
    var hostname: String
    var port: Int                       // 默认 22
    var username: String
    var keyPath: String?                // 支持 ~ 展开
    var colorTag: SSHColorTag           // gray/red/orange/yellow/green/blue/purple
    var autoReconnect: Bool             // 进程退出后 3 秒自动重连
    var lastConnected: Date?

    // 运行时状态（不序列化）
    var connectionState: SSHConnectionState   // disconnected/connecting/connected/failed
    var connectedTabID: UUID?
}
```

### ClaudeStatus（Claude 状态）

```swift
enum ClaudeStatus: String {
    case running                        // 文件内容 "running"
    case idle                           // 文件内容 "idle"
    case needsInput = "needs-input"     // 文件内容 "needs-input"
    case unknown                        // 无法解析的内容
}
```

---

## UserDefaults 键一览

所有键均由 `SettingsManager` 管理，使用 `UserDefaults.standard`。

| Key | 类型 | 默认值 | 说明 |
|---|---|---|---|
| `splitmux.defaultWorkingDirectory` | String | ~ | 全局默认工作目录（AppState 管理） |
| `terminalFontSize` | Double | 14.0 | 终端字号（9~32 pt） |
| `terminalFontName` | String | "SF Mono" | 终端字体名称 |
| `appTheme` | String | "glass" | AppTheme rawValue（dark/light/solarized/monokai/glass/glassLight） |
| `notifyThreshold` | Double | 5.0 | 通知触发阈值（秒） |
| `showNotificationBanners` | Bool | true | 是否显示系统通知横幅 |
| `confirmBeforeClose` | Bool | true | 关闭时是否弹出确认 |
| `restoreSessionsOnLaunch` | Bool | true | 启动时是否恢复上次会话 |
| `glassOpacity` | Double | 0.85 | Glass 主题终端不透明度 |

---

## 文件系统持久化

### 会话状态（Session JSON）

```
~/Library/Application Support/SplitMux/sessions.json
```

JSON Schema（DTO 层）：

```json
{
  "sessions": [
    {
      "id": "UUID字符串",
      "customName": "可选名称",
      "icon": "terminal",
      "workingDirectory": "/Users/xxx/project",
      "tabs": [
        {
          "id": "UUID字符串",
          "title": "zsh",
          "icon": "terminal",
          "contentType": "terminal",    // terminal/text/notes/webURL/sshTerminal
          "contentValue": null,         // text内容/URL字符串/SSH Host UUID
          "sshHostID": null
        }
      ],
      "activeTabID": "UUID字符串",
      "splitLayout": {                  // null = 无分屏
        "type": "horizontal",           // tab/horizontal/vertical
        "tabID": null,
        "first": { "type": "tab", "tabID": "UUID1", ... },
        "second": { "type": "tab", "tabID": "UUID2", ... },
        "ratio": 0.5
      }
    }
  ],
  "selectedSessionID": "UUID字符串"
}
```

`SplitNodeDTO` 使用 `final class`（引用类型），避免 Swift 编译器对递归值类型的无限大小报错。

### SSH 主机配置

```
~/Library/Application Support/SplitMux/ssh_hosts.json
```

格式：`[SSHHost]` 的 JSON 数组（仅 savedHosts，configHosts 从 `~/.ssh/config` 运行时解析）。

### Claude Hook 状态文件

```
/tmp/splitmux/{tabID-UUID字符串}
```

- 由 Claude Code wrapper 脚本（app bundle 内 `bin/claude`）写入
- 内容为纯文本：`running` / `idle` / `needs-input`
- App 启动时清空目录，关闭 Tab 时删除对应文件
- `ClaudeHookService` 每 0.5 秒轮询，内容变化时触发回调

### 临时 ZDOTDIR（每次启动创建）

```
/tmp/splitmux-zsh-{PID}/
  .zshenv     # source 用户 .zshenv
  .zprofile   # source 用户 .zprofile
  .zshrc      # source 用户 .zshrc + prepend wrapper bin PATH + 共享历史配置
  .zlogin     # source 用户 .zlogin
```

目的：确保 SplitMux bin wrapper（`app bundle/Resources/bin`）优先于用户 PATH，同时完整继承用户 shell 配置。

---

## 无 Core Data

本应用不使用 Core Data / SwiftData / SQLite，所有持久化均为手动 JSON 文件，由 `PersistenceService` 和 `SSHManagerService` 管理。

---

## AppTheme 主题枚举

```swift
enum AppTheme: String, CaseIterable, Identifiable {
    case dark        // Dark（默认暗色）
    case light       // Light（亮色）
    case solarized   // Solarized Dark
    case monokai     // Monokai
    case glass       // Glass Dark（frosted glass blur）
    case glassLight  // Glass Light（frosted glass blur）
}
```

Glass 主题特殊处理：
- `terminalBackground` 使用含 alpha 的 NSColor（透明度由 `glassOpacity` 控制）
- `TerminalContainerView` 安装 `NSVisualEffectView`（.hudWindow / .headerView blending .behindWindow）
- `NotifyingTerminalView.glassMode = true`，`isOpaque = false`，CALayer 透明
