import XCTest
@testable import SplitMux

@MainActor
final class AgentIslandSnapshotTests: XCTestCase {
    func testSnapshotIsNilWhenThereAreNoAgents() {
        XCTAssertNil(AgentIslandSnapshot.build(agentInfos: [], sessions: []))
    }

    func testSnapshotPrioritizesErrorOverRunningAgents() {
        let errorTabID = UUID()
        let runningTabID = UUID()

        let errorAgent = AgentInfo(
            tabID: errorTabID,
            status: .error,
            sessionName: "Work",
            tabTitle: "server",
            sessionID: UUID(),
            lastStatusChange: Date(),
            currentTool: "Write",
            currentDetail: "SplitMux/App/SplitMuxApp.swift",
            lastError: "Write failed"
        )

        let runningAgent = AgentInfo(
            tabID: runningTabID,
            status: .running,
            sessionName: "Work",
            tabTitle: "notes",
            sessionID: UUID(),
            lastStatusChange: Date().addingTimeInterval(-30),
            currentTool: "Read",
            currentDetail: "README.md"
        )

        let snapshot = AgentIslandSnapshot.build(
            agentInfos: [runningAgent, errorAgent],
            sessions: []
        )

        XCTAssertEqual(snapshot?.emphasis, .error)
        XCTAssertEqual(snapshot?.headline, "Editing SplitMuxApp.swift")
        XCTAssertEqual(snapshot?.agentCount, 2)
        XCTAssertEqual(snapshot?.summaryLine, "1 running · 1 error")
    }

    func testSnapshotResolvesSessionAndTabMetadataFromAppStateSessions() {
        let tab = Tab(id: UUID(), title: "prod-shell", icon: "terminal", content: .terminal)
        let session = Session(id: UUID(), name: "Deploy", tabs: [tab])

        let agent = AgentInfo(
            tabID: tab.id,
            status: .needsInput,
            lastStatusChange: Date(),
            currentTool: "Bash",
            currentDetail: "awaiting confirmation"
        )

        let snapshot = AgentIslandSnapshot.build(
            agentInfos: [agent],
            sessions: [session]
        )

        XCTAssertEqual(snapshot?.headline, "Running awaiting confirmation")
        XCTAssertEqual(snapshot?.contextLine, "Deploy · prod-shell")
        XCTAssertEqual(snapshot?.emphasis, .needsInput)
        XCTAssertEqual(snapshot?.primarySessionID, session.id)
        XCTAssertEqual(snapshot?.primaryTabID, tab.id)
    }
}
