# Sources and verification

## Original service and reference ports

The original project is [Spelunkr.tv](https://spelunkr.tv). Broadcast programming, schedules, channel names, descriptions, and upstream assets retain their original ownership. Video streams come from the [Internet Archive](https://archive.org). This Apple TV client is independent and does not claim endorsement.

The following public projects were inspected on 16 November 2026:

- [buddytohelpu/spelunkr-guide](https://github.com/buddytohelpu/spelunkr-guide): public broadcast protocol, schedule isolation, reference fixture, trim offsets, and station-break structure.
- [ominixisboss/Spelunkr.tv-App](https://github.com/ominixisboss/Spelunkr.tv-App): Android TV remote behavior, favorites, last-channel behavior, and live resumption.
- [Nikolay1243/spelunkr-webos](https://github.com/Nikolay1243/spelunkr-webos): native-TV integration and source attribution approach.
- [pedr/spelunkrtv-tizen-app](https://github.com/pedr/spelunkrtv-tizen-app): direct Internet Archive storage URLs for reliable seeking through video redirects.

The Swift interface, player integration, broadcast client, tests, and tvOS adapters were written for this project. Android, Roku, Tizen, and webOS interface implementations are not bundled.

## Bundled upstream scheduler

`Sources/SpelunkrCore/Resources/schedule-engine.js` contains the 64 pure declarations needed by the production site's playlist builder, version hydrator, and position resolver. It was extracted by static dependency analysis, without running the website bootstrap. It includes no browser UI, authentication, analytics, or network clients.

- Source: `https://spelunkr.tv/assets/index-Cx9zqF7W.js`
- Original bundle SHA-256: `55dced4ce8e2479a3ed4a9dfbc6616fba64ec858b7e67aec930ff4a885550cd2`
- Retrieved: 17 November 2026 UTC (16 November Pacific)
- Supported schedule engine: **5**
- Original entry points: `Dv` (build playlist), `Lb` (hydrate version), `un` (resolve position)
- Local adaptation: remove the ES-module export, expose three stable local aliases, and bundle it as a JavaScriptCore resource.

The reference port's extraction method was used during research. The shipped scheduler is extracted from the newer production bundle above. It retains upstream ownership; no independent open-source license for the upstream code is asserted. The channel metadata and recordings likewise retain their respective rights.

`Tests/SpelunkrCoreTests/Fixtures/website-schedule.json` is the recorded public website observation published by buddytohelpu/spelunkr-guide, including its original manifest and platform inputs. It is test data and is not included in the tvOS app.

## Network behavior

The current production website uses `https://data.spelunkr.tv/`, with broadcast snapshots available at `https://spelunkr.tv/broadcast/`. Both are supported. The older Supabase public bucket used by the reference port currently responds “Bucket not found” and is not used. Immutable manifests and platform data are cached in memory; an already loaded lineup remains available during outages. A newer unsupported engine causes an explicit update message.

Archive metadata selects an H.264 MP4 when a manifest lacks a compatible filename. Direct storage URLs are used when available, with Archive download URLs as a playback fallback. Filename path components are encoded independently, and metadata latency is included when seeking to the current live position.

## Validation

On 16 November 2026, all **19 core tests passed**. They cover recorded website position parity, program boundaries, before-epoch playback, version cutovers, trim and ad in-points, full-guide timeline coverage, the live seek ceiling, arrow-repeat pacing, circular touch traces, moderated community reads, URL encoding, feed fallback and recovery, cached-lineup outages, and unsupported engine detection.

The live Swift probe resolved **36 public channels with zero schedule errors**, using the lineup generated at `2026-11-17T02:24:23.899Z`. It also resolved an Archive storage URL and live seek position for Computer Chronicles. These are sampled live checks, not exhaustive verification of every recording.

The Apple TV 1080p simulators on tvOS 26 and 27.2 rendered live Archive video with the mini guide beside the picture, the same tape centered after hiding it, and a top-right preview in the full schedule. Two UI tests drive Right/Back/Left navigation, one-row arrow presses and short holds, paging two hours ahead and back, browsing without retuning, selecting another channel, and native controls opened by Up/Down/Select. The latest tvOS 27.2 run passed both tests, including Back during startup before channel-row focus is established. Screenshots are preserved under `docs/screenshots/`.

A third UI test enables automatic captions and confirms that speech-model setup or an availability explanation does not interrupt playing video. It passed on tvOS 27.2; Apple's SpeechTranscriber reports unavailable in this simulator. Actual speech recognition on a physical Apple TV has not been verified.

Full-guide physical arrow presses are captured until release, with a 500 ms initial repeat delay and 220 ms repeat interval. This handles physical key-up instead of relying solely on timestamps of SwiftUI move commands. The full schedule has a red current-time rule between cell fills and text, a lighter blue fill for the playing program, and the live pixel channel artwork in both guides. Pixel colors follow the site's fixed ink/paper/accent palette and its primary-color shade/light transformations.

Both simulator Debug and device Release builds compile successfully. `scripts/package.sh` produces an unsigned arm64 tvOS IPA. Station-break visuals are native text cards, rather than the website's complete visual treatment.

Automatic captions use public APIs from Xcode 27.2's Speech framework, guarded for tvOS 26 and weak-linked so watching remains available on older systems. AVPlayer's decoded audio is copied through MediaToolbox into a bounded buffer pool, converted off the playback thread, and supplied to SpeechAnalyzer. No microphone or external transcription server is used. Apple's English model is downloaded only when the user enables captions and installation is necessary. Seeking or tuning replaces the recognition session. The tvOS 27 audio tap supports the item mix; tvOS 26 uses an audio-track tap for the Archive MP4 recordings.

`App/Assets.xcassets/Reaction-*.imageset` contains the production website's seven yellow reaction SVGs, reconstructed from the static SVG trees of `KA`, `VA`, `qA`, `zA`, `GA`, `JA`, and `YA` in the same pinned bundle. Paths and fill rules are preserved, with the site's yellow substituted for `currentColor`. These upstream graphics retain their original ownership.

Community data is read through the website's public Supabase REST endpoints, using its public anonymous client key in the bundled `community.json`. Only active, moderated comments are selected; no user credentials, sign-in, or write requests are used. A live read of the recorded Computer Chronicles tape returned two comments and 89 reactions. Timestamps are tape offsets, including trim in-points, rather than wall-clock dates. A local client never deletes these upstream records when a program finishes.

Physical Apple TV installation requires the user's development signing team and remains separate from simulator validation. Circular touchpad gestures also need a physical remote check. Archive playback availability and encoding vary by tape.
