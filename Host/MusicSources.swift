import AppKit
import Foundation

/// Normalised playback state, whatever produced it.
struct SourceTrack {
    var title = ""
    var artist = ""
    var artworkURL = ""
    var isPlaying = false
    var elapsed: Double = 0
    var duration: Double = 0
    /// True when this source has something to show. False means "not running" or "nothing loaded".
    var available = false
    var note = ""
    /// Raw cover art, for sources that hand over bytes instead of a URL (Apple Music).
    var webVideoID: String?
    var webDocumentID: String?
    var validUntil: Date?
    var canGoNext: Bool?
    var canGoPrevious: Bool?
    var artworkData: Data?
}

enum MusicSourceKind: String, CaseIterable {
    case auto, safariYouTube, youtubeMusic, spotify, appleMusic

    var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .safariYouTube: return "Safari YouTube"
        case .youtubeMusic: return "YouTube Music"
        case .spotify: return "Spotify"
        case .appleMusic: return "Apple Music"
        }
    }
}

// MARK: - Shared AppleScript plumbing

enum ScriptRunner {
    /// Runs a script and returns trimmed stdout, or nil on any failure.
    static func run(_ source: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]

        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do { try process.run() } catch { return nil }

        let data = out.fileHandleForReading.readDataToEndOfFile()
        let errorData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(decoding: errorData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !message.isEmpty {
                Log.write("script failed: \(message.prefix(200))\n--- script ---\n\(source)")
            }
            return nil
        }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }
}

// MARK: - Spotify

/// Spotify ships a documented scripting dictionary, so this needs no JavaScript injection and
/// no per-browser special cases — unlike the YouTube Music path.
enum SpotifyController {
    static let bundleID = "com.spotify.client"

    static func poll() -> SourceTrack {
        var track = SourceTrack()
        guard ScriptRunner.isRunning(bundleID) else {
            track.note = "Spotify isn't running"
            return track
        }
        // Tab-separated rather than JSON: AppleScript has no JSON encoder, and track titles
        // contain quotes and backslashes far more often than they contain tabs.
        let script = """
        tell application "Spotify"
        \tset playState to "stopped"
        \ttry
        \t\tset playState to (player state as text)
        \tend try
        \tif playState is "stopped" then return "STOPPED"
        \tset curTrack to missing value
        \ttry
        \t\tset curTrack to current track
        \tend try
        \tif curTrack is missing value then return "STOPPED"
        \tset art to ""
        \ttry
        \t\tset art to artwork url of curTrack
        \tend try
        \tset pos to 0
        \ttry
        \t\tset pos to (round (player position))
        \tend try
        \treturn (name of curTrack) & tab & (artist of curTrack) & tab & art & tab & \
        playState & tab & (pos as integer as text) & tab & ((duration of curTrack) as integer as text)
        end tell
        """
        guard let output = ScriptRunner.run(script), output != "STOPPED" else {
            track.note = "Nothing playing in Spotify"
            return track
        }
        let fields = output.components(separatedBy: "\t")
        guard fields.count >= 6 else { return track }

        track.title = fields[0]
        track.artist = fields[1]
        track.artworkURL = fields[2]
        track.isPlaying = fields[3] == "playing"
        track.elapsed = Double(fields[4]) ?? 0
        // Spotify reports duration in milliseconds; Apple Music and the browser use seconds.
        track.duration = (Double(fields[5]) ?? 0) / 1000
        track.available = true
        return track
    }

    static func command(_ command: WidgetCommand) {
        let verb: String
        switch command {
        case .playPause: verb = "playpause"
        case .next: verb = "next track"
        case .previous: verb = "previous track"
        case .cycleSource: return   // handled by the host, not the player
        }
        _ = ScriptRunner.run("tell application \"Spotify\" to \(verb)")
    }

    /// Explicit pause, not the play/pause toggle: pausing an already-paused player is a no-op,
    /// whereas toggling it would start playback.
    static func pause() {
        guard ScriptRunner.isRunning(bundleID) else { return }
        _ = ScriptRunner.run("tell application \"Spotify\" to pause")
    }
}

// MARK: - Apple Music

enum AppleMusicController {
    static let bundleID = "com.apple.Music"
    private static let artworkPath = NSTemporaryDirectory() + "macmusicwidget-art.dat"

