import SwiftUI
import WebKit

struct TabPanelView: View {
    @Environment(AppState.self) private var appState
    @Bindable var tab: Tab
    var workingDirectory: String = ""

    var body: some View {
        Group {
            switch tab.content {
            case .terminal:
                TerminalSwiftUIView(workingDirectory: workingDirectory, tab: tab, appState: appState)

            case .sshTerminal:
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

// MARK: - Web Panel (Real WKWebView)

struct WebPanel: View {
    let url: URL

    var body: some View {
        VStack(spacing: 0) {
            WebViewWrapper(url: url)
        }
        .background(Color(red: 0.06, green: 0.06, blue: 0.08))
    }
}

struct WebViewWrapper: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> WebViewCoordinator {
        WebViewCoordinator()
    }

    class WebViewCoordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("[WebPanel] Navigation failed: \(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("[WebPanel] Provisional navigation failed: \(error.localizedDescription)")
        }
    }
}
