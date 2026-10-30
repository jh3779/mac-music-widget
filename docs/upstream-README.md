<div align="center">

<img src="Resources/AppIcon.svg" width="96" alt="Mac Music Widget">

# Mac Music Widget

**A real macOS desktop widget for Apple Music, Spotify and YouTube Music.**

Not a floating window pretending to be a widget — an actual WidgetKit widget you add
from the desktop widget gallery, with working playback controls.

Built by **[Ignacio Martin Vazquez](https://github.com/ignasave)** · MIT licensed

</div>

---

## What it does

- Shows what's playing — cover art, title, artist, progress
- **Working transport controls** — previous / play-pause / next, right in the widget
- **Three sources**: Apple Music, Spotify, YouTube Music (in any browser)
- **Auto-detect** — follows whichever player is actually playing
- Switching sources pauses the one you're leaving
- Small and medium widget sizes

## Install

```bash
git clone https://github.com/ignasave/mac-music-widget.git
cd mac-music-widget
./build.sh --install
```

Then **right-click the desktop → Edit Widgets**, search *Mac Music Widget*, and drag it out.

A prebuilt app is attached to the [latest release](https://github.com/ignasave/mac-music-widget/releases)
if you'd rather not build it.

Requires macOS 14+, and Xcode plus [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`) to build from source.

### First run

1. Approve the **Automation** prompt the first time it reads a player.
2. **YouTube Music only** — enable *Allow JavaScript from Apple Events*:
   Chrome → **View → Developer**, Safari → **Develop**. Apple Music and Spotify need nothing.

The host app runs in the background with a music-note menu bar icon: source picker,
browser picker, and Quit.

## How it works

A widget extension is **sandboxed and cannot send Apple Events**, so it can't read a music
player at all. That single constraint dictates the whole architecture:

- **`MacMusicWidgetHost`** — a normal background app (`LSUIElement`, no Dock icon). The only
  process that talks to music players.
- **`MacMusicWidgetExtension`** — the widget. It renders, and nothing else.

They communicate over **loopback HTTP on `127.0.0.1:47893`**:

| Route | Purpose |
|---|---|
| `GET /state` | Current track as JSON |
| `GET /artwork` | Cover art for players that hand over bytes instead of a URL |
| `POST /cmd/{playPause,next,previous,cycleSource}` | Widget button → host drives the player |

Loopback rather than the conventional **App Group**, because App Group entitlements must be
validated by a provisioning profile — this way the whole project stays ad-hoc signed and builds
on any machine with Xcode. The extension only needs `com.apple.security.network.client`, and
binding with `requiredInterfaceType = .loopback` keeps the server off the network.

### Reading the players

| Source | Method | Notes |
|---|---|---|
| **Apple Music** | Native AppleScript dictionary | Artwork arrives as `raw data`, not a URL — normalised to PNG and served from `/artwork`. Catalog tracks expose none, so a cover is looked up via the public iTunes Search API |
| **Spotify** | Native AppleScript dictionary | Reports duration in **milliseconds**, unlike the others |
| **YouTube Music** | AppleScript → JavaScript in a browser tab | The fragile one; depends on YouTube's player DOM |

Apple Music and Spotify are officially scriptable. The YouTube Music path injects JavaScript and
will break whenever Google reshuffles the player.

## Things learned the hard way

Documented because none of them are obvious, and each cost real debugging time:

- **Chromium's scripting command is `execute <tab> javascript "…"`.** Writing Safari's
  `… "…" in <tab>` form parses as `get "…" in <tab>` and fails with a misleading
  `-1723 Access not allowed`, which looks exactly like a permissions problem.
- **A widget renders once.** Fetching an image with `.task` inside the view never appears —
  artwork has to be resolved in the `TimelineProvider`, before the entry exists.
- **Widget layout must not be sized by its content.** The artwork box uses `Color.clear` as its
  sizing anchor with the cover drawn as an overlay; otherwise the row visibly shifts when an
  asynchronously-fetched cover lands.
- **AppleScript renders absent properties as the literal text `"missing value"`.** It is not data.
- **Live radio genuinely has no duration or position** — it gets a LIVE badge instead of a
  progress bar pinned at zero.
- **Widgets have no hover state.** The source switcher reveals for 12 s after any button press,
  because that's the closest achievable behaviour.

## Layout

| Path | Purpose |
|---|---|
| `Shared/NowPlaying.swift` | State contract + loopback endpoints, compiled into both targets |
| `Host/main.swift` | Poll loop, source resolution, command dispatch, reload policy |
| `Host/MusicSources.swift` | Apple Music and Spotify AppleScript adapters |
| `Host/Bridge.swift` | Browser AppleScript + JavaScript bridge |
| `Host/HTTPServer.swift` | Loopback server (`Network` framework, no dependencies) |
| `Widget/MusicWidget.swift` | Timeline provider, `AppIntent` buttons, layouts |
| `project.yml` | XcodeGen input — a widget extension can't be built by SwiftPM |

## License

[MIT](LICENSE) © [Ignacio Martin Vazquez](https://github.com/ignasave) — free to use, modify and
ship, commercially or otherwise. Keeping the copyright line is all that's asked.
