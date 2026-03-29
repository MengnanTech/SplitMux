import Foundation
import SwiftUI

/// Global application settings stored in UserDefaults
@Observable
@MainActor
final class SettingsManager {
    static let shared = SettingsManager()

    // MARK: - Terminal

    var fontSize: CGFloat {
        didSet { UserDefaults.standard.set(Double(fontSize), forKey: "terminalFontSize") }
    }

    var fontName: String {
        didSet { UserDefaults.standard.set(fontName, forKey: "terminalFontName") }
    }

    // MARK: - Theme

    var theme: AppTheme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: "appTheme")
            ClaudeHookService.shared.refreshAllStatuses()
        }
    }

    // MARK: - Notifications

    var notifyThresholdSeconds: TimeInterval {
        didSet { UserDefaults.standard.set(notifyThresholdSeconds, forKey: "notifyThreshold") }
    }

    var showNotificationBanners: Bool {
        didSet { UserDefaults.standard.set(showNotificationBanners, forKey: "showNotificationBanners") }
    }

    // MARK: - Glass Theme

    var glassOpacity: Double {
        didSet { UserDefaults.standard.set(glassOpacity, forKey: "glassOpacity") }
    }

    // MARK: - Behavior

    var confirmBeforeClose: Bool {
        didSet { UserDefaults.standard.set(confirmBeforeClose, forKey: "confirmBeforeClose") }
    }

    var restoreSessionsOnLaunch: Bool {
        didSet { UserDefaults.standard.set(restoreSessionsOnLaunch, forKey: "restoreSessionsOnLaunch") }
    }

    // MARK: - Init

    private init() {
        let defaults = UserDefaults.standard

        // Register defaults
        let defaultValues: [String: Any] = [
            "terminalFontSize": 14.0,
            "terminalFontName": "SF Mono",
            "appTheme": "glass",
            "notifyThreshold": 5.0,
            "showNotificationBanners": true,
            "confirmBeforeClose": true,
            "restoreSessionsOnLaunch": true,
            "glassOpacity": 0.85
        ]
        defaults.register(defaults: defaultValues)

        self.fontSize = CGFloat(defaults.double(forKey: "terminalFontSize"))
        self.fontName = defaults.string(forKey: "terminalFontName") ?? "SF Mono"
        self.theme = AppTheme(rawValue: defaults.string(forKey: "appTheme") ?? "dark") ?? .dark
        self.notifyThresholdSeconds = defaults.double(forKey: "notifyThreshold")
        self.showNotificationBanners = defaults.bool(forKey: "showNotificationBanners")
        self.confirmBeforeClose = defaults.bool(forKey: "confirmBeforeClose")
        self.restoreSessionsOnLaunch = defaults.bool(forKey: "restoreSessionsOnLaunch")
        self.glassOpacity = defaults.double(forKey: "glassOpacity")
    }

    func increaseFontSize() {
        fontSize = min(fontSize + 1, 32)
    }

    func decreaseFontSize() {
        fontSize = max(fontSize - 1, 9)
    }

    func resetFontSize() {
        fontSize = 14
    }
}

// MARK: - Theme

