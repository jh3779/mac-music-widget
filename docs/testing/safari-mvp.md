# Safari YouTube MVP: validation evidence

Date: 2026-10-30. User journeys: show regular Safari YouTube title/thumbnail/state in the **Notification Center WidgetKit widget**, control the existing Safari video without rendering video in the widget, preserve music adapters, and exclude Instagram.

This file records the 1.2.2 installation evidence. The subsequent 1.2.3 agent review, 39-test suite and build checks are recorded in [merge-review.md](merge-review.md). The installed 1.2.2 app was not replaced during that source review.

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
| Music metadata on URLs without a watch ID; CDN boundaries and old-song commands | Native Music test + Music content/background fixtures | PASS |
| Short browser lease does not erase display; heartbeats do not consume reload budget | `WidgetDisplayTests` | PASS |
| Swift shared-core suite | `CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" swift test --disable-sandbox --scratch-path .build/tests --enable-code-coverage` | **13 tests, 0 failures** |
| JavaScript suite | `node --experimental-test-coverage --test-coverage-include='**/Safari/Resources/*.js' --test Tests/JavaScript/*.test.cjs` | **15 tests, 0 failures** |
| Safari + host + WidgetKit integration compilation | `xcodegen generate --spec project-safari.yml`, then `xcodebuild -project MacMusicWidget.xcodeproj -scheme MacMusicWidgetHost -configuration Debug -derivedDataPath .build/xcode-safari CODE_SIGNING_ALLOWED=NO build` | **BUILD SUCCEEDED** |
| Safari resource packaging | Inspected built `.appex/Contents/Resources` | manifest, background, content, metadata helper and popup all present |
| Signed Safari + host + WidgetKit Release build, 1.2.2 | `xcodebuild` with the local Apple Development identity, manual signing, matching Team and Team-prefixed App Group | **BUILD SUCCEEDED** |
| Local installation and signatures | Installed to `/Applications/Mac Music Widget.app`; `codesign --verify --deep --strict`; version read from built Info.plist | PASS, 1.2.2; host and WidgetKit processes observed |
| MIT notice in downloadable binary | Compared `Contents/Resources/LICENSE` to repository `LICENSE` | Identical |
| Safari enablement and website access | Safari Settings UI: extension enabled; `youtube.com` allowed; manifest has only www/music hosts | PASS, private browsing and unsigned-extension setting left disabled |
| Live Safari native bridge and host | Popup reports ready; local `/state` contains Music title/artwork, playing state, tab/document identity and renewing validity | PASS for actual YouTube Music; no Apple Events JavaScript setting required |
| WidgetKit runtime | OS logs: successful timeline generation and artwork decoding; Notification Center UI shows installed widget and new refresh button; user confirms title and image after 1.2.2 | PASS for installation/title/artwork; long-term refresh timing still needs observation |
| Actual Music pause/resume command path | POST to the widget's document/video-bound loopback endpoint; observed pause, then restored original playing state | PASS, both observed in live host state; this does not claim a direct UI click on the AppIntent button |
| Original music-only configuration | `./build.sh` (local XcodeGen on PATH) | **BUILD SUCCEEDED**, ad-hoc app produced; not launched or installed |
| Original license and browser adapters | `git diff upstream/main -- LICENSE Host/Bridge.swift Host/Browser.swift` | Unchanged |
| Formatting | `git diff --check` | PASS |

The first restricted execution of the music-only build failed in `iconutil` with `Invalid Iconset`. Retrying the same reviewed build outside that restriction succeeded, including icon generation. This was an execution-environment failure, not a claimed successful first run.

Xcode emitted simulator-service diagnostics in the restricted environment and ordinary metadata/script-phase warnings; the macOS application/extension builds completed successfully. There are no iOS simulator tests in this project.

## Coverage scope

Measured Swift shared-core line coverage: **214/247 lines (86.6%)**. Per file: `WebMedia.swift` 91.0%, `WidgetDisplaySnapshot.swift` 90.9%, `WidgetReloadGate.swift` 100%, `LoopbackRequest.swift` 90.0%, existing/extended `NowPlaying.swift` 66.0%.

Node/V8 coverage for the four exercised extension JavaScript files reports **99.5% lines, 83.0% branches, 82.1% functions**. VM fixture coverage is not proof of Safari compatibility; line metrics especially overstate confidence for compact one-line callbacks. These numbers are not coverage for the entire host app, AppIntent integration, native extension lifecycle or WidgetKit rendering.

An earlier restricted identity lookup reported no valid signing identities. A lookup with the appropriate local access found the user's valid Apple Development identity, and signed installation/App Group IPC was subsequently verified. The previous signing blocker is resolved. This is a personal development-signed build, not a notarized public release.

