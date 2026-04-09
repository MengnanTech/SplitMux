# SplitMux — 版本更新日志

## v1.0.7（2026-03-31，Build 9）

### 主要变更
- **Glass 主题完善**：改进 frosted glass 效果，提升终端文字可读性
- Glass Dark / Glass Light 双模式：`NSVisualEffectView`（`.hudWindow` / `.headerView`）+ 自定义 ANSI 调色板（glassLight 模式对 TUI 背景色重映射）
- `TerminalContainerView` 三层结构：blur（NSVisualEffectView）→ tint（NSView）→ terminal → glaze（MousePassthroughOverlayView）
- `glassOpacity` 用户可调（默认 0.85）

**git commit**：cca1780 / 448ead7 / 7a843e0

---

## v1.0.6（Build 8）

### 主要变更
- **Tab 拖拽重排**：iTerm2 风格，侧边栏 Session 列表和 Tab 栏均支持 drag-and-drop 重排（`SessionDropDelegate`）
- **Split Pane 改进**：
  - 分割线悬停 hover 效果（4px → 6px，颜色变为 accentColor）
  - 分屏 zoom（tmux 风格，⌘⇧Z）：`Session.zoomedTabID` + `FloatingZoomButton`
  - `SplitDropZone`：Tab 拖拽到分屏区域创建新分屏
- **全局工作目录**：侧边栏顶部新增全局默认工作目录选择条（`appState.defaultWorkingDirectory`，UserDefaults 持久化）
- **右键菜单增强**：终端右键：Copy / Paste / Select All / Clear / New Tab / Split Right / Split Down
- **Bug 修复**：
  - 修复 title bar 遮挡内容（KVO 守护 styleMask + toolbar）
  - 修复 Tab 拖动重排顺序错误
  - 修复 codesign 签名顺序（深度优先）

**git commit**：155966e / d00073d / c77b536 / 2272dd4

---

## v1.0.5（Build 6→7）

### 主要变更
- **状态 source of truth 重构**：侧边栏 Claude 状态改从 `ClaudeHookService.agentInfos` 读取，修复 View 重建后状态丢失
- 增加发版脚本交互确认步骤（防止误触发）
- 两次版本号 bump（build 6 和 build 7），修复 appcast 问题

**git commit**：85e08b7 / 3975c92 / 30c247c / 13a307f

---

## v1.0.4（Build 5）

### 主要变更
- **Claude Code 退出恢复**：进程退出后侧边栏不再显示 "Idle"，恢复普通终端状态
  - `processTerminated` 清空状态文件（写入空字符串）
  - `tab.claudeStatus = nil`
  - `ClaudeHookService` 对空文件触发 callback(nil)

**git commit**：d97d6b4 / 4383855

---

## v1.0.3（Build 4）

### 主要变更
- exit status check：进程退出码处理
- appcast.xml 切换为 GitHub 托管（raw.githubusercontent.com）
- 发版脚本集成 GitHub Releases（`gh release create`）

**git commit**：d32dc8b / 6241183 / c8a6196 / a424421

---

## v1.0.2（Build 3）

### 主要变更
- **修复 Sparkle 更新不生效**：Info.plist 版本改用 `$(MARKETING_VERSION)` 变量引用
- **修复 Terminal History 乱码**：改从 SwiftTerm buffer 读取已渲染文本
- **修复 Tab 命名问题**：自增编号逻辑修正
- **修复多个 UI 问题**
- 添加 Glass Dark / Glass Light 主题（frosted glass effect）
- 修复 Swift 并发警告（MainActor isolation、Sendable、unused variable）

**git commit**：4dcca5d / ff0e55c / 1ca7801 / 58813b7 / f62f03f / 4c414cb / 719ac50 / 430386b / 153de65

---

## v1.0.1（Build 2）

### 主要变更
- **修复 Claude 状态检测 hook 未生效**：ZDOTDIR 机制确保 wrapper bin 路径在用户 shell 配置加载后追加到 PATH

**git commit**：f93984c

---

## v1.0.0（Build 1）

### 初始功能
- 多 Session 侧边栏管理
- 多 Tab + Split Pane（递归二叉树布局）
- SwiftTerm PTY 集成
- Claude Code 状态监控（文件轮询机制）
- SSH 主机管理（~/.ssh/config 解析）
- 终端历史录制与回放
- Sparkle 自动更新
- Dark / Light / Solarized / Monokai 主题
- JSON 持久化（sessions.json）
- 命令面板（⌘P）、Agent Dashboard（⌘⇧A）
