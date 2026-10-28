# Dependencies

What Deckie's PC and Linux track relies on that it did not write itself; last checked Oct 28, 2026. The rule (charter
`docs/architecture/pc-linux-track.md`, decision P16): every dependency is pinned by version and by hash, and its
licence is quoted here before it is adopted. A hash, or digest, is a long fingerprint computed from a file's exact
bytes: change one byte and it changes, so a matching hash proves a file is the one recorded here.

**In short:** one toolchain and two GitHub Actions helpers, used only to build and test, and two vendored C files,
dr_mp3, the MP3 decoder (section 4), and dr_flac, the FLAC decoder (section 5), which are compiled into
`DeckieDecode` and so are runtime dependencies (code that travels inside a Deckie program). Deckie's Swift package
(`core/`) declares no packages from elsewhere, so it has no `Package.resolved` (Swift's list of exact package
versions); dr_mp3 and dr_flac are copied files pinned by their hashes, not packages.

## 1. The Swift 6.4.1 toolchain

The toolchain is the compiler plus the libraries that come with it; 6.4.1 is the version track M chose.

**On Linux** (this cloud session and the `core-linux` CI workflow; CI, continuous integration, is GitHub building
and testing the code on every push) it comes from the official image `swift:6.4.1-noble` on Docker Hub, the public
store of Docker images (an image is a ready-made file system for running software in a container; "noble" is Ubuntu
24.04). `6.4.1-noble` is a tag, a label the publisher can later move to another image, so the workflow names the
image by digest instead:

- Image index (the list with one build per kind of processor), the digest in `.github/workflows/core-linux.yml`:
  `sha256:6304481cf2717966b7ba175162e397ea2f2cc3161909f2b2a5cf40036079a0f7`
