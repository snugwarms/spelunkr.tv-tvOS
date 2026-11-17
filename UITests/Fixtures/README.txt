subtitles.mp4 is an original synthetic test fixture: five seconds of black video,
silent mono audio, and English/Spanish timed text. It contains no third-party media.
It is bundled only in the test runner, never in the released app.

no-subtitles.mp4 is the same synthetic fixture with the timed-text tracks removed,
used to check that compatibility playback never recreates the speech audio tap.

Recreate with ffmpeg using color=c=black:s=64x64:r=1:d=5 and
anullsrc=r=48000:cl=mono inputs, plus one five-second SRT cue per language.
Encode video as H.264, audio as AAC, and subtitles as mov_text, with eng/spa
language metadata. Use -t 5 and -movflags +faststart.
