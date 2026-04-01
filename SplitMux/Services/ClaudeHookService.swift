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

    // MARK: - Agent Orchestration

    /// Tracked agent info across all tabs
    var agentInfos: [AgentInfo] = []

    /// Recent agent notifications (capped at 50)
    var recentNotifications: [AgentNotification] = []

    /// Summary counts
    var runningCount: Int { agentInfos.filter { $0.status == .running }.count }
    var needsInputCount: Int { agentInfos.filter { $0.status == .needsInput }.count }
    var idleCount: Int { agentInfos.filter { $0.status == .idle }.count }


    private init() {
        // Clean up all old status files on startup
        if let files = try? FileManager.default.contentsOfDirectory(atPath: statusDir) {
            for file in files {
                try? FileManager.default.removeItem(atPath: "\(statusDir)/\(file)")
            }
        }
        try? FileManager.default.createDirectory(
            atPath: statusDir,
            withIntermediateDirectories: true
        )
    }

    /// Start monitoring a tab's status file.
    /// If already monitoring (e.g. view recreated by SwiftUI during split),
    /// preserve existing state to avoid losing Claude detection status.
    /// Callback receives (status, toolDetailText) — detail is a formatted string like "Editing foo.swift".
    func startMonitoring(tabID: UUID, onStatusChange: @escaping @MainActor (ClaudeStatus?, String?) -> Void) {
        let path = "\(statusDir)/\(tabID.uuidString)"
        let alreadyMonitoring = pollTimers[tabID] != nil || monitors[tabID] != nil

        // Clean up any existing monitoring
        monitors[tabID]?.cancel()
        monitors.removeValue(forKey: tabID)
        pollTimers[tabID]?.invalidate()
        pollTimers.removeValue(forKey: tabID)

        if alreadyMonitoring {
            // View was recreated (e.g. split mode change) — keep existing status file
            // and agent info, just restart monitoring
        } else {
            // Fresh start — reset status file and agent info
            FileManager.default.createFile(atPath: path, contents: Data(), attributes: nil)
            lastStatus.removeValue(forKey: path)
            agentInfos.removeAll { $0.tabID == tabID }
        }

        // Primary: file system event monitoring (instant reaction, near-zero CPU)
        startFileMonitor(path: path, tabID: tabID, callback: onStatusChange)

        // Fallback: low-frequency timer in case FS events are missed
        let timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.checkStatusFile(path: path, tabID: tabID, callback: onStatusChange)
            }
        }
        pollTimers[tabID] = timer
    }

    /// Stop monitoring a tab
    func stopMonitoring(tabID: UUID) {
        monitors[tabID]?.cancel()
        monitors.removeValue(forKey: tabID)
        pollTimers[tabID]?.invalidate()
        pollTimers.removeValue(forKey: tabID)

        let path = "\(statusDir)/\(tabID.uuidString)"
        try? FileManager.default.removeItem(atPath: path)
        lastStatus.removeValue(forKey: path)

        // Remove from agent tracking
        agentInfos.removeAll { $0.tabID == tabID }
    }

    private func startFileMonitor(path: String, tabID: UUID, callback: @escaping @MainActor (ClaudeStatus?, String?) -> Void) {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .attrib],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            let flags = source.data
            guard let self else { return }
            MainActor.assumeIsolated {
                if flags.contains(.delete) || flags.contains(.rename) {
                    // File removed/replaced — cancel and try to re-establish
                    source.cancel()
                    self.monitors.removeValue(forKey: tabID)
                    self.checkStatusFile(path: path, tabID: tabID, callback: callback)
                    self.startFileMonitor(path: path, tabID: tabID, callback: callback)
                } else {
                    self.checkStatusFile(path: path, tabID: tabID, callback: callback)
                }
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        monitors[tabID] = source
    }

    private var lastStatus: [String: String] = [:]

    /// Parse status file content — supports JSON or plain string (backwards compat)
    private func parseStatusContent(_ content: String) -> (status: ClaudeStatus, tool: String?, detail: String?, error: String?) {
        if let data = content.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let statusStr = json["status"] as? String ?? "unknown"
            let status = ClaudeStatus(rawValue: statusStr) ?? .unknown
            return (status, json["tool"] as? String, json["detail"] as? String, json["error"] as? String)
        }
        // Fallback: plain string like "running"
        let status = ClaudeStatus(rawValue: content) ?? .unknown
        return (status, nil, nil, nil)
    }

    private func checkStatusFile(path: String, tabID: UUID, callback: @escaping (ClaudeStatus?, String?) -> Void) {
        guard let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            // File gone or empty — Claude has exited, clear status
            if lastStatus[path] != nil {
                lastStatus.removeValue(forKey: path)
                agentInfos.removeAll { $0.tabID == tabID }
                callback(nil, nil)
            }
            return
        }

        // Only fire callback on actual changes
        if lastStatus[path] != content {
            lastStatus[path] = content
            let parsed = parseStatusContent(content)
            let displayText = ClaudeStatus.formatToolDetail(tool: parsed.tool, detail: parsed.detail)
            updateAgentInfo(tabID: tabID, status: parsed.status, tool: parsed.tool, detail: parsed.detail, error: parsed.error)
            callback(parsed.status, displayText)
        }
    }

    // MARK: - Agent Tracking

    private func updateAgentInfo(tabID: UUID, status: ClaudeStatus, tool: String? = nil, detail: String? = nil, error: String? = nil) {
        if let index = agentInfos.firstIndex(where: { $0.tabID == tabID }) {
            let prev = agentInfos[index].status
            let prevTool = agentInfos[index].currentTool

            agentInfos[index].status = status
            agentInfos[index].currentTool = tool
            agentInfos[index].currentDetail = detail

            if let error { agentInfos[index].lastError = error }

            // Only update timestamp on status transitions, not tool changes
            if prev != status {
                agentInfos[index].lastStatusChange = Date()
                addNotification(tabID: tabID, from: prev, to: status)
            }

            // Log completed action when tool changes
            if let prevTool, prevTool != tool {
                let action = AgentAction(tool: prevTool, detail: agentInfos[index].currentDetail, success: status != .error, timestamp: Date())
                agentInfos[index].recentActions.insert(action, at: 0)
                if agentInfos[index].recentActions.count > 5 {
                    agentInfos[index].recentActions.removeLast()
                }
            }
        } else {
            var info = AgentInfo(tabID: tabID, status: status, lastStatusChange: Date())
            info.currentTool = tool
            info.currentDetail = detail
            info.lastError = error
            agentInfos.append(info)

            if status != .unknown {
                addNotification(tabID: tabID, from: nil, to: status)
            }
        }
    }

    /// Refresh agent infos with session/tab metadata from AppState
    func refreshAgentMetadata(from appState: AppState) {
        for i in agentInfos.indices {
            let tabID = agentInfos[i].tabID
            for session in appState.sessions {
                if let tab = session.tabs.first(where: { $0.id == tabID }) {
                    agentInfos[i].sessionName = session.name
                    agentInfos[i].tabTitle = tab.title
                    agentInfos[i].sessionID = session.id
                    break
                }
            }
        }
    }

    private func addNotification(tabID: UUID, from: ClaudeStatus?, to: ClaudeStatus) {
        let message: String
        if let from {
            message = "\(from.label) → \(to.label)"
        } else {
            message = "Agent started: \(to.label)"
        }

        let notification = AgentNotification(
            id: UUID(),
            tabID: tabID,
            status: to,
            message: message,
            timestamp: Date()
        )
        recentNotifications.insert(notification, at: 0)
        if recentNotifications.count > 50 {
            recentNotifications.removeLast()
        }
    }

    /// Force the next poll cycle to re-fire all status callbacks.
    /// Call this when the view tree is heavily rebuilt (e.g. theme switch)
    /// so that observation subscriptions are re-established.
    func refreshAllStatuses() {
        lastStatus.removeAll()
    }

    /// Clean up all monitors and reset agent state
    func cleanup() {
        let ids = Array(Set(pollTimers.keys).union(monitors.keys))
        for id in ids {
            stopMonitoring(tabID: id)
        }
        agentInfos.removeAll()
        recentNotifications.removeAll()
        lastStatus.removeAll()
    }
}

