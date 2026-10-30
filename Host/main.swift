import AppKit
import WidgetKit
import SafariServices

/// Background host for the Notification Center widget.
///
/// It has no window at all — the widget *is* the UI. This process exists solely because a widget
/// extension is sandboxed and cannot drive other apps over Apple Events.
final class HostDelegate: NSObject, NSApplicationDelegate {
    private let bridge = Bridge()
    private let server = HTTPServer()
    private var statusItem: NSStatusItem?

    // Persisted: a source picked from the widget should survive a host restart.
    private var browser: Browser = {
        let saved = UserDefaults.standard.string(forKey: "browser").flatMap(Browser.init(rawValue:))
        return (saved?.isInstalled == true ? saved : nil) ?? (Browser.safari.isInstalled ? .safari : Browser.installed.first) ?? .safari
    }()
    private var sourceKind: MusicSourceKind = {
        UserDefaults.standard.string(forKey: "sourceKind").flatMap(MusicSourceKind.init(rawValue:)) ?? .auto
    }() {
        didSet { UserDefaults.standard.set(sourceKind.rawValue, forKey: "sourceKind") }
    }
    /// Which source `auto` last settled on, so the menu can show it.
    private var resolvedKind: MusicSourceKind = .auto

    private var state = NowPlaying.empty
    private var reloadGate = WidgetReloadGate()
    private var pollGeneration = 0
    private var youtubePollInFlight = false
    private var interactionExpires = Date.distantPast
    private var timer: Timer?

    /// Cover art for sources that hand over bytes (Apple Music), served over loopback.
    private var artworkData: Data?
    private var artworkKey = ""
    /// Cover URLs looked up for streaming tracks that expose no artwork locally.
    private var remoteArtwork: [String: String] = [:]
    private var remoteArtworkInFlight: Set<String> = []

    /// Any button press counts as "interacting"; the source switcher shows for this long after.
    private var lastInteraction = Date.distantPast
    private static let revealWindow: TimeInterval = 12

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        server.provideState = { [weak self] in DispatchQueue.main.sync { self?.encodedState() ?? Data("{}".utf8) } }
        server.provideArtwork = { [weak self] in DispatchQueue.main.sync { self?.artworkData } }
        server.handleCommand = { [weak self] command, documentID, videoID in
            DispatchQueue.main.async { self?.run(command, documentID: documentID, videoID: videoID) }
        }
        server.start()

        installStatusItem()
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    // MARK: Polling

    private func poll() {
        if youtubePollInFlight && (sourceKind == .auto || sourceKind == .youtubeMusic) { return }
        pollGeneration += 1
        switch sourceKind {
        case .safariYouTube:
            finish(pollSafariYouTube(), from: .safariYouTube)
        case .spotify:
            finish(SpotifyController.poll(), from: .spotify)
        case .appleMusic:
            finish(withAppleMusicArtwork(AppleMusicController.poll()), from: .appleMusic)
        case .youtubeMusic:
            pollYouTubeMusic { [weak self] track in self?.finish(track, from: .youtubeMusic) }
        case .auto:
            resolveAutomatically()
        }
    }

    /// Prefers whatever is actually playing. Falls back to whatever merely has a track loaded, so
    /// a paused player still shows rather than the widget going blank.
    private func resolveAutomatically() {
        let safari = pollSafariYouTube()
        if safari.isPlaying { return finish(safari, from: .safariYouTube) }
        let spotify = SpotifyController.poll()
        if spotify.isPlaying { return finish(spotify, from: .spotify) }

        let music = AppleMusicController.poll()
        if music.isPlaying { return finish(withAppleMusicArtwork(music), from: .appleMusic) }

        pollYouTubeMusic { [weak self] youtube in
            guard let self else { return }
            if youtube.isPlaying { return self.finish(youtube, from: .youtubeMusic) }
            // Nothing is playing anywhere — show the first source that at least has a track.
            if safari.available { return self.finish(safari, from: .safariYouTube) }
            if spotify.available { return self.finish(spotify, from: .spotify) }
            if music.available { return self.finish(withAppleMusicArtwork(music), from: .appleMusic) }
            self.finish(youtube, from: .youtubeMusic)
        }
    }

    private func pollSafariYouTube(source: String = "safariYouTube") -> SourceTrack {
        var track = SourceTrack()
        guard let store = WebMediaStore.configured() else {
            track.note = "Safari App Group not configured"
            return track
        }
        guard let snapshot = WebMediaSnapshot.select(store.snapshots().filter { ($0.source ?? "safariYouTube") == source }) else {
            track.note = "Enable Safari extension and play a YouTube video"
            return track
        }
        track.title = snapshot.title
        track.artist = snapshot.author
        track.artworkURL = snapshot.artworkURL
        track.isPlaying = snapshot.isPlaying
        track.available = true
        track.webVideoID = snapshot.videoID
        track.webDocumentID = snapshot.documentID
        track.validUntil = snapshot.expiresAt
        track.canGoNext = snapshot.canGoNext
        track.canGoPrevious = snapshot.canGoPrevious
        return track
    }

