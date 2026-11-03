import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Talking to the host

/// The extension is sandboxed, so every read and every command goes over loopback to the host
/// app, which is the only process allowed to drive the browser.
enum HostClient {
    static func fetchState() async -> NowPlaying {
        var request = URLRequest(url: Loopback.stateURL)
        request.timeoutInterval = 1.5
        request.cachePolicy = .reloadIgnoringLocalCacheData
        var offline = NowPlaying.empty
        offline.connectionState = .hostUnavailable
        offline.statusNote = MediaConnectionState.hostUnavailable.message
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return offline }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(NowPlaying.self, from: data)) ?? offline
    }

    static func send(_ command: WidgetCommand, documentID: String? = nil, videoID: String? = nil) async {
        var request = URLRequest(url: Loopback.commandURL(command, documentID: documentID, videoID: videoID))
        request.httpMethod = "POST"
        request.timeoutInterval = 1.5
        _ = try? await URLSession.shared.data(for: request)
    }
}

// MARK: - Interactive buttons

struct PlayPauseIntent: AppIntent {
    @Parameter(title: "Safari document") var documentID: String?
    @Parameter(title: "Safari video") var videoID: String?
    init() {}
    init(documentID: String?, videoID: String?) { self.documentID = documentID; self.videoID = videoID }
    static var title: LocalizedStringResource = "Play or Pause"
    func perform() async throws -> some IntentResult {
        await HostClient.send(.playPause, documentID: documentID, videoID: videoID)
        return .result()
    }
}

struct NextTrackIntent: AppIntent {
    @Parameter(title: "Safari document") var documentID: String?
    @Parameter(title: "Safari video") var videoID: String?
    init() {}
    init(documentID: String?, videoID: String?) { self.documentID = documentID; self.videoID = videoID }
    static var title: LocalizedStringResource = "Next Track"
    func perform() async throws -> some IntentResult {
        await HostClient.send(.next, documentID: documentID, videoID: videoID)
        return .result()
    }
}

struct PreviousTrackIntent: AppIntent {
    @Parameter(title: "Safari document") var documentID: String?
    @Parameter(title: "Safari video") var videoID: String?
    init() {}
    init(documentID: String?, videoID: String?) { self.documentID = documentID; self.videoID = videoID }
    static var title: LocalizedStringResource = "Previous Track"
    func perform() async throws -> some IntentResult {
        await HostClient.send(.previous, documentID: documentID, videoID: videoID)
        return .result()
    }
}

struct CycleSourceIntent: AppIntent {
    static var title: LocalizedStringResource = "Switch Music Source"
    func perform() async throws -> some IntentResult {
        await HostClient.send(.cycleSource)
        return .result()
    }
}

struct RefreshMediaIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh Media"
    func perform() async throws -> some IntentResult {
        WidgetCenter.shared.reloadTimelines(ofKind: "MacMusicWidget")
        return .result()
    }
}

// MARK: - Timeline

struct NowPlayingEntry: TimelineEntry {
    let date: Date
    let state: NowPlaying
    /// Resolved before the entry is created. A widget renders once, so an image fetched
    /// asynchronously *inside* the view (via `.task`) would never appear.
    var artwork: Image? = nil
    var isStale = false
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> NowPlayingEntry {
        var demo = NowPlaying.empty
        demo.title = "Autumn Leaves"
        demo.artist = "Eddie Higgins Trio"
        demo.hasTab = true
        demo.duration = 274
        return NowPlayingEntry(date: Date(), state: demo)
    }

    func getSnapshot(in context: Context, completion: @escaping (NowPlayingEntry) -> Void) {
        Task {
            let state = await HostClient.fetchState()
            let artwork = await Self.artwork(state)
            let snapshot = WidgetDisplaySnapshot.timeline(for: state, now: Date())[0]
            completion(NowPlayingEntry(date: snapshot.date, state: state, artwork: artwork, isStale: snapshot.isStale))
        }
    }

    /// Fetches the cover art as part of building the timeline, not during rendering.
    static func artwork(_ state: NowPlaying) async -> Image? {
        guard !state.artworkURL.isEmpty, let url = URL(string: state.artworkURL) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let image = NSImage(data: data) else { return nil }
        return Image(nsImage: image)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingEntry>) -> Void) {
        Task {
            let state = await HostClient.fetchState()
            let artwork = await Self.artwork(state)
            let now = Date()
            let entries = WidgetDisplaySnapshot.timeline(for: state, now: now).map {
                NowPlayingEntry(date: $0.date, state: $0.state, artwork: artwork, isStale: $0.isStale)
            }
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(300))))
        }
    }
}

