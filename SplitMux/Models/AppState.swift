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
        // Stop git polling on default sessions before replacing
        for session in sessions {
            session.stopGitBranchPolling()
        }
        self.sessions = restored.sessions
        self.selectedSessionID = restored.selectedSessionID
        // Start git branch polling and wire save for restored sessions
        for session in sessions {
            session.startGitBranchPolling()
            wireSessionSave(session)
        }
    }

    private func setupDefault() {
        let mainSession = Session()
        let tab1 = mainSession.createTab()
        mainSession.addTab(tab1)
        mainSession.startGitBranchPolling()
        wireSessionSave(mainSession)

        sessions = [mainSession]
        selectedSessionID = mainSession.id
    }

    func addSession(workingDirectory: String? = nil) {
        let session = Session(workingDirectory: workingDirectory)
        let tab = session.createTab()
        session.addTab(tab)
        session.startGitBranchPolling()
        wireSessionSave(session)
        sessions.append(session)
        selectedSessionID = session.id
        scheduleSave()
    }

    /// Wire up a session's onChanged to trigger a debounced save
    private func wireSessionSave(_ session: Session) {
        session.onChanged = { [weak self] in
            self?.scheduleSave()
        }
    }

    func removeSession(_ id: UUID) {
        if let session = sessions.first(where: { $0.id == id }) {
            session.stopGitBranchPolling()
            // Clean up Claude agent monitoring for all tabs in this session
            for tab in session.tabs {
                ClaudeHookService.shared.stopMonitoring(tabID: tab.id)
            }
        }
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