    private func pollYouTubeMusic(_ completion: @escaping (SourceTrack) -> Void) {
        if browser == .safari, WebMediaStore.configured() != nil {
            completion(pollSafariYouTube(source: "youtubeMusic"))
            return
        }
        guard !youtubePollInFlight else { return }
        youtubePollInFlight = true
        let generation = pollGeneration
        bridge.poll(browser: browser) { [weak self] result in
            guard let self else { return }
            self.youtubePollInFlight = false
            guard generation == self.pollGeneration else { return }
            var track = SourceTrack()
            switch result {
            case .ok(let found):
                track.title = found.title
                track.artist = found.artist
                track.artworkURL = found.largeArtworkURL?.absoluteString ?? ""
                track.isPlaying = !found.isPaused
                track.elapsed = found.currentTime
                track.duration = found.duration
                track.available = true
            case .noTab, .noPlayer:
                track.note = "No YouTube Music tab"
            case .browserClosed:
                track.note = "\(self.browser.displayName) isn't running"
            case .failure(let message):
                track.note = message == "PERMISSION" ? "Automation permission needed" : "Can't read the tab"
            }
            completion(track)
        }
    }

    /// Fetches Apple Music cover art only when the track changes — it's an AppleScript round trip
    /// plus a file write, far too heavy to run on every poll.
    private func withAppleMusicArtwork(_ track: SourceTrack) -> SourceTrack {
        var track = track
        guard track.available else { return track }

        let key = "\(track.title)|\(track.artist)"
        if key != artworkKey {
            artworkKey = key
            artworkData = AppleMusicController.artwork()
        }
        if artworkData != nil {
            // Local library track: art came back as bytes, so serve it over loopback.
            // Cache-bust per track so the widget doesn't reuse the previous cover.
            let token = String(abs(key.hashValue))
            track.artworkURL = "http://127.0.0.1:\(Loopback.port)/artwork?v=\(token)"
            return track
        }

        // Only look up a cover when there is a real song to search for. Radio stations arrive
        // with a station name and no artist, and searching that returns a confident, wrong match
        // — better to show no artwork than someone else's album.
        guard !track.title.isEmpty, !track.artist.isEmpty else { return track }

        // Streaming track: no artwork over AppleScript. Look one up once, then reuse it.
        if let remote = remoteArtwork[key] {
            track.artworkURL = remote
        } else if !remoteArtworkInFlight.contains(key) {
            remoteArtworkInFlight.insert(key)
            let title = track.title, artist = track.artist
            Task { [weak self] in
                let found = await AppleMusicController.lookupArtworkURL(title: title, artist: artist)
                await MainActor.run {
                    guard let self else { return }
                    self.remoteArtworkInFlight.remove(key)
                    guard let found else { return }
                    self.remoteArtwork[key] = found
                    self.poll()   // pick it up on the next publish
                }
            }
        }
        return track
    }

    private func finish(_ track: SourceTrack, from kind: MusicSourceKind) {
        resolvedKind = kind

        var next = NowPlaying.empty
        next.title = track.title
        next.artist = track.artist
        next.artworkURL = track.artworkURL
        next.isPlaying = track.isPlaying
        next.elapsed = track.elapsed
        next.duration = track.duration
        next.webVideoID = track.webVideoID
        next.webDocumentID = track.webDocumentID
        next.validUntil = track.validUntil
        next.canGoNext = track.canGoNext
        next.canGoPrevious = track.canGoPrevious
        next.hasTab = track.available
        next.statusNote = track.available ? "" : (track.note.isEmpty ? "Nothing playing" : track.note)
        next.capturedAt = Date()
        next.sourceSelection = sourceKind.rawValue
        next.sourceActive = kind.rawValue
        next.showSourceButton = Date().timeIntervalSince(lastInteraction) < Self.revealWindow

        let interactiveChange = Date() < interactionExpires &&
            (next.title != state.title || next.isPlaying != state.isPlaying || next.sourceSelection != state.sourceSelection)
        state = next
        publishIfChanged(next, force: interactiveChange)
        refreshMenuChecks()
    }

