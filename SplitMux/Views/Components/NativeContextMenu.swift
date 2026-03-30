import SwiftUI
import AppKit

// MARK: - Native Right-Click Menu (avoids SwiftUI .contextMenu icon flicker)
//
// Transparent overlay that only intercepts right-clicks via hitTest filtering.
// All other events (left-click, drag, hover) pass through to SwiftUI below.
// Uses NSMenu.popUpContextMenu — standard AppKit context menu, no flicker.

struct NativeContextMenu: NSViewRepresentable {
    let menuBuilder: () -> NSMenu

    func makeNSView(context: Context) -> RightClickView {
        RightClickView(menuBuilder: menuBuilder)
    }

    func updateNSView(_ nsView: RightClickView, context: Context) {
        nsView.menuBuilder = menuBuilder
    }

    final class RightClickView: NSView {
        var menuBuilder: () -> NSMenu

        init(menuBuilder: @escaping () -> NSMenu) {
            self.menuBuilder = menuBuilder
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard NSApp.currentEvent?.type == .rightMouseDown else { return nil }
            return super.hitTest(point)
        }

        override func rightMouseDown(with event: NSEvent) {
            NSMenu.popUpContextMenu(menuBuilder(), with: event, for: self)
        }
    }
}

// MARK: - NSMenu closure helper

class MenuAction: NSObject {
    let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    @objc func invoke() { handler() }
}

extension NSMenu {
    @discardableResult
    func addActionItem(_ title: String, image: String, enabled: Bool = true, handler: @escaping () -> Void) -> NSMenuItem {
        let target = MenuAction(handler)
        let item = NSMenuItem(title: title, action: #selector(MenuAction.invoke), keyEquivalent: "")
        item.target = target
        item.representedObject = target
        item.image = NSImage(systemSymbolName: image, accessibilityDescription: nil)
        item.isEnabled = enabled
        addItem(item)
        return item
    }
}
