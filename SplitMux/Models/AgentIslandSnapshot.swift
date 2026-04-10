import Foundation
import SwiftUI

struct AgentIslandSnapshot: Equatable {
    enum Emphasis: String {
        case error
        case needsInput
        case running
        case idle
    }

    let headline: String
    let contextLine: String
    let summaryLine: String
    let agentCount: Int
    let emphasis: Emphasis
    let primaryTabID: UUID?
    let primarySessionID: UUID?

    var symbolName: String {
        switch emphasis {
        case .error:
            return "exclamationmark.triangle.fill"
        case .needsInput:
            return "bell.fill"
        case .running:
            return "bolt.fill"
        case .idle:
            return "pause.circle.fill"
        }
    }

    var isAnimating: Bool {
        emphasis == .running
    }

    @MainActor
    static func build(agentInfos: [AgentInfo], sessions: [Session]) -> AgentIslandSnapshot? {
        guard !agentInfos.isEmpty else { return nil }

        let tabMetadata = Dictionary(uniqueKeysWithValues: sessions.flatMap { session in
            session.tabs.map { tab in
                (
                    tab.id,
                    (
                        sessionID: session.id,
                        sessionName: session.name,
                        tabTitle: tab.title
                    )
                )
            }
        })

        let resolvedAgents = agentInfos.map { info -> ResolvedAgent in
            let fallback = tabMetadata[info.tabID]
            let sessionName = info.sessionName.isEmpty ? (fallback?.sessionName ?? "") : info.sessionName
            let tabTitle = info.tabTitle.isEmpty ? (fallback?.tabTitle ?? "") : info.tabTitle
            return ResolvedAgent(
                tabID: info.tabID,
                sessionID: info.sessionID ?? fallback?.sessionID,
                sessionName: sessionName,
                tabTitle: tabTitle,
                status: info.status,
                lastStatusChange: info.lastStatusChange,
                toolDisplayText: info.toolDisplayText
            )
        }

        guard let primary = resolvedAgents.max(by: comparePriority(lhs:rhs:)) else {
            return nil
        }

        let summaryLine = makeSummaryLine(from: resolvedAgents)
        let contextLine = makeContextLine(for: primary)
        let headline = primary.toolDisplayText ?? primary.status.label

        return AgentIslandSnapshot(
            headline: headline,
            contextLine: contextLine,
            summaryLine: summaryLine,
            agentCount: resolvedAgents.count,
            emphasis: emphasis(for: primary.status),
            primaryTabID: primary.tabID,
            primarySessionID: primary.sessionID
        )
    }

    private static func comparePriority(lhs: ResolvedAgent, rhs: ResolvedAgent) -> Bool {
        if lhs.status.priority != rhs.status.priority {
            return lhs.status.priority < rhs.status.priority
        }
        return lhs.lastStatusChange < rhs.lastStatusChange
    }

    private static func emphasis(for status: ClaudeStatus) -> Emphasis {
        switch status {
        case .error:
            return .error
        case .needsInput:
            return .needsInput
        case .running:
            return .running
        case .idle, .unknown:
            return .idle
        }
    }

    private static func makeContextLine(for agent: ResolvedAgent) -> String {
        switch (agent.sessionName.isEmpty, agent.tabTitle.isEmpty) {
        case (false, false):
            return "\(agent.sessionName) · \(agent.tabTitle)"
        case (false, true):
            return agent.sessionName
        case (true, false):
            return agent.tabTitle
        case (true, true):
            return "Claude Code agent"
        }
    }

    private static func makeSummaryLine(from agents: [ResolvedAgent]) -> String {
        let counts = Dictionary(grouping: agents, by: \.status).mapValues(\.count)
        let orderedStatuses: [ClaudeStatus] = [.running, .needsInput, .error, .idle]
        let parts = orderedStatuses.compactMap { status -> String? in
            guard let count = counts[status], count > 0 else { return nil }
            return "\(count) \(summaryLabel(for: status, count: count))"
        }

        return parts.isEmpty ? "No active agents" : parts.joined(separator: " · ")
    }

    private static func summaryLabel(for status: ClaudeStatus, count: Int) -> String {
        switch status {
        case .running:
            return count == 1 ? "running" : "running"
        case .needsInput:
            return count == 1 ? "needs input" : "need input"
        case .error:
            return count == 1 ? "error" : "errors"
        case .idle:
            return count == 1 ? "idle" : "idle"
        case .unknown:
            return "unknown"
        }
    }
}

private struct ResolvedAgent {
    let tabID: UUID
    let sessionID: UUID?
    let sessionName: String
    let tabTitle: String
    let status: ClaudeStatus
    let lastStatusChange: Date
    let toolDisplayText: String?
}
