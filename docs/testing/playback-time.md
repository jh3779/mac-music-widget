# Playback time — 1.3.0

2026-11-03. Adds elapsed / total time and a display-only progress bar to Small and Medium Notification Center widgets.

Safari's actual `#movie_player` video supplies currentTime, duration, playbackRate and whether time is advancing. Both ordinary YouTube and YouTube Music adapters use the same normalization. Infinite/live duration is represented without JSON infinity; unavailable duration remains unknown. The native boundary validates finite numbers and strict booleans, while optional fields preserve older messages and cached JSON. Resource addresses remain in tab memory.

The host projects elapsed time from receipt time to publication. SwiftUI bounded timer text and progress advance at 1x without per-second WidgetCenter requests. Pause, buffering and seeking observations freeze or correct the model. Non-1x playback uses a rate label and at most nine additional 30-second timeline samples before the existing five-minute stale entry. The OS may defer those entries or reload requests. A progress bar does not seek media.

## Verification

- Swift 24 tests and JavaScript 23 tests: **47 PASS**.
- Shared line coverage: **370/409, 90.46%**. JS: **99.59% lines, 91.24% branches, 83.87% functions**. These are not whole-app UI coverage.
- Tests cover finite time delivery through both JS adapters and the native boundary, pause/buffering, rates, live/invalid inputs, hour formatting, end clamping, ordinary ticks versus seeks, and bounded non-1x timeline samples.
- A radio without a finite duration must not trigger periodic false seek-correction reloads; a dedicated failing test preceded that correction.
- Independent agent diff review found no P1/P2. The reviewer independently ran the 23 JS tests.
- Signed Release build of host, Safari extension and WidgetKit extension: **BUILD SUCCEEDED**. Local app version 1.3.0 installed; codesign verification passed. Prior installation was retained in the task's work folder.
- Actual time-data receipt and Small/Medium visual fit require a refreshed, playing Safari tab. They are not inferred from compilation or reported as passed without observation. No actual playback was initiated solely to obtain these results.

## TDD checkpoints

| Stage | Evidence |
|---|---|
| `7ac4830` RED | Missing PlaybackTime/native time API; two new JS delivery/normalization tests failed. |
| `460fe50` GREEN | 22 Swift + 23 JS passed with timing delivery and model implemented. |
| `1c46b73` RED | Non-1x timeline test saw only 2 entries instead of 11; future sample/date/position assertions failed. |
| `cd663b5` GREEN | 23 Swift + 23 JS passed; both widget sizes compile with time/progress and bounded speed samples. |
| `03cad43` RED | Live radio incorrectly requested a reload after an ordinary 35-second heartbeat. |

Run `swift test --enable-code-coverage`, `node --test Tests/JavaScript/*.test.cjs`, and the repository Validate workflow. CI builds the Safari and music-only configurations without signing. Local signing/installation does not make this a notarized public release.

To verify on the installed Mac: refresh a permitted YouTube or YouTube Music tab, resume its player, then refresh the widget. Compare elapsed/total to Safari; pause/resume and seek; check an hour-long video, a non-1x rate, and live/unknown duration. Observe Small and Medium layouts including the temporary source button. Existing WidgetKit scheduling limitations still apply.
