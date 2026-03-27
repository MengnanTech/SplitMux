import Foundation

/// Manages SSH host configurations: persistence and ~/.ssh/config parsing
@MainActor
@Observable
final class SSHManagerService {
    static let shared = SSHManagerService()

    var savedHosts: [SSHHost] = []
    var configHosts: [SSHHost] = []

    /// All hosts: saved first, then config-imported (not duplicated)
    var allHosts: [SSHHost] {
        let savedNames = Set(savedHosts.map(\.hostname))
        let uniqueConfig = configHosts.filter { !savedNames.contains($0.hostname) }
        return savedHosts + uniqueConfig
    }

    private let fileManager = FileManager.default
    private var saveURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("SplitMux", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("ssh_hosts.json")
    }

    private init() {
        loadSavedHosts()
        parseSSHConfig()
    }

    // MARK: - CRUD

    func addHost(_ host: SSHHost) {
        savedHosts.append(host)
        save()
    }

    func removeHost(_ id: UUID) {
        savedHosts.removeAll { $0.id == id }
        save()
    }

    func updateHost(_ host: SSHHost) {
        save()
    }

    // MARK: - Persistence

    private func save() {
        do {
            let data = try JSONEncoder().encode(savedHosts)
            try data.write(to: saveURL, options: .atomic)
        } catch {
            print("[SSHManager] Save failed: \(error)")
        }
    }

    private func loadSavedHosts() {
        guard let data = try? Data(contentsOf: saveURL),
              let hosts = try? JSONDecoder().decode([SSHHost].self, from: data) else {
            return
        }
        savedHosts = hosts
    }

    // MARK: - SSH Config Parser

    func parseSSHConfig() {
        let home = fileManager.homeDirectoryForCurrentUser.path
        let configPath = "\(home)/.ssh/config"

        guard fileManager.fileExists(atPath: configPath),
              let content = try? String(contentsOfFile: configPath, encoding: .utf8) else {
            return
        }

        var hosts: [SSHHost] = []
        var current: SSHHost?

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            let parts = trimmed.split(separator: " ", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }

            let key = parts[0].lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespaces)

            switch key {
            case "host":
                // Skip wildcard patterns
                if value.contains("*") || value.contains("?") { continue }
                if let prev = current { hosts.append(prev) }
                current = SSHHost(name: value, hostname: value)

            case "hostname":
                current?.hostname = value

            case "port":
                current?.port = Int(value) ?? 22

            case "user":
                current?.username = value

            case "identityfile":
                current?.keyPath = value

            default:
                break
            }
        }

        if let last = current {
            hosts.append(last)
        }

        configHosts = hosts
    }

    /// Refresh config hosts from ~/.ssh/config
    func refreshConfig() {
        parseSSHConfig()
    }

    /// Find host by ID
    func host(for id: UUID) -> SSHHost? {
        allHosts.first { $0.id == id }
    }
}
