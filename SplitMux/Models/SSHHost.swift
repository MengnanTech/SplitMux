import Foundation
import SwiftUI

/// Represents a saved SSH connection configuration
@Observable
class SSHHost: Identifiable, Codable {
    let id: UUID
    var name: String
    var hostname: String
    var port: Int
    var username: String
    var keyPath: String?
    var colorTag: SSHColorTag
    var autoReconnect: Bool
    var lastConnected: Date?

    /// Runtime state (not persisted)
    var connectionState: SSHConnectionState = .disconnected
    /// Tab ID if currently connected
    var connectedTabID: UUID?

    init(
        id: UUID = UUID(),
        name: String = "",
        hostname: String = "",
        port: Int = 22,
        username: String = "",
        keyPath: String? = nil,
        colorTag: SSHColorTag = .gray,
        autoReconnect: Bool = false
    ) {
        self.id = id
        self.name = name
        self.hostname = hostname
        self.port = port
        self.username = username
        self.keyPath = keyPath
        self.colorTag = colorTag
        self.autoReconnect = autoReconnect
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, name, hostname, port, username, keyPath, colorTag, autoReconnect, lastConnected
    }

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        hostname = try c.decode(String.self, forKey: .hostname)
        port = try c.decode(Int.self, forKey: .port)
        username = try c.decode(String.self, forKey: .username)
        keyPath = try c.decodeIfPresent(String.self, forKey: .keyPath)
        colorTag = try c.decode(SSHColorTag.self, forKey: .colorTag)
        autoReconnect = try c.decode(Bool.self, forKey: .autoReconnect)
        lastConnected = try c.decodeIfPresent(Date.self, forKey: .lastConnected)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(hostname, forKey: .hostname)
        try c.encode(port, forKey: .port)
        try c.encode(username, forKey: .username)
        try c.encodeIfPresent(keyPath, forKey: .keyPath)
        try c.encode(colorTag, forKey: .colorTag)
        try c.encode(autoReconnect, forKey: .autoReconnect)
        try c.encodeIfPresent(lastConnected, forKey: .lastConnected)
    }

    /// Display name: custom name > user@host
    var displayName: String {
        if !name.isEmpty { return name }
        if !username.isEmpty {
            return "\(username)@\(hostname)"
        }
        return hostname
    }

    /// Build the ssh command arguments
    var sshCommand: String {
        var parts = ["ssh"]
        if port != 22 {
            parts.append("-p \(port)")
        }
        if let key = keyPath, !key.isEmpty {
            let expanded = key.replacingOccurrences(of: "~", with: FileManager.default.homeDirectoryForCurrentUser.path)
            // Quote path in case it contains spaces
            if expanded.contains(" ") {
                parts.append("-i \"\(expanded)\"")
            } else {
                parts.append("-i \(expanded)")
            }
        }
        if !username.isEmpty {
            parts.append("\(username)@\(hostname)")
        } else {
            parts.append(hostname)
        }
        return parts.joined(separator: " ")
    }
}

// MARK: - SSH Connection State

enum SSHConnectionState: String, Codable {
    case disconnected
    case connecting
    case connected
    case failed

    var icon: String {
        switch self {
        case .disconnected: return "circle"
        case .connecting: return "arrow.triangle.2.circlepath"
        case .connected: return "circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .disconnected: return Color(white: 0.4)
        case .connecting: return .yellow
        case .connected: return .green
        case .failed: return .red
        }
    }
}

// MARK: - SSH Color Tags

enum SSHColorTag: String, Codable, CaseIterable, Identifiable {
    case gray, red, orange, yellow, green, blue, purple

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .gray: return Color(white: 0.5)
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .blue: return .blue
        case .purple: return .purple
        }
    }
}