    static func poll() -> SourceTrack {
        var track = SourceTrack()
        guard ScriptRunner.isRunning(bundleID) else {
            track.note = "Music isn't running"
            return track
        }
        // Times are rounded to whole seconds *inside* AppleScript on purpose. Coercing a real to
        // text there emits the system's decimal separator, so on a comma-decimal region the
        // result is "213,4" and Double() rejects it — every duration silently became 0.
        let script = """
        tell application "Music"
        \tset playState to "stopped"
        \ttry
        \t\tset playState to (player state as text)
        \tend try
        \tif playState is "stopped" then return "STOPPED"
        \tset curTrack to missing value
        \ttry
        \t\tset curTrack to current track
        \tend try
        \tif curTrack is missing value then return "STOPPED"
        \tset pos to 0
        \ttry
        \t\tset pos to (round (player position))
        \tend try
        \tset dur to 0
        \ttry
        \t\tset dur to (round (duration of curTrack))
        \tend try
        \tset tm to ""
        \ttry
        \t\tset tm to (time of curTrack)
        \tend try
        \treturn (name of curTrack) & tab & (artist of curTrack) & tab & \
        playState & tab & (pos as integer as text) & tab & (dur as integer as text) & tab & tm
        end tell
        """
        guard let output = ScriptRunner.run(script), output != "STOPPED" else {
            track.note = "Nothing playing in Music"
            return track
        }
        let fields = output.components(separatedBy: "\t")
        guard fields.count >= 5 else {
            Log.write("music: unexpected field count \(fields.count) from \(output.prefix(160))")
            return track
        }

        // AppleScript renders absent properties as the literal text "missing value".
        let clean = fields.map { $0 == "missing value" ? "" : $0 }

        track.title = clean[0]
        track.artist = clean[1]
        track.isPlaying = clean[2] == "playing"
        track.elapsed = Double(clean[3]) ?? 0
        track.duration = Double(clean[4]) ?? 0

        // Apple Music catalog (streaming) tracks report `duration` as 0, but still populate the
        // human-readable `time` property. Parse that rather than showing a zero-length track.
        if track.duration == 0, clean.count >= 6 {
            track.duration = Self.seconds(fromMMSS: clean[5])
        }
        // A live radio stream genuinely has no duration, so that isn't worth logging.
        track.available = true
        return track
    }

    /// "3:45" -> 225. Also handles "1:02:03".
    static func seconds(fromMMSS text: String) -> Double {
        let parts = text.split(separator: ":").compactMap { Double($0) }
        guard !parts.isEmpty else { return 0 }
        return parts.reduce(0) { $0 * 60 + $1 }
    }

    /// Apple Music exposes cover art as raw bytes rather than a URL, so it has to be written out
    /// and read back. Only worth doing when the track actually changes.
    static func artwork() -> Data? {
        // Distinct markers per failure step: "no artwork on the track" and "couldn't write it out"
        // need completely different fixes, and a single "NONE" hides which one happened.
        let script = """
        tell application "Music"
        \tif player state is stopped then return "NOTRACK"
        \tif (count of artworks of current track) is 0 then return "NOART"
        \ttry
        \t\tset d to raw data of artwork 1 of current track
        \ton error errMsg
        \t\treturn "NODATA:" & errMsg
        \tend try
        \ttry
        \t\tset f to open for access (POSIX file "\(artworkPath)") with write permission
        \t\tset eof f to 0
        \t\twrite d to f
        \t\tclose access f
        \ton error errMsg
        \t\ttry
        \t\t\tclose access (POSIX file "\(artworkPath)")
        \t\tend try
        \t\treturn "NOWRITE:" & errMsg
        \tend try
        \treturn "OK"
        end tell
        """
        let outcome = ScriptRunner.run(script)
        guard outcome == "OK" else {
            Log.write("music artwork: \(outcome ?? "script failed")")
            return nil
        }
        guard let raw = FileManager.default.contents(atPath: artworkPath) else {
            Log.write("music artwork: wrote OK but file unreadable at \(artworkPath)")
            return nil
        }
        guard let image = NSImage(data: raw) else {
            Log.write("music artwork: \(raw.count) bytes not decodable as an image")
            return nil
        }

        // Normalise to PNG: the raw data can be TIFF, JPEG or PNG depending on the track.
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        return png
    }

    /// Apple Music catalog tracks expose no artwork over AppleScript at all (`count of artworks`
    /// is 0), so fall back to Apple's public iTunes Search endpoint for a cover URL. No key, no
    /// auth, and it returns a plain URL the widget can load directly.
    static func lookupArtworkURL(title: String, artist: String) async -> String? {
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            .init(name: "term", value: "\(artist) \(title)"),
            .init(name: "entity", value: "song"),
            .init(name: "limit", value: "1"),
        ]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = root["results"] as? [[String: Any]],
              let art = results.first?["artworkUrl100"] as? String else { return nil }

        // The search API returns a 100px thumbnail; the same URL serves larger sizes.
        return art.replacingOccurrences(of: "100x100bb", with: "600x600bb")
    }

    static func command(_ command: WidgetCommand) {
        let verb: String
        switch command {
        case .playPause: verb = "playpause"
        case .next: verb = "next track"
        case .previous: verb = "previous track"
        case .cycleSource: return   // handled by the host, not the player
        }
        _ = ScriptRunner.run("tell application \"Music\" to \(verb)")
    }

    /// Explicit pause, for the same reason as Spotify's.
    static func pause() {
        guard ScriptRunner.isRunning(bundleID) else { return }
        _ = ScriptRunner.run("tell application \"Music\" to pause")
    }
}
