import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: 220)

            Divider()
                .overlay(Color(white: 0.15))

            // Keep all sessions alive, show only the selected one
            ZStack {
                ForEach(appState.sessions) { session in
                    TabContentView(session: session)
                        .opacity(session.id == appState.selectedSessionID ? 1 : 0)
                        .allowsHitTesting(session.id == appState.selectedSessionID)
                }

                if appState.sessions.isEmpty {
                    Color.black
                    Text("No Session")
                        .foregroundStyle(.secondary)
                        .font(.system(.title3, design: .monospaced))
                }
            }
        }
        .background(Color.black)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Clear current tab's notification when app becomes active
            if let session = appState.selectedSession, let tab = session.activeTab {
                tab.hasNotification = false
                tab.lastNotificationMessage = nil
                appState.updateDockBadge()
            }
        }
    }
}
