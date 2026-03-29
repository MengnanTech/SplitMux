import Foundation
import AppKit
import SwiftUI
import SwiftTerm

// MARK: - Terminal Delegate

class TerminalSessionDelegate: NSObject, LocalProcessTerminalViewDelegate, @unchecked Sendable {
    var tabTitle: String
    weak var tab: Tab?
    weak var appState: AppState?

    var suppressNextNotification = false
    private var reconnectTask: Task<Void, Never>?

    init(tabTitle: String) {
        self.tabTitle = tabTitle
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        tabTitle = title
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        // Title update only — no notifications
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        if let termView = source as? NotifyingTerminalView {
            // Cancel any pending reconnect before starting a new one
            reconnectTask?.cancel()
            reconnectTask = Task { @MainActor [weak self, weak termView] in
                guard let termView else { return }
                // Clear Claude status on process exit
                if let tab = self?.tab {
                    tab.claudeStatus = nil
                    let path = "/tmp/splitmux/\(tab.id.uuidString)"
                    try? "".write(toFile: path, atomically: true, encoding: .utf8)
                }

                // SSH auto-reconnect
                guard termView.sshAutoReconnect,
                      let sshCmd = termView.sshCommand else { return }

                // Update SSH host state
                if let hostID = termView.sshHostID {
                    SSHManagerService.shared.host(for: hostID)?.connectionState = .disconnected
                }
                // Wait 3 seconds then reconnect
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                if let hostID = termView.sshHostID {
                    SSHManagerService.shared.host(for: hostID)?.connectionState = .connecting
                }
                self?.suppressNextNotification = true
                let bytes = Array((sshCmd + "\n").utf8)
                termView.send(data: bytes[...])
            }
        }
    }

    @MainActor
    func isTabCurrentlyActive() -> Bool {
        guard let tab, let appState else { return false }
        guard let session = appState.sessions.first(where: { $0.tabs.contains(where: { $0.id == tab.id }) }) else { return false }
        return session.id == appState.selectedSessionID && session.activeTabID == tab.id
    }
}

// MARK: - Custom Terminal View (bell notification + search + font + history capture)

class NotifyingTerminalView: LocalProcessTerminalView {
    var sessionDelegate: TerminalSessionDelegate?
    var cachedEnv: [String]?

    /// Callback for terminal output capture (history recording)
    var onDataReceived: ((Data) -> Void)?

    /// Callback when user clicks in this terminal pane (for split pane focus switching)
    var onPaneClicked: (() -> Void)?
    var onPaneDoubleClicked: (() -> Void)?
    private var mouseMonitor: Any?

