import Foundation

/// Result of a poll against the browser.
enum BridgeResult {
    case ok(Track)
    case noTab          // browser running, but no music.youtube.com tab open
    case noPlayer       // tab open, but the player element isn't there yet
    case browserClosed  // browser isn't running at all
    case failure(String)
}

struct ScriptError: Error {
    let message: String
}

struct Track: Equatable {
    var title: String = ""
    var byline: String = ""
    var artworkURL: String = ""
    var isPaused: Bool = true
    var currentTime: Double = 0
    var duration: Double = 0
    var volume: Double = 100
    var muted: Bool = false
    var likeStatus: String = ""   // "LIKE" | "DISLIKE" | "INDIFFERENT" | ""
    var isAd: Bool = false

    var artist: String {
        // YouTube Music bylines look like "Artist • Album • 2019".
        byline.components(separatedBy: "•").first?.trimmingCharacters(in: .whitespaces) ?? byline
    }

    /// Upscale the 60x60 thumbnail YouTube Music puts in the player bar.
    ///
    /// Between tracks — and for the whole of an ad — the player bar's `<img>` has an empty
    /// `src`, which the DOM resolves to the page URL. Only Google's image hosts are real artwork.
    var largeArtworkURL: URL? {
        guard let url = URL(string: artworkURL), let host = url.host,
              host.hasSuffix("googleusercontent.com") || host.hasSuffix("ytimg.com")
        else { return nil }

        var s = artworkURL
        if let r = s.range(of: "=w", options: .backwards) {
            s = String(s[s.startIndex..<r.lowerBound]) + "=w544-h544-l90-rj"
        }
        return URL(string: s)
    }
}

// MARK: - JavaScript payloads

private enum JS {
    /// Reads everything the widget renders in one round trip.
    static let poll = """
    (function(){var v=document.querySelector('video');var bar=document.querySelector('ytmusic-player-bar');\
    if(!v||!bar){return 'NOPLAYER';}\
    var q=function(s){var e=bar.querySelector(s);return e?e.textContent.trim():'';};\
    var img=bar.querySelector('img');\
    var p=document.querySelector('#movie_player');\
    var vol=(p&&p.getVolume)?p.getVolume():Math.round((v.volume||0)*100);\
    var r=bar.querySelector('ytmusic-like-button-renderer')||document.querySelector('ytmusic-like-button-renderer');\
    var ls=r?(r.getAttribute('like-status')||''):'';\
    var ad=p?p.classList.contains('ad-showing'):false;\
    return JSON.stringify({t:q('.title'),b:q('.byline'),a:img?img.src:'',p:v.paused,\
    c:v.currentTime||0,d:isFinite(v.duration)?v.duration:0,vol:vol,m:!!v.muted,l:ls,ad:ad});})()
    """

    static let playPause = """
    (function(){var b=document.querySelector('ytmusic-player-bar #play-pause-button');\
    if(b){b.click();return 'OK';}\
    var v=document.querySelector('video');if(v){v.paused?v.play():v.pause();return 'OK';}return 'NOPLAYER';})()
    """

    /// Pauses only if actually playing, and prefers clicking the real button so YouTube Music's
    /// own UI stays in sync.
    static let pause = """
    (function(){var v=document.querySelector('video');if(!v){return 'NOPLAYER';}\
    if(v.paused){return 'OK';}\
    var b=document.querySelector('ytmusic-player-bar #play-pause-button');\
    if(b){b.click();}else{v.pause();}return 'OK';})()
    """

    static let next = """
    (function(){var b=document.querySelector('ytmusic-player-bar .next-button');\
    if(b){b.click();return 'OK';}return 'NOPLAYER';})()
    """

    static let previous = """
    (function(){var b=document.querySelector('ytmusic-player-bar .previous-button');\
    if(b){b.click();return 'OK';}return 'NOPLAYER';})()
    """

    static let toggleLike = """
    (function(){var r=document.querySelector('ytmusic-player-bar ytmusic-like-button-renderer')\
    ||document.querySelector('ytmusic-like-button-renderer');if(!r){return 'NOPLAYER';}\
    var b=r.querySelector('#button-shape-like button')||r.querySelectorAll('button')[1];\
    if(b){b.click();return 'OK';}return 'NOPLAYER';})()
    """

    static func seek(to seconds: Double) -> String {
        """
        (function(){var p=document.querySelector('#movie_player');\
        if(p&&p.seekTo){p.seekTo(\(seconds),true);return 'OK';}\
        var v=document.querySelector('video');if(v){v.currentTime=\(seconds);return 'OK';}return 'NOPLAYER';})()
        """
    }

    static func setVolume(_ value: Double) -> String {
        """
        (function(){var p=document.querySelector('#movie_player');\
        if(p&&p.setVolume){p.setVolume(\(Int(value)));if(p.unMute){p.unMute();}return 'OK';}\
        var v=document.querySelector('video');if(v){v.volume=\(value / 100);v.muted=false;return 'OK';}return 'NOPLAYER';})()
        """
    }
}

// MARK: - Bridge

/// Talks to a browser tab over Apple Events by shelling out to `osascript`.
///
/// `osascript` is used instead of in-process `NSAppleScript` deliberately: it keeps every
/// Apple Event off the main thread with no run-loop caveats, and a hung browser can't wedge the UI.
final class Bridge {
    private let queue = DispatchQueue(label: "ytm.bridge", qos: .userInitiated)

