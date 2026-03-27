import Foundation

@Observable
class AppState {
    var sessions: [Session] = []
    var selectedSessionID: UUID?

    var selectedSession: Session? {
        sessions.first { $0.id == selectedSessionID }
    }

    init() {
        // Default session — no custom name, will show "~"
        let mainSession = Session()
        let tab1 = Tab(title: "zsh", icon: "terminal", content: .terminal)
        mainSession.addTab(tab1)

        sessions = [mainSession]
        selectedSessionID = mainSession.id
    }

    func addSession(workingDirectory: String? = nil) {
        let session = Session(workingDirectory: workingDirectory)
        let tab = Tab(title: "zsh", icon: "terminal", content: .terminal)
        session.addTab(tab)
        sessions.append(session)
        selectedSessionID = session.id
    }

    func removeSession(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        if selectedSessionID == id {
            selectedSessionID = sessions.first?.id
        }
    }

    @MainActor
    func updateDockBadge() {
        let count = sessions.flatMap(\.tabs).filter(\.hasNotification).count
        NotificationService.shared.updateDockBadge(count: count)
    }
}
