import SwiftUI
import SwiftTerm

/// Search overlay for terminal content
struct TerminalSearchBar: View {
    @Binding var isVisible: Bool
    @Binding var searchText: String
    var onSearch: (String, Bool) -> Void // (query, searchBackward)
    var onDismiss: () -> Void
    @State private var matchInfo = ""

    private var theme: AppTheme { SettingsManager.shared.theme }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(theme.sectionHeaderText)

            TextField("Search terminal...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(theme.primaryText)
                .onSubmit {
                    onSearch(searchText, false)
                }

            if !matchInfo.isEmpty {
                Text(matchInfo)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.iconDimmed)
            }

            Button {
                onSearch(searchText, true)
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .frame(width: 24, height: 24)
            .background(theme.hoverBackground)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            Button {
                onSearch(searchText, false)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .frame(width: 24, height: 24)
            .background(theme.hoverBackground)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            Button {
                isVisible = false
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.sectionHeaderText)
            }
            .buttonStyle(.plain)
            .frame(width: 24, height: 24)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(theme.tabBarBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.3), radius: 8)
        .onKeyPress(.escape) {
            isVisible = false
            onDismiss()
            return .handled
        }
    }
}
