import SwiftUI

/// Thin breadcrumb bar showing the current working directory with clickable path segments
struct BreadcrumbBar: View {
    let workingDirectory: String
    let gitBranch: String?

    private var theme: AppTheme { SettingsManager.shared.theme }

    private var pathSegments: [(name: String, fullPath: String)] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let displayPath: String
        let basePath: String

        if workingDirectory == home {
            return [("~", home)]
        } else if workingDirectory.hasPrefix(home) {
            displayPath = "~" + workingDirectory.dropFirst(home.count)
            basePath = home
        } else {
            displayPath = workingDirectory
            basePath = "/"
        }

        let parts = displayPath.split(separator: "/", omittingEmptySubsequences: true)
        var segments: [(String, String)] = []
        var currentPath = basePath

        for (index, part) in parts.enumerated() {
            let name = String(part)
            if index == 0 && name == "~" {
                currentPath = home
            } else {
                currentPath = (currentPath as NSString).appendingPathComponent(name)
            }
            segments.append((name, currentPath))
        }

        return segments
    }

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "folder.fill")
                .font(.system(size: 8))
                .foregroundStyle(theme.iconDimmed.opacity(0.75))
                .padding(.leading, 10)
                .padding(.trailing, 3)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 1) {
                    ForEach(Array(pathSegments.enumerated()), id: \.offset) { index, segment in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 6.5, weight: .semibold))
                                .foregroundStyle(theme.disabledText.opacity(0.65))
                        }

                        Button {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: segment.fullPath)
                        } label: {
                            Text(segment.name)
                                .font(.system(size: 10, weight: .regular, design: .monospaced))
                                .foregroundStyle(index == pathSegments.count - 1 ? theme.secondaryText.opacity(0.88) : theme.disabledText.opacity(0.82))
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            if hovering {
                                NSCursor.pointingHand.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            Spacer()

            // Git branch indicator
            if let branch = gitBranch {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 7.5))
                    Text(branch)
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                }
                .foregroundStyle(theme.brandCoral.opacity(0.75))
                .padding(.trailing, 10)
            }
        }
        .frame(height: 18)
        .background(theme.appCanvasBackground)
        .overlay(alignment: .bottom) {
            theme.subtleBorder.opacity(0.38).frame(height: 0.5)
        }
    }
}