    func installClickMonitor() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self = self, let eventWindow = event.window,
                  eventWindow == self.window else { return event }
            // Use hitTest from the window's contentView to find the actual
            // frontmost view at the click point — this respects z-order and
            // ignores hidden/zero-opacity views
            let windowPoint = event.locationInWindow
            guard let hitView = eventWindow.contentView?.hitTest(windowPoint),
                  hitView === self || hitView.isDescendant(of: self)
            else { return event }
            self.onPaneClicked?()
            if event.clickCount == 2 {
                self.onPaneDoubleClicked?()
            }
            return event
        }
    }

    func removeClickMonitor() {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
    }

    deinit {
        removeClickMonitor()
    }

    /// SSH host ID for auto-reconnect
    var sshHostID: UUID?
    var sshAutoReconnect: Bool = false
    var sshCommand: String?

    /// Cache last applied settings to avoid redundant updates that disrupt rendering
    var lastAppliedFontSize: CGFloat = 0
    var lastAppliedFontName: String = ""
    var lastAppliedThemeID: String = ""

    /// Deferred process start — waits until the view has a real frame so the PTY
    /// reports correct terminal dimensions (columns/rows) to child processes.
    /// We hook into setFrameSize because that's where SwiftTerm calls
    /// processSizeChange() which updates terminal.cols/rows from the frame.
    private var pendingProcessStart: (() -> Void)?
    private var processStarted = false

    func deferProcessStart(_ start: @escaping () -> Void) {
        pendingProcessStart = start
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if let start = pendingProcessStart, !processStarted, newSize.width > 0, newSize.height > 0 {
            pendingProcessStart = nil
            processStarted = true
            start()
        }
    }

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
        menu.autoenablesItems = false
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
        selectAllItem.isEnabled = true
        menu.addItem(selectAllItem)

        menu.addItem(.separator())

        let clearItem = NSMenuItem(title: "Clear", action: #selector(clearTerminal), keyEquivalent: "")
        clearItem.target = self
        clearItem.isEnabled = true
        menu.addItem(clearItem)

        menu.addItem(.separator())

        let newTabItem = NSMenuItem(title: "New Tab", action: #selector(newTabAction), keyEquivalent: "")
        newTabItem.target = self
        newTabItem.isEnabled = true
        menu.addItem(newTabItem)

        let splitRightItem = NSMenuItem(title: "Split Right", action: #selector(splitRightAction), keyEquivalent: "")
        splitRightItem.target = self
        splitRightItem.isEnabled = true
        menu.addItem(splitRightItem)

        let splitDownItem = NSMenuItem(title: "Split Down", action: #selector(splitDownAction), keyEquivalent: "")
        splitDownItem.target = self
        splitDownItem.isEnabled = true
        menu.addItem(splitDownItem)

        return menu
    }

    @objc private func newTabAction() {
        guard let delegate = sessionDelegate, let appState = delegate.appState,
              let session = appState.sessions.first(where: { $0.tabs.contains(where: { $0.id == delegate.tab?.id }) }) else { return }
        let tab = session.createTab()
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

    // MARK: - Terminal Output Capture

    /// Intercept PTY output for history recording
    override func dataReceived(slice: ArraySlice<UInt8>) {
        let data = Data(slice)
        onDataReceived?(data)
        super.dataReceived(slice: slice)
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
            envDict["TERM_PROGRAM"] = "SplitMux"
            envDict["COLORTERM"] = "truecolor"
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
        // No notification — only Claude Code task completion triggers notifications
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
        return delegate
    }

    func makeNSView(context: Context) -> NotifyingTerminalView {
        // If tab already has a live terminal view (e.g. view recreated by SwiftUI
        // during split mode change), reuse it to preserve process & detection state
        if let existing = tab.terminalView as? NotifyingTerminalView {
            existing.sessionDelegate = context.coordinator
            context.coordinator.tab = tab
            context.coordinator.appState = appState
            existing.installClickMonitor()
            return existing
        }

        let termView = NotifyingTerminalView(frame: .zero)
        termView.focusRingType = .none
        // Set default cursor to steady bar before process starts
        termView.feed(text: "\u{1B}[6 q")
        termView.sessionDelegate = context.coordinator
        tab.terminalView = termView

        // Switch active pane on click (for split pane mode)
        let tabID = tab.id
        let tabRef2 = tab
        termView.onPaneClicked = { [weak appState, weak tabRef2] in
            guard let appState = appState, let clickedTab = tabRef2,
                  let session = appState.sessions.first(where: { $0.tabs.contains(where: { $0.id == tabID }) })
            else { return }

            // Clear notification on click regardless of split mode
            if clickedTab.hasNotification {
                clickedTab.hasNotification = false
                clickedTab.lastNotificationMessage = nil
                appState.updateDockBadge()
            }

            // Switch active pane in split mode
            guard let splitRoot = session.splitRoot,
                  splitRoot.tabIDs.contains(tabID),
                  session.activeTabID != tabID
            else { return }
            session.activeTabID = tabID
        }
        termView.onPaneDoubleClicked = { [weak appState] in
            guard let appState = appState,
                  let session = appState.sessions.first(where: { $0.tabs.contains(where: { $0.id == tabID }) }),
                  session.splitRoot != nil
            else { return }
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.2)) {
                    session.activeTabID = tabID
                    session.toggleZoom()
                }
            }
        }
        termView.installClickMonitor()

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
        env["TERM_PROGRAM"] = "SplitMux"
        env["COLORTERM"] = "truecolor"
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
        history.terminalView = termView
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

        // Defer process start until the view has a real frame so the PTY
        // reports correct terminal dimensions to child processes (e.g. Claude Code
        // needs >= 70 columns to render its bordered welcome layout).
        let sshContent = tab.content
        let coordinator = context.coordinator
        termView.deferProcessStart { [weak termView] in
            guard let termView = termView else { return }
            termView.startProcess(
                executable: "/bin/zsh",
                args: ["-l"],
                environment: envPairs,
                execName: "-zsh",
                currentDirectory: dir
            )

            // For SSH tabs, send the ssh command to the shell process
            if case .sshTerminal(let hostID) = sshContent {
                if let host = SSHManagerService.shared.host(for: hostID) {
                    coordinator.suppressNextNotification = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        let bytes = Array((host.sshCommand + "\n").utf8)
                        termView.send(data: bytes[...])
                        MainActor.assumeIsolated {
                            host.connectionState = .connected
                        }
                    }
                }
            }
        }

        // Start Claude hook monitoring — the status file is the sole source of truth.
        // Claude's wrapper script (bin/claude) injects hooks that write status directly
        // to /tmp/splitmux/{tabID} on lifecycle events (UserPromptSubmit, Stop, Notification).
        let tabRef = tab
        let coordRef = context.coordinator
        ClaudeHookService.shared.startMonitoring(tabID: tab.id) { [weak tabRef, weak coordRef] status in
            guard let tab = tabRef else { return }
            let prev = tab.claudeStatus
            tab.claudeStatus = status

            // Fire notifications on meaningful transitions when tab is not active
            guard let delegate = coordRef else { return }
            let isActive = delegate.isTabCurrentlyActive() && NSApp.isActive

            if status == .needsInput && prev != .needsInput && !isActive {
                tab.hasNotification = true
                tab.lastNotificationMessage = "Claude Code — Needs Input"
                NotificationService.shared.send(
                    title: "Needs Input",
                    body: "Claude Code — Waiting for approval",
                    tabIsActive: false
                )
                Self.postToastNotification(tab: tab, appState: delegate.appState)
            } else if status == .idle && prev == .running && !isActive {
                tab.hasNotification = true
                tab.lastNotificationMessage = "Claude Code — Task Completed"
                NotificationService.shared.send(
                    title: "Task Completed",
                    body: "Claude Code — Task Completed",
                    tabIsActive: false
                )
                Self.postToastNotification(tab: tab, appState: delegate.appState)
            }
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
    }

    /// Post in-app toast notification for Claude status changes
    private static func postToastNotification(tab: Tab, appState: AppState?) {
        var info: [String: Any] = [
            "tabID": tab.id,
            "tabTitle": tab.title,
            "message": tab.lastNotificationMessage ?? ""
        ]
        if let appState,
           let session = appState.sessions.first(where: { $0.tabs.contains(where: { $0.id == tab.id }) }) {
            info["sessionID"] = session.id
            info["sessionName"] = session.name
        }
        NotificationCenter.default.post(name: .tabNotification, object: nil, userInfo: info)
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
        # Set cursor to steady bar (DECSCUSR 6)
        echo -ne '\\e[6 q'
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
