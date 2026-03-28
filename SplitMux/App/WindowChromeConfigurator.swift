import AppKit

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
        window.isMovableByWindowBackground = true
    }
}