enum AppTheme: String, CaseIterable, Identifiable {
    case dark
    case light
    case solarized
    case monokai
    case glass
    case glassLight

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dark: return "Dark"
        case .light: return "Light"
        case .solarized: return "Solarized Dark"
        case .monokai: return "Monokai"
        case .glass: return "Glass Dark"
        case .glassLight: return "Glass Light"
        }
    }

    var isGlass: Bool { self == .glass || self == .glassLight }

    var terminalBackground: NSColor {
        switch self {
        case .dark: return NSColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1.0)
        case .light: return NSColor(white: 0.995, alpha: 1.0)
        case .solarized: return NSColor(red: 0.0, green: 0.17, blue: 0.21, alpha: 1.0)
        case .monokai: return NSColor(red: 0.15, green: 0.16, blue: 0.13, alpha: 1.0)
        case .glass: return NSColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 0.15)
        case .glassLight: return NSColor(white: 1.0, alpha: 0.15)
        }
    }

    var terminalForeground: NSColor {
        switch self {
        case .dark: return NSColor(white: 0.85, alpha: 1.0)
        case .light: return NSColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0)
        case .solarized: return NSColor(red: 0.51, green: 0.58, blue: 0.59, alpha: 1.0)
        case .monokai: return NSColor(red: 0.97, green: 0.97, blue: 0.95, alpha: 1.0)
        case .glass: return NSColor(white: 0.95, alpha: 1.0)
        case .glassLight: return NSColor(red: 0.12, green: 0.12, blue: 0.15, alpha: 1.0)
        }
    }

    var sidebarBackground: Color {
        switch self {
        case .dark: return Color(red: 0.09, green: 0.09, blue: 0.11)
        case .light: return Color(white: 0.95)
        case .solarized: return Color(red: 0.0, green: 0.14, blue: 0.18)
        case .monokai: return Color(red: 0.13, green: 0.13, blue: 0.11)
        case .glass: return Color.white.opacity(0.06)
        case .glassLight: return Color.white.opacity(0.06)
        }
    }

    var contentBackground: Color {
        switch self {
        case .dark: return Color(red: 0.05, green: 0.05, blue: 0.07)
        case .light: return Color(white: 0.995)
        case .solarized: return Color(red: 0.0, green: 0.17, blue: 0.21)
        case .monokai: return Color(red: 0.15, green: 0.16, blue: 0.13)
        case .glass: return Color.clear
        case .glassLight: return Color.clear
        }
    }

    var tabBarBackground: Color {
        switch self {
        case .dark: return Color(red: 0.13, green: 0.13, blue: 0.15)
        case .light: return Color(red: 0.96, green: 0.96, blue: 0.97)
        case .solarized: return Color(red: 0.02, green: 0.15, blue: 0.19)
        case .monokai: return Color(red: 0.13, green: 0.14, blue: 0.11)
        case .glass: return Color.clear
        case .glassLight: return Color.clear
        }
    }

    var primaryText: Color {
        switch self {
        case .dark: return Color(white: 0.95)
        case .light: return Color(white: 0.1)
        case .solarized: return Color(red: 0.51, green: 0.58, blue: 0.59)
        case .monokai: return Color(red: 0.97, green: 0.97, blue: 0.95)
        case .glass: return Color(white: 1.0)
        case .glassLight: return Color(white: 0.05)
        }
    }

    var secondaryText: Color {
        switch self {
        case .dark: return Color(white: 0.6)
        case .light: return Color(white: 0.35)
        case .solarized: return Color(red: 0.40, green: 0.48, blue: 0.51)
        case .monokai: return Color(white: 0.55)
        case .glass: return Color(white: 0.7)
        case .glassLight: return Color(white: 0.25)
        }
    }

    var accentColor: Color {
        switch self {
        case .dark: return Color(red: 0.35, green: 0.68, blue: 1.0)
        case .light: return Color(red: 0.2, green: 0.48, blue: 0.95)
        case .solarized: return Color(red: 0.52, green: 0.60, blue: 0.0)
        case .monokai: return Color(red: 0.40, green: 0.85, blue: 0.37)
        case .glass: return Color(red: 0.35, green: 0.68, blue: 1.0)
        case .glassLight: return Color(red: 0.2, green: 0.48, blue: 0.95)
        }
    }

    var colorScheme: ColorScheme {
        switch self {
        case .light, .glassLight: return .light
        default: return .dark
        }
    }

    // MARK: - Design Tokens (unified from hardcoded values)

    /// Hover background for list items and interactive elements
    var hoverBackground: Color {
        switch self {
        case .dark: return Color(white: 0.16)
        case .light: return Color(white: 0.89)
        case .solarized: return Color(red: 0.04, green: 0.2, blue: 0.25)
        case .monokai: return Color(red: 0.18, green: 0.19, blue: 0.16)
        case .glass: return Color.white.opacity(0.1)
        case .glassLight: return Color(white: 0.89)
        }
    }

    // Light mode target palette:
    // appCanvasBackground: warm off-white
    // chromeSurfaceBackground: elevated white
    // chromeOverlay: low-alpha cool fog
    // brandCoral: primary branded accent
    // brandAqua: secondary branded technical accent
    // chromeShadow: soft shell shadow

    /// Base canvas background for the app shell.
    var appCanvasBackground: Color {
        switch self {
        case .light: return Color(white: 0.995)
        case .dark: return contentBackground
        case .solarized: return Color(red: 0.0, green: 0.17, blue: 0.21)
        case .monokai: return Color(red: 0.15, green: 0.16, blue: 0.13)
        case .glass: return Color.clear
        case .glassLight: return Color.clear
        }
    }

    /// Elevated chrome surface for panels, cards, and controls.
    var chromeSurfaceBackground: Color {
        switch self {
        case .light: return Color.white
        case .dark: return elevatedSurface
        case .solarized: return elevatedSurface
        case .monokai: return elevatedSurface
        case .glass: return Color.clear
        case .glassLight: return Color.clear
        }
    }

    /// Low-alpha overlay used for light shell glass and transient surfaces.
    var chromeOverlay: Color {
        switch self {
        case .light: return Color(red: 0.90, green: 0.94, blue: 0.99).opacity(0.44)
        case .dark: return subtleOverlay
        case .solarized: return subtleOverlay
        case .monokai: return subtleOverlay
        case .glass: return Color.white.opacity(0.05)
        case .glassLight: return Color(red: 0.90, green: 0.94, blue: 0.99).opacity(0.44)
        }
    }

    /// Deliberate brand hue token for the primary branded accent in the light shell.
    /// Non-light themes intentionally map this to the existing accent system.
    var brandCoral: Color {
        switch self {
        case .light: return Color(red: 0.95, green: 0.47, blue: 0.34)
        case .dark: return accentColor
        case .solarized: return accentColor
        case .monokai: return accentColor
        case .glass: return accentColor
        case .glassLight: return Color(red: 0.95, green: 0.47, blue: 0.34)
        }
    }

    /// Deliberate brand hue token for the secondary branded technical accent in the light shell.
    /// Non-light themes intentionally map this to the existing accent system.
    var brandAqua: Color {
        switch self {
        case .light: return Color(red: 0.16, green: 0.68, blue: 0.76)
        case .dark: return accentColor
        case .solarized: return accentColor
        case .monokai: return accentColor
        case .glass: return accentColor
        case .glassLight: return Color(red: 0.16, green: 0.68, blue: 0.76)
        }
    }

    /// Shell shadow tuned for the lighter chrome stack.
    var chromeShadow: Color {
        switch self {
        case .light: return Color.black.opacity(0.10)
        case .dark: return Color.black.opacity(0.45)
        case .solarized: return Color.black.opacity(0.35)
        case .monokai: return Color.black.opacity(0.40)
        case .glass: return Color.black.opacity(0.3)
        case .glassLight: return Color.black.opacity(0.10)
        }
    }

    /// Selected item background
    var selectedBackground: Color {
        switch self {
        case .dark: return Color(red: 0.2, green: 0.25, blue: 0.35)
        case .light: return Color(red: 0.22, green: 0.5, blue: 0.96).opacity(0.12)
        case .solarized: return Color(red: 0.04, green: 0.22, blue: 0.27)
        case .monokai: return Color(red: 0.2, green: 0.21, blue: 0.18)
        case .glass: return Color.white.opacity(0.15)
        case .glassLight: return Color(red: 0.22, green: 0.5, blue: 0.96).opacity(0.12)
        }
    }

    /// Tertiary text — metadata, timestamps, less important info
    var tertiaryText: Color {
        switch self {
        case .dark: return Color(white: 0.45)
        case .light: return Color(white: 0.5)
        case .solarized: return Color(red: 0.35, green: 0.43, blue: 0.46)
        case .monokai: return Color(white: 0.45)
        case .glass: return Color(white: 0.55)
        case .glassLight: return Color(white: 0.38)
        }
    }

    /// Disabled/dimmed text — paths, timestamps, least important info
    var disabledText: Color {
        switch self {
        case .dark: return Color(white: 0.38)
        case .light: return Color(white: 0.55)
        case .solarized: return Color(red: 0.3, green: 0.38, blue: 0.4)
        case .monokai: return Color(white: 0.35)
        case .glass: return Color(white: 0.48)
        case .glassLight: return Color(white: 0.42)
        }
    }

    /// Subtle borders and dividers
    var subtleBorder: Color {
        switch self {
        case .dark: return Color(white: 0.18)
        case .light: return Color(white: 0.82)
        case .solarized: return Color(red: 0.1, green: 0.25, blue: 0.3)
        case .monokai: return Color(white: 0.22)
        case .glass: return Color.white.opacity(0.12)
        case .glassLight: return Color(white: 0.82)
        }
    }

    /// Section header text (SESSIONS, SSH HOSTS, etc.)
    var sectionHeaderText: Color {
        switch self {
        case .dark: return Color(white: 0.45)
        case .light: return Color(white: 0.42)
        case .solarized: return Color(red: 0.4, green: 0.48, blue: 0.51)
        case .monokai: return Color(white: 0.5)
        case .glass: return Color(white: 0.55)
        case .glassLight: return Color(white: 0.32)
        }
    }

    /// Elevated surface backgrounds (command palette, history panel, overlays)
    var elevatedSurface: Color {
        switch self {
        case .dark: return Color(red: 0.1, green: 0.1, blue: 0.12)
        case .light: return Color(white: 0.97)
        case .solarized: return Color(red: 0.0, green: 0.12, blue: 0.16)
        case .monokai: return Color(red: 0.11, green: 0.12, blue: 0.1)
        case .glass: return Color.clear
        case .glassLight: return Color.clear
        }
    }

    /// Subtle white overlay for buttons/badges
    var subtleOverlay: Color {
        switch self {
        case .dark: return Color.white.opacity(0.07)
        case .light: return Color.black.opacity(0.05)
        case .solarized: return Color.white.opacity(0.06)
        case .monokai: return Color.white.opacity(0.06)
        case .glass: return Color.white.opacity(0.08)
        case .glassLight: return Color.black.opacity(0.05)
        }
    }

    /// Active tab / active element capsule background
    var activeTabBackground: Color {
        switch self {
        case .dark: return Color(white: 0.22)
        case .light: return Color.white.opacity(0.9)
        case .solarized: return Color(red: 0.06, green: 0.24, blue: 0.3)
        case .monokai: return Color(red: 0.22, green: 0.23, blue: 0.2)
        case .glass: return Color.white.opacity(0.15)
        case .glassLight: return Color.white.opacity(0.9)
        }
    }

    /// Inactive/body text — used for non-selected item labels
    var bodyText: Color {
        switch self {
        case .dark: return Color(white: 0.72)
        case .light: return Color(white: 0.25)
        case .solarized: return Color(red: 0.45, green: 0.52, blue: 0.55)
        case .monokai: return Color(white: 0.7)
        case .glass: return Color(white: 0.82)
        case .glassLight: return Color(white: 0.15)
        }
    }

    /// Chevron / icon dimmed color
    var iconDimmed: Color {
        switch self {
        case .dark: return Color(white: 0.42)
        case .light: return Color(white: 0.5)
        case .solarized: return Color(red: 0.35, green: 0.43, blue: 0.46)
        case .monokai: return Color(white: 0.4)
        case .glass: return Color(white: 0.52)
        case .glassLight: return Color(white: 0.38)
        }
    }

    /// Split pane divider color (normal state)
    var splitDivider: Color { subtleBorder }

    /// Split pane divider color (hover state)
    var splitDividerHover: Color { accentColor.opacity(0.6) }

    /// Sidebar gradient background for depth and richness
    var sidebarGradient: LinearGradient {
        switch self {
        case .dark:
            return LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.08, blue: 0.12),
                    Color(red: 0.10, green: 0.09, blue: 0.14),
                    Color(red: 0.09, green: 0.08, blue: 0.13)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        case .light:
            return LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.95, blue: 0.98),
                    Color(red: 0.93, green: 0.94, blue: 0.97),
                    Color(red: 0.94, green: 0.93, blue: 0.97)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        case .solarized:
            return LinearGradient(
                colors: [
                    Color(red: 0.0, green: 0.13, blue: 0.17),
                    Color(red: 0.0, green: 0.14, blue: 0.19)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        case .monokai:
            return LinearGradient(
                colors: [
                    Color(red: 0.11, green: 0.11, blue: 0.09),
                    Color(red: 0.12, green: 0.12, blue: 0.10)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        case .glass, .glassLight:
            return LinearGradient(
                colors: [Color.clear, Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}
