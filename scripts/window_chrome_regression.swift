import AppKit
import Foundation

@main
struct WindowChromeRegression {
    @MainActor
    static func main() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.toolbar = NSToolbar(identifier: "regression-toolbar")
        window.titlebarSeparatorStyle = .automatic
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false

        WindowChromeConfigurator.apply(to: window)

        precondition(window.toolbar == nil, "Expected toolbar to be removed")
        precondition(window.titlebarSeparatorStyle == .none, "Expected title bar separator to be hidden")
        precondition(window.titleVisibility == .hidden, "Expected title to be hidden")
        precondition(window.titlebarAppearsTransparent, "Expected title bar to be transparent")
        precondition(window.styleMask.contains(.fullSizeContentView), "Expected fullSizeContentView style")
        precondition(window.isMovableByWindowBackground, "Expected drag-by-background to stay enabled")
        precondition(window.standardWindowButton(.closeButton) != nil, "Expected close button to remain available")
        precondition(window.standardWindowButton(.miniaturizeButton) != nil, "Expected minimize button to remain available")
        precondition(window.standardWindowButton(.zoomButton) != nil, "Expected zoom button to remain available")

        let appFile = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("SplitMux/App/SplitMuxApp.swift")
        let appSource = try! String(contentsOf: appFile, encoding: .utf8)
        precondition(!appSource.contains(".windowStyle(.hiddenTitleBar)"), "Expected app to avoid hiddenTitleBar window style so traffic lights stay visible")
    }
}
