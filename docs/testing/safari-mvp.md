# Safari YouTube MVP: validation evidence

Date: 2026-10-30. User journeys: show regular Safari YouTube title/thumbnail/state in the **Notification Center WidgetKit widget**, control the existing Safari video without rendering video in the widget, preserve music adapters, and exclude Instagram.

## Executed results

Environment: Apple Silicon Mac, Xcode 27.1 (`27A9275`), Apple Swift 6.4 compiler in Swift 5 language mode, XcodeGen 2.46.0, Node 26.0.0. Deployment target is macOS 14; this is not proof of runtime behavior on every supported OS.

| Guarantee / check | Actual command or test | Result |
|---|---|---|
| Native message types, bounds and video identity; safe thumbnail construction | `WebMediaTests.testNativeBoundaryRejectsUntrustedMetadata` | PASS |
| Freshness, playing-vs-paused selection, heartbeat ordering, atomic storage, profile separation and corrupt input | `WebMediaTests` | PASS |
| Commands bind to a tab/document, expire after eight seconds and are consumed once | `WebMediaTests.testCommandsAreBoundToDocumentExpireAndAreConsumedOnce` | PASS |
| Reload coalescing, artwork changes and interactive override | `WebMediaTests.testReloadGateCoalescesChangesButEventuallyPublishesLatest` | PASS |
| Loopback controls require POST and reject browser origin/invalid Host; document/video target parsing | `LoopbackRequestTests` | PASS |
| YouTube-only eligibility; Instagram posts/reels/embeds excluded; minimal manifest permissions | `Tests/JavaScript/media.test.cjs` | PASS |
| Background origin/frame/private-mode checks and native command routing | `Tests/JavaScript/extension.test.cjs` | PASS |
| Document/video mismatch, duplicate/expired commands, disabled previous button, SPA navigation, autoplay rejection | Content-script tests using a deterministic DOM/browser fixture | PASS |
| Native status popup: success/error/disconnection | Popup fixture test | PASS |
| Swift shared-core suite | `CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" swift test --disable-sandbox --scratch-path .build/tests --enable-code-coverage` | **10 tests, 0 failures** |
| JavaScript suite | `node --experimental-test-coverage --test-coverage-include='**/Safari/Resources/*.js' --test Tests/JavaScript/*.test.cjs` | **11 tests, 0 failures** |
| Safari + host + WidgetKit integration compilation | `xcodegen generate --spec project-safari.yml`, then `xcodebuild -project MacMusicWidget.xcodeproj -scheme MacMusicWidgetHost -configuration Debug -derivedDataPath .build/xcode-safari CODE_SIGNING_ALLOWED=NO build` | **BUILD SUCCEEDED** |
| Safari resource packaging | Inspected built `.appex/Contents/Resources` | manifest, background, content, metadata helper and popup all present |
| Original music-only configuration | `./build.sh` (local XcodeGen on PATH) | **BUILD SUCCEEDED**, ad-hoc app produced; not launched or installed |
| Original license and browser adapters | `git diff upstream/main -- LICENSE Host/Bridge.swift Host/Browser.swift` | Unchanged |
| Formatting | `git diff --check` | PASS |

The first restricted execution of the music-only build failed in `iconutil` with `Invalid Iconset`. Retrying the same reviewed build outside that restriction succeeded, including icon generation. This was an execution-environment failure, not a claimed successful first run.

Xcode emitted simulator-service diagnostics in the restricted environment and ordinary metadata/script-phase warnings; the macOS application/extension builds completed successfully. There are no iOS simulator tests in this project.

## Coverage scope

Measured Swift shared-core line coverage: **193/225 lines (85.8%)**. Per file: `WebMedia.swift` 90.6%, `WidgetReloadGate.swift` 95.2%, `LoopbackRequest.swift` 90.0%, existing/extended `NowPlaying.swift` 66.0%.

