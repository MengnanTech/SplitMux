import SwiftUI

/// Terminal output history browser with search, export, and replay
struct TerminalHistoryView: View {
    let tabID: UUID
    @Binding var isVisible: Bool
    @State private var searchQuery = ""
    @State private var searchResults: [Int] = []  // indices into displayLines
    @State private var selectedResultIndex = 0

    private var theme: AppTheme { SettingsManager.shared.theme }

    private var history: TerminalHistory {
        TerminalHistoryService.shared.history(for: tabID)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(.blue)

                Text("Terminal History")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(theme.secondaryText)

                Spacer()

                // Stats
                HStack(spacing: 8) {
                    Text("\(history.displayLines.count) lines")
                    Text(history.sizeString)
                    Text(formatDuration(history.duration))
                }
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(theme.iconDimmed)

                // Export button
                Button { exportHistory() } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.sectionHeaderText)
                }
                .buttonStyle(.plain)
                .help("Export history")

                // Close button
                Button { isVisible = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(theme.sectionHeaderText)
                        .frame(width: 20, height: 20)
                        .background(theme.subtleOverlay)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(theme.elevatedSurface)

            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.iconDimmed)

                TextField("Search history...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(.caption, design: .monospaced))
                    .onSubmit { performSearch() }

                if !searchResults.isEmpty {
                    Text("\(selectedResultIndex + 1)/\(searchResults.count)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(theme.sectionHeaderText)

                    Button { navigateResult(-1) } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)

                    Button { navigateResult(1) } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(theme.sidebarBackground)

            Divider().overlay(theme.subtleBorder.opacity(0.5))

            // History content
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(history.displayLines) { line in
                            Text(line.text)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(theme.bodyText)
                                .textSelection(.enabled)
                                .id(line.id)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 1)
                                .background(
                                    isHighlighted(line.id) ? Color.yellow.opacity(0.15) : Color.clear
                                )
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: selectedResultIndex) { _, newValue in
                    if !searchResults.isEmpty {
                        proxy.scrollTo(searchResults[newValue], anchor: .center)
                    }
                }
            }

            // Footer bar
            HStack(spacing: 12) {
                Spacer()

                // Recording toggle
                HStack(spacing: 4) {
                    Circle()
                        .fill(history.isRecording ? Color.red : theme.disabledText)
                        .frame(width: 6, height: 6)
                    Text(history.isRecording ? "Recording" : "Paused")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(theme.iconDimmed)
                }
                .onTapGesture {
                    history.isRecording.toggle()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(theme.elevatedSurface)
        }
        .frame(height: 280)
        .background(theme.contentBackground)
    }

    // MARK: - Actions

    private func performSearch() {
        guard !searchQuery.isEmpty else {
            searchResults = []
            return
        }
        let q = searchQuery.lowercased()
        searchResults = history.displayLines
            .filter { $0.text.lowercased().contains(q) }
            .map(\.id)
        selectedResultIndex = 0
    }

    private func navigateResult(_ offset: Int) {
        guard !searchResults.isEmpty else { return }
        selectedResultIndex = (selectedResultIndex + offset + searchResults.count) % searchResults.count
    }

    private func isHighlighted(_ lineID: Int) -> Bool {
        searchResults.contains(lineID)
    }

    private func exportHistory() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "terminal-history-\(tabID.uuidString.prefix(8)).txt"

        if panel.runModal() == .OK, let url = panel.url {
            try? history.exportToFile(url: url, includeTimestamps: true)
        }
    }

    // MARK: - Formatting

    private func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "\(Int(seconds))s" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        return "\(Int(seconds / 3600))h \(Int((seconds / 60).truncatingRemainder(dividingBy: 60)))m"
    }
}
