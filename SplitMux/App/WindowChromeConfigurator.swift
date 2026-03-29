import AppKit
import SwiftUI

enum WindowChromeConfigurator {
    private static let blurID = "splitmux.glass.blur"

    @MainActor
    static func apply(to window: NSWindow) {
        window.toolbar = nil
        window.titlebarSeparatorStyle = .none
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        if !window.styleMask.contains(.fullSizeContentView) {
            window.styleMask.insert(.fullSizeContentView)
        }
        window.isMovableByWindowBackground = false

        applyGlassIfNeeded(to: window)
    }

    @MainActor
    static func applyGlassIfNeeded(to window: NSWindow) {
        let isGlass = SettingsManager.shared.theme.isGlass

        if isGlass {
            window.isOpaque = false
            window.backgroundColor = .clear

            // Replace contentView with NSVisualEffectView wrapping the SwiftUI hosting view
            if let currentContent = window.contentView,
               !(currentContent is NSVisualEffectView) {

                let blurView = NSVisualEffectView()
                blurView.identifier = NSUserInterfaceItemIdentifier(blurID)
                blurView.material = .fullScreenUI
                blurView.blendingMode = .behindWindow
                blurView.state = .active

                // Move SwiftUI hosting view into the blur view
                currentContent.removeFromSuperview()
                currentContent.translatesAutoresizingMaskIntoConstraints = false
                blurView.addSubview(currentContent)
                NSLayoutConstraint.activate([
                    currentContent.topAnchor.constraint(equalTo: blurView.topAnchor),
                    currentContent.bottomAnchor.constraint(equalTo: blurView.bottomAnchor),
                    currentContent.leadingAnchor.constraint(equalTo: blurView.leadingAnchor),
                    currentContent.trailingAnchor.constraint(equalTo: blurView.trailingAnchor),
                ])

                window.contentView = blurView
            }

            // Make SwiftUI views transparent so blur shows through
            if let contentView = window.contentView {
                makeTransparent(contentView)
            }
            for delay in [0.1, 0.3, 0.8, 1.5] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    if let contentView = window.contentView {
                        self.makeTransparent(contentView)
                    }
                }
            }
        } else {
            window.isOpaque = true
            window.backgroundColor = NSColor.windowBackgroundColor

            // Restore: move SwiftUI hosting view back out of blur view
            if let blurView = window.contentView as? NSVisualEffectView,
               let hostingView = blurView.subviews.first {
                hostingView.removeFromSuperview()
                window.contentView = hostingView
            }
        }
    }

    private static func makeTransparent(_ view: NSView) {
        // Skip the blur view itself
        if view.identifier?.rawValue == blurID { return }

        view.wantsLayer = true
        view.layer?.backgroundColor = .clear
        view.layer?.isOpaque = false
        if let scrollView = view as? NSScrollView {
            scrollView.drawsBackground = false
        }
        for subview in view.subviews {
            makeTransparent(subview)
        }
    }
}

// MARK: - Window Drag Area

struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowDragNSView {
        WindowDragNSView()
    }

    func updateNSView(_ nsView: WindowDragNSView, context: Context) {}
}

class WindowDragNSView: NSView {
    override public var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}
