import AppKit
import SwiftUI

/// Top-centered floating agent capsule rendered in a child NSPanel.
struct AgentIslandOverlay: NSViewRepresentable {
    let snapshot: AgentIslandSnapshot?
    var onTap: () -> Void

    func makeNSView(context: Context) -> AgentIslandAnchorView {
        let view = AgentIslandAnchorView()
        view.snapshot = snapshot
        view.onTap = onTap
        return view
    }

    func updateNSView(_ nsView: AgentIslandAnchorView, context: Context) {
        nsView.snapshot = snapshot
        nsView.onTap = onTap
        nsView.syncPanel()
    }

    static func dismantleNSView(_ nsView: AgentIslandAnchorView, coordinator: ()) {
        nsView.hidePanel()
    }
}

final class AgentIslandAnchorView: NSView {
    var snapshot: AgentIslandSnapshot?
    var onTap: (() -> Void)?

    nonisolated(unsafe) private var panel: AgentIslandPanel?
    nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeObservers()

        guard let window else {
            hidePanel()
            return
        }

        installObservers(for: window)
        syncPanel()
    }

    override func layout() {
        super.layout()
        updatePanelPosition()
    }

    func syncPanel() {
        guard let parentWindow = window else { return }

        if observers.isEmpty {
            installObservers(for: parentWindow)
        }

        guard let snapshot else {
            hidePanel()
            return
        }

        let panel = panel ?? makePanel(parentWindow: parentWindow)
        panel.onTap = onTap
        panel.update(snapshot: snapshot)
        panel.orderFront(nil)
        updatePanelPosition()
    }

    func hidePanel() {
        removeObservers()
        if let panel {
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
            self.panel = nil
        }
    }

    private func makePanel(parentWindow: NSWindow) -> AgentIslandPanel {
        let panel = AgentIslandPanel()
        panel.onTap = onTap
        parentWindow.addChildWindow(panel, ordered: .above)
        self.panel = panel
        return panel
    }

    private func installObservers(for window: NSWindow) {
        let names: [Notification.Name] = [
            NSWindow.didMoveNotification,
            NSWindow.didResizeNotification,
            NSWindow.didChangeScreenNotification,
            NSWindow.didBecomeKeyNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification
        ]

        observers = names.map { name in
            NotificationCenter.default.addObserver(
                forName: name,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.syncPanel()
                }
            }
        }
    }

    private func removeObservers() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }

    private func updatePanelPosition() {
        guard let parentWindow = window, let panel else { return }

        let size = panel.frame.size
        let x = parentWindow.frame.midX - (size.width / 2.0)
        let y = parentWindow.frame.maxY - size.height - 14
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    deinit {
        let observerRefs = observers
        observers.removeAll()
        observerRefs.forEach(NotificationCenter.default.removeObserver)

        let panelRef = panel
        panel = nil

        MainActor.assumeIsolated {
            if let panelRef {
                panelRef.parent?.removeChildWindow(panelRef)
                panelRef.orderOut(nil)
            }
        }
    }
}

private final class AgentIslandPanel: NSPanel {
    var onTap: (() -> Void)?

    private let hostingView = NSHostingView(rootView: AgentIslandCapsuleView(snapshot: nil, onTap: {}))

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 58),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        ignoresMouseEvents = false
        isMovableByWindowBackground = false
        collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]

        contentView = hostingView
    }

    func update(snapshot: AgentIslandSnapshot) {
        hostingView.rootView = AgentIslandCapsuleView(snapshot: snapshot, onTap: { [weak self] in
            self?.handleTap()
        })
        let size = hostingView.fittingSize
        setContentSize(size)
        contentView?.frame = NSRect(origin: .zero, size: size)
    }

    private func handleTap() {
        onTap?()
    }
}

private struct AgentIslandCapsuleView: View {
    let snapshot: AgentIslandSnapshot?
    let onTap: () -> Void

    @State private var isHovered = false

    private var theme: AppTheme { SettingsManager.shared.theme }

    var body: some View {
        if let snapshot {
            HStack(spacing: 12) {
                ZStack {
                    Capsule()
                        .fill(accentColor(for: snapshot).opacity(0.18))
                        .frame(width: 34, height: 26)

                    Image(systemName: snapshot.symbolName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(accentColor(for: snapshot))
                        .symbolEffect(.pulse.byLayer, options: .repeating, value: snapshot.isAnimating)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.headline)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)

                    Text(secondaryLine(for: snapshot))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text("\(snapshot.agentCount)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.primaryText)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(theme.isGlass ? 0.12 : 0.08))
                    )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(width: 320)
            .background(capsuleBackground)
            .scaleEffect(isHovered ? 1.015 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.82), value: isHovered)
            .onTapGesture(perform: onTap)
            .onHover { isHovered = $0 }
        }
    }

    private var capsuleBackground: some View {
        Capsule()
            .fill(.ultraThinMaterial)
            .overlay(
                Capsule()
                    .fill(theme.chromeSurfaceBackground.opacity(theme.isGlass ? 0.78 : 0.9))
            )
            .overlay(
                Capsule()
                    .stroke(theme.subtleBorder.opacity(0.5), lineWidth: 0.6)
            )
            .shadow(color: .black.opacity(theme.isGlass ? 0.22 : 0.14), radius: 16, y: 8)
    }

    private func accentColor(for snapshot: AgentIslandSnapshot) -> Color {
        switch snapshot.emphasis {
        case .error:
            return .red
        case .needsInput:
            return .orange
        case .running:
            return theme.accentColor
        case .idle:
            return theme.secondaryText
        }
    }

    private func secondaryLine(for snapshot: AgentIslandSnapshot) -> String {
        if snapshot.contextLine.isEmpty {
            return snapshot.summaryLine
        }
        return "\(snapshot.contextLine) · \(snapshot.summaryLine)"
    }
}
