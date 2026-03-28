import SwiftUI
import UniformTypeIdentifiers

/// Overlay that shows drop zones when a tab is being dragged over the content area
/// Dropping on an edge triggers a split in that direction
struct SplitDropZoneOverlay: View {
    let session: Session
    @State private var activeEdge: SplitDirection?
    @State private var isDragging = false

    private var theme: AppTheme { SettingsManager.shared.theme }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Edge drop zones — invisible hit targets
                ForEach(SplitDirection.allCases, id: \.rawValue) { direction in
                    dropZone(direction: direction, size: geo.size)
                }

                // Visual highlight overlay when hovering an edge
                if let edge = activeEdge {
                    edgeHighlight(direction: edge, size: geo.size)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    @ViewBuilder
    private func dropZone(direction: SplitDirection, size: CGSize) -> some View {
        let edgeThickness: CGFloat = 60

        Color.clear
            .frame(
                width: direction.isHorizontal ? edgeThickness : size.width,
                height: direction.isHorizontal ? size.height : edgeThickness
            )
            .contentShape(Rectangle())
            .position(edgePosition(direction: direction, size: size))
            .onDrop(of: [.text], isTargeted: makeIsTargetedBinding(direction)) { providers in
                handleDrop(providers: providers, direction: direction)
            }
    }

    private func makeIsTargetedBinding(_ direction: SplitDirection) -> Binding<Bool> {
        Binding(
            get: { activeEdge == direction },
            set: { isTargeted in
                withAnimation(.easeInOut(duration: 0.15)) {
                    activeEdge = isTargeted ? direction : (activeEdge == direction ? nil : activeEdge)
                }
            }
        )
    }

    private func edgePosition(direction: SplitDirection, size: CGSize) -> CGPoint {
        switch direction {
        case .right: return CGPoint(x: size.width - 30, y: size.height / 2)
        case .left: return CGPoint(x: 30, y: size.height / 2)
        case .down: return CGPoint(x: size.width / 2, y: size.height - 30)
        case .up: return CGPoint(x: size.width / 2, y: 30)
        }
    }

    @ViewBuilder
    private func edgeHighlight(direction: SplitDirection, size: CGSize) -> some View {
        let highlight = theme.accentColor.opacity(0.15)
        let border = theme.accentColor.opacity(0.6)

        Group {
            switch direction {
            case .right:
                HStack(spacing: 0) {
                    Spacer()
                    ZStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(highlight)
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(border, style: StrokeStyle(lineWidth: 2, dash: [6, 3]))
                        VStack(spacing: 4) {
                            Image(systemName: "rectangle.split.2x1")
                                .font(.system(size: 20))
                            Text("Split Right")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                        }
                        .foregroundStyle(theme.accentColor)
                    }
                    .frame(width: size.width * 0.4)
                    .padding(4)
                }

            case .left:
                HStack(spacing: 0) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(highlight)
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(border, style: StrokeStyle(lineWidth: 2, dash: [6, 3]))
                        VStack(spacing: 4) {
                            Image(systemName: "rectangle.split.2x1")
                                .font(.system(size: 20))
                            Text("Split Left")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                        }
                        .foregroundStyle(theme.accentColor)
                    }
                    .frame(width: size.width * 0.4)
                    .padding(4)
                    Spacer()
                }

            case .down:
                VStack(spacing: 0) {
                    Spacer()
                    ZStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(highlight)
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(border, style: StrokeStyle(lineWidth: 2, dash: [6, 3]))
                        VStack(spacing: 4) {
                            Image(systemName: "rectangle.split.1x2")
                                .font(.system(size: 20))
                            Text("Split Down")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                        }
                        .foregroundStyle(theme.accentColor)
                    }
                    .frame(height: size.height * 0.4)
                    .padding(4)
                }

            case .up:
                VStack(spacing: 0) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(highlight)
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(border, style: StrokeStyle(lineWidth: 2, dash: [6, 3]))
                        VStack(spacing: 4) {
                            Image(systemName: "rectangle.split.1x2")
                                .font(.system(size: 20))
                            Text("Split Up")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                        }
                        .foregroundStyle(theme.accentColor)
                    }
                    .frame(height: size.height * 0.4)
                    .padding(4)
                    Spacer()
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func handleDrop(providers: [NSItemProvider], direction: SplitDirection) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { data, _ in
            guard let data = data as? Data,
                  let uuidString = String(data: data, encoding: .utf8),
                  let tabID = UUID(uuidString: uuidString) else { return }

            Task { @MainActor in
                // The dragged tab becomes the active tab, then split
                session.activeTabID = tabID
                withAnimation(.easeInOut(duration: 0.2)) {
                    session.splitActiveTab(direction: direction)
                }
            }
        }

        return true
    }
}

private extension SplitDirection {
    var isHorizontal: Bool {
        self == .left || self == .right
    }
}
