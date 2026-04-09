# SplitMux — Bug 修复记录与排查指南

## Bug 修复历史（从 git log 提取）

---

### BUG-01：Claude 状态检测 hook 未生效

- **现象**：运行 Claude Code 后，侧边栏和分屏角标始终不显示状态（running/needs-input/idle）
- **根因**：wrapper bin 路径未注入到 zsh PATH，或 ZDOTDIR 加载顺序导致用户 `.zshrc` 覆盖了 PATH
- **解决**：创建临时 ZDOTDIR，在用户 `.zshrc` source 完毕后追加 `export PATH="$wrapperBinPath:$PATH"`，确保 wrapper 始终优先
- **Commit**：f93984c
- **教训**：PATH 注入必须在所有用户 shell 配置加载完成之后执行，否则用户配置会重置 PATH

---

### BUG-02：Terminal History 乱码 + Tab 命名问题

- **现象**：历史面板显示乱码 ANSI 序列；新建 Tab 名称出现重复编号
- **根因**：历史录制直接拼接原始 PTY 字节（含 ANSI 转义码）；Tab 编号逻辑未正确统计已有编号
- **解决**：历史显示改为从 `SwiftTerm.Terminal.getBufferAsData()` 读取已渲染文本（ANSI 已处理）；Tab 编号改为遍历所有已有 title 提取最大编号
- **Commit**：153de65
- **教训**：终端输出必须经过 VT 解释器处理后才能用于文本展示；自增编号需考虑中间删除的情况

---

### BUG-03：Info.plist 版本硬编码导致 Sparkle 更新不生效

- **现象**：发版后 Sparkle 不提示更新，尽管 appcast.xml 已更新
- **根因**：`Info.plist` 中 `CFBundleShortVersionString` 和 `CFBundleVersion` 被硬编码为旧版本，`project.yml` 中的版本变量未传递到实际 bundle
- **解决**：在 `project.yml` 的 info properties 中使用 `"$(MARKETING_VERSION)"` 和 `"$(CURRENT_PROJECT_VERSION)"` 引用构建变量，确保版本号从 project.yml 单点管理
- **Commit**：719ac50
- **教训**：Info.plist 版本字段必须使用 xcconfig 变量引用，不能硬编码；发版后应验证 bundle `CFBundleVersion` 是否正确

---

### BUG-04：多个 UI 和逻辑问题（v1.0.2）

- **现象**：多处 UI 渲染异常、逻辑错误（具体描述见 commit）
- **Commit**：430386b
- **教训**：发版前需全量验证核心交互路径

---

### BUG-05：Claude Code 退出后侧边栏仍显示"Idle"

- **现象**：Claude Code 进程退出后，Session 状态仍显示 Idle 而非恢复正常终端状态
- **根因**：进程退出时未清除 `/tmp/splitmux/{tabID}` 文件内容，`ClaudeHookService` 仍读到旧的 "idle" 值
- **解决**：在 `TerminalSessionDelegate.processTerminated` 中清空状态文件（写入空字符串），并将 `tab.claudeStatus` 置 nil；`ClaudeHookService.checkStatusFile` 在文件为空/不存在时触发 callback(nil) 清除状态
- **Commit**：4383855（逻辑）/ 6241183（exit status check）
- **教训**：Hook 文件是状态的 source of truth，进程退出必须主动清空；空文件和文件不存在需等价处理

---

### BUG-06：侧边栏 Session 状态丢失

- **现象**：切换 Session 或 SwiftUI 重建后，侧边栏的 Claude 状态（running/needs-input）消失
- **根因**：侧边栏直接读取 `tab.claudeStatus`，但 SwiftUI 重建 View 时 `@Observable` 订阅断开，导致状态不同步
- **解决**：侧边栏改为从 `ClaudeHookService.agentInfos` 读取（全局单例不受 View 重建影响），`agentInfos` 作为状态 source of truth
- **Commit**：30c247c
- **教训**：跨 View 共享的状态应放在 Service 单例，而非依赖 View 的 @Observable 订阅链；View 重建会断开 `@Observable` 的 withObservationTracking 订阅