- Its build for 64-bit Intel and AMD Linux (amd64), the manifest (the image's parts list), 1,732 bytes:
  `sha256:1a784fc9de712a985020336bbc447c21050777cbe3b76f915eb352fd21b50f3d`
- The four layers it lists (compressed archives that, unpacked in order, make the file system):
  1. `sha256:7a48b8f0e5c73d0cc2a85b008978396aa19d253dc1b96fdb0b769ee6dcbeca4a` (about 30 MB)
  2. `sha256:f5f09386b896a175c2c6e4e5769fd236abaa07c8bf3d249ddb34955d752bdf30` (about 130 MB)
  3. `sha256:04c2cdae010c9a2b417d4535a3ef423bc7a60f729febfa808abe1e6e42445602` (about 1.15 GB)
  4. `sha256:bec0e898d00ed5962c7071e418d06a93eaf2e5addaba79a43d681279a23ef805` (173 bytes)

Built Oct 26, 2026 (manifest labels). On Oct 28 the index digest was read from Docker Hub's reply header and
confirmed by hashing the downloaded index, whose amd64 entry is the manifest above. This session unpacked these four
layers, each checked against its hash, into `/opt/swift-641` (status log entry 1), where Swift reports 6.4.1-RELEASE.

**On Windows** (the `core-windows` CI workflow) the Swift project's official 6.4.1-RELEASE installer is installed by
the action `compnerd/gha-setup-swift` (section 2), asked for `swift-version: swift-6.4.1-release` (the download
directory on swift.org) and `swift-build: 6.4.1-RELEASE` (the file). Its hash is not recorded yet: Swift's
download site is blocked from this cloud session (status log entry 1).

**Inside the toolchain:** Swift Testing (the test framework the parity tests use) and Foundation (Swift's library of
everyday types: text, dates, files) ship with it, so neither is a separate package dependency.

**Licence:** Apache 2.0 with the Runtime Library Exception. Quoted from the toolchain's own file,
`/opt/swift-641/usr/share/swift/LICENSE.txt` (211 lines, SHA-256 `770af8291f70...`), indentation trimmed:

```text
Apache License
Version 2.0, January 2004
...
## Runtime Library Exception to the Apache 2.0 License: ##
As an exception, if you use this Software to compile your source code and
portions of this Software are embedded into the binary product as a result,
you may redistribute such product without providing attribution as would
otherwise be required by Sections 4(a), 4(b) and 4(d) of the License.
```

In plain words: Apache 2.0 is on the allowlist, and a program built with Swift need not carry Swift's credit notice
just because parts of Swift's runtime (the support code every Swift program runs with) end up inside it.

## 2. GitHub Actions helpers (ready-made steps other projects publish for GitHub's build machines)

| Action | Version | What it does | Used in |
|---|---|---|---|
| `actions/checkout` | `v4` | copies this repository onto the build machine | both workflows |
| `compnerd/gha-setup-swift` | `main` (its documented reference; its `v3` tag does not exist) | installs the Swift toolchain on Windows | `core-windows.yml` |

Both are recorded by version tag only, which, like an image tag, the publisher can move. Pinning each to a commit
hash (the fingerprint of one exact version of its code) is pending, and so is quoting their licences: this session
may not read other GitHub repositories, so it cannot look either up. Nothing they do ends up in a Deckie product.

## 3. What will ship later

When a Windows or Linux build ships, the Swift runtime and Foundation (with its copy of ICU, a text-handling
library) travel with it; each will be listed here with its licence quoted before that build is released. dr_mp3
and dr_flac (sections 4 and 5) already travel inside anything built with `DeckieDecode`.

## 4. dr_mp3, the MP3 decoder (vendored)

dr_mp3 is a single C header file by David Reid that decodes MP3 (MPEG-1, 2 and 2.5 audio, layers I to III); its
decoding core is minimp3 by Lion (lieff). It is vendored: copied into the repository unmodified at
`core/Sources/CDrMp3/include/dr_mp3.h`, compiled as the C target `CDrMp3` (whose `dr_mp3.c` switches on the
implementation, leaves out the file-opening functions, `DR_MP3_NO_STDIO`, and decodes straight to float,
`DR_MP3_FLOAT_OUTPUT`), and used by `core/Sources/DeckieDecode/MP3Reader.swift`. Nothing is downloaded at build
time. Christopher approved vendoring it on Oct 28, 2026, and the lead took responsibility for the one download.

| | |
|---|---|
| Version | the header's first lines say `dr_mp3 - v0.7.4 - TBD` (`DRMP3_VERSION_STRING` "0.7.4"): the copy on the `master` branch, whose release date is not set yet, so not a tagged release |
| Source | `https://raw.githubusercontent.com/mackron/dr_libs/master/dr_mp3.h`, downloaded Oct 28, 2026 |
| SHA-256 | `390e4e0ef0cff80fb86ebf1b461d6947cfa4ed699a4fe107e5a5e69a47db2950` |
| Size | 198,991 bytes, 5,140 lines |

The URL names a branch, which moves, so the hash is the pin: anything that does not hash to the value above is not
this file. The commit the branch pointed at is not recorded (the download was the only access to the repository
allowed). Compiled with clang it gives no warnings under the package's flags, `-Wall -Wextra` or `-pedantic
-std=c99`, so no warning is silenced.

**Licence:** a choice of public domain (the Unlicense) or MIT No Attribution (MIT-0). Deckie takes it as public
domain, and under MIT-0 where public domain is not recognised; both are on the allowlist (MIT-0 is MIT without the
condition to keep the notice). The minimp3 code inside is dedicated to the public domain under CC0, also on the
allowlist. Quoted from the end of the header:

```text
This software is available as a choice of the following licenses. Choose
whichever you prefer.

===============================================================================
ALTERNATIVE 1 - Public Domain (www.unlicense.org)
===============================================================================
This is free and unencumbered software released into the public domain.

Anyone is free to copy, modify, publish, use, compile, sell, or distribute this
software, either in source code form or as a compiled binary, for any purpose,
commercial or non-commercial, and by any means.

In jurisdictions that recognize copyright laws, the author or authors of this
software dedicate any and all copyright interest in the software to the public
domain. We make this dedication for the benefit of the public at large and to
the detriment of our heirs and successors. We intend this dedication to be an
overt act of relinquishment in perpetuity of all present and future rights to
this software under copyright law.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

For more information, please refer to <http://unlicense.org/>

===============================================================================
ALTERNATIVE 2 - MIT No Attribution
===============================================================================
Copyright 2023 David Reid

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

/*
    https://github.com/lieff/minimp3
    To the extent possible under law, the author(s) have dedicated all copyright and related and neighboring rights to this software to the public domain worldwide.
    This software is distributed without any warranty.
    See <http://creativecommons.org/publicdomain/zero/1.0/>.
```

**Measured against the lab.** On the generated test tones, `DeckieDecode` decodes MP3 to the same length as the lab's
reader and at offset 0 from it, within 1.3e-6 sample for sample (`core/Tests/DeckieDecodeTests/WAVDecodeTests.swift`
has the numbers). The lab's reader, Python's `soundfile` 0.14.0 with its own libsndfile 1.2.2 (which decodes MP3
through mpg123), was installed from PyPI into this cloud session's user folder for that measurement only; nothing
in `core/` uses it.

**How to update:** download the header again to the same path (or a release's copy, if one is chosen), record the
new version line, SHA-256, URL and date here, re-quote the licence block, then run `swift build` (still no warnings)
and `swift test`: the MP3 tests pin frame counts and click positions to the sample. `MP3Reader.swift` switches off
dr_mp3's own trimming through four fields of its `drmp3` struct (`delayInPCMFrames`, `paddingInPCMFrames`,
`totalPCMFrameCount`, `onMeta`) and reads the tag through its metadata callback; check they still mean the same.

## 5. dr_flac, the FLAC decoder (vendored)

dr_flac is a single C header file by David Reid, the author of dr_mp3, that decodes FLAC, native or in an Ogg
container (Ogg-FLAC). It is vendored: copied into the repository unmodified at
`core/Sources/CDrFlac/include/dr_flac.h`, compiled as the C target `CDrFlac` (whose `dr_flac.c` switches on the
implementation and leaves out the file-opening functions, `DR_FLAC_NO_STDIO`, and sets no other option, so Ogg-FLAC
and the frame checksums stay on), and used by `core/Sources/DeckieDecode/FLACReader.swift`. Nothing is downloaded at
build time. Christopher approved vendoring it on Oct 28, 2026, and the lead took responsibility for the one
download.

| | |
|---|---|
| Version | the header's first lines say `dr_flac - v0.13.4 - TBD` (`DRFLAC_VERSION_STRING` "0.13.4"): the copy on the `master` branch, whose release date is not set yet, so not a tagged release |
| Source | `https://raw.githubusercontent.com/mackron/dr_libs/master/dr_flac.h`, downloaded Oct 28, 2026 |
| SHA-256 | `b0bf397159f212676454ac9dc92b515adf5d535750bc7a9b122d9a8101ddd100` |
| Size | 523,451 bytes, 12,444 lines |

The URL names a branch, which moves, so the hash is the pin: anything that does not hash to the value above is not
this file. The commit the branch pointed at is not recorded (the download was the only access to the repository
allowed). Compiled with clang it gives no warnings under the package's flags, `-Wall -Wextra` or `-pedantic
-std=c99`, so no warning is silenced.

**Licence:** the same choice as dr_mp3's, word for word: public domain (the Unlicense) or MIT No Attribution
(MIT-0). Deckie takes it as public domain, and under MIT-0 where public domain is not recognised; both are on the
allowlist. The file holds no code under any other licence. Quoted from the end of the header:

```text
This software is available as a choice of the following licenses. Choose
whichever you prefer.

===============================================================================
ALTERNATIVE 1 - Public Domain (www.unlicense.org)
===============================================================================
This is free and unencumbered software released into the public domain.

Anyone is free to copy, modify, publish, use, compile, sell, or distribute this
software, either in source code form or as a compiled binary, for any purpose,
commercial or non-commercial, and by any means.

In jurisdictions that recognize copyright laws, the author or authors of this
software dedicate any and all copyright interest in the software to the public
domain. We make this dedication for the benefit of the public at large and to
the detriment of our heirs and successors. We intend this dedication to be an
overt act of relinquishment in perpetuity of all present and future rights to
this software under copyright law.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

For more information, please refer to <http://unlicense.org/>

===============================================================================
ALTERNATIVE 2 - MIT No Attribution
===============================================================================
Copyright 2023 David Reid

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/
```

**Measured against the lab.** On the generated test tones, 16-bit and 24-bit, `DeckieDecode` decodes FLAC to the
same length as the lab's reader, at offset 0 from it, every sample identical
(`core/Tests/DeckieDecodeTests/FLACDecodeTests.swift` has the numbers). The lab's reader is the same `soundfile`
0.14.0 with libsndfile 1.2.2 as for MP3 (section 4); libsndfile decodes FLAC through libFLAC. It cannot read
Ogg-FLAC, which dr_flac reads by default.

**Where dr_flac alone differs from the lab**, each handled in `FLACReader.swift` and pinned by a test: it cannot
open a file with an ID3v2 tag in front (it skips the tag, then reads the metadata blocks from byte 42, inside it),
so the reader skips the tags itself; it drops a frame whose checksum fails and goes on, and at a frame it cannot
parse, or a cut, stops as if the stream had ended, all without an error, so the reader reads frame by frame,
checks the frame numbers and refuses such files, as the lab does; and it decodes past STREAMINFO's frame count,
where the lab stops, so the reader stops there too.

**How to update:** download the header again to the same path (or a release's copy, if one is chosen), record the
new version line, SHA-256, URL and date here, re-quote the licence block, then run `swift build` (still no warnings)
and `swift test`: the FLAC tests pin every sample of the test tones and the messages for damaged files.
`FLACReader.swift` reads the `drflac` struct's `channels`, `sampleRate`, `bitsPerSample`, `totalPCMFrameCount`,
`maxBlockSizeInPCMFrames` and `memoryStream` (its read position), and the current frame's header numbers and
`pcmFramesRemaining`; check they still mean the same.

## Checked and rejected

**ffmpeg's libraries from Ubuntu 24.04**, checked Oct 28, 2026 as the Linux decoder track M section 3.1 names:
`libavformat-dev`, `libavcodec-dev`, `libswresample-dev`, `libavutil-dev` and the runtime libraries they require
(`libavformat60`, `libavcodec60`, `libswresample4`, `libavutil58`), all version `7:6.1.1-3ubuntu5` (ffmpeg 6.1.1)
from the archive's `universe` section. **Rejected: these builds are GPL**, which the allowlist forbids even
dynamically linked. ffmpeg's own code is mostly LGPL, but Debian and Ubuntu build it with its GPL parts switched on
(`--enable-gpl`, with GPL libraries such as x264 linked in). Quoted from `/usr/share/doc/libavcodec60/copyright`
(SHA-256 `2be0250f940dc713...`; the eight packages carry the identical file):

```text
For building the default Debian packages some of the GPL licensed files are used,
so the resulting binaries are licensed under GPL v2+.
```

The installed `libavcodec.so.60` bears it out: it links libx264, libx265 and libxvidcore, whose own copyright
files each say `License: GPL-2+`. So no Deckie code links ffmpeg, and CI installs none of it. An ffmpeg built
with the LGPL configuration would be a separate decision, recorded here first.

**The ffmpeg command-line program** (Ubuntu package `ffmpeg`, the same GPL build, `7:6.1.1-3ubuntu5`) is used only
as a development tool, on a developer's machine, to make the test files that are not WAV (`tone.mp3`,
`tone48k.mp3`, `tone_mono.mp3`, `tone.m4a`, `tone.aiff`, `tone_sowt.aifc`, `tone.flac`, `tone24.flac` and
`tone.oga`) from Deckie's own generated signal (`core/Tools/make_audio_fixtures.py`). It is not installed in CI,
and nothing in the package links it or calls it; the files it writes are test data.

## Licence allowlist (track M section 3.4, confirmed as the single list by the main session, Oct 28, 2026)

- **Ship:** MIT, BSD 2-clause and 3-clause, Apache 2.0, ISC, zlib, public domain, CC0.
- **Ship only dynamically linked** (kept as a separate library file, not built into Deckie's program), with each
  case named in this file: LGPL 2.1 and LGPL 3.
- **Not decided, so not allowed until the main session says otherwise:** MPL 2.0 (this decides Symphonia and
  Eigen).
- **Never:** GPL, AGPL, CC BY-NC (non-commercial), research-only.
- The CI check of this list is not built yet.

## How to update: on the quarterly update day, or within a week of a security advisory (track M)

1. Choose the new version and read its changelog (the publisher's list of what changed).
2. Re-record every hash here. Swift image: the `docker-content-digest` header Docker Hub returns for
   `registry-1.docker.io/v2/library/swift/manifests/<tag>`, confirmed by hashing the fetched index, then its amd64
   manifest and layers; the index digest also goes into `core-linux.yml`. Windows: the tag in `core-windows.yml` and
   the installer's hash. Actions: the tag and, once possible, the commit hash.
3. Re-quote the licence file and check it is still on the allowlist.
4. Rerun the parity tests on both CI workflows, and ask the main session to rerun the 373-track benchmark on the Mac.
5. Update the "last checked" date above. Any new direct dependency gets a written reason here.