    // MARK: Public API

    func poll(browser: Browser, completion: @escaping (BridgeResult) -> Void) {
        run(js: JS.poll, browser: browser) { raw in
            switch raw {
            case .success(let out):
                if out == "NOTAB" { return completion(.noTab) }
                if out == "NOPLAYER" || out.isEmpty { return completion(.noPlayer) }
                guard let track = Self.decode(out) else {
                    return completion(.failure("Unreadable response from the page."))
                }
                completion(.ok(track))
            case .failure(let error):
                completion(error.message == "BROWSER_CLOSED" ? .browserClosed : .failure(error.message))
            }
        }
    }

    func playPause(browser: Browser) { fireAndForget(JS.playPause, browser) }
    func pause(browser: Browser) { fireAndForget(JS.pause, browser) }
    func next(browser: Browser) { fireAndForget(JS.next, browser) }
    func previous(browser: Browser) { fireAndForget(JS.previous, browser) }
    func toggleLike(browser: Browser) { fireAndForget(JS.toggleLike, browser) }
    func seek(_ seconds: Double, browser: Browser) { fireAndForget(JS.seek(to: seconds), browser) }
    func setVolume(_ value: Double, browser: Browser) { fireAndForget(JS.setVolume(value), browser) }

    private func fireAndForget(_ js: String, _ browser: Browser) {
        run(js: js, browser: browser) { _ in }
    }

    // MARK: Plumbing

    private static func decode(_ json: String) -> Track? {
        guard let data = json.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var t = Track()
        t.title = o["t"] as? String ?? ""
        t.byline = o["b"] as? String ?? ""
        t.artworkURL = o["a"] as? String ?? ""
        t.isPaused = o["p"] as? Bool ?? true
        t.currentTime = o["c"] as? Double ?? 0
        t.duration = o["d"] as? Double ?? 0
        t.volume = o["vol"] as? Double ?? 100
        t.muted = o["m"] as? Bool ?? false
        t.likeStatus = o["l"] as? String ?? ""
        t.isAd = o["ad"] as? Bool ?? false
        return t
    }

    private func run(js: String, browser: Browser, completion: @escaping (Result<String, ScriptError>) -> Void) {
        queue.async {
            guard browser.isRunning else {
                return DispatchQueue.main.async { completion(.failure(ScriptError(message: "BROWSER_CLOSED"))) }
            }
            let script = Self.appleScript(js: js, browser: browser)
            let result = Self.osascript(script)
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Wraps a JS snippet in a tab-finding AppleScript for the given browser.
    private static func appleScript(js: String, browser: Browser) -> String {
        let payload = escapeForAppleScript(js)
        // The two dictionaries differ in shape. Chromium's command is `execute <tab> javascript <text>`;
        // writing Safari's `... "code" in <tab>` form instead parses as `get "code" in <tab>`,
        // which fails with a misleading `-1723 Access not allowed`.
        let evaluate = browser.isSafari
            ? "do JavaScript \"\(payload)\" in t"
            : "execute t javascript \"\(payload)\""

        return """
        tell application "\(browser.rawValue)"
        \tset _out to "NOTAB"
        \trepeat with w in windows
        \t\trepeat with t in tabs of w
        \t\t\ttry
        \t\t\t\tif (URL of t) contains "music.youtube.com" then
        \t\t\t\t\tset _out to (\(evaluate))
        \t\t\t\t\texit repeat
        \t\t\t\tend if
        \t\t\tend try
        \t\tend repeat
        \t\tif _out is not "NOTAB" then exit repeat
        \tend repeat
        \treturn _out
        end tell
        """
    }

    /// AppleScript string literals only understand backslash and double-quote escapes,
    /// and cannot contain raw newlines.
    private static func escapeForAppleScript(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }

    private static func osascript(_ source: String) -> Result<String, ScriptError> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]

        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err

        do {
            try process.run()
        } catch {
            return .failure(ScriptError(message: "Couldn't launch osascript: \(error.localizedDescription)"))
        }

        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let stdout = String(decoding: outData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let stderr = String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

        if process.terminationStatus != 0 {
            Log.write("osascript exit \(process.terminationStatus)\nSTDERR: \(stderr)\nSCRIPT: \(source)")
            return .failure(ScriptError(message: Self.humanize(stderr)))
        }
        return .success(stdout)
    }

    /// Turn the two AppleScript failures users actually hit into actionable text.
    private static func humanize(_ stderr: String) -> String {
        // -1743: the app was never granted Automation access in Privacy & Security.
        if stderr.contains("-1743") || stderr.localizedCaseInsensitiveContains("not allowed to send Apple events") {
            return "PERMISSION"
        }
        // Chrome's real message when "Allow JavaScript from Apple Events" is off. Note that a
        // malformed `execute` command also yields `Access not allowed (-1723)`, so that code is
        // deliberately NOT treated as the JS toggle — it would mask a scripting-syntax bug.
        if stderr.contains("-2700")
            || stderr.localizedCaseInsensitiveContains("JavaScript through AppleScript is turned off")
            || stderr.localizedCaseInsensitiveContains("Allow JavaScript from Apple Events") {
            return "JS_DISABLED"
        }
        return stderr.isEmpty ? "Unknown AppleScript error." : stderr
    }
}
