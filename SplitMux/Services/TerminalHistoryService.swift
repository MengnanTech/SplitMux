import Foundation

/// Manages terminal output history instances per tab
@MainActor
@Observable
final class TerminalHistoryService {
    static let shared = TerminalHistoryService()

    private var histories: [UUID: TerminalHistory] = [:]

    /// Global recording enabled
    var isRecordingEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isRecordingEnabled, forKey: "historyRecordingEnabled")
        }
    }

    /// Maximum bytes per tab history (default 50MB)
    var maxBytesPerTab: Int = 50_000_000 {
        didSet {
            UserDefaults.standard.set(maxBytesPerTab, forKey: "historyMaxBytesPerTab")
            for (_, history) in histories {
                history.maxBytes = maxBytesPerTab
            }
        }
    }

    private init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            "historyRecordingEnabled": true,
            "historyMaxBytesPerTab": 50_000_000
        ])
        isRecordingEnabled = defaults.bool(forKey: "historyRecordingEnabled")
        maxBytesPerTab = defaults.integer(forKey: "historyMaxBytesPerTab")
        if maxBytesPerTab == 0 { maxBytesPerTab = 50_000_000 }
    }

    /// Get or create history for a tab
    func history(for tabID: UUID) -> TerminalHistory {
        if let existing = histories[tabID] {
            return existing
        }
        let h = TerminalHistory(tabID: tabID)
        h.maxBytes = maxBytesPerTab
        h.isRecording = isRecordingEnabled
        histories[tabID] = h
        return h
    }

    /// Remove history for a tab (cleanup)
    func removeHistory(for tabID: UUID) {
        histories[tabID]?.stopReplay()
        histories.removeValue(forKey: tabID)
    }

    /// All active histories
    var activeHistories: [TerminalHistory] {
        Array(histories.values)
    }

    /// Total memory used across all histories
    var totalBytes: Int {
        histories.values.reduce(0) { $0 + $1.totalBytes }
    }

    var totalSizeString: String {
        let bytes = totalBytes
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }
}