Node/V8 coverage for the four exercised extension JavaScript files reports **100% lines, 87.1% branches, 79.2% functions**. VM fixture coverage is not proof of Safari compatibility; line metrics especially overstate confidence for compact one-line callbacks. These numbers are not coverage for the entire host app, AppIntent integration, native extension lifecycle or WidgetKit rendering.

No live browser E2E, signed App Group IPC, Notification Center rendering, or real-player regression test is claimed. The current environment reported `0 valid identities found` for code signing. A developer Team, valid signing identities and App Group configuration are still required for the live test path.

## TDD checkpoints

There was no external plan file. Tests were derived from the user journeys above and subsequent control/Instagram clarifications.

| Stage | Commit | Observed evidence |
|---|---|---|
| Metadata RED | `0153550` | Swift test compilation reached the new tests and failed because `WebMediaSnapshot` was absent; JS tests failed because the metadata implementation did not yet exist. An earlier cache-permission failure was corrected before counting RED. |
| Requested controls RED | `25cae1d` | Test referenced missing command mailbox API and new snapshot identity fields. |
| Initial GREEN | `d25f2fa` | Eight Swift and two JS tests passed; all three Xcode targets built. |
| Request-boundary RED | `ce9e6a1` | `LoopbackRequest` missing at compile time. |
| Request-boundary GREEN | `d532382` | Ten Swift tests passed; expanded JS suite and Instagram exclusion passed. |
| Stale-command RED | `df5cf41` | Expired-command test observed `true !== false`; native request tests referenced missing video-ID binding. |
| Stale-command GREEN | `8512feb` | Same suites passed with video-ID binding and expiration enforced; three-target build passed again. |

These checkpoints remain reachable on `feat/safari-youtube-notification-widget`. Preserve this table in any later squash so the RED/GREEN evidence remains reviewable.

## Required manual acceptance tests

Use the README's signing/install steps first. Keep the host running and add the widget through the **date/time → Notification Center → Edit Widgets** flow. Record OS/Safari version, source state, host response time, widget response time and results; do not simply mark these passed after a compile.

| Scenario | Expected result | Current status |
|---|---|---|
| Enable extension and grant youtube.com access | Toolbar native status succeeds; host reads the same App Group | Not run |
| Play a regular public YouTube video | Correct title/thumbnail and playing state in small and medium widgets | Not run |
| Pause/resume from Safari and widget | State follows; widget controls affect only the displayed tab/video | Not run |
| Playlist first/middle/last item | Previous/next reflects enabled YouTube buttons; no invented browser-history behavior | Not run |
| Two tabs, two windows, multiple Safari profiles | Playing/newest transition wins; no cross-tab/profile command | Not run |
| Navigate to another video while widget is stale | Old widget controls are ignored until target matches | Not run |
| Ads, autoplay transition, title change, live video | No previous-video/ad metadata mismatch; no fake progress for general videos | Not run |
| Close tab, quit Safari, revoke permission, disable extension | Host excludes expired snapshot; widget eventually expires/reloads | Not run |
| Suspend tab or sleep/wake Mac | Expired commands never replay; fresh data resumes when Safari runs again | Not run |
| Private window, Shorts, external embeds, Instagram reel/post | No supported snapshot from those pages | Not run |
| Safari autoplay rejection | No optimistic play-state update; manually play in Safari to recover | Not run |
| Thumbnail network failure / restricted video | Title/state remains usable where available; image placeholder, no DRM workaround | Not run |
| Spotify / Apple Music / YouTube Music | Existing reading/artwork/controls/source switching still work | Not run |
| Notification Center visible/hidden over time | Measure real throttling and expiry; never infer latency from the two-second poll interval | Not run |

Known follow-ups after signed testing: improve user-visible command failure reporting if needed; validate DOM against actual YouTube changes; consider less aggressive expiry/renewal only after measuring real WidgetKit behavior. Other streaming sites need individual adapters and tests. **Instagram remains excluded**, including in any future optional system Now Playing path.
