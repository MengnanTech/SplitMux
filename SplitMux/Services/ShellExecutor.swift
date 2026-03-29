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
    /// When true, the view's layer is non-opaque so glass blur shows through
    var glassMode = false

    override var isOpaque: Bool { !glassMode }

    override func makeBackingLayer() -> CALayer {
        let layer = super.makeBackingLayer()
        if glassMode {
            layer.isOpaque = false
        }
        return layer
    }

    var sessionDelegate: TerminalSessionDelegate?
    var cachedEnv: [String]?

    /// Callback for terminal output capture (history recording)
    var onDataReceived: ((Data) -> Void)?

    /// Callback when user clicks in this terminal pane (for split pane focus switching)
    var onPaneClicked: (() -> Void)?
    var onPaneDoubleClicked: (() -> Void)?
    nonisolated(unsafe) private var mouseMonitor: Any?

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
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
    }

    /// SSH host ID for auto-reconnect
    var sshHostID: UUID?
    var sshAutoReconnect: Bool = false
    var sshCommand: String?

    /// Cache last applied settings to avoid redundant updates that disrupt rendering
    var lastAppliedFontSize: CGFloat = 0
    var lastAppliedFontName: String = ""
    var lastAppliedThemeID: String = ""
    var lastAppliedGlassOpacity: Double = -1

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
        glassMode = false
        self.nativeBackgroundColor = Self.terminalBackgroundColor(for: theme)
        self.nativeForegroundColor = theme.terminalForeground

        if theme == .glassLight {
            // Light-optimized ANSI palette: dark-themed TUIs often paint panels
            // with ANSI black backgrounds. In glassLight we remap those fills to
            // a muted shell tone so terminal apps don't force the whole pane dark.
            // Order: black, red, green, yellow, blue, magenta, cyan, white,
            //        bright black, bright red, bright green, bright yellow,
            //        bright blue, bright magenta, bright cyan, bright white
            let c = { (r: UInt16, g: UInt16, b: UInt16) in
                SwiftTerm.Color(red: r &* 257, green: g &* 257, blue: b &* 257)
            }
            let palette: [SwiftTerm.Color] = [
                c(158, 170, 186),   // black -> lifted shell gray for TUI backgrounds
                c(198,  63,  67),   // red — warm brick
                c( 74, 131,  79),   // green — forest
                c(173, 125,  17),   // yellow — amber
                c( 69, 120, 191),   // blue — cobalt
                c(150,  89, 153),   // magenta — plum
                c( 54, 137, 138),   // cyan — teal
                c(242, 245, 248),   // white
                c(110, 122, 138),   // bright black
                c(215,  83,  87),   // bright red
                c( 96, 150, 102),   // bright green
                c(196, 149,  33),   // bright yellow
                c( 92, 143, 214),   // bright blue
                c(172, 111, 175),   // bright magenta
                c( 75, 160, 162),   // bright cyan
                c(255, 255, 255),   // bright white
            ]
            installColors(palette)
        }
    }

    private static func terminalBackgroundColor(for theme: AppTheme) -> NSColor {
        guard theme.isGlass else { return theme.terminalBackground }
        // SwiftTerm's internal Color has no alpha — it converts any
        // NSColor to solid RGB for per-cell background drawing.
        // So true transparency is impossible. Instead we use solid
        // colors that visually match the frosted glass aesthetic.
        switch theme {
        case .glassLight:
            return NSColor(calibratedRed: 0.905, green: 0.92, blue: 0.945, alpha: 1.0)
        case .glass:
            return NSColor(calibratedRed: 0.13, green: 0.14, blue: 0.18, alpha: 1.0)
        default:
            return theme.terminalBackground
        }
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

/// Container that hosts an optional NSVisualEffectView (glass blur)
/// behind the terminal, so the frosted glass effect shows through
/// SwiftTerm's transparent background.
class TerminalContainerView: NSView {
    private static let blurID = NSUserInterfaceItemIdentifier("terminal.glass.blur")
    private static let tintID = NSUserInterfaceItemIdentifier("terminal.glass.tint")
    private static let glazeID = NSUserInterfaceItemIdentifier("terminal.glass.glaze")

    func installGlass(
        material: NSVisualEffectView.Material,
        blendingMode: NSVisualEffectView.BlendingMode,
        appearance: NSAppearance?,
        tintColor: NSColor,
        glazeColor: NSColor
    ) {
        // Set appearance on the container itself so all children inherit it
        self.appearance = appearance

        if let existing = subviews.first(where: { $0.identifier == Self.blurID }) as? NSVisualEffectView {
            existing.material = material
            existing.blendingMode = blendingMode
            existing.appearance = appearance
        } else {
            let blur = NSVisualEffectView()
            blur.identifier = Self.blurID
            blur.material = material
            blur.blendingMode = blendingMode
            blur.state = .active
            blur.appearance = appearance
            blur.translatesAutoresizingMaskIntoConstraints = false
            addSubview(blur, positioned: .below, relativeTo: subviews.first)
            NSLayoutConstraint.activate([
                blur.topAnchor.constraint(equalTo: topAnchor),
                blur.bottomAnchor.constraint(equalTo: bottomAnchor),
                blur.leadingAnchor.constraint(equalTo: leadingAnchor),
                blur.trailingAnchor.constraint(equalTo: trailingAnchor),
            ])
        }

        if let tintView = subviews.first(where: { $0.identifier == Self.tintID }) {
            tintView.wantsLayer = true
            tintView.layer?.backgroundColor = tintColor.cgColor
            tintView.appearance = appearance
            return
        }

        let tintView = NSView()
        tintView.identifier = Self.tintID
        tintView.wantsLayer = true
        tintView.layer?.backgroundColor = tintColor.cgColor
        tintView.translatesAutoresizingMaskIntoConstraints = false
        tintView.appearance = appearance
        if let blurView = subviews.first(where: { $0.identifier == Self.blurID }) {
            addSubview(tintView, positioned: .above, relativeTo: blurView)
        } else {
            addSubview(tintView, positioned: .below, relativeTo: subviews.first)
        }
        NSLayoutConstraint.activate([
            tintView.topAnchor.constraint(equalTo: topAnchor),
            tintView.bottomAnchor.constraint(equalTo: bottomAnchor),
            tintView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tintView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        if let glazeView = subviews.first(where: { $0.identifier == Self.glazeID }) {
            glazeView.wantsLayer = true
            glazeView.layer?.backgroundColor = glazeColor.cgColor
            glazeView.appearance = appearance
            return
        }

        let glazeView = MousePassthroughOverlayView()
        glazeView.identifier = Self.glazeID
        glazeView.wantsLayer = true
        glazeView.layer?.backgroundColor = glazeColor.cgColor
        glazeView.translatesAutoresizingMaskIntoConstraints = false
        glazeView.appearance = appearance
        if let terminalView = subviews.first(where: { $0 is NotifyingTerminalView }) {
            addSubview(glazeView, positioned: .above, relativeTo: terminalView)
        } else {
            addSubview(glazeView, positioned: .above, relativeTo: subviews.last)
        }
        NSLayoutConstraint.activate([
            glazeView.topAnchor.constraint(equalTo: topAnchor),
            glazeView.bottomAnchor.constraint(equalTo: bottomAnchor),
            glazeView.leadingAnchor.constraint(equalTo: leadingAnchor),
            glazeView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    func removeBlur() {
        subviews.first(where: { $0.identifier == Self.blurID })?.removeFromSuperview()
        subviews.first(where: { $0.identifier == Self.tintID })?.removeFromSuperview()
        subviews.first(where: { $0.identifier == Self.glazeID })?.removeFromSuperview()
    }
}

final class MousePassthroughOverlayView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

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

    func makeNSView(context: Context) -> TerminalContainerView {
        let container = TerminalContainerView()

        // If tab already has a live terminal view (e.g. view recreated by SwiftUI
        // during split mode change), reuse it to preserve process & detection state
        if let existing = tab.terminalView as? NotifyingTerminalView {
            existing.sessionDelegate = context.coordinator
            context.coordinator.tab = tab
            context.coordinator.appState = appState
            existing.installClickMonitor()
            // Re-parent into new container
            existing.removeFromSuperview()
            existing.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(existing)
            NSLayoutConstraint.activate([
                existing.topAnchor.constraint(equalTo: container.topAnchor),
                existing.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                existing.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                existing.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            ])
            Self.applyGlassBlur(to: container)
            return container
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
        termView.lastAppliedGlassOpacity = settings.glassOpacity
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

        // Add terminal into container
        termView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(termView)
        NSLayoutConstraint.activate([
            termView.topAnchor.constraint(equalTo: container.topAnchor),
            termView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            termView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            termView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        Self.applyGlassBlur(to: container)

        return container
    }

    func updateNSView(_ nsView: TerminalContainerView, context: Context) {
        guard let termView = nsView.subviews.compactMap({ $0 as? NotifyingTerminalView }).first else { return }
        // Only apply settings when values actually changed — avoids redundant
        // font/theme resets that can disrupt terminal rendering mid-output
        let settings = SettingsManager.shared
        if termView.lastAppliedFontSize != settings.fontSize || termView.lastAppliedFontName != settings.fontName {
            termView.updateFontSize(settings.fontSize, fontName: settings.fontName)
            termView.lastAppliedFontSize = settings.fontSize
            termView.lastAppliedFontName = settings.fontName
        }
        let themeID = settings.theme.rawValue
        if termView.lastAppliedThemeID != themeID || termView.lastAppliedGlassOpacity != settings.glassOpacity {
            termView.applyTheme(settings.theme)
            termView.lastAppliedThemeID = themeID
            termView.lastAppliedGlassOpacity = settings.glassOpacity
            Self.applyGlassBlur(to: nsView)
        }
    }

    private static func applyGlassBlur(to container: TerminalContainerView) {
        container.removeBlur()
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
