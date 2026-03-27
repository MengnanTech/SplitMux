import SwiftUI

@main
struct SplitMuxApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .preferredColorScheme(.dark)
                .onAppear {
                    NotificationService.shared.requestPermission()
                }
        }
    }
}
