import Foundation
import AppKit
import SwiftUI
import SwiftTerm

// MARK: - Terminal Delegate

class TerminalSessionDelegate: NSObject, LocalProcessTerminalViewDelegate, @unchecked Sendable {
    var tabTitle: String
    weak var tab: Tab?
    weak var appState: AppState?
    private var lastPromptTime: Date = Date()
    private var commandStartTime: Date?

    var notifyThreshold: TimeInterval = 5
    var suppressNextNotification = false

    init(tabTitle: String) {
        self.tabTitle = tabTitle
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        let oldTitle = tabTitle
        tabTitle = title

        let isShellPrompt = title.contains("zsh") || title.contains("bash") || title.contains("-zsh")
        let wasRunningCommand = !oldTitle.contains("zsh") && !oldTitle.contains("bash") && !oldTitle.contains("-zsh") && !oldTitle.isEmpty

        if isShellPrompt && wasRunningCommand, let start = commandStartTime {
            let elapsed = Date().timeIntervalSince(start)
            if suppressNextNotification {
                suppressNextNotification = false
            } else if elapsed >= notifyThreshold {
                let msg = "\(oldTitle) — \(Self.formatDuration(elapsed))"
                notify(message: msg, title: "Command Finished")
            }
            commandStartTime = nil
        } else if !isShellPrompt && commandStartTime == nil {
            commandStartTime = Date()
        }
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastPromptTime)

        if suppressNextNotification {
            suppressNextNotification = false
        } else if elapsed >= notifyThreshold {
            let dir = directory.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "terminal"
            let msg = "\(tabTitle) in \(dir) — \(Self.formatDuration(elapsed))"
            notify(message: msg, title: "Command Finished")
        }

        lastPromptTime = now
        commandStartTime = nil
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        // Reset Claude detection on process exit
        if let termView = source as? NotifyingTerminalView {
            termView.claudeDetected = false
            termView.recentOutput = ""
        }

        let msg = "\(tabTitle) exited (\(exitCode ?? 0))"
        notify(message: msg, title: "Process Exited")

        // SSH auto-reconnect
        if let termView = source as? NotifyingTerminalView,
           termView.sshAutoReconnect,
           let sshCmd = termView.sshCommand {
            Task { @MainActor in
                // Update SSH host state
                if let hostID = termView.sshHostID {
                    SSHManagerService.shared.host(for: hostID)?.connectionState = .disconnected
                }
                // Wait 3 seconds then reconnect
                try? await Task.sleep(for: .seconds(3))
                if let hostID = termView.sshHostID {
                    SSHManagerService.shared.host(for: hostID)?.connectionState = .connecting
                }
                self.suppressNextNotification = true
                let bytes = Array((sshCmd + "\n").utf8)
                termView.send(data: bytes[...])
            }
        }
    }

    /// Unified notification — marks tab, sends system notification with smart suppression, updates dock badge
    private func notify(message: String, title: String) {
        Task { @MainActor [weak self] in
            guard let self, let tab = self.tab else { return }

            // Mark tab notification state
            tab.hasNotification = true
            tab.lastNotificationMessage = message

            // Smart suppression: is this tab currently active + visible?
            let tabIsActive = self.isTabActive()

            // Send (will suppress to beep-only if tab is active + app focused)
            NotificationService.shared.send(
                title: title,
                body: message,
                tabIsActive: tabIsActive
            )

            // Update dock badge
            if let appState = self.appState {
                let total = appState.sessions.flatMap(\.tabs).filter(\.hasNotification).count
                NotificationService.shared.updateDockBadge(count: total)
            }
        }
    }

    @MainActor
    private func isTabActive() -> Bool {
        return isTabCurrentlyActive()
    }

    @MainActor
    func isTabCurrentlyActive() -> Bool {
        guard let tab, let appState else { return false }
        guard let session = appState.sessions.first(where: { $0.tabs.contains(where: { $0.id == tab.id }) }) else { return false }
        return session.id == appState.selectedSessionID && session.activeTabID == tab.id
    }

    private static func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "\(Int(seconds))s"
        } else if seconds < 3600 {
            return "\(Int(seconds / 60))m \(Int(seconds.truncatingRemainder(dividingBy: 60)))s"
        } else {
            return "\(Int(seconds / 3600))h \(Int((seconds / 60).truncatingRemainder(dividingBy: 60)))m"
        }
    }
}

// MARK: - Custom Terminal View (bell notification + search + font + history capture)

class NotifyingTerminalView: LocalProcessTerminalView {
    var sessionDelegate: TerminalSessionDelegate?
    var cachedEnv: [String]?

