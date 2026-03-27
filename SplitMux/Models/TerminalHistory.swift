import Foundation

/// A single recorded chunk of terminal output
struct TerminalHistoryEntry {
    let timestamp: Date
    let data: Data
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
    }

    /// Get all recorded text concatenated
    var fullText: String {
        entries.map(\.text).joined()
    }

    /// Search history for a query, returns matching entry indices and text ranges
    func search(query: String) -> [(entryIndex: Int, range: Range<String.Index>)] {
        guard !query.isEmpty else { return [] }
        let q = query.lowercased()
        var results: [(entryIndex: Int, range: Range<String.Index>)] = []
        for (i, entry) in entries.enumerated() {
            let lower = entry.text.lowercased()
            var searchStart = lower.startIndex
            while let range = lower.range(of: q, range: searchStart..<lower.endIndex) {
                let originalRange = entry.text.index(entry.text.startIndex, offsetBy: lower.distance(from: lower.startIndex, to: range.lowerBound))..<entry.text.index(entry.text.startIndex, offsetBy: lower.distance(from: lower.startIndex, to: range.upperBound))
                results.append((entryIndex: i, range: originalRange))
                searchStart = range.upperBound
            }
        }
        return results
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

    func startReplay(feedBlock: @escaping (Data) -> Void) {
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

    private func replayNextEntry(feedBlock: @escaping (Data) -> Void) {
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
