import SwiftUI
import AppKit

/// Uses an NSPanel child window to float a zoom button above terminal NSViews.
/// NSPanel is the only reliable way to receive clicks over terminal views.
struct FloatingZoomButton: NSViewRepresentable {
    var onTap: () -> Void

    func makeNSView(context: Context) -> FloatingZoomAnchorView {
        let view = FloatingZoomAnchorView()
        view.onTap = onTap
        return view
    }

    func updateNSView(_ nsView: FloatingZoomAnchorView, context: Context) {
        nsView.onTap = onTap
        nsView.showPanel()
    }

    static func dismantleNSView(_ nsView: FloatingZoomAnchorView, coordinator: ()) {
        nsView.hidePanel()
    }
}

/// Invisible anchor view that manages the floating panel's lifecycle and position.
class FloatingZoomAnchorView: NSView {
    var onTap: (() -> Void)? {
        didSet { panel?.onTap = onTap }
    }
    private var panel: ZoomPanel?
    private var positionObserver: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            showPanel()
        } else {
            hidePanel()
        }
    }

    override func layout() {
        super.layout()
        updatePanelPosition()
    }

    func showPanel() {
        guard let parentWindow = window, panel == nil else {
            updatePanelPosition()
            return
        }

        let p = ZoomPanel()
        p.onTap = onTap
        parentWindow.addChildWindow(p, ordered: .above)
        panel = p

        // Track parent window movement
        positionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: parentWindow,
            queue: .main
        ) { [weak self] _ in
            self?.updatePanelPosition()
        }

        updatePanelPosition()
    }

    func hidePanel() {
        if let observer = positionObserver {
            NotificationCenter.default.removeObserver(observer)
            positionObserver = nil
        }
        if let p = panel {
            p.parent?.removeChildWindow(p)
            p.orderOut(nil)
            panel = nil
        }
    }

    private func updatePanelPosition() {
        guard let parentWindow = window, let panel = panel else { return }

        // Convert this view's top-right corner to screen coordinates
        let localPoint = NSPoint(x: bounds.maxX - 38, y: bounds.maxY - 10)
        let windowPoint = convert(localPoint, to: nil)
        let screenPoint = parentWindow.convertPoint(toScreen: windowPoint)

        panel.setFrameOrigin(screenPoint)
    }

    deinit {
        hidePanel()
    }
}

/// Borderless floating panel that holds the zoom button.
private class ZoomPanel: NSPanel {
    var onTap: (() -> Void)?
    private var isHovered = false

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 28, height: 28),
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

        let buttonView = ZoomButtonView(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        buttonView.panel = self
        contentView = buttonView
    }

    func handleTap() {
        onTap?()
    }
}

/// The actual button drawn inside the panel.
private class ZoomButtonView: NSView {
    weak var panel: ZoomPanel?
    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self
        )
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        NSCursor.pointingHand.push()
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        NSCursor.pop()
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        panel?.handleTap()
    }

    override func draw(_ dirtyRect: NSRect) {
        // Background
        let bgColor = isHovered
            ? NSColor.controlAccentColor.withAlphaComponent(0.3)
            : NSColor.controlAccentColor.withAlphaComponent(0.15)
        let path = NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6)
        bgColor.setFill()
        path.fill()

        // Icon
        guard let icon = NSImage(systemSymbolName: "arrow.down.right.and.arrow.up.left",
                                  accessibilityDescription: "Exit Zoom") else { return }
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        let configured = icon.withSymbolConfiguration(config) ?? icon

        // Tint
        let tinted = configured.copy() as! NSImage
        tinted.lockFocus()
        NSColor.controlAccentColor.set()
        NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
        tinted.unlockFocus()

        let iconSize = tinted.size
        let x = (bounds.width - iconSize.width) / 2
        let y = (bounds.height - iconSize.height) / 2
        tinted.draw(in: NSRect(x: x, y: y, width: iconSize.width, height: iconSize.height))
    }
}
