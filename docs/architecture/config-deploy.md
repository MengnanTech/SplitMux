# SplitMux — 构建与发布流程

## 项目文件

- `project.yml`：XcodeGen 配置，定义：
  - 目标平台：macOS 15.0
  - Swift 版本：6.0（`SWIFT_STRICT_CONCURRENCY: complete`）
  - Bundle ID：`com.levi.SplitMux`
  - SPM 依赖：SwiftTerm 1.2.0+、Sparkle 2.6.0+
  - `SUFeedURL`：`https://raw.githubusercontent.com/MengnanTech/SplitMux/main/appcast.xml`
  - `SUPublicEDKey`：`EbZeL4SmTBcud40r+8WuD4aFqK02Bl/DFeKYOHHClb8=`
  - App Sandbox：**禁用**（允许 shell 进程 + SSH 访问文件系统）
  - `DEVELOPMENT_TEAM`：2XGP34AR96

- `.xcodeproj`：由 XcodeGen 从 project.yml 生成，不直接编辑

---

## Sparkle 自动更新机制

### 工作流

1. App 启动时，`SPUStandardUpdaterController(startingUpdater: true)` 自动检查更新
2. Sparkle 从 `SUFeedURL` 拉取 `appcast.xml`（托管在 GitHub raw）
3. 比较 `sparkle:version`（build number）与当前版本
4. 验证 `sparkle:edSignature`（Ed25519 签名，私钥在开发机 Keychain）
5. 满足 `sparkle:minimumSystemVersion` 时提示用户更新

### appcast.xml 结构

```xml
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
  <channel>
    <title>SplitMux</title>
    <item>
      <title>1.0.7</title>
      <pubDate>Tue, 31 Mar 2026 02:14:21 +0800</pubDate>
      <sparkle:version>9</sparkle:version>                    <!-- build number -->
      <sparkle:shortVersionString>1.0.7</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
      <enclosure
        url="https://github.com/MengnanTech/SplitMux/releases/download/v1.0.7/SplitMux-1.0.7.dmg"
        length="3682172"
        type="application/octet-stream"
        sparkle:edSignature="..."/>
    </item>
  </channel>
</rss>
```

appcast.xml 仅保留最新版本（单 item），由发版脚本自动生成并 push 到 main 分支。

---

## 一键发版脚本：`scripts/build-and-notarize.sh`

### 用法

```bash
./scripts/build-and-notarize.sh [patch|minor|major|x.y.z]
# 默认 patch（如 1.0.6 → 1.0.7）
```

### 完整流程（按执行顺序）

| 步骤 | 操作 | 说明 |
|---|---|---|
| 1 | 自动 bump 版本 | 读取 project.yml 中 `MARKETING_VERSION` 和 `CURRENT_PROJECT_VERSION`，自动递增 |
| 2 | 确认提示 | 交互确认（可通过 `SKIP_CONFIRM=1` 跳过） |
| 3 | git commit | `chore: bump version to x.y.z (build N)` |
| 4 | xcodegen | 从 project.yml 重新生成 .xcodeproj |
| 5 | Clean build dir | 清理 `build/` 目录 |
| 6 | xcodebuild archive | Release 构建，输出 `build/SplitMux.xcarchive` |
| 7 | 手动 codesign | 先签名所有嵌套 frameworks/dylibs（deepest-first），再签名主 App（`--options runtime --timestamp`） |
| 8 | codesign --verify | 验证签名完整性 |
| 9 | xattr -cr | 清除 provenance xattr（hdiutil 要求） |
| 10 | create-dmg | 创建 drag-to-install DMG（带窗口布局和 App icon） |
| 11 | xcrun notarytool submit | 提交公证（`--wait` 等待完成），使用 Keychain profile `SplitMux-Notary` |
| 12 | xcrun stapler staple | 将公证票据 staple 到 DMG |
| 13 | generate_appcast | Sparkle 工具生成 appcast.xml（含 EdDSA 签名） |
| 14 | gh release create | 在 GitHub 创建 Release，上传 `SplitMux-x.y.z.dmg` |
| 15 | git commit appcast.xml | `chore: update appcast.xml for vx.y.z`，push 到 main |

### 关键配置

```bash
KEYCHAIN_PROFILE="SplitMux-Notary"      # xcrun notarytool 凭证 profile
TEAM_ID="2XGP34AR96"
SIGNING_IDENTITY="Developer ID Application: DENG LI (2XGP34AR96)"
GITHUB_REPO="MengnanTech/SplitMux"
```

### codesign 签名顺序（重要）

深度优先：先签名嵌套的 XPC service / framework / dylib，再签名主 App bundle。逆序会导致主 App 签名无效（因嵌套组件签名后会改变主 bundle 哈希）。

```bash
find "$APP_DST" -depth \( -name "*.dylib" -o -type d \( -name "*.framework" -o -name "*.xpc" -o -name "*.app" \) \) ...
codesign ... "$component"   # 先签内层
codesign --force --deep ... "$APP_DST"  # 再签主 App
```

### 发布后 URLs

- GitHub Release：`https://github.com/MengnanTech/SplitMux/releases/tag/vx.y.z`
- DMG 下载：`https://github.com/MengnanTech/SplitMux/releases/download/vx.y.z/SplitMux-x.y.z.dmg`
- Appcast：`https://raw.githubusercontent.com/MengnanTech/SplitMux/main/appcast.xml`

---

## Claude Code Hook 集成（运行时）

### 机制

Claude Code wrapper 脚本位于 `SplitMux.app/Contents/Resources/bin/claude`，在每个终端 Tab 的 PATH 最高优先级。

环境变量注入（`TerminalSwiftUIView.makeNSView`）：

```bash
SPLITMUX_TAB_ID="{tabID-UUID}"          # 用于定位状态文件
__SPLITMUX_BIN="{app bundle}/Resources/bin"  # wrapper bin 路径
ZDOTDIR="/tmp/splitmux-zsh-{PID}"       # 覆盖 zsh dotfiles 加载顺序，确保 wrapper PATH 最优先
```

Wrapper 在 Claude Code 生命周期事件时写入：
```
/tmp/splitmux/{SPLITMUX_TAB_ID}  →  "running" | "idle" | "needs-input"
```

`ClaudeHookService` 每 0.5 秒轮询，驱动 UI 更新。

---

## 构建依赖

| 工具 | 用途 | 安装 |
|---|---|---|
| Xcode 26.0 | 编译 | App Store |
| xcodegen | project.yml → .xcodeproj | `brew install xcodegen` |
| create-dmg | 创建 DMG | `brew install create-dmg` |
| gh CLI | GitHub Release | `brew install gh` |
| Sparkle generate_appcast | 生成 appcast + 签名 | 编译 Xcode 项目后在 DerivedData 中 |
| xcrun notarytool | Apple 公证 | 随 Xcode 附带，需配置 Keychain profile |
