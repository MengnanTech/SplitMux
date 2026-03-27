import SwiftUI

struct TabPanelView: View {
    @Environment(AppState.self) private var appState
    @Bindable var tab: Tab
    var workingDirectory: String = ""

    var body: some View {
        Group {
            switch tab.content {
            case .terminal:
                TerminalSwiftUIView(workingDirectory: workingDirectory, tab: tab, appState: appState)

            case .text(let text):
                TextEditorPanel(text: text) { newText in
                    tab.content = .text(newText)
                }

            case .notes(let notes):
                NotesPanel(notes: notes) { newNotes in
                    tab.content = .notes(newNotes)
                }

            case .webURL(let url):
                WebPanel(url: url)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Text Editor Panel

struct TextEditorPanel: View {
    @State private var text: String
    var onChange: (String) -> Void

    init(text: String, onChange: @escaping (String) -> Void) {
        self._text = State(initialValue: text)
        self.onChange = onChange
    }

    var body: some View {
        TextEditor(text: $text)
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(Color(white: 0.85))
            .scrollContentBackground(.hidden)
            .padding(12)
            .background(Color(red: 0.06, green: 0.06, blue: 0.08))
            .onChange(of: text) { _, newValue in
                onChange(newValue)
            }
    }
}

// MARK: - Notes Panel

struct NotesPanel: View {
    @State private var notes: String
    var onChange: (String) -> Void

    init(notes: String, onChange: @escaping (String) -> Void) {
        self._notes = State(initialValue: notes)
        self.onChange = onChange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "note.text")
                    .foregroundStyle(.orange)
                Text("Notes")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color(white: 0.6))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(red: 0.08, green: 0.08, blue: 0.1))

            TextEditor(text: $notes)
                .font(.body)
                .foregroundStyle(Color(white: 0.85))
                .scrollContentBackground(.hidden)
                .padding(12)
                .onChange(of: notes) { _, newValue in
                    onChange(newValue)
                }
        }
        .background(Color(red: 0.06, green: 0.06, blue: 0.08))
    }
}

// MARK: - Web Panel

struct WebPanel: View {
    let url: URL

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "globe")
                .font(.system(size: 32))
                .foregroundStyle(Color(white: 0.2))
            Text(url.absoluteString)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Color(white: 0.3))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.06, green: 0.06, blue: 0.08))
    }
}
