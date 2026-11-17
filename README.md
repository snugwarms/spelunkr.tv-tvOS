# Spelunkr for Apple TV

A native, independent tvOS client for [spelunkr.tv](https://spelunkr.tv). It tunes into the same synchronized broadcasts, plays Internet Archive tapes through AVPlayer, and puts the guide beside the picture.

Download the unsigned Apple TV IPA from [GitHub Releases](https://github.com/snugwarms/spelunkr.tv-tvOS/releases). Sign it for your Apple TV before installing.

![Full program guide with the current channel in the top right](docs/screenshots/full-guide.png)

## The viewing layout

With the mini guide open, the **video fills the TV's height and sits against the left edge**, preserving its original proportions. A 4:3 tape on a 1920 × 1080 display gets a 1440 × 1080 picture and a 480-pixel sidebar. If a tape is wider, the mini guide covers the right edge of the picture instead of shrinking it to make room.

Press **Right again** for a classic blue full-screen program guide: a two-hour schedule, channel numbers and pixel icons, program details, earlier/later pages, and the currently playing channel in the top-right corner. A red line marks the current time above the cell backgrounds and behind the text; the playing program has a lighter blue background. Browsing does not retune. Select a program to tune that channel live. Left/Right navigate the schedule, including returning from a later time page. Back returns to the mini guide; Back again closes it and centers the video. There is no Full Screen button.

All viewing modes use the same AVPlayer and preserve playback while the layout changes. The original picture is never stretched. Up, Down, or Select while watching opens **native tvOS playback controls**, including **Rejoin Live**, **Last Channel**, and guide actions. Seeking and fast-forward cannot play beyond the current live position; rewinding remains available.

## Comments and reactions

The app reads the same public, moderated tape comments and reactions as the website. Comments appear in the **bottom left** when playback reaches their timestamp on the tape. They persist upstream and reappear on future broadcasts of that recording; they are not a transient chat tied to one airing. Rewinding re-arms later comments so they can appear again.

The website's seven **yellow SVG reaction icons** float upward over the video. Both historical tape reactions and relevant new arrivals are supported. The mini guide's speech-bubble menu independently toggles comments and floating reactions; settings are remembered. These features display community activity. Account login, posting comments, and sending reactions are not implemented.

## Run on an Apple TV

Requires a Mac with Xcode to build, and an Apple TV running tvOS 17 or later to watch. This release was built with Xcode 27.2.

1. Open `Spelunkr.xcodeproj` in Xcode. No third-party packages or project generator are required.
2. Select the **Spelunkr** target, then **Signing & Capabilities**. Choose your development team and a unique bundle identifier if needed.
3. Pair your Apple TV using Xcode's **Devices and Simulators** window. Select it as the run destination.
4. Press **Run**. Xcode signs and installs the app.

An unsigned device package can also be generated with `./scripts/package.sh`; the result is `build/Spelunkr-tvOS-unsigned.ipa`. It must be signed with an appropriate tvOS provisioning profile before a real Apple TV can install it. There is no App Store or TestFlight release.

For signing and sideloading, I personally recommend [Signulous](https://www.signulous.com/).

## Remote controls

| Control | Action |
| --- | --- |
| Right while watching | Open the mini guide |
| Right in the mini guide | Open the full program guide |
| Back in a guide | Full guide → mini guide → watching |
| Left in the mini guide | Close the mini guide |
| Up / Down in a guide | Browse channels without retuning; held arrows repeat at a controlled rate |
| Left / Right in the full guide | Browse programs and earlier/later schedule pages |
| Select on a channel | Tune the live broadcast |
| Up / Down / Select while watching | Open native player controls |
| Play / Pause | Pause or resume playback |
| Hold Select on a channel | Add or remove a favorite |
| Last Channel in native controls | Return to the previous channel |
| Rejoin Live in native controls | Resynchronize to the live broadcast |

Favorites and the last channel survive app restarts. Returning from the background rejoins the current broadcast. Programs, ads, and station breaks advance at their scheduled wall-clock boundaries; network retries cannot replace a more recently selected channel. Standard tvOS focus navigation handles directional touchpad swipes. Circular touch input is also mapped to channel-row navigation through GameController, while AVKit provides its native transport gestures. Circular gestures require physical Siri Remote validation; simulator checks cover button navigation.

Physical arrows in the full guide are tracked from press to release: one move on key-down, then repeats only after a 500 ms hold, every 220 ms. The app does not treat the operating system's key-repeat bursts as separate taps. Icons use the live lineup's pixel artwork and palette, below the number in the mini guide and beside it in the full guide.

## Subtitles

Embedded subtitle tracks use AVKit's native selection controls when present. Automatic speech captions are removed in version 0.1.1. The app no longer links Speech or MediaToolbox or installs an audio tap.

## Development and checks

```sh
./scripts/build.sh
swift test -c release
# Include the remote / layout simulator check:
./scripts/test.sh 'platform=tvOS Simulator,name=Apple TV 4K (4th generation) (at 1080p)'
# Inspect real feeds and a tape's resolved media URL:
swift run spelunkr-probe --media computer-chronicles
```

The Xcode project is checked in. After adding native app or UI-test files, regenerate it with `python3 scripts/generate-project.py` (Python standard library only). The core is a local Swift package; JavaScriptCore executes a pinned, bundled scheduler, with all networking handled by Swift. The app requires no companion computer or server.

The simulator checks run the **Release** configuration used for the IPA. Version 0.1.1 replaces tuple results in guide-loading task groups with concrete result records, fixing a reproduced optimized-build abort in `AsyncTask.completeFuture` during startup. The IPA is small because recordings stream from the Internet Archive and Apple's player frameworks are supplied by tvOS; no video recordings or speech models are bundled.

See [PROVENANCE.md](PROVENANCE.md) for source attribution, the scheduler pin, and validation details. This is a native viewing client: website account features, Discord login, submissions, and the site's non-viewing pages are not implemented.
