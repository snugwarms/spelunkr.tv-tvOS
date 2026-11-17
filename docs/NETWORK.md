# Network request report

Measured 16 November 2026 Pacific. This is an **unofficial client**, not a service operated or endorsed by Spelunkr.tv's creator.

## Scope and version

The measurements below are from the **0.1.2 development candidate**, with its reduced polling policy, on an Apple TV 1080p simulator running tvOS 26. The test watched Computer Chronicles in the foreground with comments and reactions enabled and automatic captions disabled. They are measured samples, not traffic guarantees for every tape or network.

**Published 0.1.1 still uses the original polling intervals:** one lineup check per minute and two community requests every 15 seconds, ordinarily about **9 API requests/minute** while watching. The lower rates below are for 0.1.2, which is still undergoing final validation. Source-level limits added after the sample further cap broadcast/API concurrency at four.

Counts use `URLSessionTaskMetrics`: network transactions are separated from local-cache reads, and conditional HTTP 304 responses count as network requests. A failed attempt also counts. AVPlayer's media request counters are reported separately; this is not a packet capture, and those counters should not be confused with the API counts. Received API body bytes exclude headers and TLS overhead. Audit logs are local and opt-in; no audit telemetry is uploaded.

## Actual requests by destination

| Destination | Cold start plus 9m 7.5s watching | Warm reopen plus 2m 4s watching | What it does |
| --- | ---: | ---: | --- |
| `data.spelunkr.tv` | **42 network**, 1 local-cache transaction; 1,085,334 received body bytes | **1 network** HTTP 304, 41 local-cache transactions; 0 network body bytes | Lineup, manifests, station-break platform data |
| `spelunkr.tv/broadcast/` | **0** | **0** | Backup only if the primary broadcast host fails |
| `jbuopkuluyfjwgsrigry.supabase.co/rest/v1/` | **20 network**; 8,174 body bytes | **6 network**; 555 body bytes | Moderated comments and tape reactions: 10/10 in the first sample, 3/3 in the second |
| `archive.org/metadata/` | **1 network**; 3,870 body bytes | **2 network attempts**, including one unsuccessful attempt; 2 local-cache transactions; 3,870 body bytes | Resolve the selected tape's storage URL, metadata, and synopsis |
| Internet Archive video storage | AVPlayer reported **60 media requests**, **155,255,390 bytes** | See the machine-readable report | Video byte ranges and buffering; this traffic goes to Archive, not Spelunkr |
| `audio.spelunkr.tv/bumps/` | **0 in this sample** | **0 in this sample** | Scheduled station-break music, when applicable |

The cold broadcast load comprised **38 versioned manifests + 2 shared platform files + 1 initial lineup = 41 requests**, followed by one conditional lineup check about five minutes later. Shared platform files were fetched once, not once per channel. The warm reopen demonstrates HTTP-cache reuse: the broadcast server received one conditional lineup check rather than another full manifest download.

The [machine-readable sample](network-audit-2026-11-16.json) includes durations, per-host/path counts, and separate player counters. It contains no API credentials, authorization headers, or comment contents.

## 0.1.2 ongoing request budget

| Behavior | Requests |
| --- | --- |
| Broadcast lineup | **1 GET every 5 minutes**, normally revalidated with the HTTP cache; new manifest versions add their required downloads |
| Unchanged channel manifests/platform files | **0 periodic GETs** from the app's in-memory cache; HTTP disk caching is also respected across relaunches |
| Comments | Ordinarily **1 GET/minute** while enabled and video is actually playing |
| Reactions | Ordinarily **1 GET/minute** while enabled and video is actually playing |
| Both community overlays disabled, or paused playback | **0 new community fetches**; an already-started request can finish |
| App backgrounded | Refresh tasks are cancelled; no ongoing app polling |
| Browse a loaded guide or move focus | **0 additional requests merely for moving focus**; the schedule is computed locally |
| Selected tape metadata | One fetch per previously uncached tape, with memory and HTTP-cache reuse; synopsis uses that same response |

Ordinary foreground polling is therefore **about 2.2 API requests/minute, or 132/hour**, versus approximately 540/hour in 0.1.1: about **76% fewer polling requests**. With both overlays off, steady app polling is one lineup request every five minutes. This excludes cold startup, manual refresh, tuning new tapes, new schedule versions, errors/redirects, and media downloads.

## Controls against excessive traffic

- Broadcast/Archive metadata requests share a **four-request concurrency limit**. Guide jobs are also queued in groups of four; requests for the same pending asset are coalesced.
- Community requests query a **12-minute tape-time window**, in five-minute buckets, rather than the complete recording history. Data already fetched is played locally at its saved timestamps.
- Community data is cached for one minute across quick revisits. Disabled overlay endpoints are skipped. New community fetch batches are separated by at least **15 seconds**, including channel changes and seeks.
- Each community endpoint is limited to **two pages of 1,000 records** per batch. Ordinary polls use two total requests; a dense window can use four. This replaces the earlier maximum of 20 pages per endpoint. Very dense windows can omit records beyond that cap; upstream records are never changed or deleted.
- Failed community polls back off, up to five minutes. Broadcast refreshes also retry the fallback host only after a primary failure. Manual user actions and Archive/player retries can still add traffic.
- Rewinding or seeking outside the prefetched community window can trigger a new batch, subject to the 15-second minimum. It does not download the full tape's comment history.
- No website HTML, web app bundle, channel icons, reaction images, or scheduler code is downloaded during normal viewing: the native app and pinned assets supply those locally. Channel icon pixels arrive with the lineup.
- Automatic caption transcription and volume processing run on the device. Apple may download its speech model when captions are enabled; Apple-managed model traffic was not part of these measurements and is not sent to Spelunkr.

## Limits of this report

AVPlayer controls video and bumper-audio buffering and byte-range retries, so their request count depends on encoding, seeks, connection quality, and caching. Bumper playback and Apple speech-model downloads were not exercised in this sample. The backup site also received no requests, so its failure-path budget is code-reviewed rather than measured here. HTTP caches can be purged by tvOS. Device hardware/network behavior can differ from the simulator.

The 0.1.2 measurements and budgets should be reviewed with the service creator before treating them as an agreed load policy. No claim of creator approval is made.
