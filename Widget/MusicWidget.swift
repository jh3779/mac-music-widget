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
        guard let (data, _) = try? await URLSession.shared.data(for: request) else {
            var offline = NowPlaying.empty
            offline.statusNote = "Host app not running"
            return offline
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(NowPlaying.self, from: data)) ?? .empty
    }

    static func send(_ command: WidgetCommand, documentID: String? = nil) async {
        var request = URLRequest(url: Loopback.commandURL(command, documentID: documentID))
        request.httpMethod = "POST"
        request.timeoutInterval = 1.5
        _ = try? await URLSession.shared.data(for: request)
    }
}

// MARK: - Interactive buttons

struct PlayPauseIntent: AppIntent {
    @Parameter(title: "Safari document") var documentID: String?
    init() {}
    init(documentID: String?) { self.documentID = documentID }
    static var title: LocalizedStringResource = "Play or Pause"
    func perform() async throws -> some IntentResult {
        await HostClient.send(.playPause, documentID: documentID)
        return .result()
    }
}

struct NextTrackIntent: AppIntent {
    @Parameter(title: "Safari document") var documentID: String?
    init() {}
    init(documentID: String?) { self.documentID = documentID }
    static var title: LocalizedStringResource = "Next Track"
    func perform() async throws -> some IntentResult {
        await HostClient.send(.next, documentID: documentID)
        return .result()
    }
}

struct PreviousTrackIntent: AppIntent {
    @Parameter(title: "Safari document") var documentID: String?
    init() {}
    init(documentID: String?) { self.documentID = documentID }
    static var title: LocalizedStringResource = "Previous Track"
    func perform() async throws -> some IntentResult {
        await HostClient.send(.previous, documentID: documentID)
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

// MARK: - Timeline

struct NowPlayingEntry: TimelineEntry {
    let date: Date
    let state: NowPlaying
    /// Resolved before the entry is created. A widget renders once, so an image fetched
    /// asynchronously *inside* the view (via `.task`) would never appear.
    var artwork: Image? = nil
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
            completion(NowPlayingEntry(date: Date(), state: state, artwork: await Self.artwork(state)))
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
            let entry = NowPlayingEntry(date: Date(), state: state, artwork: await Self.artwork(state))
            // The host pushes a reload whenever anything changes, so this is only a safety net
            // for the case where the host dies without telling anyone.
            let now = Date()
            let next = now.addingTimeInterval(300)
            if let expiry = state.validUntil {
                var unavailable = NowPlaying.empty
                unavailable.statusNote = "Safari update unavailable"
                unavailable.sourceSelection = state.sourceSelection
                unavailable.sourceActive = state.sourceActive
                let expired = NowPlayingEntry(date: max(expiry, now), state: unavailable)
                completion(Timeline(entries: expiry > now ? [entry, expired] : [expired], policy: .after(next)))
            } else {
                completion(Timeline(entries: [entry], policy: .after(next)))
            }
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
        VStack(alignment: .leading, spacing: 6) {
            artwork(size: 46)
            Text(state.title.isEmpty ? "—" : state.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(2)
            Text(state.effectiveSource == "safariYouTube" ? (state.isPlaying ? "Playing · Safari" : "Paused · Safari") : state.artist)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Button(intent: PreviousTrackIntent(documentID: state.webDocumentID)) { Image(systemName: "backward.fill") }
                    .disabled(state.canGoPrevious == false)
                    .accessibilityLabel("Previous")
                Button(intent: PlayPauseIntent(documentID: state.webDocumentID)) {
                    Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                }
                Button(intent: NextTrackIntent(documentID: state.webDocumentID)) { Image(systemName: "forward.fill") }
                    .disabled(state.canGoNext == false)
                    .accessibilityLabel("Next")
            }
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .semibold))
            if state.showSourceButton { sourceButton }
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
                Text(state.effectiveSource == "safariYouTube" ? (state.isPlaying ? "Playing · Safari" : "Paused · Safari") : state.artist)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 2)
                if state.effectiveSource != "safariYouTube" { progress }
                Spacer(minLength: 2)

                HStack(spacing: 16) {
                    Button(intent: PreviousTrackIntent(documentID: state.webDocumentID)) { Image(systemName: "backward.fill") }
                    .disabled(state.canGoPrevious == false)
                    .accessibilityLabel("Previous")
                    Button(intent: PlayPauseIntent(documentID: state.webDocumentID)) {
                        Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    Button(intent: NextTrackIntent(documentID: state.webDocumentID)) { Image(systemName: "forward.fill") }
                    .disabled(state.canGoNext == false)
                    .accessibilityLabel("Next")

                    if state.showSourceButton {
                        Spacer(minLength: 6)
                        sourceButton
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Tapping cycles Auto -> YouTube Music -> Spotify -> Apple Music. A widget button can only
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
        .help(state.sourceLabel)
    }

    /// A widget can't tick once a second, but `ProgressView(timerInterval:)` animates on its own
    /// between reloads, so the bar keeps moving without burning refreshes.
    @ViewBuilder
    private var progress: some View {
        if state.duration <= 0 {
            // Live radio genuinely has no duration or seek position, so a progress bar would
            // just sit empty at zero. Label it instead.
            if state.isPlaying {
                Text("LIVE")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.white.opacity(0.16), in: Capsule())
            }
        } else {
            let start = state.capturedAt.addingTimeInterval(-state.elapsed)
            let end = start.addingTimeInterval(state.duration)
            if state.isPlaying {
                ProgressView(timerInterval: start...end, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.linear)
                .tint(.white)
            } else {
                ProgressView(value: min(state.elapsed / state.duration, 1))
                    .progressViewStyle(.linear)
                    .tint(.white.opacity(0.7))
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
            Image(systemName: "music.note.list")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(.secondary)
            Text(state.statusNote.isEmpty ? "Not playing" : state.statusNote)
                .font(.system(size: 12, weight: .medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
