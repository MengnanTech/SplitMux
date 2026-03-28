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
                .font(.system(size: 9))
                .foregroundStyle(theme.iconDimmed)
                .padding(.leading, 12)
                .padding(.trailing, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(Array(pathSegments.enumerated()), id: \.offset) { index, segment in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 7, weight: .semibold))
                                .foregroundStyle(theme.disabledText)
                        }

                        Button {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: segment.fullPath)
                        } label: {
                            Text(segment.name)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(index == pathSegments.count - 1 ? theme.secondaryText : theme.disabledText)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.white.opacity(0.001)) // ensure hit area
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
                .padding(.vertical, 3)
            }

            Spacer()

            // Git branch indicator
            if let branch = gitBranch {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 8))
                    Text(branch)
                        .font(.system(size: 10, design: .monospaced))
                        .lineLimit(1)
                }
                .foregroundStyle(theme.accentColor.opacity(0.8))
                .padding(.trailing, 12)
            }
        }
        .frame(height: 22)
        .background(theme.tabBarBackground.opacity(0.5))
        .overlay(alignment: .bottom) {
            theme.subtleBorder.frame(height: 0.5)
        }
    }
}
