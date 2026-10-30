# Architecture and feasibility review

Reviewed 2026-10-30. Upstream base: `ignasave/mac-music-widget@c1e1f25`.

## Upstream inspection

The repository is MIT licensed, copyright Ignacio Martin Vazquez. `LICENSE` is unchanged.
The source consists of two XcodeGen targets with no external runtime package dependencies:

| Path | Responsibility and observed flow |
|---|---|
| `project.yml`, `build.sh` | Generate an Xcode project; Swift 5 language mode, macOS 14 minimum; ad-hoc build/install helper |
| `Host/main.swift` | AppKit accessory app, menu source/browser selectors, two-second polling, source arbitration, change-driven WidgetCenter reload requests |
| `Host/MusicSources.swift` | Spotify and Apple Music AppleScript adapters; native artwork or public iTunes artwork lookup |
| `Host/Bridge.swift`, `Host/Browser.swift` | YouTube Music DOM queries through browser AppleScript; Safari and Chromium dictionaries differ |
| `Host/HTTPServer.swift` | Network.framework loopback server for state, artwork and commands |
| `Shared/NowPlaying.swift` | Codable state/command contract |
| `Widget/MusicWidget.swift` | SwiftUI WidgetKit timeline, artwork fetched before rendering, AppIntent controls, small/medium layouts |

The upstream widget is already a real WidgetKit extension despite README wording centered on desktop placement. This fork instructs installation in Notification Center. WidgetKit itself also allows desktop placement; no floating-window implementation was added.

Original event flow: player → host poll → normalized state → loopback GET `/state` → timeline + artwork → widget. AppIntent → POST `/cmd/*` → host → player's AppleScript API. Source changes pause the source being left. These music adapters remain intact; source arbitration now also includes Safari YouTube.

The upstream reload condition compared absolute playback position against the last publication, producing requests roughly every 12 seconds during playback. A shared gate now ignores ordinary progress and coalesces visible changes. Artwork changes are included. Safari expiry renewal also requests updates, but cannot override WidgetKit scheduling.

## Options considered

| Approach | Feasibility | Permissions and limits | Decision |
|---|---|---|---|
| Public system Now Playing APIs | Public APIs publish/manage an app's own playback. They are not a documented general query for arbitrary apps' current metadata. The newer Now Playing framework is also publication/session oriented. | No supported universal read API was established in this review. Control Center displaying a title does not grant third-party access. | Do not claim a public universal reader exists. |
| Private `MediaRemote` | Existing projects can obtain system-selected title/artwork and transport across apps that publish metadata. This could broaden coverage without site DOM adapters. | Private API/entitlement restrictions changed in macOS 15.4. An adapter uses a system Perl process and a helper framework as a compatibility workaround. Its “all versions” claim is the project's claim, not verified here. App Store guideline 2.5.1 requires public APIs. | A possible personal-use experiment, not included or executed in this MVP. Do not disable SIP or claim future compatibility. |
| Safari Web Extension | Site-authorized content scripts can inspect the player DOM. Background scripts can send native messages; the native extension and host can share an App Group. | Explicit Safari enablement and website access; signing/App Group configuration; page lifecycle and browser throttling; site DOM may change. | Implemented for regular YouTube watch pages only. Instagram remains excluded. |
| Safari AppleScript | A host can query tab URLs/titles and execute JavaScript. The existing YouTube Music path already uses this. | Automation consent; JavaScript requires Safari's developer setting. A tab title alone does not prove playback or provide artwork. Broad scripting access and fragile DOM queries remain. | Preserve for YouTube Music; do not add it as a silent fallback for general videos. |

