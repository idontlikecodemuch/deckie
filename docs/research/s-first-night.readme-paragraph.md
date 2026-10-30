## set_analysis.py (Oct 30, 2026): a recorded set read back against the booth's log and the audio (research S)
`nice -n 19 .venv/bin/python -I set_analysis.py <Sets folder> --deck ../deck-app/Deck/Resources/deck_data.json
--cache <scratch folder> [--jobs 2] [--prefix set_oct24]` reads the booth's set recordings (`Deck set <date time>.aac`
with their `log.json`) where they lie and never copies them into the repository. Decoded audio (mono float, 22,050 Hz),
Beat This beats, beat-synchronous chroma, the crate's own chroma (from the feature files' audio paths) and the matches
go to the cache; each stage is cached and `--redo decode|beats|chroma|crate|hub|match` recomputes one. It prints the
inventory, the songs as the booth logged them, an audio check of each play against the crate (32-beat chroma windows,
hub-corrected, identified only when two overlapping paths agree and the speed and key movement fit a deck), the
booth's pitch reading against the measured tempo, the transitions with the rank of the next song among the booth's
picks (the app's filters and sampler replayed), Camelot relations, tempo changes, play lengths against the mix-out
window and the tempo of the night in 10-minute bins. Writes `<prefix>_songs.tsv` and `<prefix>_transitions.tsv`
(times, ids, tempos and ranks only). The first full run takes about 25 minutes at two workers (the crate chroma is
most of it); a re-run from the cache about a minute. Letter: `docs/research/s-first-night.md`.
