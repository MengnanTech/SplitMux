import Foundation
import SwiftTerm

/// A single recorded chunk of terminal output (for replay/export)
struct TerminalHistoryEntry {
    let timestamp: Date
    let data: Data
    let text: String
}

/// A single line of terminal output read from the rendered buffer
struct DisplayLine: Identifiable {
    let id: Int
    let text: String
}

/// Records and manages terminal output history for a single tab
@Observable
@MainActor
class TerminalHistory {
    let tabID: UUID
    private(set) var entries: [TerminalHistoryEntry] = []
    private(set) var totalBytes: Int = 0
    var isRecording: Bool = true

    /// Maximum bytes to keep in memory (50MB)
    var maxBytes: Int = 50_000_000

    // Replay state
    var isReplaying: Bool = false
    var replayPosition: Int = 0
    var replaySpeed: Double = 1.0
    private var replayTimer: Timer?

    /// Reference to the terminal for buffer reading
    weak var terminalView: LocalProcessTerminalView?

    /// Bumped on each append to trigger view refresh
    private(set) var dataVersion: Int = 0

    init(tabID: UUID) {
        self.tabID = tabID
    }

    /// Append terminal output data
    func append(data: Data) {
        guard isRecording else { return }
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) ?? ""
        let entry = TerminalHistoryEntry(timestamp: Date(), data: data, text: text)
        entries.append(entry)
        totalBytes += data.count

        // Trim old entries if over limit
        while totalBytes > maxBytes && !entries.isEmpty {
            let removed = entries.removeFirst()
            totalBytes -= removed.data.count
        }

        dataVersion += 1
    }

    /// Read display lines directly from the terminal's rendered buffer.
    /// This gives perfectly rendered text — all ANSI codes, cursor movements,
    /// and overwrites are already resolved by SwiftTerm.
    var displayLines: [DisplayLine] {
        _ = dataVersion  // subscribe to changes
        guard let terminal = terminalView?.terminal else { return [] }

        let data = terminal.getBufferAsData()
        guard let text = String(data: data, encoding: .utf8) else { return [] }

        var lines: [DisplayLine] = []
        for (i, line) in text.components(separatedBy: "\n").enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            lines.append(DisplayLine(id: i, text: trimmed))
        }
        return lines
    }

    /// Get all recorded text concatenated
    var fullText: String {
        entries.map(\.text).joined()
    }

    /// Export history to a file
    func exportToFile(url: URL, includeTimestamps: Bool = false) throws {
        var output = ""
        for entry in entries {
            if includeTimestamps {
                let formatter = ISO8601DateFormatter()
                output += "[\(formatter.string(from: entry.timestamp))] "
            }
            output += entry.text
        }
        try output.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Total recording duration
    var duration: TimeInterval {
        guard let first = entries.first?.timestamp, let last = entries.last?.timestamp else { return 0 }
        return last.timeIntervalSince(first)
    }

    /// Formatted size string
    var sizeString: String {
        if totalBytes < 1024 { return "\(totalBytes) B" }
        if totalBytes < 1024 * 1024 { return "\(totalBytes / 1024) KB" }
        return String(format: "%.1f MB", Double(totalBytes) / (1024 * 1024))
    }

    // MARK: - Replay

    func startReplay(feedBlock: @escaping @Sendable (Data) -> Void) {
        guard !entries.isEmpty else { return }
        isReplaying = true
        replayPosition = 0
        replayNextEntry(feedBlock: feedBlock)
    }

    func stopReplay() {
        isReplaying = false
        replayTimer?.invalidate()
        replayTimer = nil
    }

    private func replayNextEntry(feedBlock: @escaping @Sendable (Data) -> Void) {
        guard isReplaying, replayPosition < entries.count else {
            stopReplay()
            return
        }

        let entry = entries[replayPosition]
        feedBlock(entry.data)
        replayPosition += 1

        guard replayPosition < entries.count else {
            stopReplay()
            return
        }

        let nextEntry = entries[replayPosition]
        let delay = nextEntry.timestamp.timeIntervalSince(entry.timestamp) / replaySpeed
        let clampedDelay = min(max(delay, 0.001), 2.0) // clamp: 1ms to 2s

        replayTimer = Timer.scheduledTimer(withTimeInterval: clampedDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.replayNextEntry(feedBlock: feedBlock)
            }
        }
    }
}
