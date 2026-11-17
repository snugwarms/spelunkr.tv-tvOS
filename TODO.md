# Apple TV app to-do

This checklist tracks app requests and releases. Items are checked only when implemented and verified, or published where requested.

## Published

- [x] Publish source and unsigned IPA for 0.1.1 with the reproduced Release startup crash fixed.
- [x] Remove live-caption code from 0.1.1; keep that release available separately.
- [x] Put a prominent **UNOFFICIAL** notice at the top of the GitHub README.
- [x] Include the owner's personal Signulous recommendation in the README.

## Version 0.1.2

- [x] Restore automatic captions on top of the startup fix. Prefer native tvOS generated subtitles when available; start speech processing only after the video is ready. The shared audio path and caption availability passed Release checks; actual transcription remains a hardware check.
- [x] Publish a network report with measured request counts, destinations, cold startup, warm reopen, ongoing polling, media traffic, and limitations. **Leave the report unchanged from this point, per the user's latest instruction.** The app's final polling setting is five minutes.
- [x] Reduce server load: **five-minute lineup, comment, and reaction checks**, HTTP caching, capped concurrent requests, bounded tape-time queries, cached community windows, and no polling for disabled overlays. Five-minute community polling is the user's latest request, replacing the earlier one-minute plan. Implemented and checked; published report remains unchanged as requested.
- [x] Slow circular/iPod scrolling and use a gentler acceleration curve. Implemented; simulated touch-trace tests pass; real Siri Remote feel still needs confirmation.
- [x] Add smooth, fast guide scrolling, respecting Reduce Motion. Implemented and visually reviewed.
- [x] Rejoin live and start playing whenever the app is reopened or returns from the background, even after pausing. Verified by pause/background-return and cold-reopen Release checks.
- [x] Keep video/audio playing while the OS Quick Settings/Control Center is open; do not pause or retune merely because the scene is temporarily inactive.
- [x] Show the tape synopsis at the top of the mini guide and in the full guide; make the channel description smaller. Cache summaries; only fetch missing Internet Archive metadata after focus has settled for a second. No description requests go to Spelunkr's server. Implemented and checked in the guides.
- [x] Reduce loud bumper music through **universal LUFS normalization** for tapes, ads, and bumpers. Use a real loudness meter, bounded gain, and peak protection; share audio processing with captions. The initial fixed bumper reduction is superseded by this request.
- [x] Enforce stereo output/downmixing and disable audio spatialization for videos and bumper music, including AirPods playback; do this silently.
- [x] Keep delay introduced by volume leveling below five seconds, within the user's five-to-ten-second ceiling. Keep reaction/comment presentation locked to the displayed tape timestamp; remove early/late “show immediately” reaction behavior. A read-only capability probe succeeded; no push subscription is shipped. The app follows the requested five-minute polling policy.
- [x] Open both mini guide and full guide on the currently playing channel and bring it into view.
- [x] When scrolling vertically on the full guide's current-time page, select the program airing now on each destination channel instead of its leftmost program.
- [x] Keep three-digit channel numbers on one line and move their column slightly left in both guides.
- [x] Run the final optimized checks (**26 core tests and six simulator UI tests passed**), build and verify the arm64 IPA, and publish source plus release assets. [Version 0.1.2](https://github.com/snugwarms/spelunkr.tv-tvOS/releases/tag/v0.1.2) is live. Local IPA: `build/releases/0.1.2/Spelunkr-tvOS-unsigned.ipa`.

## Version 0.1.3 hotfix

- [x] Reduce circular touchpad scrolling again: four rows per slow turn instead of six, gentler acceleration capped at 1.25×, and at least 160 ms between row movements. Preserve slide animations and arrow-button timing. Optimized touch-trace checks passed; physical remote feel needs confirmation.
- [x] Remove Watch TV, Earlier, Now, and Later buttons from the full guide and enlarge the top-right preview by 20% in each dimension. Keep Left/Right time browsing and Back navigation working. Simulator navigation checks and screenshot review passed.
- [x] Verify optimized scrolling tests and guide navigation (**26 core tests and two Release simulator checks passed**) and build and validate the unsigned arm64 Apple TV IPA, version 0.1.3 build 4.
- [x] Publish source plus hotfix assets. [Version 0.1.3](https://github.com/snugwarms/spelunkr.tv-tvOS/releases/tag/v0.1.3) is live; both uploads and the IPA checksum were verified. Local IPA: `build/releases/0.1.3/Spelunkr-tvOS-unsigned.ipa`.

## Version 0.1.4 subtitle hotfix

- [x] Show a single subtitle control: use the native menu when subtitles are available, and the app's automatic-caption toggle otherwise. Keep its state current. Native-track and fallback-control checks passed.
- [x] Save native subtitle On/Off, language, and generated/embedded preference, and restore it after closing/reopening, channel changes, and background return. Native language/Off restoration on a new player item and fallback On/Off across actual app termination/relaunch passed.
- [x] Verify subtitle toggling and persistence in Release (**26 core tests and six simulator checks passed**) and build and validate the unsigned arm64 IPA, version 0.1.4 build 5. Actual generated transcription still needs hardware confirmation.
- [x] Publish source plus hotfix assets. [Version 0.1.4](https://github.com/snugwarms/spelunkr.tv-tvOS/releases/tag/v0.1.4) is live; uploads and the IPA checksum were verified. Local IPA: `build/releases/0.1.4/Spelunkr-tvOS-unsigned.ipa`.

## Version 0.1.5 — Open Mic / Warp Zone investigation

- [x] Identify the sampled tapes: Open Mic's “Jam Session in Judique” (`teli1ns-Jam_session_in_Judique1991`) and Warp Zone's “Bad Influence!: Ecco, Lemmings” (`bad_influence_se1ep9`), observed at 20:42 UTC on 17 November. Both files and nonzero byte-range requests were available; both use H.264/AAC.
- [x] Reproduce HTTP 403 on both channel manifests without site-origin headers and HTTP 200 with them. Supply Origin/Referer only on Spelunkr broadcast requests. Regression checks cover both hosts, Archive header isolation, and unchanged request counts. **27 Release core tests passed.** The frozen network report remains unchanged.
- [x] Check native playback of the two exact recordings and a known-good control, including live-position seeking and normalization: **three Release simulator checks passed through a temporary local relay**. Direct native external connections failed with network-unavailable errors even for the control; these runs do not establish direct-device playback. No relay is included in the app.
- [x] Improve the diagnostic CLI so requested channels can be checked together without fetching all channel guides; add opt-in, bounded live-media checks that ordinary tests skip.
- [x] Build and validate the unsigned arm64 Apple TV IPA, version 0.1.5 build 6, and publish source plus release assets. [Version 0.1.5](https://github.com/snugwarms/spelunkr.tv-tvOS/releases/tag/v0.1.5) is live; uploads and the IPA checksum were verified. Local IPA: `build/releases/0.1.5/Spelunkr-tvOS-unsigned.ipa`.
- [x] Record the user's hardware feedback: 0.1.5 did **not** resolve the playback freeze. The confirmed recordings and follow-up are tracked under 0.1.6.

## Version 0.1.6 — startup freeze investigation

- [x] Investigate the 25–50 second freeze and No Signal retry on “Sons of Pitches in Concert” and “Bad Influence!: Cheat Devices, Code Screens.” The old fallback returned to the same mirror, and the old 25-second timer discarded stalled startup. Prefer the primary US storage address, try distinct replicas on failure, retain progressing loads, and start available media promptly. Stale item callbacks are isolated by attempt.
- [x] Verify actual codecs and use Apple TV compatible conversions when needed. Sons/Bad Influence use H.264 Constrained Baseline level 3.0; Blockbuster uses H.264 Main level 3.0. All are 640×480 yuv420p with stereo AAC-LC at 44.1 kHz. These tapes already meet Apple TV's format support. The resolver also selects existing Archive H.264 conversions by recording provenance when needed.
- [x] Test paused startup → audio processing → live seek → play for all three recordings. Exercise the actual player model with an unavailable primary, advancing video frames, a genuine 30-second live-range delay, catch-up within eight seconds of live, and manual rewind. Fix the extra lag found by the delayed-start check.
- [x] Show the installed app version at the bottom right of the mini guide. Screenshot review and a version-matching UI check passed.
- [x] Include Mandatory Viewing's current tape, “Blockbuster: Customer Service Training,” in the same investigation. All three sampled metadata responses selected Canadian mirrors under the previous code and expose separate US storage addresses. Native playback checks of all three exact recordings passed through the temporary relay.
- [x] Replace generic No Signal with clearer connection, download-stall, missing-recording, access, and format errors; include retry timing and a smaller diagnostic code/server line. HTTP failures are not mislabeled as unsupported codecs. A genuinely unavailable decoder waits for the next program instead of repeatedly requesting the same file.
- [x] Pass **35 Release core tests and 16 Release simulator checks**. Recovery tests use the real TVModel with injected feeds and byte transport, not a replacement player implementation. Direct native external access on this development machine remains unavailable; the temporary relay is not part of the app.
- [x] Build/validate the unsigned arm64 IPA, version 0.1.6 build 7, and publish source plus release assets. [Version 0.1.6](https://github.com/snugwarms/spelunkr.tv-tvOS/releases/tag/v0.1.6) is live; uploads and the IPA checksum were verified. Local IPA: `build/releases/0.1.6/Spelunkr-tvOS-unsigned.ipa`.
- [ ] Confirm the three reported channels play directly on the user's Apple TV with 0.1.6; the installed version and detailed error line now identify any remaining failure.

## Preserve existing behavior

- Full-height, original-aspect video beside or under the mini guide; top-right preview in the full guide.
- Back closes guides; Left/Right browse time pages in the full guide; controlled held-arrow repeat.
- Native controls from Up, Down, or Select, with Rejoin Live and Last Channel; seeking stops at live.
- Timestamped bottom-left comments, original yellow floating reactions, channel icons, and a contiguous red time line behind guide text.

## Hardware confirmation

- [ ] Confirm the replacement no longer crashes on the user's Apple TV 4K third generation / tvOS 27.2 after Signulous installation.
- [ ] Confirm physical-device captions, normalization, AirPods stereo output, circular-scrolling feel, and playback after reopening. Simulator checks alone do not establish these results.
