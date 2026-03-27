import Foundation

@MainActor
@Observable
class AppState {
    var sessions: [Session] = []
    var selectedSessionID: UUID?

    var selectedSession: Session? {
        sessions.first { $0.id == selectedSessionID }
    }

    /// Standard init — starts with default, restore happens in onAppear
    init() {
        setupDefault()
    }

    /// Empty init for PersistenceService to populate
    init(empty: Bool) {
        // Intentionally left empty
    }

    /// Restore saved state (call from MainActor context, e.g. onAppear)
    func restoreIfNeeded() {
        guard SettingsManager.shared.restoreSessionsOnLaunch,
              let restored = PersistenceService.shared.load() else { return }
        self.sessions = restored.sessions
        self.selectedSessionID = restored.selectedSessionID
    }

    private func setupDefault() {
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
        scheduleSave()
    }

    func removeSession(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        if selectedSessionID == id {
            selectedSessionID = sessions.first?.id
        }
        scheduleSave()
    }

    func updateDockBadge() {
        let count = sessions.flatMap(\.tabs).filter(\.hasNotification).count
        NotificationService.shared.updateDockBadge(count: count)
    }

    // MARK: - Persistence

    private var saveTimer: Timer?

    /// Debounced save — avoids rapid writes during bulk operations
    func scheduleSave() {
        saveTimer?.invalidate()
        let appState = self
        saveTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { _ in
            MainActor.assumeIsolated {
                PersistenceService.shared.save(appState)
            }
        }
    }

    func saveNow() {
        saveTimer?.invalidate()
        PersistenceService.shared.save(self)
    }
}
