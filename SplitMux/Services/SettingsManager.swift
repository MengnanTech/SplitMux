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
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "appTheme") }
    }

    // MARK: - Notifications

    var notifyThresholdSeconds: TimeInterval {
        didSet { UserDefaults.standard.set(notifyThresholdSeconds, forKey: "notifyThreshold") }
    }

    var showNotificationBanners: Bool {
        didSet { UserDefaults.standard.set(showNotificationBanners, forKey: "showNotificationBanners") }
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
            "appTheme": "dark",
            "notifyThreshold": 5.0,
            "showNotificationBanners": true,
            "confirmBeforeClose": true,
            "restoreSessionsOnLaunch": true
        ]
        defaults.register(defaults: defaultValues)

        self.fontSize = CGFloat(defaults.double(forKey: "terminalFontSize"))
        self.fontName = defaults.string(forKey: "terminalFontName") ?? "SF Mono"
        self.theme = AppTheme(rawValue: defaults.string(forKey: "appTheme") ?? "dark") ?? .dark
        self.notifyThresholdSeconds = defaults.double(forKey: "notifyThreshold")
        self.showNotificationBanners = defaults.bool(forKey: "showNotificationBanners")
        self.confirmBeforeClose = defaults.bool(forKey: "confirmBeforeClose")
        self.restoreSessionsOnLaunch = defaults.bool(forKey: "restoreSessionsOnLaunch")
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

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dark: return "Dark"
        case .light: return "Light"
        case .solarized: return "Solarized Dark"
        case .monokai: return "Monokai"
        }
    }

    var terminalBackground: NSColor {
        switch self {
        case .dark: return NSColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1.0)
        case .light: return NSColor(red: 0.98, green: 0.98, blue: 0.96, alpha: 1.0)
        case .solarized: return NSColor(red: 0.0, green: 0.17, blue: 0.21, alpha: 1.0)
        case .monokai: return NSColor(red: 0.15, green: 0.16, blue: 0.13, alpha: 1.0)
        }
    }

    var terminalForeground: NSColor {
        switch self {
        case .dark: return NSColor(white: 0.85, alpha: 1.0)
        case .light: return NSColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0)
        case .solarized: return NSColor(red: 0.51, green: 0.58, blue: 0.59, alpha: 1.0)
        case .monokai: return NSColor(red: 0.97, green: 0.97, blue: 0.95, alpha: 1.0)
        }
    }

    var sidebarBackground: Color {
        switch self {
        case .dark: return Color(red: 0.1, green: 0.1, blue: 0.12)
        case .light: return Color(red: 0.94, green: 0.94, blue: 0.95)
        case .solarized: return Color(red: 0.0, green: 0.14, blue: 0.18)
        case .monokai: return Color(red: 0.12, green: 0.12, blue: 0.1)
        }
    }

    var contentBackground: Color {
        switch self {
        case .dark: return .black
        case .light: return Color(white: 0.98)
        case .solarized: return Color(red: 0.0, green: 0.17, blue: 0.21)
        case .monokai: return Color(red: 0.15, green: 0.16, blue: 0.13)
        }
    }

    var tabBarBackground: Color {
        switch self {
        case .dark: return Color(red: 0.12, green: 0.12, blue: 0.14)
        case .light: return Color(red: 0.92, green: 0.92, blue: 0.93)
        case .solarized: return Color(red: 0.02, green: 0.15, blue: 0.19)
        case .monokai: return Color(red: 0.13, green: 0.14, blue: 0.11)
        }
    }

    var primaryText: Color {
        switch self {
        case .dark: return .white
        case .light: return .black
        case .solarized: return Color(red: 0.51, green: 0.58, blue: 0.59)
        case .monokai: return Color(red: 0.97, green: 0.97, blue: 0.95)
        }
    }

    var secondaryText: Color {
        switch self {
        case .dark: return Color(white: 0.55)
        case .light: return Color(white: 0.4)
        case .solarized: return Color(red: 0.40, green: 0.48, blue: 0.51)
        case .monokai: return Color(white: 0.55)
        }
    }

    var accentColor: Color {
        switch self {
        case .dark: return .green
        case .light: return .blue
        case .solarized: return Color(red: 0.52, green: 0.60, blue: 0.0)
        case .monokai: return Color(red: 0.40, green: 0.85, blue: 0.37)
        }
    }

    var colorScheme: ColorScheme {
        switch self {
        case .light: return .light
        default: return .dark
        }
    }
}