Live installation reproduced a separate display bug: 1.2.0 replaced title/artwork with `Safari update unavailable` after its 45-second browser lease, even while fresh host data existed. The user confirmed that exact message. Version 1.2.1 retains display content, marks stale content after five minutes, and provides a refresh AppIntent. Version 1.2.2 also avoids replacing the browser's `MediaMetadata` global, selects the actual player's video ahead of unrelated page videos, and reports page delivery diagnostics in the popup. Both newly modeled adapter cases failed before the fix. The user confirmed title/artwork with 1.2.2; the actual Music pause/resume transport path passed. The two adapter changes were installed together, so the live failure is not attributed conclusively to one of them alone.

Updating the app can invalidate content scripts in already-open Safari tabs. Reload the tab and resume playback after each installation. This was observed during the live installation; the native popup could report ready while an old tab no longer submitted metadata.

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
| YouTube Music RED | `136546f` | New Music metadata helper/native identity tests failed before the adapter existed. |
| YouTube Music GREEN | `55c8a7b` | Eleven Swift and fourteen JS tests passed; signed 1.2.0 installed and live Music metadata received. |
| Widget display RED | `e4f1f3b` | User-reproduced blank display regression; tests could not find the new `WidgetDisplaySnapshot` policy. |
| Widget display GREEN | `529a1ab` | Thirteen Swift tests passed; signed 1.2.1 built and installed with a refresh control. |
| Page adapter RED | `a933305` | Two JS tests failed: native `MediaMetadata` was overwritten, and an unrelated unready video hid Music metadata. |
| Page adapter GREEN | `8d0c782` | Fifteen JS and thirteen Swift tests pass; signed 1.2.2 installed, user confirmed title/artwork, and actual Music pause/resume transport passed. |

These checkpoints remain reachable on `feat/safari-youtube-notification-widget`. Preserve this table in any later squash so the RED/GREEN evidence remains reviewable.

## Required manual acceptance tests

Use the README's signing/install steps first. Keep the host running and add the widget through the **date/time → Notification Center → Edit Widgets** flow. Record OS/Safari version, source state, host response time, widget response time and results; do not simply mark these passed after a compile.

| Scenario | Expected result | Current status |
|---|---|---|
| Enable extension and grant youtube.com access | Toolbar native status succeeds; host reads the same App Group | PASS for www/music permission and Music native IPC |
| Play YouTube Music, including a URL without a watch ID | Correct title/artwork/playing state reaches host | PASS; sustained renewing state observed after tab reload |
| 1.2.2 display repair | Preserve title/artwork despite short browser lease; stale marker/manual refresh after five minutes | Regression tests PASS; user confirmed title/image; sustained five-minute visual timing not measured |
| Play a regular public YouTube video | Correct title/thumbnail and playing state in small and medium widgets | Not run |
| Pause/resume from Safari and widget | State follows; widget controls affect only the displayed tab/video | Music transport endpoint → Safari pause/resume PASS; direct AppIntent UI click not verified |
| Playlist first/middle/last item | Previous/next reflects enabled YouTube buttons; no invented browser-history behavior | Not run |
| Two tabs, two windows, multiple Safari profiles | Playing/newest transition wins; no cross-tab/profile command | Not run |
| Navigate to another video while widget is stale | Old widget controls are ignored until target matches | Not run |
| Ads, autoplay transition, title change, live video | No previous-video/ad metadata mismatch; no fake progress for general videos | Not run |
| Close tab, quit Safari, revoke permission, disable extension | Host excludes expired snapshot; widget shows unavailable on next fetch, or marks last observation stale while waiting | Not run |
| Suspend tab or sleep/wake Mac | Expired commands never replay; fresh data resumes when Safari runs again | Not run |
| Private window, Shorts, external embeds, Instagram reel/post | No supported snapshot from those pages | Not run |
| Safari autoplay rejection | No optimistic play-state update; manually play in Safari to recover | Not run |
| Thumbnail network failure / restricted video | Title/state remains usable where available; image placeholder, no DRM workaround | Not run |
| Spotify / Apple Music / legacy YouTube Music | Existing reading/artwork/controls/source switching still work | Not run; new Safari Music path checked separately above |
| Notification Center visible/hidden over time | Measure real throttling and expiry; never infer latency from the two-second poll interval | Not run |

Known follow-ups after signed testing: improve user-visible command failure reporting if needed; validate DOM against actual YouTube changes; consider less aggressive expiry/renewal only after measuring real WidgetKit behavior. Other streaming sites need individual adapters and tests. **Instagram remains excluded**, including in any future optional system Now Playing path.
