import Foundation

/// Saves and restores session layout to disk
@MainActor
final class PersistenceService {
    static let shared = PersistenceService()

    private let fileManager = FileManager.default
    private var saveURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("SplitMux", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sessions.json")
    }

    // MARK: - Codable DTOs

    struct SessionDTO: Codable {
        let id: String
        let customName: String?
        let icon: String
        let workingDirectory: String
        let tabs: [TabDTO]
        let activeTabID: String?
        let splitLayout: SplitNodeDTO?
    }

    struct TabDTO: Codable {
        let id: String
        let title: String
        let icon: String
        let contentType: String // "terminal", "text", "notes", "webURL", "sshTerminal"
        let contentValue: String? // text content, URL string, or SSH host ID
        let sshHostID: String?
    }

    /// Recursive DTO needs to use a class (reference type) to avoid infinite size
    final class SplitNodeDTO: Codable {
        let type: String // "tab", "horizontal", "vertical"
        let tabID: String?
        let first: SplitNodeDTO?
        let second: SplitNodeDTO?
        let ratio: Double?

        init(type: String, tabID: String?, first: SplitNodeDTO?, second: SplitNodeDTO?, ratio: Double?) {
            self.type = type
            self.tabID = tabID
            self.first = first
            self.second = second
            self.ratio = ratio
        }
    }

    struct AppStateDTO: Codable {
        let sessions: [SessionDTO]
        let selectedSessionID: String?
    }

    // MARK: - Save

    func save(_ appState: AppState) {
        let dto = AppStateDTO(
            sessions: appState.sessions.map { sessionToDTO($0) },
            selectedSessionID: appState.selectedSessionID?.uuidString
        )
        do {
            let data = try JSONEncoder().encode(dto)
            try data.write(to: saveURL, options: .atomic)
        } catch {
            print("[PersistenceService] Save failed: \(error)")
        }
    }

    private func sessionToDTO(_ session: Session) -> SessionDTO {
        SessionDTO(
            id: session.id.uuidString,
            customName: session.customName,
            icon: session.icon,
            workingDirectory: session.workingDirectory,
            tabs: session.tabs.map { tabToDTO($0) },
            activeTabID: session.activeTabID?.uuidString,
            splitLayout: session.splitRoot.map { splitNodeToDTO($0) }
        )
    }

    private func tabToDTO(_ tab: Tab) -> TabDTO {
        let (type, value): (String, String?) = switch tab.content {
        case .terminal: ("terminal", nil)
        case .text(let s): ("text", s)
        case .notes(let s): ("notes", s)
        case .webURL(let url): ("webURL", url.absoluteString)
        case .sshTerminal(let hostID): ("sshTerminal", hostID.uuidString)
        }
        return TabDTO(id: tab.id.uuidString, title: tab.title, icon: tab.icon, contentType: type, contentValue: value, sshHostID: tab.sshHostID?.uuidString)
    }

    private func splitNodeToDTO(_ node: SplitNode) -> SplitNodeDTO {
        switch node {
        case .tab(let id):
            return SplitNodeDTO(type: "tab", tabID: id.uuidString, first: nil, second: nil, ratio: nil)
        case .horizontal(let first, let second, let ratio):
            return SplitNodeDTO(type: "horizontal", tabID: nil, first: splitNodeToDTO(first), second: splitNodeToDTO(second), ratio: ratio)
        case .vertical(let first, let second, let ratio):
            return SplitNodeDTO(type: "vertical", tabID: nil, first: splitNodeToDTO(first), second: splitNodeToDTO(second), ratio: ratio)
        }
    }

    // MARK: - Load

    func load() -> AppState? {
        guard let data = try? Data(contentsOf: saveURL),
              let dto = try? JSONDecoder().decode(AppStateDTO.self, from: data) else {
            return nil
        }
        let appState = AppState(empty: true)
        appState.sessions = dto.sessions.compactMap { dtoToSession($0) }
        appState.selectedSessionID = dto.selectedSessionID.flatMap { UUID(uuidString: $0) }

        // Validate selected session exists
        if let id = appState.selectedSessionID,
           !appState.sessions.contains(where: { $0.id == id }) {
            appState.selectedSessionID = appState.sessions.first?.id
        }

        // Ensure at least one session
        if appState.sessions.isEmpty {
            return nil
        }

        return appState
    }

    private func dtoToSession(_ dto: SessionDTO) -> Session? {
        guard let id = UUID(uuidString: dto.id) else { return nil }

        // Verify working directory still exists
        var isDir: ObjCBool = false
        let dir: String
        if FileManager.default.fileExists(atPath: dto.workingDirectory, isDirectory: &isDir), isDir.boolValue {
            dir = dto.workingDirectory
        } else {
            dir = FileManager.default.homeDirectoryForCurrentUser.path
        }

        let session = Session(
            id: id,
            name: dto.customName,
            icon: dto.icon,
            workingDirectory: dir
        )

        for tabDTO in dto.tabs {
            if let tab = dtoToTab(tabDTO) {
                session.tabs.append(tab)
            }
        }

        if session.tabs.isEmpty {
            let tab = Tab(title: "zsh", icon: "terminal", content: .terminal)
            session.tabs.append(tab)
        }

        session.activeTabID = dto.activeTabID.flatMap { UUID(uuidString: $0) } ?? session.tabs.first?.id

        // Restore split layout — validate that all referenced tabs still exist
        if let layoutDTO = dto.splitLayout,
           let splitNode = dtoToSplitNode(layoutDTO) {
            let splitTabIDs = Set(splitNode.tabIDs)
            let sessionTabIDs = Set(session.tabs.map(\.id))
            // Only restore split if ALL referenced tabs exist
            if splitTabIDs.isSubset(of: sessionTabIDs) && splitTabIDs.count >= 2 {
                session.splitRoot = splitNode
            }
        }

        return session
    }

    private func dtoToTab(_ dto: TabDTO) -> Tab? {
        guard let id = UUID(uuidString: dto.id) else { return nil }
        let content: TabContent = switch dto.contentType {
        case "terminal": .terminal
        case "text": .text(dto.contentValue ?? "")
        case "notes": .notes(dto.contentValue ?? "")
        case "webURL": .webURL(URL(string: dto.contentValue ?? "about:blank") ?? URL(string: "about:blank")!)
        case "sshTerminal":
            {
                if let hostID = UUID(uuidString: dto.contentValue ?? "") {
                    return .sshTerminal(hostID: hostID)
                }
                return .terminal
            }()
        default: .terminal
        }
        let tab = Tab(id: id, title: dto.title, icon: dto.icon, content: content)
        tab.sshHostID = dto.sshHostID.flatMap { UUID(uuidString: $0) }
        return tab
    }

    private func dtoToSplitNode(_ dto: SplitNodeDTO) -> SplitNode? {
        switch dto.type {
        case "tab":
            guard let idStr = dto.tabID, let id = UUID(uuidString: idStr) else { return nil }
            return .tab(id)
        case "horizontal":
            guard let first = dto.first.flatMap({ dtoToSplitNode($0) }),
                  let second = dto.second.flatMap({ dtoToSplitNode($0) }) else { return nil }
            return .horizontal(first, second, ratio: dto.ratio ?? 0.5)
        case "vertical":
            guard let first = dto.first.flatMap({ dtoToSplitNode($0) }),
                  let second = dto.second.flatMap({ dtoToSplitNode($0) }) else { return nil }
            return .vertical(first, second, ratio: dto.ratio ?? 0.5)
        default:
            return nil
        }
    }
}
