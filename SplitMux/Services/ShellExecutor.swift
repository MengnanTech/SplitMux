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

        return menu
    }

    @objc private func clearTerminal() {
        feed(text: "\u{0C}")  // Form feed (Ctrl+L)
    }

    // MARK: - Terminal Output Capture + Claude Detection

    /// Whether Claude Code has been detected in this terminal
    private var _claudeDetected: Bool = false
    /// Clean text buffer for detection (ANSI stripped, main-thread only)
    private var _cleanBuffer = ""
    private let _bufferLimit = 2000

    /// Intercept PTY output for history recording + Claude status detection
    override func dataReceived(slice: ArraySlice<UInt8>) {
        let data = Data(slice)
        onDataReceived?(data)

        // Convert to string and strip ANSI escape codes for detection
        if let raw = String(data: data, encoding: .utf8) {
            let clean = Self.stripANSI(raw)
            if !clean.isEmpty {
                DispatchQueue.main.async { [weak self] in
                    self?.processClaudeDetection(clean)
                }
            }
        }

        super.dataReceived(slice: slice)
    }

    /// Strip ANSI escape sequences from text
    private static func stripANSI(_ text: String) -> String {
        // Match: ESC[ ... letter, ESC] ... BEL/ST, ESC( ... char
        text.replacingOccurrences(
            of: "\u{1B}\\[[0-9;?]*[A-Za-z]|\u{1B}\\][^\u{07}\u{1B}]*(?:\u{07}|\u{1B}\\\\)|\u{1B}\\([A-Za-z]|\u{1B}[=>]",
            with: "",
            options: .regularExpression
        )
    }

    @MainActor
    private func processClaudeDetection(_ cleanText: String) {
        guard let delegate = sessionDelegate, let tab = delegate.tab else { return }

        // Accumulate clean buffer
        _cleanBuffer += cleanText
        if _cleanBuffer.count > _bufferLimit {
            _cleanBuffer = String(_cleanBuffer.suffix(_bufferLimit))
        }

        // Phase 1: Detect Claude Code startup
        if !_claudeDetected {
            // Look for Claude Code startup markers in accumulated buffer
            if _cleanBuffer.contains("Claude Code v")
                || _cleanBuffer.contains("for shortcuts")
                || _cleanBuffer.contains("(1M context)")
                || _cleanBuffer.contains("context)") {
                _claudeDetected = true
                tab.claudeStatus = .running
                writeStatusFile(tabID: tab.id, status: "running")
                print("[SplitMux] Claude Code detected in tab \(tab.id.uuidString.prefix(8))")
            }
            return
        }

        // Phase 2: Track status changes
        if cleanText.contains("for shortcuts") || cleanText.contains("❯") {
            // Claude is at its prompt, waiting for user input
            if tab.claudeStatus != .idle {
                tab.claudeStatus = .idle
                writeStatusFile(tabID: tab.id, status: "idle")
                print("[SplitMux] Claude status → idle")
            }
        } else if cleanText.contains("[Y/n]") || cleanText.contains("yes]")
                    || cleanText.contains("Allow once") || cleanText.contains("Allow always") {
            // Claude needs permission/confirmation
            if tab.claudeStatus != .needsInput {
                tab.claudeStatus = .needsInput
                writeStatusFile(tabID: tab.id, status: "needs-input")
                print("[SplitMux] Claude status → needs-input")
                // Send notification
                tab.hasNotification = true
                tab.lastNotificationMessage = "Claude Code — Needs Input"
                NotificationService.shared.send(
                    title: "Needs Input",
                    body: "Claude Code — Needs Input",
                    tabIsActive: delegate.isTabCurrentlyActive()
                )
            }
        } else {
            // Any other output = Claude is working
            let trimmed = cleanText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count > 3 && tab.claudeStatus == .idle {
                tab.claudeStatus = .running
                writeStatusFile(tabID: tab.id, status: "running")
                print("[SplitMux] Claude status → running")
            }
        }
    }

    private func writeStatusFile(tabID: UUID, status: String) {
        let path = "/tmp/splitmux/\(tabID.uuidString)"
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

        // Start Claude hook monitoring for this tab
        let tabRef = tab
        ClaudeHookService.shared.startMonitoring(tabID: tab.id) { [weak tabRef] status in
            guard let tab = tabRef else { return }
            tab.claudeStatus = status

            if status == .idle || status == .needsInput {
                tab.hasNotification = true
                let message = status == .idle ? "Claude Code — Completed" : "Claude Code — Needs Input"
                tab.lastNotificationMessage = message
                NotificationService.shared.send(
                    title: status == .idle ? "Task Completed" : "Needs Input",
                    body: message
                )
            }
        }

        return termView
    }

    func updateNSView(_ nsView: NotifyingTerminalView, context: Context) {
        // Apply live settings changes
        let settings = SettingsManager.shared
        nsView.updateFontSize(settings.fontSize, fontName: settings.fontName)
        nsView.applyTheme(settings.theme)
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
        let zshrc = """
        [ -f "\(home)/.zshrc" ] && source "\(home)/.zshrc"
        export PATH="\(wrapperBinPath):$PATH"
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