// MARK: - Views

struct MusicWidgetView: View {
    var entry: NowPlayingEntry
    @Environment(\.widgetFamily) private var family

    private var state: NowPlaying { entry.state }

    var body: some View {
        Group {
            if state.hasTab {
                switch family {
                case .systemSmall: small
                default: medium
                }
            } else {
                unavailable
            }
        }
        // The system's default widget margins are generous on macOS and left the card looking
        // mostly empty. They're disabled on the configuration, so this is the real inset.
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .containerBackground(for: .widget) {
            if let artwork = entry.artwork {
                artwork
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 30, opaque: true)
                    .overlay(.black.opacity(0.30))
            } else {
                Color.black.opacity(0.22)
            }
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            artwork(size: 36)
            Text(state.title.isEmpty ? "—" : state.title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(2)
            creatorLine
                .font(.system(size: 10))
            progress
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Button(intent: PreviousTrackIntent(documentID: state.webDocumentID, videoID: state.webVideoID)) { Image(systemName: "backward.fill") }
                    .disabled(entry.isStale || state.canGoPrevious == false)
                    .accessibilityLabel("Previous")
                Button(intent: PlayPauseIntent(documentID: state.webDocumentID, videoID: state.webVideoID)) {
                    Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                }
                .disabled(entry.isStale)
                Button(intent: NextTrackIntent(documentID: state.webDocumentID, videoID: state.webVideoID)) { Image(systemName: "forward.fill") }
                    .disabled(entry.isStale || state.canGoNext == false)
                    .accessibilityLabel("Next")
                refreshButton
                sourceButton
            }
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .semibold))
        }
    }

    private var medium: some View {
        // Explicit leading alignment: without it a row that ends up narrower than the widget
        // gets centred, and the artwork drifts inward instead of holding its left margin.
        HStack(alignment: .center, spacing: 12) {
            // Square, matched to the widget's height, so there is no dead space beside it.
            artworkFillingHeight
            VStack(alignment: .leading, spacing: 1) {
                Text(state.title.isEmpty ? "—" : state.title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    // Without this the surrounding Spacers win the height negotiation and the
                    // title gets squeezed back to a single truncated line.
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                creatorLine
                    .font(.system(size: 12))

                Spacer(minLength: 2)
                progress
                Spacer(minLength: 2)

                HStack(spacing: 12) {
                    Button(intent: PreviousTrackIntent(documentID: state.webDocumentID, videoID: state.webVideoID)) { Image(systemName: "backward.fill") }
                    .disabled(entry.isStale || state.canGoPrevious == false)
                    .accessibilityLabel("Previous")
                    Button(intent: PlayPauseIntent(documentID: state.webDocumentID, videoID: state.webVideoID)) {
                        Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .disabled(entry.isStale)
                    Button(intent: NextTrackIntent(documentID: state.webDocumentID, videoID: state.webVideoID)) { Image(systemName: "forward.fill") }
                    .disabled(entry.isStale || state.canGoNext == false)
                    .accessibilityLabel("Next")
                    refreshButton

                    sourceButton
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var playbackLabel: String {
        entry.isStale ? "업데이트 대기" : (state.isPlaying ? "재생 중" : "일시정지")
    }

    private var creatorLine: some View {
        HStack(spacing: 4) {
            Text(state.creatorLabel)
                .lineLimit(1)
                .accessibilityLabel(state.creatorRole + ": " + state.creatorLabel)
                .layoutPriority(1)
            Image(systemName: entry.isStale ? "clock.badge.exclamationmark" : (state.isPlaying ? "play.fill" : "pause.fill"))
                .font(.system(size: family == .systemSmall ? 8 : 9))
                .accessibilityLabel(playbackLabel)
                .help(playbackLabel)
        }
        .foregroundStyle(.secondary)
    }

    private var appURL: URL? { HostAppLink.url(.open, extensionIdentifier: Bundle.main.bundleIdentifier) }
    private var settingsURL: URL? { HostAppLink.url(.safariSettings, extensionIdentifier: Bundle.main.bundleIdentifier) }

    private var refreshButton: some View {
        Button(intent: RefreshMediaIntent()) { Image(systemName: "arrow.clockwise") }
            .buttonStyle(.plain)
            .accessibilityLabel("새로 고침")
            .help("현재 미디어 정보 새로 고침")
    }

    /// Tapping cycles Auto -> Safari YouTube -> YouTube Music -> Spotify -> Apple Music. A widget button can only
    /// fire an intent, so cycling is the only in-widget picker available.
    private var sourceButton: some View {
        Button(intent: CycleSourceIntent()) {
            Image(systemName: state.sourceSymbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .background(.white.opacity(0.14), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state.sourceLabel)
        .help("소스 전환 · " + state.sourceLabel)
    }

    /// System timer views advance without a new WidgetKit timeline each second.
    @ViewBuilder
    private var progress: some View {
        let timing = state.playbackTime
        if timing.isLive {
            Text("LIVE")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 3) {
                HStack(spacing: 2) {
                    if let interval = timing.timerInterval(since: state.capturedAt), !entry.isStale {
                        Text(timerInterval: interval, countsDown: false, showsHours: timing.duration >= 3_600)
                            .multilineTextAlignment(.leading)
                    } else {
                        Text(PlaybackTime.clock(timing.position(since: state.capturedAt, at: entry.date)))
                    }
                    Spacer(minLength: 0)
                    Text("/ " + (timing.hasDuration ? PlaybackTime.clock(timing.duration) : "--:--"))
                    if timing.rate != 1 { Text("×" + String(format: "%g", timing.rate)) }
                }
                .font(.system(size: family == .systemSmall ? 9 : 10))
                .monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(.secondary)
                if timing.hasDuration {
                    if let interval = timing.timerInterval(since: state.capturedAt), !entry.isStale {
                        ProgressView(timerInterval: interval, countsDown: false) {
                            EmptyView()
                        } currentValueLabel: {
                            EmptyView()
                        }
                        .progressViewStyle(.linear)
                        .tint(.white)
                    } else {
                        ProgressView(value: timing.position(since: state.capturedAt, at: entry.date) / timing.duration)
                            .progressViewStyle(.linear)
                            .tint(.white.opacity(0.7))
                    }
                }
            }
        }
    }

    private func artwork(size: CGFloat) -> some View {
        artworkImage(cornerRadius: size / 8)
            .frame(width: size, height: size)
    }

    /// Square, filling the height the family gives us.
    ///
    /// `Color.clear` is the sizing anchor on purpose: it has no intrinsic size, so the frame is
    /// identical whether or not the cover has loaded, and the artwork is drawn *into* that fixed
    /// box as an overlay. Sizing the box from the image instead makes the whole row jump when
    /// the image arrives — very visible with Apple Music, where the cover is fetched
    /// asynchronously and the first render has none.
    private var artworkFillingHeight: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .frame(maxHeight: .infinity)
            .overlay { artworkContent }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func artworkImage(cornerRadius: CGFloat) -> some View {
        Color.clear
            .overlay { artworkContent }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    @ViewBuilder
    private var artworkContent: some View {
        if let artwork = entry.artwork {
            if state.effectiveSource == "safariYouTube" {
                artwork.resizable().scaledToFit()
            } else {
                artwork.resizable().scaledToFill()
            }
        } else {
            ZStack {
                Rectangle().fill(.white.opacity(0.12))
                Image(systemName: "music.note")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var unavailable: some View {
        VStack(spacing: 6) {
            Text(state.connectionState?.message ?? (state.statusNote.isEmpty ? "재생 중인 미디어 없음" : state.statusNote))
                .font(.system(size: family == .systemSmall ? 10 : 12, weight: .medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if state.connectionState != .hostUnavailable {
                HStack(spacing: 4) {
                    sourceButton
                    Text(state.sourceLabel).lineLimit(1)
                }
                .font(.system(size: 10))
            }
            HStack(spacing: 10) {
                Button("새로 고침", intent: RefreshMediaIntent())
                if let appURL { Link("앱 열기", destination: appURL) }
                if family != .systemSmall, state.connectionState != nil, let settingsURL {
                    Link("Safari 설정", destination: settingsURL)
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(appURL)
    }

}

// MARK: - Entry point

@main
struct MacMusicWidgetBundle: WidgetBundle {
    var body: some Widget { MacMusicWidget() }
}

struct MacMusicWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MacMusicWidget", provider: Provider()) { entry in
            MusicWidgetView(entry: entry)
        }
        .configurationDisplayName("Mac Music Widget")
        .description("Music and Safari YouTube in Notification Center: thumbnail, title and playback controls.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}
