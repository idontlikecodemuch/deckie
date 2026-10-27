---
name: project-cd-loudness-todo
description: Loudness normalisation is now built into the disc build (done Oct 24, 2026); the discs burned Oct 23 were unnormalised
metadata:
  type: project
---

Since Oct 24, 2026 `_pool build/build_two_discs.py` normalises every disc file as it stages it: two-pass ffmpeg loudnorm in linear mode to -10 LUFS integrated with a -2 dBTP ceiling before the CBR 320 encode (MP3 decoding overshoots by up to about 2 dB), LRA 20 so it stays a pure gain change, and for tracks whose peaks block the lift a fallback of gain to target plus a peak limiter with one correction pass (19 of 91 tracks needed it). Result on the v3 set (41 + 50 tracks, Get It On included): spread 1.3 dB (-11.0 to -9.7), median -10.0, decoded peaks at most +0.3 dBTP. The scan is `CDs v3/loudness-scan-normalised.tsv`; `CDs v3/soundcheck.sh` plays excerpts for an A/B. The two copies of each disc burned on Oct 23 are the old unnormalised files (12 dB spread); their ISOs are kept in `CDs v3/ISO-burned-oct23`.

**Why:** Mike plays on a CDJ-1000MK3 with no auto-gain and had complained about level jumps.

**How to apply:** nothing extra to do; any rebuild of the discs normalises. Never normalise the originals in place (`Mike page/tracks/` are hard links to them). The web player still serves the original, unnormalised MP3s. Related: [[project-mixer-toolkit]].
