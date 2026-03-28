import SwiftUI

struct EmptyStateView: View {
    @Environment(AppState.self) private var appState
    @State private var isHovering = false

    private var theme: AppTheme { SettingsManager.shared.theme }

    var body: some View {
        VStack(spacing: 32) {
            // Abstract split icon inspired by app icon
            ZStack {
                // Left card
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 1, green: 0.42, blue: 0.42), Color(red: 1, green: 0.63, blue: 0.48)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 52, height: 72)
                    .rotationEffect(.degrees(-6))
                    .offset(x: -30)
                    .shadow(color: Color(red: 1, green: 0.42, blue: 0.42).opacity(0.3), radius: 12, y: 6)

                // Right card
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.31, green: 0.8, blue: 0.77), Color(red: 0.27, green: 0.66, blue: 0.88)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 52, height: 72)
                    .rotationEffect(.degrees(6))
                    .offset(x: 30)
                    .shadow(color: Color(red: 0.31, green: 0.8, blue: 0.77).opacity(0.3), radius: 12, y: 6)

                // Center divider dot
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 1, green: 0.42, blue: 0.42), Color(red: 0.31, green: 0.8, blue: 0.77)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: 10, height: 10)

                // Terminal symbol on left
                Text(">_")
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .rotationEffect(.degrees(-6))
                    .offset(x: -30)

                // Code symbol on right
                Text("{ }")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .rotationEffect(.degrees(6))
                    .offset(x: 30)
            }
            .frame(width: 140, height: 100)

            VStack(spacing: 10) {
                Text("SplitMux")
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.secondaryText)

                Text("Press \u{2318}N to start a new session")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(theme.disabledText)
            }

            // Start button
            Button {
                appState.addSession()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                    Text("New Session")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    theme.brandCoral,
                                    theme.brandAqua
                                ],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .shadow(color: theme.chromeShadow.opacity(isHovering ? 0.22 : 0.14), radius: isHovering ? 10 : 5, y: 3)
                )
                .scaleEffect(isHovering ? 1.04 : 1.0)
                .animation(.easeOut(duration: 0.15), value: isHovering)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isHovering = hovering
            }
        }
    }
}