Sources: [Apple Now Playing](https://developer.apple.com/documentation/nowplaying), [MPNowPlayingInfoCenter.default](https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter/default()), [external player events](https://developer.apple.com/documentation/mediaplayer/handling-external-player-events-notifications), [Safari native messaging](https://developer.apple.com/documentation/safariservices/messaging-between-the-app-and-javascript-in-a-safari-web-extension), [Safari permissions](https://developer.apple.com/documentation/safariservices/managing-safari-web-extension-permissions), [Safari developer settings](https://developer.apple.com/documentation/safari-developer-tools/developer-settings).

Private API evidence: [MediaRemote adapter implementation and explanation](https://github.com/ungive/mediaremote-adapter), [Fastfetch's macOS 15.4 regression](https://github.com/fastfetch-cli/fastfetch/issues/1737), [App Review Guidelines §2.5.1](https://developer.apple.com/app-store/review/guidelines/#software-requirements). No code or license from those projects was imported.

**Instagram constraint:** any future universal Now Playing experiment must prove it can exclude Instagram. A Safari bundle identifier alone cannot identify which website produced media. If website attribution is unavailable, do not enable a generic Safari fallback that would accidentally include Instagram.

## Implemented Safari pipeline

1. Manifest V2 declares only `nativeMessaging` and `https://www.youtube.com/*`; top-frame content injection only. No all-sites access, external-page messaging, or screen capture.
2. The content script accepts only `/watch` with an 11-character ID, matching `ytd-watch-flexy[video-id]`, a loaded video and a nonempty title. It hides metadata during ad playback or a navigation transition. Shorts/embeds are deliberately excluded.
3. Player events and a two-second heartbeat send a bounded snapshot. The background validates Safari-provided sender origin, top frame and non-private tab, then serializes native requests.
4. The native extension validates types/lengths/IDs again, supplies its own receipt timestamp, and atomically stores one snapshot per Safari profile/tab in the App Group. Heartbeats preserve the last playback transition time. No arbitrary artwork URL crosses this boundary.
5. The host selects fresh evidence (45-second lifetime). Playing wins over paused; newer playback transitions win ties; tab ID breaks remaining ties. Safari is independent of the existing YouTube Music browser preference.
6. The host publishes the selected state through the existing loopback protocol. The WidgetKit timeline fetches the thumbnail before rendering and includes an expiry entry. It displays the thumbnail/title/state and transport buttons; it does not fetch or decode video.
7. Commands carry the displayed document UUID and video ID. The host rejects stale targets and stores a single pending command for eight seconds. The next native response returns it; the background sends it to that tab; the content script checks document/video/expiry/duplicate ID before acting. Previous/next click only enabled YouTube controls. Playback activation policies still apply.

The host polls rather than relying on unverified cross-process wakeup guarantees. It must remain running. The widget retains the original loopback connection so Spotify/Apple Music/YouTube Music and the ad-hoc build remain available. App Group sharing is limited to the host/Safari extension; the widget needs only its original network entitlement.

## Limits and next evidence needed

- **Freshness:** Apple's ordinary budget example is 40–70 daily refreshes for a frequently viewed widget; the OS can coalesce/defer requests. The 30-second application gate is a request ceiling, never a refresh promise. An expiry entry may make the widget unavailable until the next system reload, even while a video keeps playing. Test with Notification Center both visible and hidden.
- **Controls:** two-second browser heartbeat is best effort; suspended tabs can miss the eight-second delivery window. Commands are consumed once, are not retried and do not have end-to-end acknowledgement. Repeated clicks coalesce. UI state only reflects later observations, not optimistic success.
- **Metadata/DRM:** a protected stream can play without exposing usable title/artwork, or can offer metadata unrelated to its current ad. This implementation neither reads encrypted video nor bypasses access restrictions. Thumbnail failure yields a placeholder.
- **Site fragility:** YouTube may change its DOM, SPA events or player controls. The adapter fails closed for mismatched video identity. It requires live signed-extension testing after such changes.
- **Persistence:** expired snapshots are ignored and cleaned on later input; interruption can leave stale local files. Unconsumed command files can also remain but expire and are never executed after expiry. These are local caches, not a guarantee of immediate physical deletion.
- **Trust:** local loopback requests enforce HTTP method, Host and browser-origin rejection. They do not authenticate against other same-user local programs. App Group access depends on correct signing/entitlements.
- **Other sites:** add an explicit permission and a separate adapter only after verifying title, artwork, playback, controls, ad/DRM behavior, SPA navigation, background tabs and revocation. Instagram is excluded by user requirement.

References: [WidgetKit updates](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date), [App Group containers and signing](https://developer.apple.com/documentation/xcode/accessing-app-group-containers).
