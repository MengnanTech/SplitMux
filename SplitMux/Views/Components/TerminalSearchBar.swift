import SwiftUI
import SwiftTerm

/// Compact floating search bar — positioned top-right like browser find (Cmd+F)
struct TerminalSearchBar: View {
    @Binding var isVisible: Bool
    @Binding var searchText: String
    var onSearch: (String, Bool) -> Bool // (query, searchBackward) -> found
    var onDismiss: () -> Void
    @State private var hasMatch: Bool?
    @FocusState private var isFocused: Bool

    private var theme: AppTheme { SettingsManager.shared.theme }

    var body: some View {
        HStack(spacing: 6) {
            // Search field
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.iconDimmed)

                TextField("Find", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.primaryText)
                    .focused($isFocused)
                    .frame(width: 140)
                    .onChange(of: searchText) { _, newValue in
                        if newValue.isEmpty {
                            hasMatch = nil
                        } else {
                            hasMatch = onSearch(newValue, false)
                        }
                    }
                    .onSubmit {
                        if !searchText.isEmpty {
                            hasMatch = onSearch(searchText, false)
                        }
                    }

                // Match status indicator
                if let hasMatch, !searchText.isEmpty {
                    Text(hasMatch ? "✓" : "0")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(hasMatch ? .green : .red.opacity(0.7))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(theme.contentBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(isFocused ? theme.accentColor.opacity(0.5) : theme.subtleBorder, lineWidth: 1)
                    )
            )

            // Nav buttons
            Button {
                if !searchText.isEmpty {
                    hasMatch = onSearch(searchText, true)
                }
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
            }
            .buttonStyle(.plain)
            .frame(width: 22, height: 22)
            .background(theme.hoverBackground)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            Button {
                if !searchText.isEmpty {
                    hasMatch = onSearch(searchText, false)
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
            }
            .buttonStyle(.plain)
            .frame(width: 22, height: 22)
            .background(theme.hoverBackground)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            // Close
            Button {
                isVisible = false
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(theme.iconDimmed)
            }
            .buttonStyle(.plain)
            .frame(width: 22, height: 22)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(theme.chromeSurfaceBackground)
                .shadow(color: theme.chromeShadow, radius: 8, y: 2)
        )
        .onAppear { isFocused = true }
        .onKeyPress(.escape) {
            isVisible = false
            onDismiss()
            return .handled
        }
    }
}
