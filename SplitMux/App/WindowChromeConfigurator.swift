import AppKit
import SwiftTerm
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

        let theme = SettingsManager.shared.theme

        if isGlass {
            window.isOpaque = false
            window.backgroundColor = .clear
            // Set window appearance so ALL NSVisualEffectViews render
            // in the correct light/dark mode regardless of system setting
            window.appearance = NSAppearance(named: theme == .glassLight ? .aqua : .darkAqua)

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

            // Make SwiftUI hosting views transparent so blur shows through
            // sidebar/tabbar areas. Terminal views are skipped — they manage
            // their own near-opaque themed background.
            if let contentView = window.contentView {
                makeTransparent(contentView)
            }
            // Re-apply once after SwiftUI finishes its initial layout pass
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if let contentView = window.contentView {
                    self.makeTransparent(contentView)
                }
            }
        } else {
            window.isOpaque = true
            window.backgroundColor = NSColor.windowBackgroundColor
            window.appearance = nil  // Follow system

            // Restore: move SwiftUI hosting view back out of blur view
            if let blurView = window.contentView as? NSVisualEffectView,
               let hostingView = blurView.subviews.first {
                hostingView.removeFromSuperview()
                window.contentView = hostingView
            }
        }
    }

    @MainActor
    private static func makeTransparent(_ view: NSView) {
        // Skip terminal container — it manages its own glass layers
        // (blur + tint + glaze). Recursing into it would clear them.
        if view is TerminalContainerView { return }

        // Skip SwiftTerm terminal views
        if view is LocalProcessTerminalView { return }

        // Don't clear NSVisualEffectView backgrounds, but still recurse children
        if view is NSVisualEffectView {
            for subview in view.subviews {
                makeTransparent(subview)
            }
            return
        }

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
