import AppKit
import Foundation

/// A browser that can host a music.youtube.com tab and expose it to Apple Events.
enum Browser: String, CaseIterable, Identifiable {
    case chrome = "Google Chrome"
    case brave = "Brave Browser"
    case edge = "Microsoft Edge"
    case arc = "Arc"
    case vivaldi = "Vivaldi"
    case chromium = "Chromium"
    case safari = "Safari"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var bundleIdentifier: String {
        switch self {
        case .chrome: return "com.google.Chrome"
        case .brave: return "com.brave.Browser"
        case .edge: return "com.microsoft.edgemac"
        case .arc: return "company.thebrowser.Browser"
        case .vivaldi: return "com.vivaldi.Vivaldi"
        case .chromium: return "org.chromium.Chromium"
        case .safari: return "com.apple.Safari"
        }
    }

    /// Safari's scripting dictionary uses `do JavaScript`; Chromium forks use `execute javascript`.
    var isSafari: Bool { self == .safari }

    /// Whether the app is installed on this machine.
    var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }

    /// Whether the app is currently running. We never auto-launch a browser just to poll it.
    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    static var installed: [Browser] { allCases.filter(\.isInstalled) }
}
