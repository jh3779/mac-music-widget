import Foundation

/// The contract between the host app and the widget extension.
///
/// The widget is a sandboxed extension and cannot send Apple Events, so it never talks to the
/// browser itself. The host app polls YouTube Music and publishes this over loopback; the
/// widget reads it and posts commands back.
struct NowPlaying: Codable, Equatable {
    var title: String = ""
    var artist: String = ""
    var artworkURL: String = ""
    var isPlaying: Bool = false
    var elapsed: Double = 0
    var duration: Double = 0
    var playbackRate: Double? = nil
    var isAdvancing: Bool? = nil
    var isLive: Bool? = nil
    var playbackTime: PlaybackTime {
        PlaybackTime(elapsed: elapsed, duration: duration, rate: playbackRate ?? 1,
                     isAdvancing: isPlaying && (isAdvancing ?? true),
                     isLive: isLive ?? (webDocumentID == nil && duration <= 0 && isPlaying))
    }
    /// False when there's no music.youtube.com tab, so the widget can show a real reason.
    var hasTab: Bool = false
    var statusNote: String = ""
    var connectionState: MediaConnectionState? = nil
    /// When the host captured this. The widget extrapolates `elapsed` from it so the progress
    /// bar keeps moving between refreshes instead of freezing at the last polled value.
    var capturedAt: Date = .init(timeIntervalSince1970: 0)
    /// Safari evidence expires when permission, tab, browser, or native messaging disappears.
    var validUntil: Date? = nil

    var webDocumentID: String? = nil
    var webVideoID: String? = nil
    var canGoNext: Bool? = nil
    var canGoPrevious: Bool? = nil

    /// Kept in the wire contract for older host/widget versions.
    var showSourceButton: Bool = false

    /// What the user picked in the widget: "auto", "youtubeMusic", "spotify", "appleMusic".
    var sourceSelection: String = "auto"
    /// What that actually resolved to. Differs from the selection only when it is "auto".
    var sourceActive: String = ""

    /// Whichever source is actually on screen — the pinned one, or what "auto" resolved to.
    var effectiveSource: String {
        sourceSelection == "auto" ? sourceActive : sourceSelection
    }

    var creatorRole: String { effectiveSource == "safariYouTube" ? "채널" : "아티스트" }
    var creatorLabel: String {
        let name = artist.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return name.isEmpty ? creatorRole + " 정보 없음" : name
    }

    /// Glyph for the source button. Deliberately generic SF Symbols rather than brand logos:
    /// third-party marks can't be redistributed, and the widget stays visually consistent.
    var sourceSymbol: String {
        switch effectiveSource {
        case "youtubeMusic", "safariYouTube": return "play.rectangle.fill"
        case "spotify": return "waveform"
        case "appleMusic": return "music.note"
        default: return "sparkles"
        }
    }

    /// Spoken/tooltip name, so the icon-only button stays identifiable.
    var sourceLabel: String {
        let short: String
        switch effectiveSource {
        case "youtubeMusic": short = "YouTube Music"
        case "safariYouTube": short = "Safari YouTube"
        case "spotify": short = "Spotify"
        case "appleMusic": short = "Apple Music"
        default: short = "No source"
        }
        return sourceSelection == "auto" ? "Auto — \(short)" : short
    }

    static let empty = NowPlaying()
}

enum WidgetCommand: String, Codable, CaseIterable {
    case playPause, next, previous
    /// Advances the input source. A widget button can only fire an intent, so cycling is the
    /// only way to offer a picker without leaving the widget.
    case cycleSource
}

/// Loopback endpoint shared by both targets. A fixed high port keeps the widget's fetch trivial.
enum Loopback {
    static let port: UInt16 = 47893
    static var stateURL: URL { URL(string: "http://127.0.0.1:\(port)/state")! }
    static func commandURL(_ command: WidgetCommand, documentID: String? = nil, videoID: String? = nil) -> URL {
        var url = URLComponents(string: "http://127.0.0.1:\(port)/cmd/\(command.rawValue)")!
        if let documentID { url.queryItems = [URLQueryItem(name: "document", value: documentID)] }
        if let videoID { url.queryItems = (url.queryItems ?? []) + [URLQueryItem(name: "video", value: videoID)] }
        return url.url!
    }
}
