import SwiftUI

struct TabContentView: View {
    @Bindable var session: Session

    var body: some View {
        VStack(spacing: 0) {
            if session.tabs.count > 1 {
                TabBarView(session: session, onAddTab: addTab)
            }

            ZStack {
                ForEach(session.tabs) { tab in
                    TabPanelView(tab: tab, workingDirectory: session.workingDirectory)
                        .opacity(tab.id == session.activeTabID ? 1 : 0)
                        .allowsHitTesting(tab.id == session.activeTabID)
                }
            }
            .contextMenu {
                Button {
                    addTab()
                } label: {
                    Label("New Tab", systemImage: "plus")
                }
            }
        }
        .background(Color.black)
        .keyboardShortcut("t", modifiers: .command)
    }

    private func addTab() {
        let tab = Tab(title: "zsh", icon: "terminal", content: .terminal)
        withAnimation(.easeInOut(duration: 0.15)) {
            session.addTab(tab)
        }
    }
}
