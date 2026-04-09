# SplitMux — 架构总览

> 分析时间：2026-03-31 | HEAD: cca1780

## 应用定位

SplitMux 是一款 macOS 原生终端复用器（Terminal Multiplexer），面向大量使用 Claude Code / AI 编程工具的开发者。核心卖点：

- 多 Session 侧边栏管理（类似 iTerm2 的 Profile 切换）
- 每个 Session 支持多 Tab，每个 Tab 可拆分为任意深度的分屏（Split Pane），布局用递归二叉树（`SplitNode`）表达
- 深度集成 Claude Code：通过状态文件监控（`/tmp/splitmux/{tabID}`）实时检测 Agent 状态（running / needs-input / idle），在分屏角标和侧边栏实时展示
- SSH 主机管理：自动解析 `~/.ssh/config`，支持一键连接和自动重连
- 终端历史录制与回放（上限 50 MB，逐帧时间戳）
- 全局命令面板（Command Palette，⌘P）、Agent 编排 Dashboard（⌘⇧A）
- 六套主题：Dark / Light / Solarized / Monokai / Glass Dark / Glass Light（frosted glass blur）

## 技术栈

| 层次 | 技术 |
|---|---|
| UI 框架 | SwiftUI（macOS 15.0+）+ AppKit（NSView 桥接） |
| 状态管理 | Swift `@Observable`（Observation 框架）+ `@MainActor` 全局隔离 |
| 终端引擎 | [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) 1.2.0（VT100/xterm PTY 渲染） |
| 自动更新 | [Sparkle](https://github.com/sparkle-project/Sparkle) 2.6.0（EdDSA 签名 appcast.xml） |
| 数据持久化 | JSON 序列化（`Codable` DTO），写入 `~/Library/Application Support/SplitMux/sessions.json` |
| 构建描述 | [XcodeGen](https://github.com/yonaskolb/XcodeGen)（`project.yml`）—— YAML → `.xcodeproj` |
| Swift 版本 | Swift 6.0（`SWIFT_STRICT_CONCURRENCY: complete`） |
| 最低系统 | macOS 15.0（Sequoia） |
| Bundle ID | `com.levi.SplitMux` |
| 签名 | Developer ID Application: DENG LI (2XGP34AR96)，无 App Sandbox |
| GitHub 仓库 | MengnanTech/SplitMux |

## 版本历史（来自 git log，共 78 commits）

| 版本 | Build | 日期 | 主要变更 |
|---|---|---|---|
| v1.0.1 | 2 | 初期 | 修复 Claude 状态检测 hook 未生效；修复 Terminal History 乱码和 Tab 命名 |
| v1.0.2 | 3 | 初期 | 修复 Info.plist 版本硬编码导致 Sparkle 更新不生效；修复多个 UI 问题；appcast 切换 GitHub 托管 |
| v1.0.3 | 4 | 初期 | exit status check；发版脚本集成 GitHub Releases |
| v1.0.4 | 5 | 初期 | Claude Code 退出后侧边栏不再显示 Idle，恢复普通终端状态 |
| v1.0.5 | 6→7 | 初期 | 侧边栏 session 状态从 `hookService.agentInfos` 读取（修复状态丢失）；增加脚本确认步骤 |
| v1.0.6 | 8 | 初期 | Tab 拖拽重排（iTerm2 风格）；Split Pane 改进；全局工作目录设置；右键菜单增强；修复 title bar 遮挡内容和 codesign 签名顺序 |
| v1.0.7 | 9 | 2026-03-31 | Glass 主题完善（frosted glass terminal） |

## 项目目录结构

```
SplitMux/
├── project.yml                        # XcodeGen 构建描述（版本号在此管理）
├── appcast.xml                        # Sparkle 更新源（发版脚本自动提交）
├── scripts/
│   └── build-and-notarize.sh          # 一键发版：bump版本 → xcodegen → archive → sign → DMG → notarize → GitHub Release → appcast
├── SplitMux/
│   ├── App/
│   │   ├── SplitMuxApp.swift              # @main 入口、菜单栏、Sparkle、窗口生命周期
│   │   └── WindowChromeConfigurator.swift # NSWindow 全尺寸内容区 KVO 保持
│   ├── Models/
│   │   ├── AppState.swift                 # 全局根状态（@Observable @MainActor）
│   │   ├── Session.swift                  # 会话（Tab 集合、分屏根节点、git branch 轮询）
│   │   ├── Tab.swift                      # 单 Tab（TabContent 枚举、通知状态、Claude 状态）
│   │   ├── SplitNode.swift                # 分屏布局递归二叉树
│   │   ├── SSHHost.swift                  # SSH 主机配置（Codable）
│   │   └── TerminalHistory.swift          # 终端历史录制（录制、回放、导出）
│   ├── Views/
│   │   ├── ContentView.swift              # 根视图（侧边栏 + 主区 + 覆盖层 + 键盘快捷键）
│   │   ├── Sidebar/
│   │   │   ├── SidebarView.swift          # 会话列表、Agent 状态、SSH 区、底部 footer
│   │   │   └── SSHHostsSection.swift      # SSH 主机列表子组件
│   │   ├── TabContent/
│   │   │   ├── TabContentView.swift       # 单 Session Tab 内容容器
│   │   │   ├── TabBarView.swift           # 顶部 Tab 栏（拖拽重排）
│   │   │   └── TabPanelView.swift         # 单 Tab 面板（分屏叶节点）
│   │   └── Components/
│   │       ├── SplitPaneView.swift        # 递归分屏渲染 + 可拖动分割线
│   │       ├── AgentOrchestrationView.swift # Agent 编排 Dashboard
│   │       ├── CommandPaletteView.swift   # 全局命令面板
│   │       ├── TerminalHistoryView.swift  # 历史录制面板
│   │       ├── SettingsView.swift         # 设置界面
│   │       ├── SSHHostEditorView.swift    # SSH 主机编辑
│   │       ├── BreadcrumbBar.swift        # 路径面包屑
│   │       ├── TerminalSearchBar.swift    # 终端内搜索
│   │       ├── NativeContextMenu.swift    # NSMenu 右键桥接
│   │       ├── NotificationToast.swift    # 任务完成 Toast
│   │       ├── FloatingZoomButton.swift   # 分屏放大浮动按钮
│   │       ├── SplitDropZone.swift        # Tab 拖拽分屏 Drop Zone
│   │       └── EmptyStateView.swift       # 空状态占位
│   └── Services/
│       ├── ShellExecutor.swift            # NotifyingTerminalView + TerminalSwiftUIView（PTY 桥接）
│       ├── ClaudeHookService.swift        # Claude 状态文件轮询（/tmp/splitmux/{tabID}）
│       ├── SettingsManager.swift          # UserDefaults 设置 + AppTheme 主题枚举（全量 design tokens）
│       ├── PersistenceService.swift       # Session/Tab/SplitNode JSON DTO 序列化
│       ├── SSHManagerService.swift        # SSH CRUD + ~/.ssh/config 解析
│       ├── TerminalHistoryService.swift   # 各 Tab TerminalHistory 实例注册表
│       └── NotificationService.swift     # macOS 通知权限 + Dock Badge 计数
```
