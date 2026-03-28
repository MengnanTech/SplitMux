import AppKit
import SwiftUI

enum WindowChromeConfigurator {
    @MainActor
    static func apply(to window: NSWindow) {
        window.toolbar = nil
        window.titlebarSeparatorStyle = .none
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        if !window.styleMask.contains(.fullSizeContentView) {
            window.styleMask.insert(.fullSizeContentView)
        }
        // Do NOT set isMovableByWindowBackground = true — it makes the entire
        // window background a drag region, preventing terminal text selection,
        // sidebar divider dragging, and split pane divider resizing.
        // The native title bar area is still draggable with fullSizeContentView.
        window.isMovableByWindowBackground = false
    }
}

// MARK: - Window Drag Area

/// NSView that acts as a window drag region (like a title bar).
/// Use as a SwiftUI background on areas that should allow window dragging
/// (sidebar header, empty tab bar space) without affecting content interaction.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowDragNSView {
        WindowDragNSView()
    }

    func updateNSView(_ nsView: WindowDragNSView, context: Context) {}
}

class WindowDragNSView: NSView {
    override public var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        // Initiate window move via the standard title bar mechanism
        window?.performDrag(with: event)
    }
}