    /// Callback for terminal output capture (history recording)
    var onDataReceived: ((Data) -> Void)?

    /// SSH host ID for auto-reconnect
    var sshHostID: UUID?
    var sshAutoReconnect: Bool = false
    var sshCommand: String?

    /// Cache last applied settings to avoid redundant updates that disrupt rendering
    var lastAppliedFontSize: CGFloat = 0
    var lastAppliedFontName: String = ""
    var lastAppliedThemeID: String = ""

    // MARK: - Search

    @discardableResult
    func searchTerminal(query: String, backward: Bool = false) -> Bool {
        guard !query.isEmpty else { return false }
        if backward {
            return self.findPrevious(query)
        } else {
            return self.findNext(query)
        }
    }

    // MARK: - Font Size

    func updateFontSize(_ size: CGFloat, fontName: String) {
        if let customFont = NSFont(name: fontName, size: size) {
            self.font = customFont
        } else {
            self.font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        }
    }

    // MARK: - Theme

    func applyTheme(_ theme: AppTheme) {
        self.nativeBackgroundColor = theme.terminalBackground
        self.nativeForegroundColor = theme.terminalForeground
    }

    // MARK: - Right-click context menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let hasSelection = getSelection() != nil

        let copyItem = NSMenuItem(title: "Copy", action: #selector(copy(_:)), keyEquivalent: "")
        copyItem.target = self
        copyItem.isEnabled = hasSelection
        menu.addItem(copyItem)

        let pasteItem = NSMenuItem(title: "Paste", action: #selector(paste(_:)), keyEquivalent: "")
        pasteItem.target = self
        pasteItem.isEnabled = NSPasteboard.general.string(forType: .string) != nil
        menu.addItem(pasteItem)

        menu.addItem(.separator())

        let selectAllItem = NSMenuItem(title: "Select All", action: #selector(selectAll(_:)), keyEquivalent: "")
        selectAllItem.target = self
        menu.addItem(selectAllItem)

        menu.addItem(.separator())

        let clearItem = NSMenuItem(title: "Clear", action: #selector(clearTerminal), keyEquivalent: "")
        clearItem.target = self
        menu.addItem(clearItem)

        menu.addItem(.separator())

        let newTabItem = NSMenuItem(title: "New Tab", action: #selector(newTabAction), keyEquivalent: "")
        newTabItem.target = self
        menu.addItem(newTabItem)

        let splitRightItem = NSMenuItem(title: "Split Right", action: #selector(splitRightAction), keyEquivalent: "")
        splitRightItem.target = self
        menu.addItem(splitRightItem)

        let splitDownItem = NSMenuItem(title: "Split Down", action: #selector(splitDownAction), keyEquivalent: "")
        splitDownItem.target = self
        menu.addItem(splitDownItem)

        return menu
    }

    @objc private func newTabAction() {
        guard let delegate = sessionDelegate, let appState = delegate.appState,
              let session = appState.sessions.first(where: { $0.tabs.contains(where: { $0.id == delegate.tab?.id }) }) else { return }
        let tab = Tab(title: "zsh", icon: "terminal", content: .terminal)
        session.addTab(tab)
    }

    @objc private func splitRightAction() {
        guard let delegate = sessionDelegate, let appState = delegate.appState,
              let session = appState.sessions.first(where: { $0.tabs.contains(where: { $0.id == delegate.tab?.id }) }) else { return }
        session.splitActiveTab(direction: .right)
    }

    @objc private func splitDownAction() {
        guard let delegate = sessionDelegate, let appState = delegate.appState,
              let session = appState.sessions.first(where: { $0.tabs.contains(where: { $0.id == delegate.tab?.id }) }) else { return }
        session.splitActiveTab(direction: .down)
    }

    @objc private func clearTerminal() {
        feed(text: "\u{0C}")  // Form feed (Ctrl+L)
    }

    // MARK: - Terminal Output Capture + Claude Detection

    /// Claude Code detected in this terminal (reset on process exit)
    var claudeDetected = false
    /// Sliding window of recent clean text for pattern matching
    var recentOutput = ""
    /// Debug log file handle (temporary — remove after verification)
    private static let debugLog: FileHandle? = {
        let path = "/tmp/splitmux-debug.log"
        FileManager.default.createFile(atPath: path, contents: nil)
        return FileHandle(forWritingAtPath: path)
    }()

    private static func log(_ msg: String) {
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(msg)\n"
        debugLog?.seekToEndOfFile()
        debugLog?.write(line.data(using: .utf8) ?? Data())
    }

    /// ANSI escape code stripping regex — handles CSI, OSC, DCS, character sets, keypad, cursor save/restore
    private static let ansiRegex = try! NSRegularExpression(pattern: [
        "\u{1B}\\[[0-9;:?]*[A-Za-z]",                                   // CSI sequences (incl. colon-separated SGR)
        "\u{1B}\\][^\u{07}\u{1B}]*(?:\u{07}|\u{1B}\\\\)",               // OSC sequences
        "\u{1B}P[^\u{1B}]*\u{1B}\\\\",                                  // DCS sequences
        "\u{1B}[()][A-Za-z]",                                           // Character set designation
        "\u{1B}[=>78]",                                                  // Keypad mode + cursor save/restore
        "\u{1B}#[0-9]",                                                  // Double-width/height lines
    ].joined(separator: "|"))

    /// Strip ANSI escape codes from terminal output
    private static func stripAnsi(_ raw: String) -> String {
        let range = NSRange(raw.startIndex..., in: raw)
        return ansiRegex.stringByReplacingMatches(in: raw, range: range, withTemplate: "")
    }

    /// Collapse runs of whitespace (2+ spaces) to single space for window efficiency
    private static func compactWhitespace(_ s: String) -> String {
        s.replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)
    }

    /// Intercept PTY output for history recording + Claude detection
    override func dataReceived(slice: ArraySlice<UInt8>) {
        let data = Data(slice)
        onDataReceived?(data)

        // Claude detection from terminal output
        // Use lenient UTF-8 decoding — chunk boundaries often split multi-byte chars
        let raw = String(decoding: data, as: UTF8.self)
        let clean = Self.stripAnsi(raw)

        // Call detectClaude directly — dataReceived is already on main queue
        if !clean.isEmpty {
            detectClaude(clean)
        }

        super.dataReceived(slice: slice)
    }

    private func detectClaude(_ text: String) {
        guard let delegate = sessionDelegate else {
            Self.log("detectClaude: no sessionDelegate")
            return
        }
        guard let tab = delegate.tab else {
            Self.log("detectClaude: delegate.tab is nil")
            return
        }

        // Compact whitespace before adding to window — TUI apps fill rows with spaces
        // which would otherwise flood the window and push out actual text
        let compact = Self.compactWhitespace(text)
        recentOutput = String((recentOutput + compact).suffix(2000))

        // Step 1: Detect Claude startup — "Claude Code" followed by version
        if !claudeDetected {
            if recentOutput.range(of: #"Claude Code v\d+\.\d+"#, options: .regularExpression) != nil {
                claudeDetected = true
                tab.claudeStatus = .running
                writeStatus(tab: tab, status: "running")
                Self.log("✅ Claude DETECTED! tab=\(tab.id.uuidString.prefix(8)) → .running")
            } else if compact.contains("claude") || compact.contains("Claude") {
                let preview = String(recentOutput.suffix(300)).replacingOccurrences(of: "\n", with: "\\n")
                Self.log("detectClaude: has 'claude' but no version match. tail=\(preview)")
            }
            return
        }

        // Step 2: Track status transitions
        let isActive = delegate.isTabCurrentlyActive() && NSApp.isActive
        let prev = tab.claudeStatus

        // Claude-specific idle indicator (not a generic shell prompt)
        let isIdle = recentOutput.contains("? for shortcuts")
        let needsInput = text.contains("[Y/n]") || text.contains("Allow once") || text.contains("Allow always")

        if needsInput {
            if prev != .needsInput {
                tab.claudeStatus = .needsInput
                writeStatus(tab: tab, status: "needs-input")
                Self.log("Claude → needs-input")
            }
        } else if isIdle && (prev == .running || prev == .needsInput) {
            // Transition: running/needsInput → idle = task completed
            tab.claudeStatus = .idle
            writeStatus(tab: tab, status: "idle")
            Self.log("Claude → idle (prev=\(prev?.rawValue ?? "nil"), isActive=\(isActive))")
            if prev == .running && !isActive {
                tab.hasNotification = true
                tab.lastNotificationMessage = "Claude Code — Task Completed"
                NotificationService.shared.send(
                    title: "Task Completed",
                    body: "Claude Code — Task Completed",
                    tabIsActive: false
                )
            }
        } else if !isIdle && prev == .idle {
            // User sent new message → Claude working again
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count > 5 {
                tab.claudeStatus = .running
                writeStatus(tab: tab, status: "running")
                // Clear window so old "? for shortcuts" doesn't re-trigger idle
                recentOutput = ""
                Self.log("Claude → running (new message)")
            }
        }
    }

    private func writeStatus(tab: Tab, status: String) {
        let path = "/tmp/splitmux/\(tab.id.uuidString)"
        try? status.write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// Restart the shell process in a new working directory without visible `cd` command
    func restartProcess(in directory: String) {
        terminate()
        terminal.resetToInitialState()

        let env: [String]
        if let cached = cachedEnv {
            env = cached
        } else {
            var envDict = ProcessInfo.processInfo.environment
            let home = envDict["HOME"] ?? NSHomeDirectory()
            let extraPaths = [
                "\(home)/.local/bin",
                "\(home)/.cargo/bin",
                "/opt/homebrew/bin",
                "/usr/local/bin"
            ]
            let currentPath = envDict["PATH"] ?? "/usr/bin:/bin"
            envDict["PATH"] = (extraPaths + [currentPath]).joined(separator: ":")
            envDict["TERM"] = "xterm-256color"
            envDict["LANG"] = "en_US.UTF-8"
            env = envDict.map { "\($0.key)=\($0.value)" }
        }

        var dir = directory
        var isDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: dir, isDirectory: &isDir) || !isDir.boolValue {
            dir = NSHomeDirectory()
        }

        startProcess(
            executable: "/bin/zsh",
            args: ["-l"],
            environment: env,
            execName: "-zsh",
            currentDirectory: dir
        )
    }

    override func bell(source: Terminal) {
        super.bell(source: source)
        Task { @MainActor in
            guard let delegate = self.sessionDelegate, let tab = delegate.tab else { return }
            // Only notify if tab is NOT active (user is looking at another tab/app)
            let tabIsActive = delegate.appState.flatMap { appState in
                appState.sessions.first(where: { $0.tabs.contains(where: { $0.id == tab.id }) })
                    .map { $0.id == appState.selectedSessionID && $0.activeTabID == tab.id }
            } ?? false

            if !tabIsActive || !NSApp.isActive {
                tab.hasNotification = true
                tab.lastNotificationMessage = "Bell — \(delegate.tabTitle)"
                NotificationService.shared.send(
                    title: "Terminal Bell",
                    body: delegate.tabTitle,
                    tabIsActive: tabIsActive
                )
            }
        }
    }
}

// MARK: - SwiftUI Wrapper

struct TerminalSwiftUIView: NSViewRepresentable {
    let workingDirectory: String
    let tab: Tab
    let appState: AppState

    init(workingDirectory: String? = nil, tab: Tab, appState: AppState) {
        self.workingDirectory = workingDirectory
            ?? FileManager.default.homeDirectoryForCurrentUser.path
        self.tab = tab
        self.appState = appState
    }

    func makeCoordinator() -> TerminalSessionDelegate {
        let delegate = TerminalSessionDelegate(tabTitle: tab.title)
        delegate.tab = tab
        delegate.appState = appState
        delegate.notifyThreshold = SettingsManager.shared.notifyThresholdSeconds
        return delegate
    }

    func makeNSView(context: Context) -> NotifyingTerminalView {
        let termView = NotifyingTerminalView(frame: .zero)
        termView.focusRingType = .none
        termView.sessionDelegate = context.coordinator
        tab.terminalView = termView

        let settings = SettingsManager.shared
        termView.applyTheme(settings.theme)
        termView.updateFontSize(settings.fontSize, fontName: settings.fontName)
        termView.lastAppliedFontSize = settings.fontSize
        termView.lastAppliedFontName = settings.fontName
        termView.lastAppliedThemeID = settings.theme.rawValue
        termView.processDelegate = context.coordinator

        var env = ProcessInfo.processInfo.environment
        let home = env["HOME"] ?? NSHomeDirectory()

        // Claude/Codex hook wrapper path (inside app bundle)
        let wrapperBinPath = Bundle.main.resourcePath.map { $0 + "/bin" } ?? ""

        let extraPaths = [
            "\(home)/.local/bin",
            "\(home)/.cargo/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin"
        ]
        let currentPath = env["PATH"] ?? "/usr/bin:/bin"
        env["PATH"] = (extraPaths + [currentPath]).joined(separator: ":")
        env["TERM"] = "xterm-256color"
        env["LANG"] = "en_US.UTF-8"

        // SplitMux env vars for Claude hook integration
        env["SPLITMUX_TAB_ID"] = tab.id.uuidString
        env["__SPLITMUX_BIN"] = wrapperBinPath

        // Create ZDOTDIR with custom .zshrc that ensures wrapper PATH
        // survives all shell profile sourcing
        let zdotdir = Self.createZdotdir(wrapperBinPath: wrapperBinPath, home: home)
        env["ZDOTDIR"] = zdotdir

        let envPairs = env.map { "\($0.key)=\($0.value)" }
        termView.cachedEnv = envPairs

        var dir = workingDirectory
        var isDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: dir, isDirectory: &isDir) || !isDir.boolValue {
            dir = home
        }

        // Wire up terminal output history recording
        let history = TerminalHistoryService.shared.history(for: tab.id)
        termView.onDataReceived = { data in
            MainActor.assumeIsolated {
                history.append(data: data)
            }
        }

        // SSH terminal: start zsh then feed ssh command
        if case .sshTerminal(let hostID) = tab.content {
            termView.sshHostID = hostID
            if let host = SSHManagerService.shared.host(for: hostID) {
                termView.sshAutoReconnect = host.autoReconnect
                termView.sshCommand = host.sshCommand
                host.connectionState = .connecting
                host.connectedTabID = tab.id
            }
        }

        termView.startProcess(
            executable: "/bin/zsh",
            args: ["-l"],
            environment: envPairs,
            execName: "-zsh",
            currentDirectory: dir
        )

        // For SSH tabs, send the ssh command to the shell process
        if case .sshTerminal(let hostID) = tab.content {
            if let host = SSHManagerService.shared.host(for: hostID) {
                // Suppress the "command finished" notification for auto-typed SSH commands
                context.coordinator.suppressNextNotification = true
                // Small delay to let shell initialize, then type the command
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    let bytes = Array((host.sshCommand + "\n").utf8)
                    termView.send(data: bytes[...])
                    MainActor.assumeIsolated {
                        host.connectionState = .connected
                    }
                }
            }
        }

        // Start Claude hook monitoring for this tab (status file based — updates status only, no notifications)
        let tabRef = tab
        ClaudeHookService.shared.startMonitoring(tabID: tab.id) { [weak tabRef] status in
            guard let tab = tabRef else { return }
            tab.claudeStatus = status
        }

        return termView
    }

    func updateNSView(_ nsView: NotifyingTerminalView, context: Context) {
        // Only apply settings when values actually changed — avoids redundant
        // font/theme resets that can disrupt terminal rendering mid-output
        let settings = SettingsManager.shared
        if nsView.lastAppliedFontSize != settings.fontSize || nsView.lastAppliedFontName != settings.fontName {
            nsView.updateFontSize(settings.fontSize, fontName: settings.fontName)
            nsView.lastAppliedFontSize = settings.fontSize
            nsView.lastAppliedFontName = settings.fontName
        }
        let themeID = settings.theme.rawValue
        if nsView.lastAppliedThemeID != themeID {
            nsView.applyTheme(settings.theme)
            nsView.lastAppliedThemeID = themeID
        }
        context.coordinator.notifyThreshold = settings.notifyThresholdSeconds
    }

    /// Create a temporary ZDOTDIR that forwards to user dotfiles,
    /// then prepends our wrapper bin to PATH after all profile sourcing.
    private static func createZdotdir(wrapperBinPath: String, home: String) -> String {
        let zdotdir = NSTemporaryDirectory() + "splitmux-zsh-\(ProcessInfo.processInfo.processIdentifier)"
        try? FileManager.default.createDirectory(atPath: zdotdir, withIntermediateDirectories: true)

        // .zshenv — sourced first for ALL shells
        let zshenv = """
        [ -f "\(home)/.zshenv" ] && source "\(home)/.zshenv"
        """

        // .zprofile — sourced for login shells, after .zshenv
        let zprofile = """
        [ -f "\(home)/.zprofile" ] && source "\(home)/.zprofile"
        """

        // .zshrc — sourced for interactive shells, after .zprofile
        // Prepend wrapper bin AFTER all user config so it survives PATH reordering
        // Enable shared history across all SplitMux tabs
        let zshrc = """
        [ -f "\(home)/.zshrc" ] && source "\(home)/.zshrc"
        export PATH="\(wrapperBinPath):$PATH"
        export HISTFILE="\(home)/.zsh_history"
        setopt SHARE_HISTORY
        setopt INC_APPEND_HISTORY
        """

        // .zlogin — sourced last for login shells
        let zlogin = """
        [ -f "\(home)/.zlogin" ] && source "\(home)/.zlogin"
        """

        try? zshenv.write(toFile: zdotdir + "/.zshenv", atomically: true, encoding: .utf8)
        try? zprofile.write(toFile: zdotdir + "/.zprofile", atomically: true, encoding: .utf8)
        try? zshrc.write(toFile: zdotdir + "/.zshrc", atomically: true, encoding: .utf8)
        try? zlogin.write(toFile: zdotdir + "/.zlogin", atomically: true, encoding: .utf8)

        return zdotdir
    }
}
