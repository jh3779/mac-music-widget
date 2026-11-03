# Creator labels and connection recovery — 1.4.0

2026-11-03. User journeys: read the uploader under the title; identify why Safari metadata is missing; recover via a source change, app launch or Safari settings without additional website permissions.

Small and Medium now show the existing author field rather than replacing it with the playback sentence. Safari YouTube labels it as a channel; music sources label it as an artist. Whitespace is normalized, an absent name has an explicit fallback, and VoiceOver gets the full role/name plus playback state. Channel names are supplied by YouTube's visible owner element, not independently verified identities. No new scraping endpoint or media fetch is added.

The host distinguishes recent metadata, a permitted page without media, a reachable native bridge without page evidence, expired metadata, configuration errors, and host HTTP failure. These observations cannot establish that website permission was explicitly denied. The source button remains available, including empty state. Transport and source-change pause commands are rejected when there is no displayed media, preventing blind legacy browser commands.

Recovery URLs derive from the containing bundle ID and allow only app launch and Safari extension settings. Parameters, foreign schemes and unknown actions are rejected. The host Info.plist registers its own bundle-ID scheme. Widget empty states use an app-launch widgetURL; Medium also has a Safari-settings link. The extension popup offers both routes when native supplies them. These are user-initiated; the app does not enable permissions or automatically reload/play pages.

The App Group health cache contains only receipt time and an optional approved source. It retains at most 64 recent keys, ignores records at 10 minutes, and prunes on subsequent writes. Ping does not disguise an expired player as healthy. An unrelated tab close creates no record; valid metadata in another tab takes priority over an empty-page record. No additional domains or permissions, Instagram metadata, titles, authors or URLs are added to health records.

## Automated evidence

| Guarantee | Test | Result |
|---|---|---|
| Creator whitespace, role and missing-name fallback | ConnectionTests | PASS |
| No bridge, bridge-only, empty page, fresh and expired metadata differ | ConnectionTests | PASS |
| Other tab clears cannot hide fresh playback; unrelated closes leave no health record | ConnectionTests | PASS |
| Health records expire, are bounded and omit media identity | ConnectionTests | PASS |
| Only fixed containing-app recovery routes are accepted | ConnectionTests, extension.test.cjs | PASS |
| The approved sender origin determines no-media source | extension.test.cjs | PASS |
| Popup uses durable evidence despite background restart | extension.test.cjs | PASS |
| Existing timing, command targeting, Instagram exclusion and music adapters' shared policies | Existing test suites | PASS |

- RED checkpoint `d467a16`: Swift failed to compile because the new creator, connection and recovery APIs did not exist.
- RED checkpoint `83ace16`: three JS failures (Korean diagnostics, source-specific clear, durable popup state).
- GREEN: `CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" swift test --disable-sandbox --scratch-path .build/connection-tests --enable-code-coverage`: **29 passed**.
- GREEN: `node --experimental-test-coverage --test-coverage-include='**/Safari/Resources/*.js' --test Tests/JavaScript/*.test.cjs`: **26 passed**.
- Shared core line coverage **470/521 = 90.21%**. JS line **99.61%**, branch **92.00%**, function **83.87%**. These exclude native host/WidgetKit UI coverage.
- Safari three-target Release build with the existing development identity: **BUILD SUCCEEDED**, deep/strict codesign verification passed. Original LICENSE remains an app resource.

## Manual verification remaining

1. After installation, refresh an already-permitted Safari YouTube/YouTube Music tab and play media. Check Small and Medium title, full/long/absent channel or artist, state icon, elapsed/total and all buttons.
2. Cycle sources from the empty state; verify that an unrelated player is not controlled. Existing Spotify/Apple Music runtime regression remains manual.
3. Remove media, close a permitted tab and suspend Safari. Compare the empty-page and delayed-receipt instructions. The host discards command targets after 45 seconds; WidgetKit may keep its older display for minutes.
4. Quit only the host, use “앱 열기”, and verify the installed app launches. Test Safari settings from the popup and Medium empty state. Opening settings must not grant permission automatically.
5. Restart Safari/background extension and confirm recent metadata is still reported. Verify Instagram remains absent.

Automated results and installation do not establish these live UI steps as passed. OS reload budget and Safari suspension remain limitations; this change does not promise automatic reinjection or real-time widget updates.

References: [AppKit application URL handler](https://developer.apple.com/documentation/appkit/nsapplicationdelegate/application(_:open:)), [Widget URL](https://developer.apple.com/documentation/swiftui/view/widgeturl(_:)).

The music-only two-target Debug configuration also returned **BUILD SUCCEEDED** with signing disabled. This verifies compilation, not music app Automation permission or actual playback.
