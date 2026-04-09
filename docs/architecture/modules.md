# SplitMux — 模块与类职责

## 入口层（App/）

### `SplitMuxApp` — `SplitMux/App/SplitMuxApp.swift`
- `@main` 结构体，遵循 `App` 协议
- 持有 `@State private var appState = AppState()`（唯一 AppState 实例，通过 `.environment(appState)` 注入全局）
- 持有 `SPUStandardUpdaterController`（Sparkle，启动时即开始检查更新）
- 注册菜单命令：New Session（⌘N）、New Tab（⌘T）、Split Right（⌘D）、Split Down（⌘⇧D）、Command Palette（⌘P）、Agent Dashboard（⌘⇧A）、Terminal History（⌘⇧H）、字体大小调整（⌘+/⌘-/⌘0）
- `onAppear` 调用 `NotificationService.shared.requestPermission()` 和 `appState.restoreIfNeeded()`
- `willTerminate` 调用 `appState.saveNow()` 和 `ClaudeHookService.shared.cleanup()`
- 嵌套结构：`WindowConfigurator`（NSViewRepresentable）→ `WindowConfiguratorView`（NSView + NSWindowDelegate）
  - 监控 `styleMask` 和 `toolbar` KVO，防止 SwiftUI 重置窗口样式
  - `windowShouldClose` 弹出确认 Alert，关闭窗口时终止整个 App（防止 AppState 悬空）

### `WindowChromeConfigurator` — `SplitMux/App/WindowChromeConfigurator.swift`
- 封装 NSWindow 的全尺寸内容区（`fullSizeContentView`）配置逻辑
- 被 `WindowConfiguratorView.applyConfig(_:)` 调用

---

## 数据模型层（Models/）

### `AppState` — `SplitMux/Models/AppState.swift`
- `@MainActor @Observable class`，全局单一状态根节点
- 关键属性：
  - `sessions: [Session]` — 所有会话列表
  - `selectedSessionID: UUID?` — 当前激活的会话
  - `defaultWorkingDirectory: String` — 全局默认工作目录（持久化到 UserDefaults key: `splitmux.defaultWorkingDirectory`）
- 关键方法：
  - `restoreIfNeeded()` — 从 `PersistenceService` 恢复上次状态，启动 git branch 轮询
  - `addSession(workingDirectory:)` — 创建新 Session，接线 `onChanged` 回调，触发防抖保存
  - `removeSession(_ id:)` — 移除 Session，清理 Claude 监控，更新 Dock Badge
  - `scheduleSave()` — 1 秒防抖 Timer，触发 `PersistenceService.save()`
  - `saveNow()` — 立即保存（App 退出时调用）
  - `updateDockBadge()` — 统计所有 Tab 未读通知数量

### `Session` — `SplitMux/Models/Session.swift`
- `@MainActor @Observable class`，实现 `Identifiable, Hashable`
- 关键属性：
  - `tabs: [Tab]` — Tab 列表
  - `activeTabID: UUID?` — 当前活跃 Tab
  - `splitRoot: SplitNode?` — 分屏布局树根（nil = 单 Tab 无分屏）
  - `zoomedTabID: UUID?` — 放大显示的 Tab（tmux 风格 zoom）
  - `tabDragState: TabDragState?` — Tab 拖拽共享状态
  - `workingDirectory: String` — 会话工作目录
  - `gitBranch: String?` — 当前 git 分支（3 秒轮询）
  - `onChanged: (() -> Void)?` — AppState 注册的保存回调
- 关键方法：
  - `createTab()` — 自动编号（zsh / zsh 2 / zsh 3...）
  - `removeTab(_ tabID:)` — 清理 SSH 状态、终端历史、Claude 监控，智能选择下一个活跃 Tab
  - `splitActiveTab(direction:)` — 在分屏树中插入新节点，或创建新分屏根
  - `unsplit()` / `toggleZoom()` — 退出分屏 / 切换放大
  - `startGitBranchPolling()` / `stopGitBranchPolling()` — 每 3 秒在 detached Task 中执行 `git rev-parse --abbrev-ref HEAD`

### `Tab` — `SplitMux/Models/Tab.swift`
- `@Observable class`，实现 `Identifiable, Hashable`
- 关键属性：
  - `content: TabContent` — 枚举：`.terminal` / `.text(String)` / `.notes(String)` / `.webURL(URL)` / `.sshTerminal(hostID: UUID)`
  - `terminalView: NSView?` — 强引用，防止 SwiftUI 重建时 PTY 进程丢失
  - `claudeStatus: ClaudeStatus?` — running / idle / needsInput / unknown
  - `hasNotification: Bool` / `lastNotificationMessage: String?` — 未读通知状态
  - `sshHostID: UUID?` — SSH 主机关联

### `SplitNode` — `SplitMux/Models/SplitNode.swift`
- `indirect enum`（递归值类型），实现 `Equatable`
  - `.tab(UUID)` — 叶节点，引用一个 Tab ID
  - `.horizontal(SplitNode, SplitNode, ratio: Double)` — 左右分割，ratio 为左侧占比
  - `.vertical(SplitNode, SplitNode, ratio: Double)` — 上下分割
