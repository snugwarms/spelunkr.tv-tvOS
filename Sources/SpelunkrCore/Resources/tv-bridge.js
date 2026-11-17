// Native tvOS adapter for the pinned Spelunkr engine 5. No browser or network APIs.
var SpelunkrTV = (() => {
    const playlists = new Map();
    function playlist(id) {
        if (!playlists.has(id)) throw new Error('Channel is not loaded: ' + id);
        return playlists.get(id);
    }
    function program(p) {
        const i = p.item;
        return {
            key: p.key, type: i.type, id: i.id || '',
            title: i.title || (i.type === 'ad' ? 'A word from the past' : i.type === 'up-next' ? 'Up next' : 'Station break'),
            year: i.year == null ? '' : String(i.year), startMs: p.startMs, endMs: p.endMs,
            synopsis: typeof i.description === 'string' ? i.description : typeof i.synopsis === 'string' ? i.synopsis : null
        };
    }
    return {
        load(json) {
            const data = JSON.parse(json);
            const versions = data.versions.map(v => tvHydrateVersion(v.manifest, v.platform, v.pointer));
            playlists.set(data.id, tvBuildPlaylist(data.id, versions));
            // Bound memory when the public lineup changes.
            if (playlists.size > 80) playlists.delete(playlists.keys().next().value);
            return 'ok';
        },
        guide(id, at) {
            const list = playlist(id), current = tvResolveAt(list, at);
            let next = null, cursor = current.endMs;
            for (let n = 0; n < 100; n++) {
                const p = tvResolveAt(list, cursor);
                if (p.endMs <= cursor) throw new Error('Schedule failed to advance');
                if (p.item.type === 'video') { next = program(p); break; }
                cursor = p.endMs;
            }
            return JSON.stringify({ current: program(current), next });
        },
        timeline(id, start, end) {
            const list = playlist(id), rows = [];
            let cursor = start;
            for (let n = 0; cursor < end && n < 600; n++) {
                const p = tvResolveAt(list, cursor), item = program(p);
                if (p.endMs <= cursor) throw new Error('Schedule failed to advance');
                const previous = rows[rows.length - 1];
                if (item.type !== 'video' && previous) previous.endMs = item.endMs;
                else rows.push(item);
                cursor = p.endMs;
            }
            return JSON.stringify(rows);
        },
        tune(id, at) {
            const list = playlist(id), p = tvResolveAt(list, at), i = p.item;
            const result = {
                program: program(p), archiveID: null, file: null, inPoint: 0,
                cards: [], audioFile: null, audioInPoint: 0, audioTitle: null, audioArtist: null
            };
            if (i.type === 'video') {
                result.archiveID = i.id; result.file = i.file || i.mp4 || null; result.inPoint = i.inS || 0;
            } else if (i.type === 'ad') {
                result.archiveID = i.slice.tape; result.file = i.slice.file; result.inPoint = (i.slice.inMs || 0) / 1000;
            } else {
                const groups = [i.channelBump, i.platformBump].filter(Boolean);
                let cursor = i.half === 'close' ? 0 : 3500;
                if (cursor) result.cards.push({text: 'SPELUNKR', start: 0, end: cursor});
                groups.forEach((bump, index) => {
                    for (const slide of bump.slides || []) {
                        const length = Math.max(2500, 1500 + slide.text.length * 55);
                        result.cards.push({ text: slide.text, start: cursor, end: cursor + length });
                        cursor += length;
                    }
                    cursor += 2000 + (index === 0 && groups.length > 1 ? 300 : 0);
                });
                const audio = i.channelAudio || i.platformAudio;
                if (audio && audio.filename) {
                    result.audioFile = audio.filename; result.audioInPoint = audio.startOffset || 0;
                    result.audioTitle = audio.title || null; result.audioArtist = audio.artist || null;
                }
                if (i.type === 'up-next') {
                    const next = tvResolveAt(list, p.endMs);
                    result.cards = [{ text: 'UP NEXT\n' + (next.item.title || 'Stay tuned'), start: 0, end: i.durMs }];
                }
            }
            return JSON.stringify(result);
        }
    };
})();
