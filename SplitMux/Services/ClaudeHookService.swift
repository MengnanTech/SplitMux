import Foundation
import SwiftUI

/// Monitors Claude Code hook status files for tab state changes
@MainActor
@Observable
final class ClaudeHookService {
    static let shared = ClaudeHookService()

    private let statusDir = "/tmp/splitmux"
    private var monitors: [UUID: DispatchSourceFileSystemObject] = [:]
    private var dirMonitor: DispatchSourceFileSystemObject?
    private var pollTimers: [UUID: Timer] = [:]

    private init() {
        try? FileManager.default.createDirectory(
            atPath: statusDir,
            withIntermediateDirectories: true
        )
    }

    /// Start monitoring a tab's status file
    func startMonitoring(tabID: UUID, onStatusChange: @escaping @MainActor (ClaudeStatus) -> Void) {
        let path = "\(statusDir)/\(tabID.uuidString)"

        // Create the file if it doesn't exist
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }

        // Poll-based monitoring (reliable across all scenarios)
        let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.checkStatusFile(path: path, callback: onStatusChange)
            }
        }
        pollTimers[tabID] = timer
    }

    /// Stop monitoring a tab
    func stopMonitoring(tabID: UUID) {
        pollTimers[tabID]?.invalidate()
        pollTimers.removeValue(forKey: tabID)

        let path = "\(statusDir)/\(tabID.uuidString)"
        try? FileManager.default.removeItem(atPath: path)
    }

    private var lastStatus: [String: String] = [:]

    private func checkStatusFile(path: String, callback: @escaping (ClaudeStatus) -> Void) {
        guard let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            return
        }

        // Only fire callback on actual changes
        if lastStatus[path] != content {
            lastStatus[path] = content
            let status = ClaudeStatus(rawValue: content) ?? .unknown
            callback(status)
        }
    }

    /// Clean up all monitors
    func cleanup() {
        for (id, _) in pollTimers {
            stopMonitoring(tabID: id)
        }
    }
}

enum ClaudeStatus: String {
    case running
    case idle
    case needsInput = "needs-input"
    case unknown

    var icon: String {
        switch self {
        case .running: return "bolt.fill"
        case .idle: return "pause.circle.fill"
        case .needsInput: return "bell.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    var label: String {
        switch self {
        case .running: return "Running"
        case .idle: return "Idle"
        case .needsInput: return "Needs Input"
        case .unknown: return "Unknown"
        }
    }

    var color: Color {
        switch self {
        case .running: return .blue
        case .idle: return Color(white: 0.45)
        case .needsInput: return .orange
        case .unknown: return Color(white: 0.35)
        }
    }
}