- 关键操作（均为纯函数，返回新树）：
  - `insertSplit(at:newTabID:direction:)` — 在目标叶节点处插入新分屏
  - `removing(tabID:)` — 移除叶节点，父节点坍缩为剩余子节点
  - `siblingTabID(of:)` — 查找最近兄弟 Tab（用于关闭 Tab 时的焦点转移）
  - `updatingRatio(at:newRatio:)` — 更新指定路径的分割比例
- 辅助枚举：`SplitDirection`（right/left/down/up）、`SplitPath`（first/second）

### `SSHHost` — `SplitMux/Models/SSHHost.swift`
- `@Observable class`，实现 `Identifiable, Codable`
- 持久化字段：id / name / hostname / port / username / keyPath / colorTag / autoReconnect / lastConnected
- 运行时状态（不序列化）：`connectionState: SSHConnectionState`（disconnected/connecting/connected/failed）/ `connectedTabID: UUID?`
- 计算属性 `sshCommand: String` — 自动拼接 ssh 命令行（含 -p / -i / user@host）
- 关联枚举：`SSHColorTag`（7色标签）、`SSHConnectionState`（4状态 + icon/color）

### `TerminalHistory` — `SplitMux/Models/TerminalHistory.swift`
- `@Observable @MainActor class`
- `entries: [TerminalHistoryEntry]`（timestamp + data + text），上限 50 MB（超限从头裁剪）
- `displayLines: [DisplayLine]` — 从 `SwiftTerm.Terminal.getBufferAsData()` 读取已渲染文本（ANSI 已处理）
- 支持 `startReplay(feedBlock:)` / `stopReplay()`，逐帧回放（间隔 = 原始录制间隔 / replaySpeed，clamp 1ms~2s）
- `exportToFile(url:includeTimestamps:)` — 导出为纯文本文件

---

## 视图层（Views/）

### `ContentView` — `SplitMux/Views/ContentView.swift`
- 根布局：`HStack { SidebarView + SidebarDivider + ZStack(sessions) }`
- 用 `ZStack + opacity` 而非 `if/else` 保持所有 Session 的 TabContentView 存活（防止 PTY 进程重建）
- 管理 Command Palette / Agent Dashboard 覆盖层
- 注册全量键盘快捷键（⌘T / ⌘N / ⌘W / ⌘F / ⌘D / ⌘⇧D / ⌘1-9 / ⌘⇧[] / ⌘⇧W / ⌘⇧Z）
- `SidebarDivider`（NSViewRepresentable）：拖动调整侧边栏宽度（140-400px），NSCursor 精确控制

### `SidebarView` — `SplitMux/Views/Sidebar/SidebarView.swift`
- 顶部：Sessions 标题 + "+" 按钮 + 拖拽区域（`WindowDragArea`）
- 全局工作目录选择条（NSOpenPanel）
- Session 列表（`ScrollView + LazyVStack`）：支持 drag-and-drop 重排（`SessionDropDelegate`）
- `SessionRow` 展示：icon / 名称 / 路径 / git 分支 / Claude Agent 状态（从 `ClaudeHookService.agentInfos` 读取）/ 未读角标
- 底部：AgentsSidebarSection + SSHHostsSection + Footer（会话计数）
- 右键菜单通过 `NativeContextMenu` 桥接，包含：New Tab / New Session / Copy Path / Set Working Directory / Rename / Duplicate / Split Right/Left/Down/Up / Delete

### `TabBarView` — `SplitMux/Views/TabContent/TabBarView.swift`
- 顶部 Tab 切换栏，支持 iTerm2 风格的 Tab 拖拽重排和拖拽到分屏区域

### `TabPanelView` — `SplitMux/Views/TabContent/TabPanelView.swift`
- 分屏叶节点的内容容器，托管 `TerminalSwiftUIView`

### `SplitPaneView` — `SplitMux/Views/Components/SplitPaneView.swift`
- 递归渲染 `SplitNode` 树
  - `.tab` → `TabPanelView`（含 Claude 状态角标 `SplitPaneStatusBadge`）
  - `.horizontal` → `HSplitContent`（GeometryReader + HStack + 可拖动分割线）
  - `.vertical` → `VSplitContent`（GeometryReader + VStack + 可拖动分割线）
- Zoom 逻辑：放大节点 ratio 设为 1.0，另一侧 opacity=0
- 分割线悬停 hover 效果：4px → 6px，颜色变为 accentColor

### `TerminalSwiftUIView` — `SplitMux/Services/ShellExecutor.swift`
- `NSViewRepresentable`，是最核心的终端桥接层
- `makeNSView`：
  1. 若 `tab.terminalView` 已存在（SwiftUI 重建），复用旧 `NotifyingTerminalView`（保留 PTY 进程）
  2. 否则创建新 `NotifyingTerminalView`，配置 Click Monitor（分屏焦点切换）
  3. 创建临时 ZDOTDIR，确保 wrapper bin 路径优先于用户 PATH
  4. 注入环境变量：`SPLITMUX_TAB_ID` / `__SPLITMUX_BIN` / `TERM=xterm-256color` / `TERM_PROGRAM=SplitMux`
  5. 延迟启动 PTY（`deferProcessStart`，等待视图有真实 frame，避免 PTY 列数为 0）
  6. 启动 `ClaudeHookService.startMonitoring(tabID:)`，注册状态回调
  7. SSH Tab：启动 zsh 后 0.5s 发送 ssh 命令；设置 `sshAutoReconnect` 标志
