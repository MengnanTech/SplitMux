import SwiftUI
import WebKit

struct TabPanelView: View {
    @Environment(AppState.self) private var appState
    @Bindable var tab: Tab
    var workingDirectory: String = ""
    private var theme: AppTheme { SettingsManager.shared.theme }

    var body: some View {
        Group {
            switch tab.content {
            case .terminal:
                terminalView

            case .sshTerminal:
                terminalView

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

    @ViewBuilder
    private var terminalView: some View {
        TerminalSwiftUIView(workingDirectory: workingDirectory, tab: tab, appState: appState)
    }
}

// MARK: - Text Editor Panel

struct TextEditorPanel: View {
    @State private var text: String
    var onChange: (String) -> Void
    private var theme: AppTheme { SettingsManager.shared.theme }

    init(text: String, onChange: @escaping (String) -> Void) {
        self._text = State(initialValue: text)
        self.onChange = onChange
    }

    var body: some View {
        TextEditor(text: $text)
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(theme.primaryText)
            .scrollContentBackground(.hidden)
            .padding(12)
            .background(theme.contentBackground)
            .onChange(of: text) { _, newValue in
                onChange(newValue)
            }
    }
}

// MARK: - Notes Panel

struct NotesPanel: View {
    @State private var notes: String
    var onChange: (String) -> Void
    private var theme: AppTheme { SettingsManager.shared.theme }

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
                    .foregroundStyle(theme.secondaryText)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(theme.elevatedSurface)

            TextEditor(text: $notes)
                .font(.body)
                .foregroundStyle(theme.primaryText)
                .scrollContentBackground(.hidden)
                .padding(12)
                .onChange(of: notes) { _, newValue in
                    onChange(newValue)
                }
        }
        .background(theme.contentBackground)
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