    private func encodedState() -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(state)) ?? Data("{}".utf8)
    }

    /// Widget reloads are a limited resource, so only ask for one when something a viewer would
    /// notice actually changed — not on every poll tick.
    private func publishIfChanged(_ next: NowPlaying, force: Bool = false) {
        guard reloadGate.shouldReload(next, force: force) else { return }
        WidgetCenter.shared.reloadTimelines(ofKind: "MacMusicWidget")
    }

    // MARK: Commands

    /// Commands go to whichever source is currently on screen, so the buttons always control
    /// what the widget is actually showing.
    private func run(_ command: WidgetCommand, documentID: String?, videoID: String?) {
        if command != .cycleSource {
            if state.webDocumentID != nil {
                guard let documentID, let videoID, documentID == state.webDocumentID, videoID == state.webVideoID else { return }
            } else if documentID != nil || videoID != nil { return }
        }
        interactionExpires = Date().addingTimeInterval(8)
        lastInteraction = Date()
        // Publish again once the reveal window lapses, so the switcher actually disappears
        // rather than lingering until the next unrelated state change.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.revealWindow + 0.5) { [weak self] in
            self?.poll()
        }

        if command == .cycleSource {
            // Silence the source we're leaving, so switching doesn't end up with two players
            // going at once (or music continuing from something the widget no longer shows).
            pauseCurrentSource()

            let all = MusicSourceKind.allCases
            let index = all.firstIndex(of: sourceKind) ?? 0
            sourceKind = all[(index + 1) % all.count]
            refreshMenuChecks()
            poll()
            return
        }

        if state.webDocumentID != nil {
            if let action = SafariCommand.Action(rawValue: command.rawValue) { sendSafari(action) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in self?.poll() }
            return
        }
        switch resolvedKind {
        case .safariYouTube:
            if let action = SafariCommand.Action(rawValue: command.rawValue) { sendSafari(action) }
        case .spotify:
            SpotifyController.command(command)
        case .appleMusic:
            AppleMusicController.command(command)
        case .youtubeMusic, .auto:
            switch command {
            case .playPause: bridge.playPause(browser: browser)
            case .next: bridge.next(browser: browser)
            case .previous: bridge.previous(browser: browser)
            case .cycleSource: break   // already handled above
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.poll() }
    }

    /// Pauses whichever source is currently on screen. Safe to call unconditionally — every
    /// backend uses a real pause rather than a toggle, so pausing an idle player does nothing.
    private func sendSafari(_ action: SafariCommand.Action) {
        // Address the exact document that supplied the displayed state, never the frontmost tab.
        guard let store = WebMediaStore.configured(),
              let snapshot = store.snapshots().first(where: { $0.documentID == state.webDocumentID && $0.videoID == state.webVideoID }) else { return }
        do { try store.enqueue(action, for: snapshot) }
        catch { Log.write("Safari command unavailable; metadata may have expired") }
    }

    private func pauseCurrentSource() {
        if state.webDocumentID != nil { sendSafari(.pause); return }
        switch resolvedKind {
        case .safariYouTube: sendSafari(.pause)
        case .spotify: SpotifyController.pause()
        case .appleMusic: AppleMusicController.pause()
        case .youtubeMusic, .auto: bridge.pause(browser: browser)
        }
    }

    // MARK: Menu bar

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "Music Widget")

        let menu = NSMenu()
        menu.addItem(withTitle: "Source", action: nil, keyEquivalent: "")
        for kind in MusicSourceKind.allCases {
            let entry = menu.addItem(
                withTitle: "  \(kind.displayName)",
                action: #selector(selectSource(_:)),
                keyEquivalent: ""
            )
            entry.target = self
            entry.representedObject = kind.rawValue
        }

        menu.addItem(.separator())
        menu.addItem(withTitle: "Browser (for YouTube Music)", action: nil, keyEquivalent: "")
        for candidate in Browser.installed {
            let entry = menu.addItem(
                withTitle: "  \(candidate.displayName)",
                action: #selector(selectBrowser(_:)),
                keyEquivalent: ""
            )
            entry.target = self
            entry.representedObject = candidate.rawValue
        }

        menu.addItem(.separator())
        if Bundle.main.object(forInfoDictionaryKey: "MediaAppGroup") != nil {
            menu.addItem(withTitle: "Safari Extension Settings…", action: #selector(openSafariSettings), keyEquivalent: "").target = self
            menu.addItem(.separator())
        }
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
        refreshMenuChecks()
    }

    private func refreshMenuChecks() {
        guard let menu = statusItem?.menu else { return }
        for entry in menu.items {
            guard let raw = entry.representedObject as? String else { continue }
            if let kind = MusicSourceKind(rawValue: raw) {
                entry.state = (kind == sourceKind) ? .on : .off
                // In Auto, mark what it actually landed on.
                if sourceKind == .auto, kind == resolvedKind, kind != .auto {
                    entry.state = .mixed
                }
            } else if let candidate = Browser(rawValue: raw) {
                entry.state = (candidate == browser) ? .on : .off
            }
        }
    }

    @objc private func openSafariSettings() {
        guard let identifier = Bundle.main.bundleIdentifier else { return }
        SFSafariApplication.showPreferencesForExtension(withIdentifier: identifier + ".safari") { _ in }
    }

    @objc private func selectSource(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let picked = MusicSourceKind(rawValue: raw) else { return }
        guard picked != sourceKind else { return }
        pauseCurrentSource()
        sourceKind = picked
        pollGeneration += 1
        interactionExpires = Date().addingTimeInterval(8)
        poll()
    }

    @objc private func selectBrowser(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let picked = Browser(rawValue: raw) else { return }
        browser = picked
        pollGeneration += 1
        UserDefaults.standard.set(picked.rawValue, forKey: "browser")
        poll()
    }
}

let app = NSApplication.shared
let delegate = HostDelegate()
app.delegate = delegate
app.run()