---

### BUG-07：title bar 遮挡终端内容

- **现象**：全尺寸内容区（fullSizeContentView）配置后，终端内容被 title bar 遮挡
- **根因**：SwiftUI 在窗口获得焦点或某些状态变化时会重置 `styleMask`，使 `fullSizeContentView` 标志丢失
- **解决**：用 KVO 监听 `window.styleMask` 和 `window.toolbar` 的变化，每次变化后立即重新调用 `WindowChromeConfigurator.apply(to:)`；用 `isApplying` 标志防止递归触发
- **Commit**：d00073d
- **教训**：SwiftUI 的 NSWindow 配置极不稳定，任何需要持久化的 NSWindow 属性都必须用 KVO 守护；`WindowConfiguratorView` 的 `viewDidMoveToWindow` 是最可靠的注册时机

---

### BUG-08：Tab 拖动重排失效 + codesign 签名顺序错误

- **现象**：拖动 Tab 重排时顺序不正确或无响应；公证后 DMG 内 App 签名验证失败
- **根因**：Tab 拖拽逻辑未正确处理 drop 位置计算；codesign 先签主 App 再签内层 framework，导致内层签名后主 App 哈希失效
- **解决**：修正拖拽 delegate 逻辑；发版脚本改为 `find -depth` 深度优先签名嵌套组件，最后签主 App
- **Commit**：d00073d / 155966e
- **教训**：多组件 bundle 的 codesign 必须严格遵循"从内到外"顺序；签名后务必 `codesign --verify --deep --strict` 验证

---

### BUG-09：override intrinsicContentSize 破坏窗口缩放（已回滚）

- **现象**：尝试通过 override `intrinsicContentSize` 允许窗口缩小，但引入了窗口尺寸异常
- **根因**：SwiftUI 对 NSWindow 最小尺寸的控制与自定义 intrinsicContentSize 冲突
- **解决**：直接回滚该 commit，改用其他方式处理窗口尺寸约束
- **Commit**：2272dd4（引入）/ c77b536（回滚）
- **教训**：在 SwiftUI 托管的 NSWindow 中 override intrinsicContentSize 风险高；优先使用 `.frame(minWidth:minHeight:)` 等 SwiftUI 原生约束

---

## 常见排查路径

### Claude 状态不更新

1. 检查 `/tmp/splitmux/` 目录是否存在对应 tabID 文件
2. 检查 `which claude` 是否指向 SplitMux wrapper（应在 app bundle Resources/bin 下）
3. 确认 `SPLITMUX_TAB_ID` 环境变量在终端中可见（`echo $SPLITMUX_TAB_ID`）
4. 检查 `ClaudeHookService.pollTimers` 是否注册了对应 tabID

### 分屏布局恢复失败

1. 检查 `~/Library/Application Support/SplitMux/sessions.json` 中 `splitLayout.tabID` 是否与 `tabs[].id` 一致
2. `PersistenceService.dtoToSession` 会校验所有 split tabID 必须存在于 session.tabs 中，且数量 >= 2

### 窗口样式被重置（title bar 重新出现）

1. 查看 `WindowConfiguratorView` 的 KVO 是否正确绑定（`viewDidMoveToWindow` 是否触发）
2. 确认 `isApplying` 标志防止无限循环

### SSH 连接无法自动重连

1. 检查 `SSHHost.autoReconnect` 是否为 true
2. 检查 `processTerminated` 中的 `sshAutoReconnect` 标志
3. 自动重连等待 3 秒，Task 可能被 cancel（Tab 关闭时）

### Sparkle 不提示更新

1. 确认 `SUFeedURL` 指向正确的 raw GitHub URL
2. 确认 `appcast.xml` 中的 `sparkle:version`（build number）大于当前 App 的 build number
3. 确认 App bundle 中的 `CFBundleVersion` 使用了构建变量而非硬编码
4. 检查 EdDSA 签名：`sparkle:edSignature` 必须与私钥匹配
