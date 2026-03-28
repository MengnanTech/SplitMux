import SwiftUI

/// Toast notification that appears when a non-active tab has output
struct NotificationToastOverlay: View {
    @Environment(AppState.self) private var appState
    @State private var toasts: [ToastItem] = []

    private var theme: AppTheme { SettingsManager.shared.theme }

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Spacer()
            ForEach(toasts) { toast in
                ToastView(toast: toast, theme: theme) {
                    // Navigate to the tab
                    if let sessionID = toast.sessionID {
                        withAnimation(.easeOut(duration: 0.12)) {
                            appState.selectedSessionID = sessionID
                        }
                        if let session = appState.sessions.first(where: { $0.id == sessionID }) {
                            session.activeTabID = toast.tabID
                            // Clear notification
                            if let tab = session.tabs.first(where: { $0.id == toast.tabID }) {
                                tab.hasNotification = false
                                tab.lastNotificationMessage = nil
                                appState.updateDockBadge()
                            }
                        }
                    }
                    dismissToast(toast.id)
                } onDismiss: {
                    dismissToast(toast.id)
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, 16)
        .padding(.bottom, 16)
        .allowsHitTesting(!toasts.isEmpty)
        .onReceive(NotificationCenter.default.publisher(for: .tabNotification)) { notification in
            guard let info = notification.userInfo,
                  let tabTitle = info["tabTitle"] as? String,
                  let message = info["message"] as? String,
                  let tabID = info["tabID"] as? UUID else { return }

            let sessionID = info["sessionID"] as? UUID
            let sessionName = info["sessionName"] as? String

            let toast = ToastItem(
                tabID: tabID,
                sessionID: sessionID,
                tabTitle: tabTitle,
                sessionName: sessionName,
                message: message
            )

            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                toasts.append(toast)
                // Keep max 3 toasts visible
                if toasts.count > 3 {
                    toasts.removeFirst()
                }
            }

            // Auto-dismiss after 4 seconds
            let toastID = toast.id
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(4))
                dismissToast(toastID)
            }
        }
    }

    private func dismissToast(_ id: UUID) {
        withAnimation(.easeOut(duration: 0.2)) {
            toasts.removeAll { $0.id == id }
        }
    }
}

struct ToastItem: Identifiable {
    let id = UUID()
    let tabID: UUID
    let sessionID: UUID?
    let tabTitle: String
    let sessionName: String?
    let message: String
    let timestamp = Date()
}

struct ToastView: View {
    let toast: ToastItem
    let theme: AppTheme
    var onTap: () -> Void
    var onDismiss: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            // Accent bar
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.orange)
                .frame(width: 3, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "terminal")
                        .font(.system(size: 9))
                        .foregroundStyle(theme.iconDimmed)

                    if let session = toast.sessionName {
                        Text(session)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(theme.secondaryText)
                        Text("/")
                            .font(.system(size: 9))
                            .foregroundStyle(theme.disabledText)
                    }

                    Text(toast.tabTitle)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(theme.primaryText)
                }

                Text(toast.message)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(theme.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()

            // Close button
            if isHovered {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(theme.tertiaryText)
                        .frame(width: 16, height: 16)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: 320, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(theme.elevatedSurface.opacity(0.85))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(theme.subtleBorder.opacity(0.5), lineWidth: 0.5)
                )
        )
        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        .onTapGesture { onTap() }
        .onHover { isHovered = $0 }
    }
}

extension Notification.Name {
    static let tabNotification = Notification.Name("tabNotification")
}