// MARK: - Agent Info

struct AgentAction: Identifiable {
    let id = UUID()
    let tool: String
    let detail: String?
    let success: Bool
    let timestamp: Date

    var displayText: String {
        ClaudeStatus.formatToolDetail(tool: tool, detail: detail) ?? tool
    }
}

struct AgentInfo: Identifiable {
    let tabID: UUID
    var status: ClaudeStatus
    var sessionName: String = ""
    var tabTitle: String = ""
    var sessionID: UUID?
    var lastStatusChange: Date
    var currentTool: String?
    var currentDetail: String?
    var lastError: String?
    var recentActions: [AgentAction] = []

    var id: UUID { tabID }

    var toolDisplayText: String? {
        ClaudeStatus.formatToolDetail(tool: currentTool, detail: currentDetail)
    }

    var duration: TimeInterval {
        Date().timeIntervalSince(lastStatusChange)
    }

    var durationString: String {
        let s = Int(duration)
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m \(s % 60)s" }
        return "\(s / 3600)h \((s / 60) % 60)m"
    }
}

// MARK: - Agent Notification

struct AgentNotification: Identifiable {
    let id: UUID
    let tabID: UUID
    let status: ClaudeStatus
    let message: String
    let timestamp: Date
}

// MARK: - Claude Status

enum ClaudeStatus: String {
    case running
    case idle
    case needsInput = "needs-input"
    case error
    case unknown

    var icon: String {
        switch self {
        case .running: return "bolt.fill"
        case .idle: return "pause.circle.fill"
        case .needsInput: return "bell.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    var label: String {
        switch self {
        case .running: return "Running"
        case .idle: return "Idle"
        case .needsInput: return "Needs Input"
        case .error: return "Error"
        case .unknown: return "Unknown"
        }
    }

    var color: Color {
        switch self {
        case .running: return .blue
        case .idle: return Color(white: 0.45)
        case .needsInput: return .orange
        case .error: return .red
        case .unknown: return Color(white: 0.35)
        }
    }

    /// Priority for picking the most important status to display
    var priority: Int {
        switch self {
        case .error: return 4
        case .needsInput: return 3
        case .running: return 2
        case .idle: return 1
        case .unknown: return 0
        }
    }

    /// Format tool name + detail into a short display string
    static func formatToolDetail(tool: String?, detail: String?) -> String? {
        guard let tool else { return nil }
        let verb: String
        switch tool {
        case "Edit", "Write": verb = "Editing"
        case "Read": verb = "Reading"
        case "Bash": verb = "Running"
        case "Grep", "Glob": verb = "Searching"
        case "Agent": verb = "Agent"
        default: verb = tool
        }
        if let detail, !detail.isEmpty {
            let short = (detail as NSString).lastPathComponent
            return "\(verb) \(short)"
        }
        return verb
    }
}
