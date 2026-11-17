# Apple TV app to-do

This checklist tracks requests for version 0.1.2. Items are checked only when implemented and verified, or published where requested.

## Published

- [x] Publish source and unsigned IPA for 0.1.1 with the reproduced Release startup crash fixed.
- [x] Remove live-caption code from 0.1.1; keep that release available separately.
- [x] Put a prominent **UNOFFICIAL** notice at the top of the GitHub README.
- [x] Include the owner's personal Signulous recommendation in the README.

## Version 0.1.2

- [ ] Restore automatic captions on top of the startup fix. Prefer native tvOS generated subtitles when available; start speech processing only after the video is ready. Initial caption-enabled Release checks passed; final audio integration remains.
- [ ] Publish a network report with measured request counts, destinations, cold startup, warm reopen, ongoing polling, media traffic, and limitations.
- [ ] Reduce server load: five-minute lineup checks, one-minute community checks, HTTP caching, capped concurrent requests, bounded tape-time queries, cached community windows, and no polling for disabled overlays. Implemented; final audit and validation remain.
- [ ] Slow circular/iPod scrolling and use a gentler acceleration curve. Implemented; simulated touch-trace tests pass; real Siri Remote feel still needs confirmation.
- [ ] Add smooth, fast guide scrolling, respecting Reduce Motion. Implemented; final visual review remains.
- [ ] Rejoin live and start playing whenever the app is reopened or returns from the background, even after pausing. State reset implemented; reopen test is being completed.
- [ ] Show the tape synopsis at the top of the mini guide and in the full guide; make the channel description smaller. Use already-loaded metadata to avoid requests on every focus change. Implemented; final verification remains.
- [ ] Reduce loud bumper music through **universal LUFS normalization** for tapes, ads, and bumpers. Use a real loudness meter, bounded gain, and peak protection; share audio processing with captions. The initial fixed bumper reduction is superseded by this request.
- [ ] Open both mini guide and full guide on the currently playing channel and bring it into view.
- [ ] When scrolling vertically on the full guide's current-time page, select the program airing now on each destination channel instead of its leftmost program.
- [ ] Keep three-digit channel numbers on one line and move their column slightly left in both guides.
- [ ] Run the final optimized core and simulator checks, build the 0.1.2 IPA, verify its contents, publish source and release assets, and provide the local IPA path.

## Preserve existing behavior

- Full-height, original-aspect video beside or under the mini guide; top-right preview in the full guide.
- Back closes guides; Left/Right browse time pages in the full guide; controlled held-arrow repeat.
- Native controls from Up, Down, or Select, with Rejoin Live and Last Channel; seeking stops at live.
- Timestamped bottom-left comments, original yellow floating reactions, channel icons, and a contiguous red time line behind guide text.

## Hardware confirmation

- [ ] Confirm the replacement no longer crashes on the user's Apple TV 4K third generation / tvOS 27.2 after Signulous installation.
- [ ] Confirm physical-device captions, normalization, circular-scrolling feel, and playback after reopening. Simulator checks alone do not establish these results.
