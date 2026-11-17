# Apple TV app to-do

This checklist tracks requests for version 0.1.2. Items are checked only when implemented and verified, or published where requested.

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

## Preserve existing behavior

- Full-height, original-aspect video beside or under the mini guide; top-right preview in the full guide.
- Back closes guides; Left/Right browse time pages in the full guide; controlled held-arrow repeat.
- Native controls from Up, Down, or Select, with Rejoin Live and Last Channel; seeking stops at live.
- Timestamped bottom-left comments, original yellow floating reactions, channel icons, and a contiguous red time line behind guide text.

## Hardware confirmation

- [ ] Confirm the replacement no longer crashes on the user's Apple TV 4K third generation / tvOS 27.2 after Signulous installation.
- [ ] Confirm physical-device captions, normalization, AirPods stereo output, circular-scrolling feel, and playback after reopening. Simulator checks alone do not establish these results.