- `TerminalContainerView`（NSView）：管理 glass blur 层（NSVisualEffectView + tint + glaze）

---

## 服务层（Services/）

### `ClaudeHookService` — `SplitMux/Services/ClaudeHookService.swift`
- `@MainActor @Observable final class`，单例
- 机制：每 0.5 秒轮询 `/tmp/splitmux/{tabID}` 文件内容（"running" / "idle" / "needs-input"）
- `agentInfos: [AgentInfo]` — 全局 Agent 状态注册表（tabID / sessionName / tabTitle / status / lastStatusChange）
- `recentNotifications: [AgentNotification]` — 最近 50 条状态变化通知
- 启动时清空 `/tmp/splitmux/` 目录（防残留）
- `startMonitoring(tabID:onStatusChange:)`：防重复注册（View 重建时保留现有状态，仅重启 Timer）
- `stopMonitoring(tabID:)`：清理 Timer + 删除状态文件 + 移出 agentInfos
- `refreshAllStatuses()`：清空 lastStatus 缓存，强制下次轮询回调（主题切换后调用）
- `cleanup()`：App 退出时全量清理

### `SettingsManager` — `SplitMux/Services/SettingsManager.swift`
- `@Observable @MainActor final class`，单例
- UserDefaults 持久化（所有 key 见下方 data-model.md）
- `AppTheme` 枚举（6 个主题）包含完整的 design token 系统：
  - 基础色：`primaryText` / `secondaryText` / `tertiaryText` / `disabledText` / `bodyText`
  - 交互色：`hoverBackground` / `selectedBackground` / `activeTabBackground`
  - 表面色：`sidebarBackground` / `contentBackground` / `tabBarBackground` / `elevatedSurface`
  - 分割线色：`splitDivider` / `splitDividerHover`
  - 品牌色（Light 模式独有）：`brandCoral` / `brandAqua`
  - Chrome 层：`chromeOverlay` / `chromeSurfaceBackground` / `chromeShadow`
  - Glass 模式：`terminalBackground` / `terminalForeground`（含 alpha 通道）

### `PersistenceService` — `SplitMux/Services/PersistenceService.swift`
- `@MainActor final class`，单例
- 保存路径：`~/Library/Application Support/SplitMux/sessions.json`
- DTO 层（防止 @Observable 直接 Codable）：`AppStateDTO / SessionDTO / TabDTO / SplitNodeDTO`（class 避免递归值类型无限大小）
- 恢复时校验：工作目录不存在则回退 `~`，splitLayout 中所有引用 tabID 必须存在才恢复分屏，sessions 为空时返回 nil（触发重新初始化）

### `SSHManagerService` — `SplitMux/Services/SSHManagerService.swift`
- `@MainActor @Observable final class`，单例
- `savedHosts: [SSHHost]` — 用户手动添加（持久化到 `~/Library/Application Support/SplitMux/ssh_hosts.json`）
- `configHosts: [SSHHost]` — 从 `~/.ssh/config` 解析（不序列化），去重规则：saved 优先
- 解析 `~/.ssh/config`：跳过通配符 Host（含 `*`/`?`），识别 Hostname / Port / User / IdentityFile 指令
- `updateHost`：config host 首次编辑时自动 promote 到 savedHosts

### `NotifyingTerminalView` — `SplitMux/Services/ShellExecutor.swift`
- `LocalProcessTerminalView` 子类（SwiftTerm）
- `glassMode: Bool` — 控制 CALayer isOpaque，实现 glass 透明穿透
- `dataReceived(slice:)` — 重写拦截 PTY 输出，转发给 `onDataReceived` 回调（历史录制）
- `searchTerminal(query:backward:)` — 封装 SwiftTerm 的 `findNext/findPrevious`
- `restartProcess(in:)` — 复用缓存的 env，terminate + resetToInitialState + startProcess（切换工作目录时用）
- `deferProcessStart(_:)` — 重写 `setFrameSize`，等待 frame > 0 后才启动 PTY（确保 PTY 报告正确终端宽度）
- `installClickMonitor()` — NSEvent.addLocalMonitorForEvents 捕获左键点击，通过 hitTest 确认点击目标后触发 `onPaneClicked`（分屏焦点切换）
- 右键菜单：Copy / Paste / Select All / Clear（发送 Ctrl+L） / New Tab / Split Right / Split Down

### `TerminalHistoryService` — `SplitMux/Services/TerminalHistoryService.swift`
- 管理每个 Tab 对应的 `TerminalHistory` 实例（按 tabID 索引）
- `removeHistory(for tabID:)` — Tab 关闭时清理
