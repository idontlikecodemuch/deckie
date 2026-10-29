# Dependencies

What Deckie's PC and Linux track relies on that it did not write itself; last checked Oct 28, 2026 (section 8,
Oct 29). The rule (charter `docs/architecture/pc-linux-track.md`, decision P16): every dependency is pinned by version
and by hash, and its licence is quoted here before it is adopted. A hash, or digest, is a long fingerprint computed from a file's exact
bytes: change one byte and it changes, so a matching hash proves a file is the one recorded here.

**In short:** one toolchain and six GitHub Actions helpers, used only to build and test; two vendored C files,
dr_mp3, the MP3 decoder (section 4), and dr_flac, the FLAC decoder (section 5), which are compiled into
`DeckieDecode` and so are runtime dependencies (code that travels inside a Deckie program); ONNX Runtime, the engine
that runs the beat tracker's model (section 6), of which only the C header is vendored, its library being opened at
run time from a file fetched per machine, never linked and never committed; the Beat This! beat tracker's
trained weights (section 7), exported to a model file per machine by a script whose Python tools are
development-only; and the weights of Google's YAMNet audio tagger, the vocal tagger's model (section 8), fetched by
pinned URL and hash and exported the same way. Deckie's Swift package (`core/`) declares no packages from elsewhere,
so it has no `Package.resolved` (Swift's list of exact package versions); dr_mp3, dr_flac and the ONNX Runtime header
are copied files pinned by their hashes, not packages.

## Acknowledgements table (the shape the apps render; keep it equal to the sections below)

The apps show an acknowledgements screen generated from this file (the main session, Oct 29, 2026): one row per
entry that ships, with its name, version, licence as the licence names itself, and for a model its training sets
with their terms and the replacement path. The sections below hold the quotes and the evidence; this table must say
the same thing in one line each, and is updated in the same commit as any section.

| Entry | Version | Licence | Training sets and their terms (models) | Replacement path (models) |
|---|---|---|---|---|
| Swift runtime and Foundation (with ICU) | 6.4.1 | Apache 2.0 with the Runtime Library Exception (section 1); listed in full before the first PC or Linux build ships (section 3) | | |
| dr_mp3 | 0.7.4 | public domain (the Unlicense) or MIT No Attribution, taken as public domain (section 4) | | |
| dr_flac | 0.13.4 | the same choice, taken as public domain (section 5) | | |
| ONNX Runtime | 1.31.1 | MIT; carries Eigen under MPL 2.0, unmodified, with its notice (section 6); the shipped library is Deckie's own build without Microsoft's usage-reporting client | | |
| Beat This! (beat tracker, checkpoint `final0`) | ISMIR 2024 release, checkpoint `final0` | MIT (section 7) | 15 sets, everything but GTZAN; terms range from MIT and CC BY to CC BY-NC and all rights reserved, each in section 7's table | tempo and bar grid from Deckie's own code at lower confidence (section 7) |
| YAMNet (vocal tagger) | tensorflow/models commit a6e25e2 weights | Apache 2.0 (section 8) | AudioSet: labels CC BY 4.0, clips are their YouTube uploaders'; trained by Google (section 8) | vocal fields absent, record flagged `vocal_unknown` (section 8) |

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
| `actions/checkout` | `v4` | copies this repository onto the build machine, and ONNX Runtime's source at its pinned commit for its build (section 6) | all three workflows |
| `compnerd/gha-setup-swift` | `main` (its documented reference; its `v3` tag does not exist) | installs the Swift toolchain on Windows | `core-windows.yml` |
| `actions/cache` | `v4` | keeps ONNX Runtime's library and the exported Beat This! and YAMNet models between runs (sections 6 to 8), keyed on the hashes of the scripts that make them | `core-linux.yml` |
| `actions/setup-python` | `v5` | installs Python 3.12, which runs ONNX Runtime's build scripts and Deckie's helper for that build | `onnxruntime-build.yml` |
| `actions/upload-artifact` | `v4` | keeps each built ONNX Runtime archive with the run that made it | `onnxruntime-build.yml` |
| `actions/download-artifact` | `v4` | gathers those archives for the job that publishes them | `onnxruntime-build.yml` |

All six are recorded by version tag only, which, like an image tag, the publisher can move. Pinning each to a commit
hash (the fingerprint of one exact version of its code) is pending, and so is quoting their licences: this session
may not read other GitHub repositories, so it cannot look either up. Nothing they do ends up in a Deckie product.

## 3. What will ship later

When a Windows or Linux build ships, the Swift runtime and Foundation (with its copy of ICU, a text-handling
library) travel with it; each will be listed here with its licence quoted before that build is released. dr_mp3
and dr_flac (sections 4 and 5) already travel inside anything built with `DeckieDecode`. A build that tracks beats
also carries ONNX Runtime's library (section 6) and the Beat This! model file (section 7); the shipped library is
Deckie's own build of the pinned release without Microsoft's usage-reporting client, never the official archive's
(section 6), and it contains Eigen, under MPL 2.0, which ships unmodified with its notice under the main session's
decision (section 6),
and the Beat This! weights ship under D15 with their training sets recorded (section 7) and shown in the
acknowledgements. A build that tags vocals carries the YAMNet model file (section 8), Apache 2.0,
with AudioSet's attribution in the acknowledgements.

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

## 6. ONNX Runtime, the model runtime (header vendored, library opened at run time)

ONNX Runtime is Microsoft's engine for running trained models saved as ONNX (an open file format for neural
networks). `DeckieInference` uses it to run the Beat This! model (section 7). Microsoft's own Swift package builds
only on Apple's systems (track M section 6), so Deckie calls ONNX Runtime's C interface itself:

- **The header is vendored.** `onnxruntime_c_api.h` and the two headers it includes, `onnxruntime_ep_c_api.h` and
  `onnxruntime_error_code.h`, are copied unmodified from the Linux release archive into
  `core/Sources/COnnxRuntime/include/` (the Windows archive's copies are the same but for Windows line endings).
  With a small C file of Deckie's, `deckie_ort.c`, they make the C target `COnnxRuntime`.
- **The library is opened at run time, not linked.** `deckie_ort.c` opens the shared library with `dlopen`
  (`LoadLibraryExW` on Windows), looks up its one entry point, `OrtGetApiBase`, and asks it for the function table
  of the header's API version, 31; a library too old to offer it is refused with its version. So `swift build`
  needs no ONNX Runtime anywhere, which keeps the Windows probe and a fresh checkout building, and the tests that run
  a model skip, saying why, where the library is missing. The library's path comes from the environment variable
  `DECKIE_ONNXRUNTIME_LIB`, or by default `core/.deps/onnxruntime/lib/libonnxruntime.so` in the checkout.
- **The library is fetched per machine, not committed.** `core/Tools/fetch-onnxruntime.sh` downloads the Linux
  archive, checks its SHA-256 (below) before unpacking anything, and unpacks it into `core/.deps/onnxruntime/`, which
  `.gitignore` keeps out of the repository; CI caches that folder. Nothing is downloaded at build time or during
  analysis.
- **Its usage reporting is switched off before it starts.** Microsoft's official builds report usage to Microsoft
  unless the environment variable `ORT_DISABLE_TELEMETRY` is set before the library starts (the archive's
  `Privacy.md` says so; the Linux library carries Microsoft's 1DS reporting client and the address
  `mobile.events.data.microsoft.com`, the Windows one reports through Windows' event tracing). `deckie_ort.c` sets
  the variable to `1` in Deckie's own process before opening the library, unless the user already set it, and a test
  checks it; the C API's `DisableTelemetryEvents` is called too, as a second layer, though on its own it would come
  after the client has started. The Python tools below that import the `onnxruntime` package set the same variable
  before importing it, and both workflows set it for every step. Found Oct 29, 2026 (status log entry 12).
- **A shipped build carries a library we build ourselves, without the client** (the main session's decision, Oct
  29, 2026, recorded on `main` as a note on D3 and in the charter's constraints). The variable closes the matter for
  development, CI and the bench only, because it trusts the library to honour it. Before the first PC build, and
  before any Mac bench binary is handed to an engine bound for TestFlight, ONNX Runtime is built on the same CI from
  its pinned release tag with `--no_telemetry` (the build option that leaves the 1DS client out), and the resulting
  archives are pinned here by size and SHA-256 like the official ones. The promise is a release test, not the
  variable: `OnnxRuntime.ReportingClientScan` reads a library file for the client's traces (the reporting address,
  the 1DS client's own names, the SQLite and mbedTLS text inside it, and the Windows event-tracing provider name),
  and the test `shippedLibrariesCarryNoReportingClient` fails on any library named in `DECKIE_SHIPPED_ONNXRUNTIME`
  (paths separated by `:`, `;` on Windows) that carries one. The build time and the size difference against the
  official library go into the status log when the build exists.

Christopher approved downloading the release archives on Oct 28, 2026, and the lead took responsibility for them.

| | |
|---|---|
| Version | 1.31.1: release tag `v1.31.1`, built Oct 23, 2026 from commit `41d4d61f14b9c1dd0b2ccda1e9b85dd415fd0496` (the archives' `GIT_COMMIT_ID`); C API version 31 |
| Source | `https://github.com/microsoft/onnxruntime/releases/download/v1.31.1/<archive>`, downloaded Oct 28, 2026, when it was the latest release. GitHub's API refused this session (`releases/latest` answered that the repository is not enabled for it), so "latest" was read from the repository's tags (`git ls-remote --tags`, the highest `vX.Y.Z`), not from GitHub's own "latest" label |
| Linux x86_64 archive | `onnxruntime-linux-x64-1.31.1.tgz`, 11,413,655 bytes, SHA-256 `c849e36a1ef3e22d4ff217b9d1ce4a3cf5b9467b975610913ae959ad5b16bdc9`, pinned in `fetch-onnxruntime.sh` |
| Windows x64 archive | `onnxruntime-win-x64-1.31.1.zip`, 82,929,944 bytes, SHA-256 `5869e26bb25314375f2d5ef1877e3ea06b1543d6c710e6e4a1ec2f7177ab4b2c`; no script fetches it yet (the note at the top of `fetch-onnxruntime.sh` says how to use it); most of it is debug symbols (`.pdb`, 429 MB unpacked), which are not needed |
| macOS arm64 archive | `onnxruntime-osx-arm64-1.31.1.tgz`, 36,936,435 bytes, SHA-256 `2e1344a1926ee50eb25b38153cb6992c3567515aef0e677a1a520a1798896d6f`, downloaded Oct 29, 2026 to record these facts for the Mac bench (its `GIT_COMMIT_ID` is the same commit); about half of it is debug symbols (`.dSYM`), not needed. The Mac fetches it by the same pinned pattern once Christopher says yes in the main session |
| The libraries in them | `lib/libonnxruntime.so.1.31.1`, 29,345,384 bytes, SHA-256 `a96f132e5eb5ca04e23a7d2fc1078fb95aa591e8d71d0f237702ece3a1e0f4ea`; `lib/onnxruntime.dll`, 17,253,728 bytes, SHA-256 `cb2fa518b18356617f6f9f460c012501da2819ec7e5c1d80bd8f5de20492db0c`; `lib/libonnxruntime.1.31.1.dylib`, 44,797,256 bytes, SHA-256 `17500d6b1e37e70f43a2c57d94233a1bc29fbcb297be0a5f8c7c13184f3307ba`. The macOS library carries the 1DS reporting client too (its address, namespace and source-file names are in it) but none of curl, mbedTLS or SQLite: on macOS the client uses the system's own HTTP, TLS and database libraries. `ORT_DISABLE_TELEMETRY` is honoured there as on Linux |
| Vendored headers | `onnxruntime_c_api.h`, 422,790 bytes, SHA-256 `43d584f596ef66820421317df32a79a95fc1d39ee46cb3971a870c08d8ba4baa`; `onnxruntime_ep_c_api.h`, 165,249 bytes, `b64036772115dbc6f06a900487ce22d34e862100db03e2ad62210758e27a19b2`; `onnxruntime_error_code.h`, 2,775 bytes, `5ce3b054e798eced8d14f5b86e98692fd33470463f96194ce0700a2d53dd8721` |

**Deckie's own build** (the library a shipped build carries; first run pending). The workflow
`.github/workflows/onnxruntime-build.yml` builds the release above on GitHub's machines, Linux x86_64
(`ubuntu-latest`), Windows x64 (`windows-latest`) and macOS arm64 (`macos-latest`), when started by hand (Actions,
onnxruntime-build, Run workflow) and when a push changes the workflow or its scripts. Each job checks out commit
`41d4d61f14b9c1dd0b2ccda1e9b85dd415fd0496` and stops if the tag `v1.31.1` points anywhere else, then runs ONNX Runtime's
own `build.sh` (`build.bat` on Windows) with `--config Release --build_shared_lib --parallel --skip_tests
--skip_submodule_sync --no_telemetry --compile_no_warning_as_error --cmake_extra_defines onnxruntime_BUILD_UNIT_TESTS=OFF
FETCHCONTENT_TRY_FIND_PACKAGE_MODE=NEVER`, plus `--osx_arch arm64 --apple_deploy_target 14.0` on macOS (14.0 being the
oldest macOS Microsoft's macOS archive is built for) and, on Windows, the Visual Studio generator the machine has: a
CPU-only release build of the shared library, tests neither built nor run, without the reporting client. The
workflow's comments say where each flag comes from. **Its dependencies** (abseil, Eigen, protobuf, ONNX, flatbuffers
and the rest of what a CPU build needs) are downloaded by the build itself, through CMake, from the addresses in
ONNX Runtime's `cmake/deps.txt` at that commit, each checked against the SHA-1 written beside it there, and never
taken from what the build machine has installed. One of them, mp11 (Boost.Mp11, header-only), is declared without a
hash in ONNX Runtime's CMake, so `core/Tools/onnxruntime-build.py` fetches it first, checked against deps.txt the same
way, and hands CMake that copy. With `--no_telemetry` the 1DS client, and the curl, mbedTLS, SQLite and zlib it
brings, are neither fetched nor built. **The gate:** before uploading, each job scans its library with
`core/Tools/scan-onnxruntime.sh` (Linux, macOS) or `scan-onnxruntime.ps1` (Windows), whose markers are copies of
`ReportingClientScan.markers` that a first job checks against the Swift list, and uploads nothing that carries any.
Each job then uploads an archive named like Microsoft's with `-deckie-no-telemetry` added and laid out the same way
(the library and its links, the three vendored headers, checked against the vendored copies, `LICENSE`,
`ThirdPartyNotices.txt`, `Privacy.md`, `VERSION_NUMBER`, `GIT_COMMIT_ID`), with a `.sha256` file beside it, and writes
the library's and the archive's sizes and SHA-256 values and the build time into its job summary. Started with
`publish` ticked, the workflow puts them on this repository's release `onnxruntime-1.31.1-deckie-no-telemetry`
(`https://github.com/idontlikecodemuch/deckie/releases/tag/onnxruntime-1.31.1-deckie-no-telemetry`), from which
`fetch-onnxruntime.sh --deckie` fetches the Linux archive once its hash is recorded here and in the script.

| Platform | File | Bytes | SHA-256 |
|---|---|---|---|
| Linux x86_64 | `onnxruntime-linux-x64-1.31.1-deckie-no-telemetry.tgz` | first run pending | first run pending |
| | `lib/libonnxruntime.so.1.31.1` in it | first run pending | first run pending |
| Windows x64 | `onnxruntime-win-x64-1.31.1-deckie-no-telemetry.zip` | first run pending | first run pending |
| | `lib/onnxruntime.dll` in it | first run pending | first run pending |
| macOS arm64 | `onnxruntime-osx-arm64-1.31.1-deckie-no-telemetry.tgz` | first run pending | first run pending |
| | `lib/libonnxruntime.1.31.1.dylib` in it | first run pending | first run pending |

The build times, and the sizes against Microsoft's libraries (29,345,384 bytes on Linux, 17,253,728 on Windows,
44,797,256 on macOS, where Microsoft's also holds the CoreML and WebGPU execution providers this CPU-only build leaves
out), go into the status log with the first run. Two things found while reading ONNX Runtime's build files at the
pinned commit, both with the main session: **on Windows**, `--no_telemetry` means the event-tracing provider is never
registered (the Windows environment then holds ONNX Runtime's base telemetry class, whose functions do nothing,
instead of `WindowsTelemetry`), but the provider's definition, `onnxruntime/core/platform/windows/telemetry.cc`, is
compiled into every Windows build and referred to by `inference_session.cc`, so its name, `Microsoft.ML.ONNXRuntime`,
may still be in the DLL, in which case the Windows gate fails by design; and **Eigen**: ONNX Runtime's build applies
two patches of its own to Eigen's source on every platform (`cmake/patches/eigen/s390x-build.patch` and
`s390x-build-werror.patch`, as Microsoft's builds do), changing three files used only on IBM Z (s390x) and
`Eigen/src/Core/RandomImpl.h` (a branch for big-endian machines only), so the MPL decision below, which rests on
Deckie shipping Microsoft's library unrebuilt with Eigen unmodified, meets a rebuilt library whose Eigen files are
patched, though not in any code these three platforms compile differently.

**Licence:** MIT, on the allowlist. Quoted from the archives' `LICENSE` (1,073 bytes, SHA-256 `2f07c72751ae...`, the
same text in both); each vendored header begins "Licensed under the MIT License":

```text
MIT License

Copyright (c) Microsoft Corporation

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

**What the library carries.** The archives' `ThirdPartyNotices.txt` (338,088 bytes, SHA-256 `143764b952fd...`) lists
the code of others built into ONNX Runtime, across all of its builds. Most of it is under licences on the allowlist
(Apache 2.0, BSD, MIT, zlib, public domain). One entry is under the Mozilla Public License 2.0: **Eigen**, a C++
maths library. ONNX Runtime's CPU kernels use Eigen, so the library file contains MPL 2.0 code. MPL 2.0 is copyleft
file by file: it covers Eigen's own files (unmodified in ONNX Runtime's build) and not Deckie's code, and a binary
distribution must tell its users where Eigen's source is. Nothing of ONNX Runtime's is built into Deckie's program.

The notice text is the file `ThirdPartyNotices.txt` at the top of the archive's one folder, beside `LICENSE`;
`fetch-onnxruntime.sh` unpacks it to `core/.deps/onnxruntime/ThirdPartyNotices.txt`. Eigen's entry starts at its
line 417 (after the `_____` that separates entries) and runs on with the licence's full text; its first lines:

```text
Eigen

MPL v2.0
Mozilla Public License Version 2.0


==================================

1. Definitions

--------------
```

**What the official Linux library carries for its reporting client** (read from the library's own strings, Oct
29, 2026). Besides the notice file's entries, the official Linux library statically contains, for the 1DS client
above: **curl 8.20.0** (the curl licence, an MIT-style permission notice that is not on the allowlist word for
word; the notice file lists it), **mbedTLS** (Apache 2.0), **SQLite 3.53.1** (public domain) and **zlib** (zlib
licence). The official Windows library has none of these. **Decision** (the main session, Oct 29, 2026): the curl
licence is not added to the allowlist; these four are present only in the official development binaries and leave
with the client when Deckie's own `--no_telemetry` build replaces them (above). Should that build still link any of
them, which and why is reported to the main session before anything ships. RapidJSON, whose test files carry the
JSON Licence, leaves no trace in either library.

**The MPL 2.0 decision** (the main session, Oct 28, 2026). Files under MPL 2.0 ship when they are unmodified, with
their notices in the app's acknowledgements. Any change Deckie ever makes to an MPL file is published. Where an
equivalent under a licence already on the allowlist exists, it is preferred. Eigen inside ONNX Runtime qualifies as
it is: Deckie ships Microsoft's library file without changing or rebuilding it, and the acknowledgements carry
Eigen's entry from the notice file above. MPL 2.0 is on the allowlist in those terms (below).

**How to update:** choose the release and read its notes for changes to the C API; download both archives from the
release page; record their sizes and SHA-256 values here, and the Linux archive's in `fetch-onnxruntime.sh`
(`VERSION`, `SHA256`, `SIZE`); copy the three headers from the Linux archive over the vendored ones and record their
hashes (a new API version changes `ORT_API_VERSION`, so the test that expects 31 changes with it; the shim then
refuses libraries older than the header, while newer libraries still offer the older version); re-quote `LICENSE`
and reread `ThirdPartyNotices.txt` for new licences; reread `Privacy.md` and check that `ORT_DISABLE_TELEMETRY` is
still the switch (`strings` on the library should show it); delete `core/.deps/onnxruntime` and run the script again;
run `swift build` (no warnings) and `swift test`, which reruns the beat tracker's parity tests. CI fetches the new
archive once, since the script's hash is its cache key. Then rebuild Deckie's own archives: change `ORT_VERSION`,
`ORT_TAG`, `ORT_COMMIT`, `RELEASE_TAG` and the archive names in `onnxruntime-build.yml`, run it with `publish`, and
record its archives above and the Linux one in `fetch-onnxruntime.sh` (`--deckie`).

## 7. Beat This!, the beat tracker (weights exported per machine; development-only Python tools)

Beat This! is the beat and downbeat tracker of Francesco Foscarin, Jan Schlüter and Gerhard Widmer (Institute of
Computational Perception, JKU Linz; "Beat This! Accurate Beat Tracking Without DBN Postprocessing", ISMIR 2024),
published as the Python package `beat_this` with trained checkpoints (a checkpoint is a saved set of a network's
learned numbers, its weights). Deckie uses the `final0` checkpoint, the paper's main model trained on all its data
except the GTZAN set, with seed 0, exported to ONNX:

- `core/Tools/export_beat_this.py` loads the checkpoint through the package's own loader, which downloads it once
  from the authors' file share (the package's `CHECKPOINT_URL`; the checkpoints are not on GitHub's release pages),
  checks its SHA-256, exports the network alone (spectrogram in, beat and downbeat logits out, for any length) to
  `core/.models/beat_this_final0.onnx`, which `.gitignore` keeps out of the repository, and checks the export
  against PyTorch. Like ONNX Runtime's library, the model file is made per machine; CI makes it once and caches it.
- The rest of the package's method, the spectrogram, the chunking of long pieces and the peak picking, is ported to
  Swift in `DeckieCore` (`Sources/DeckieCore/Beat/`), following the package's source; no Python runs during
  analysis.

Christopher approved the downloads (the model, the package and the Python tools that export it) on Oct 28, 2026,
and the lead took responsibility for them.

| | |
|---|---|
| Package | `beat_this` 1.1.0 from PyPI (`beat_this-1.1.0-py3-none-any.whl`, SHA-256 `3f2b2d1e027c6dac380bf80c71555e3c28a4036a7f1af20129a945915a72a645`); repository `https://github.com/CPJKU/beat_this` |
| Checkpoint | `final0`: `https://cloud.cp.jku.at/public.php/dav/files/7ik4RrBKTS273gp/final0.ckpt`, downloaded Oct 28, 2026, 81,058,141 bytes, SHA-256 `8c328b45f59d8dd3dff219253ff6a8d6482be57d0133a29140e2febbf8eb8331` (pinned in the export script, which refuses any other file). A PyTorch Lightning 2.3.0 checkpoint of 20,251,712 parameters, read with `weights_only=True` (tensors only, no code is run) |
| Exported model | `beat_this_final0.onnx`, 82,098,829 bytes, SHA-256 `f1d932049c9344ae3b1192673ef895c97807ba59fc1aa3d4e8d3d17c43c9b8dc` (also in the export script, which says whether a new export matches), ONNX opset 17; input `spect` (float32, 1 x T x 128), outputs `beat` and `downbeat` (float32, 1 x T), T free. Two exports here gave these same bytes: one under Python 3.13, one in a fresh Python 3.12 environment set up as CI sets it up |
| Export check | largest difference between ONNX Runtime 1.31.1 and PyTorch in a logit: 2.3e-6 on random spectrograms of 13 to 1,512 frames, 1.1e-5 on a click track whose logits reach 12.5 |

**Licence:** MIT, on the allowlist, for the code and, as the authors state, for the published weights. Quoted from
the repository's `LICENSE`, fetched raw from GitHub (`https://raw.githubusercontent.com/CPJKU/beat_this/main/LICENSE`)
on Oct 28, 2026 (1,113 bytes, SHA-256 `909ab6549794...`; the wheel carries the identical file):

```text
MIT License

Copyright (c) 2024 Institute of Computational Perception, JKU Linz, Austria

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

and from the repository's README (fetched the same way, 17,037 bytes, SHA-256 `be7b51a9b6ff...`), section "License":

```text
The code and the published model weights are released under the [MIT license](LICENSE). Note that some of the training files are fully copyrighted or under limited Creative Commons licenses, and it is up to the user to assess whether this may impact their use case.
```

So the weights are under the same terms as the code. The second sentence leaves it to users to judge whether a model
trained partly on copyrighted recordings and recordings under limited Creative Commons licences affects them. That is
a question about the training data, not a licence on the weights, and the main session's training-data rule (in the
allowlist below) now answers it: the MIT weights ship even though Deckie could not ship the recordings they were
trained on, unless one of those data sets' own licences forbids commercial use, in which case the weights count as
non-commercial. The rule asks for each data set, its licence and the trainer to be recorded here beside the weights:
that record follows (Oct 29, 2026). In short, three sets state non-commercial terms on their own pages (ASAP, RWC,
Filosax), much of the rest is commercial music the sets do not license, and the trainer holds no rights in the
recordings. Under the Oct 28 wording that read as non-commercial; Christopher decided on Oct 29 (P19, now D15 in the
allowlist below) that weights ship under their publisher's licence with the training sets recorded as disclosure, so
Beat This! ships, MIT, with the record below shown in the acknowledgements.

**Training data.** This is the record the "Still to do" above asks for: what the `final0` checkpoint was trained on,
on what terms each data set's audio and beat annotations are published, and who trained it. All of it was read on
Oct 29, 2026, from the places named; where a host did not answer, the text says so. A *beat annotation* is a list of
the times of a piece's beats, in most sets with the first beat of each bar (the *downbeat*) marked; the network learns
to reproduce them. A *spectrogram* is a picture of a recording's frequencies over time, which the network reads in
place of the audio. Creative Commons (CC) terms: BY means credit the author, NC non-commercial use only, SA
share-alike (adaptations keep the same licence); CC BY and CC BY-SA allow commercial use, CC BY-NC and CC BY-NC-SA do
not. "Own page" below means the distributor's own page, read on GitHub. "mirdata" means the loader for that set in
mirdata (`https://github.com/mir-dataset-loaders/mirdata`, file `mirdata/datasets/<set>.py`), an open-source Python
library for music data sets whose loaders record a licence line and a download address; that is second-hand evidence,
its maintainers' reading and not the distributor's word.

*What `final0` saw.* The README (`https://raw.githubusercontent.com/CPJKU/beat_this/main/README.md`): "`final0`,
`final1`, `final2`: Our main model, trained on all data except the GTZAN dataset, with three different seeds"; its
training section says "All 16 datasets and annotations must be correctly set up". The training code (`launch_scripts/train.py` and
`beat_this/dataset/dataset.py` on GitHub, read through the fetch tool) makes GTZAN the only test set and keeps it out of
training and validation. From every other set it takes each piece that the set's `single.split` file marks `train` or
`val` (all 15 have one; GTZAN has none), and the `--no-val` flag, which the README's commands for `final0` to `final2`
use, moves the `val` pieces into training as well. No piece is marked as a test piece. So `final0` was trained on every
piece of the 15 sets in the table below, including the pieces the paper holds out as test folds in its 8-fold
cross-validation (testing in which each eighth of the data takes a turn at being held out); the only data it never saw
is GTZAN. The paper could not be fetched (see the last paragraph); web-search excerpts of its text give 4,556 pieces for
these sets after dropping two (a Beatles piece without downbeats and one with empty beats), with about 15 percent of
each set as the validation part, GTZAN's 993 pieces as the test set, SIMAC and SMC as beats only, and RWC as four
collections (classical, pop, royalty-free, jazz). One excerpt says Filosax is used as its backing tracks only and
GuitarSet as its comping (accompaniment) tracks only; a second search did not repeat that, so it is unconfirmed.

*Where the files come from.* The beat annotations are copied into `https://github.com/CPJKU/beat_this_annotations`
(own page: v1.0 is the paper's set, v1.1 has corrections; `LICENSE` is MIT, "Copyright (c) 2024 Institute of
Computational Perception"). Its README names each set's source, says only "Please cite the relevant papers when using
these beat annotations", and states no terms for any set; the MIT line is on the repository. The authors do not publish
the audio. The spectrograms they trained on are published as one .zip per set in Zenodo record 13922116 (named in the
README; zenodo.org did not resolve, so any licence the record carries is unread), and the README's way to rebuild them
needs the user to hold the original audio.

| Data set: what it is | Audio: who has it, on what terms | Beat annotations: who, on what terms |
|---|---|---|
| **Ballroom**: 698 excerpts of about 30 s, eight dance styles (Gouyon et al., ISMIR 2004 tempo contest) | Commercial music the set does not license: the 30 s previews on ballroomdancers.com, a CD seller (search text of the Extended Ballroom paper, Marchand and Peeters); the contest copy is at mtg.upf.edu (not read). No licence read. mirdata: CC BY-NC-SA 4.0, without saying for which part | Krebs, Böck and Widmer (ISMIR 2013), `https://github.com/CPJKU/BallroomAnnotations`: no licence stated (own page); "It does not include the audio files" |
| **SIMAC**: the rhythm part of the EU project Semantic Interaction with Music Audio Contents; beats only | Not published (mirdata: "not available for download"); where the audio comes from is not stated in what I read. mirdata: CC BY-NC-SA 4.0 (its source, semanticaudio.org, not tried) | Böck, Davies and Knees (ISMIR 2019), `https://github.com/superbock/ISMIR2019`, folder `simac/`: no licence file or statement on the page (own page) |
| **SMC**: 217 excerpts of 40 s chosen because beat trackers find them hard (Holzapfel et al., IEEE TASLP 2012; MIREX 2012); beats only | Source of the audio and its licence not found: search excerpts give no licence and no public download | Holzapfel et al.; copy in `superbock/ISMIR2019`, folder `smc/`: no licence stated (own page) |
| **Hainsworth**: 222 excerpts of about 60 s, six genres (Hainsworth's PhD thesis, 2004) | Commercial music the set does not license: "drawn directly from CD recordings" (search text of a downbeat-tracking review, arXiv 1906.03870). mirdata: "not available for download", yet gives CC BY-NC-SA 4.0 with no source I could read | Hainsworth's, revised by Böck et al. in 2014 (mirdata); copy in `superbock/ISMIR2019`, folder `hainsworth/`: no licence stated (own page) |
| **HJDB**: hardcore, jungle and drum and bass dance music, 235 or 236 excerpts of 30 s to 2 min, sources differ (Hockman, Davies and Fujinaga, ISMIR 2012) | Source and licence not stated in anything read; the Zenodo record is said to link to where the audio can be had, and to say that many of these sets' audio is not public (search text; zenodo.org not resolved) | Downbeats by a drum-and-bass musician (search text); copy in `superbock/ISMIR2019`, folder `hjdb/`: no licence stated (own page) |
| **Beatles**: 179 songs with beats, chords, keys, sections (Isophonics, Queen Mary C4DM) | Commercial recordings the set does not license: mirdata, "audio files ... are not available for download", the user supplies a copy | Isophonics, isophonics.net (not tried); mirdata: "we couldn't find the license information"; copy in `superbock/ISMIR2019`, folder `beatles/`: no licence stated (own page) |
| **Harmonix Set**: 912 Western pop tracks, beats, downbeats, structure (Nieto et al., ISMIR 2019; reproduced and partly corrected in a later paper the annotation README says to cite as well) | Not included: YouTube links (the uploaders' audio) and alignment scores; no audio licence on the page. A 1.2 GB archive of mel spectrograms (spectrograms on a hearing-based pitch scale) is on Dropbox: "Users must agree to the License included before using these data" (own page) | Oriol Nieto, `https://github.com/urinieto/harmonixset`: MIT, "Copyright (c) 2019 Oriol Nieto" (`LICENSE` read raw): commercial use allowed |
| **RWC**: the Real World Computing music database, AIST, Japan (Goto et al.); pop (100 songs), jazz (50), classical (50) per mirdata, plus royalty-free | Recorded for the database, not released commercial music (mirdata). Original terms, as mirdata quotes them: "Users who have submitted the Pledge and received authorization may freely use the database for research purposes". Re-released as RWC 2.0 on Zenodo (record 17177919) "under a Creative Commons license" of unnamed kind (own page, `https://github.com/rwc-music/rwc-annotations`; zenodo.org not resolved); mirdata gives CC BY-NC 4.0 for RWC Popular | AIST's annotations (staff.aist.go.jp, not tried), partly corrected by Böck and by Foscarin (annotation README). The newer set at `rwc-music/rwc-annotations`: "licensed under the CC BY-NC 4.0" (own page): non-commercial |
| **TapCorrect**: 101 tracks, tapped beats corrected by a program and by hand, with downbeats (Driedger, Schreiber, de Haas and Müller, ISMIR 2019) | Not hosted: "YouTube links to all 101 music recordings" (own page); the set licenses none of that audio | "The TapCorrect dataset is published under a Creative Commons Attribution-ShareAlike 4.0 International" (own page, `https://github.com/chordify/tapcorrect`): commercial use allowed, adaptations under the same terms; the program's code is LGPL 3, not used here |
| **JAAH**: Jazz Audio-Aligned Harmony, 113 tracks from two Smithsonian jazz anthologies (Eremenko, Demirel, Bozkurt and Serra, ISMIR 2018, UPF MTG) | Not in the repository (annotations and chroma features only); the tracks come from two commercial anthologies (search text), which the set does not license | `https://github.com/MTG/JAAH`: no licence file or statement on the page (own page); the Zenodo record v0.1 is said to list "CC-BY" (search text; zenodo.org not resolved). Beats and downbeats corrected and added for Beat This! by Vogl and Foscarin (annotation README) |
| **Filosax**: 48 multitrack jazz recordings of about 6 min, up to five saxophonists, stems including the original Aebersold backing track (Foster and Dixon, Queen Mary University of London, ISMIR 2021) | Under an access agreement that mirdata quotes: "Filosax may be used only for non-commercial research purposes", and it "may not be sold, leased, published or distributed to any third party without written permission". The Aebersold backing tracks are commercial play-alongs (mirdata links their sales pages), not licensed by the set | Foster and Dixon (bar starts and chord changes), partly corrected by Foscarin (annotation README); the one agreement covers the whole set (mirdata): non-commercial research only |
| **ASAP**: Aligned Scores and Performances, classical piano with beat, downbeat and time-signature annotations (Foscarin et al., ISMIR 2020) | Not distributed there: "The audio files are not distributed in this repository" (own page); taken from MAESTRO v2.0.0 by Google Magenta, which mirdata gives as CC BY-NC-SA 4.0 | Foscarin, `https://github.com/fosfrancesco/asap-dataset`: "made available under a Creative Commons Attribution Non-Commercial Share-Alike 4.0 (CC BY-NC-SA 4.0) license" (README, and `LICENSE.md` read raw): non-commercial |
| **Groove MIDI**: 1,150 MIDI files, 13.6 hours of drumming on an electronic kit, with audio synthesised from the playing (Gillick et al., Google Magenta, ICML 2019) | Google Magenta; synthesised audio, not recorded music (mirdata). mirdata: CC BY 4.0 (magenta.tensorflow.org not tried) | From Magenta's data (the annotation README names its page); terms as for the audio, CC BY 4.0 per mirdata |
| **GuitarSet**: 360 excerpts of about 30 s of acoustic guitar, 16 annotations each (Xi, Bittner, Ye, Pauwels and Bello, NYU MARL, ISMIR 2018) | Recorded for the set (hexaphonic pickup and a Neumann U-87 microphone, mirdata), not released music. On Zenodo, record 3371780 (own page); the data's licence is unread (zenodo.org not resolved). The GitHub repository is MIT ("Copyright (c) 2018 Music and Audio Research Laboratory - NYU"); mirdata's "MIT License" matches it and is not a statement about the data | In the same Zenodo archive; terms unread, as for the audio |
| **Candombe**: 35 studio recordings, over 2 hours, of candombe drumming in groups of three to five drums, beats and downbeats by an expert (Nunes, Rocamora, Jure and Biscainho, ISMIR 2015) | Recorded in studio for musicological research (mirdata); Zenodo record 6533068; mirdata: CC BY 4.0 (zenodo.org not resolved) | In the same record, same terms (mirdata) |

Not in `final0`'s training: **GTZAN**, the test set (Tzanetakis and Cook; 1,000 excerpts of 30 s, 10 genres). mirdata says
its audio is "no longer available for download" and that it "couldn't find the license information"; beat annotations
in `superbock/ISMIR2019`, folder `gtzan/`.

*Reading the table.* The audio is commercial music that its set does not itself license for Ballroom, Hainsworth, the
Beatles, JAAH and Filosax's backing tracks; for Harmonix and TapCorrect it is YouTube recordings whose rights are the
uploaders' and rights-holders'; for SIMAC, SMC and HJDB no source read says what the audio is. Terms stated as
non-commercial: ASAP (CC BY-NC-SA 4.0, on its own page; its audio source MAESTRO is CC BY-NC-SA 4.0 per mirdata), RWC
(CC BY-NC 4.0 on the re-release's annotations; the original was for research purposes under a pledge) and Filosax
(non-commercial research only); second-hand only, from mirdata, for SIMAC, Hainsworth and Ballroom (CC BY-NC-SA 4.0).
Terms that allow commercial use, stated by the distributor: Harmonix (MIT) and TapCorrect (CC BY-SA 4.0); second-hand,
from mirdata, for Groove MIDI and Candombe (CC BY 4.0). No licence stated on the page read: the SIMAC, SMC, HJDB,
Hainsworth, Beatles and Ballroom annotations, and JAAH's repository. Not read: the data licences of GuitarSet,
Candombe, Groove MIDI and JAAH at their own hosts.

*What the authors say, and the trainers.* Only the README's "License" section (quoted above): the code and the
published weights are MIT, and "some of the training files are fully copyrighted or under limited Creative Commons
licenses, and it is up to the user to assess whether this may impact their use case." Nothing in the README, the
annotations README or the training code that I read says more about rights in the training audio, or states that the
data's licences were checked. The trainer is the Institute of Computational Perception, JKU Linz (the `LICENSE`'s
copyright holder). No source read says it holds rights in any of the training audio, and the README's own sentence
says some of it is copyrighted by others. Two of the paper's authors made or corrected beat annotations: Foscarin
(ASAP, and corrections to RWC, Harmonix, JAAH and Filosax) and Widmer (Ballroom, with Krebs and Böck; the annotation
README also credits Böck with RWC corrections and Vogl with JAAH's). That is authorship of annotations, not ownership of
the recordings.

*What could not be read.* These hosts did not resolve from this session ("getaddrinfo ENOTFOUND"): arxiv.org and
ar5iv.labs.arxiv.org (the paper, arXiv 2407.21658), zenodo.org (the spectrogram record and the Zenodo pages of
GuitarSet, Candombe and JAAH), huggingface.co, ismir2024program.ismir.net, research.jku.at and themoonlight.io. After
those failed no further host outside GitHub was tried, so isophonics.net, staff.aist.go.jp, magenta.tensorflow.org,
dave-foster.github.io, mtg.upf.edu, mtg.github.io, semanticaudio.org and mirdata.readthedocs.io are unread. The paper
is therefore known only from excerpts of its text in web-search results (the data set list, the 4,556, the 15 percent,
GTZAN as the test set, the second-hand claims marked "search text"). The fetch tool returns a summary with quotations
of at most 125 characters; the quotations above are from it, and, unlike the `LICENSE` and README quotations earlier
in this section, were not saved, counted or hashed. The GitHub tool here covers only this repository. Nothing was
downloaded and no dataset or code was run.

These are the facts the allowlist's D15 asks to be recorded and shown; under it the weights ship (above).

**Replacement path** (D15 asks for one per model): without the beat model, Deckie's own code in `DeckieCore` still
gives a tempo and a bar grid, the lab's model-free way (the grid fit over onsets with the tempo multipliers, the
phrase lattice from novelty), at lower confidence and with `grid.source` saying so; the main session is measuring
that path against the shipped grid on the 373 tracks (Oct 29, 2026) and its result settles whether the path is the
fallback or, as Christopher asked, whether a model is needed for beats at all.

**Development-time tools (never shipped).** The export script and the fixture scripts (`make_beat_fixtures.py`,
`make_onnx_fixture.py`) run on PyTorch and its companions, pinned by version in `core/Tools/export-requirements.txt`
and installed only on a developer's machine and in CI's export step (licences from each package's own metadata;
none of this code reaches a Deckie program, and nothing in `core/` imports it):

| Package | Version | Licence |
|---|---|---|
| `torch` | 2.15.0+cpu, PyTorch's CPU-only build from `https://download.pytorch.org/whl/cpu` | Apache 2.0, BSD 2- and 3-clause, BSL 1.0, ISC, MIT, zlib (its parts) |
| `torchaudio` | 2.11.1+cpu, same index | BSD |
| `beat_this` | 1.1.0 | MIT |
| `einops` | 0.8.2 | MIT |
| `rotary-embedding-torch` | 0.9.1 | MIT |
| `soxr` | 1.1.0 | LGPL 2.1 or later (python-soxr, around libsoxr): the package's own resampler, used only to make the reference numbers |
| `numpy` | 2.5.3 | BSD 3-clause and others |
| `onnx` | 1.23.2 | Apache 2.0 |
| `onnxruntime` (for Python) | 1.31.1 | MIT |

Only these direct dependencies are pinned, and by version only: what they pull in is not pinned, and no wheel is
pinned by hash yet. The exported model is pinned by its hash and checked numerically, which is what reaches Deckie.
torch 2.9 and later call the exporter used here (TorchScript-based, `dynamo=False`) "legacy"; their default one
needs the `onnxscript` package as well. If a later torch drops the legacy exporter, the export moves to the new one
and its model is checked the same way.

**How to update:** change the pins in `export-requirements.txt` (and the torch line in `core-linux.yml`, which
installs torch first); for another checkpoint, record its URL and SHA-256 in the export script and here; run the
export script, record the new model's SHA-256 in the script (`ONNX_SHA256`) and here; regenerate the reference
numbers with `make_beat_fixtures.py` and run `swift test`, which compares the Swift port with the package again;
re-quote the `LICENSE` and the README's licence section. CI exports again once, since the export script and its
requirements are its cache key.

**Replacement path** (D15): without YAMNet the vocal fields are absent, the mix windows treat every bar as
vocal-free and the record carries the flag `vocal_unknown` (status log entry 11); the place for a second model
(`VocalPatchModel`) is built and empty.

## 8. YAMNet, the vocal tagger's model (weights fetched by pinned hash and exported per machine; development-only Python tools)

YAMNet is Google's audio event tagger (tensorflow/models, `research/audioset/yamnet`, maintained by Manoj Plakal and
Dan Ellis): a MobileNet v1 network of 3.7 million weights that scores 521 classes of sound, singing, choir and
rapping among them, for each 0.96 s patch of audio, every 0.48 s, and gives a 1,024-value embedding (a vector
describing how the patch sounds) before its classifier. `DeckieInference`'s vocal tagger reads it as one vocal
probability per bar in the lab's shape and uses the mean embedding as the track's style vector (the research and the
choice: `docs/research/n-vocal-tagger.md`; the main session chose YAMNet on Oct 28, 2026 after ruling out Spleeter
and EfficientAT under the training-data rule).

- `core/Tools/fetch-vocal-models.sh` downloads the Keras weights, `yamnet.h5`, from Google's own storage (the URL
  the model's README gives) and the three source files that define the network and its features (`params.py`,
  `features.py`, `yamnet.py`) from tensorflow/models at a pinned commit, checks every file's SHA-256 (below) before
  using it, and runs `core/Tools/export_yamnet.py`, which builds the network with those files in TensorFlow, loads
  the weights, converts the network alone to ONNX with tf2onnx (log-mel patches in, scores and embeddings out),
  checks ONNX Runtime against TensorFlow and writes `core/.models/yamnet.onnx`, which `.gitignore` keeps out of the
  repository. The weights are not kept. CI does the same once and caches the model file.
- The front end (YAMNet's log-mel patches, from `features.py`) is rewritten in Swift in `DeckieCore`
  (`Sources/DeckieCore/Vocal/YAMNetFrontEnd.swift`), checked against `features.py` run in TensorFlow by
  `core/Tools/make_yamnet_fixtures.py`; no Python runs during analysis.

Christopher approved the download (vocal-model weights, and the one-time export tools) on Oct 28, 2026, and the
lead took responsibility for it.

| | |
|---|---|
| Weights | `https://storage.googleapis.com/audioset/yamnet.h5`, downloaded Oct 28, 2026: 15,296,092 bytes, SHA-256 `13c3308955bbfaef262f175ac9c40e47b134573a93984f009220dd7cc12a1744` (pinned in the fetch script and the export script, which refuse any other file); the server's own record of the file: last modified Nov 18, 2019, MD5 `8234225c045859752bd4a2e101f8cd1a` |
| Model code | tensorflow/models commit `a6e25e28dc8433dde6c1319186a41e6d81a03f2d` (Oct 28, 2026), `research/audioset/yamnet/`, fetched raw from `https://raw.githubusercontent.com/tensorflow/models/<commit>/research/audioset/yamnet/<file>`: `params.py` 1,847 bytes, SHA-256 `925bb1e62461016031f98aea09aeac28975dd516f5747513767de5d1b06b6145`; `features.py` 7,490 bytes, `e6cd53f81d072c7c43be4c7fff2b9dd0c5ccc7d64f2fbcfc85b44013d6d2ed5e`; `yamnet.py` 5,541 bytes, `7ef3df32b7ecb782490b5a04d7581a23cfcf701dbf476bc4d03deefe22cdb040`. Used to build the network for the export and to make the reference numbers; nothing of them is copied into Deckie |
| Exported model | `yamnet.onnx`, 14,938,528 bytes, SHA-256 `96bb0dc54745dbbc95ef3f289830c94eec92a6914c4ab711a821bc8aa1c93cfd` (also in the export script, the fetch script and `YAMNet.recordedExportSHA256`, which say whether a new export matches), ONNX opset 17; input `patches` (float32, n x 96 x 64), outputs `scores` (float32, n x 521, after the sigmoid) and `embeddings` (float32, n x 1024), n free. Every export here gave these same bytes: three under Python 3.13, one in a fresh Python 3.12 environment set up as CI sets it up |
| Export check | largest difference between ONNX Runtime 1.31.1 and TensorFlow 2.21.0: 2.6e-6 in a score and 1.6e-6 (relative) in an embedding, on random patches in batches of 1, 7 and 33 and on the patches of synthesised music; the network as built for the export against the source's own waveform model: identical |
| Class indices | read from `yamnet_class_map.csv` beside the code at the same commit (14,096 bytes, SHA-256 `cdf24d193e19...`), which is not copied: Deckie names the classes it uses in its own words (`YAMNetClass`), and the crate never carries the ontology's names |

**Licence:** Apache 2.0, on the allowlist, for the code and the weights. tensorflow/models' `LICENSE` at the pinned
commit (11,512 bytes, SHA-256 `5b17814bf0de8cf65069bc6d7cc38cff19fcaa864d243423ad3ef3db01b52385`) opens:

```text
Copyright 2022 Google LLC. All rights reserved.

All files in the following folders:
/community
/official
/orbit
/research
/tensorflow_models

Are licensed as follows:

                                 Apache License
                           Version 2.0, January 2004
                        http://www.apache.org/licenses/
```

and each of the three source files begins "Copyright 2019 The TensorFlow Authors All Rights Reserved. Licensed under
the Apache License, Version 2.0". The weights file is not in the repository: the model's README in that folder
(5,183 bytes, SHA-256 `e837352cc874...`) points to it ("YAMNet model weights ... in Keras saved weights in HDF5
format") and states no other terms for it, and the TensorFlow Hub and Kaggle listing of the same model gives Apache
2.0 (second-hand, from track N; kaggle.com could not be reached from this session). So the weights are taken as
Apache 2.0, published by the code's owner beside its Apache 2.0 code.

**Training data and trainer, and the attribution (the training-data rule).** The README: "YAMNet is a pretrained
deep net that predicts 521 audio event classes based on the AudioSet-YouTube corpus". Data set: **AudioSet**, by
Google: about two million 10-second excerpts of YouTube videos labelled with 527 sound classes (YAMNet drops six:
"the gendered versions (Male/Female) of Speech and Singing", "Battle cry and Funny music"). Its labels are published
under CC BY 4.0, which allows commercial use (second-hand, from track N: research.google.com could not be reached
from this session to quote it). AudioSet publishes no audio, only video IDs, times and labels; the audio is each
YouTube video's, under its uploader's copyright and YouTube's terms. Trainer: Google, which runs YouTube; Google is
not the owner of the uploaders' audio. The main session accepted AudioSet-trained weights under the rule on Oct 28,
2026 (YAMNet "trained on AudioSet alone", with AudioSet attributed). Attribution, for the app's acknowledgements:

```text
YAMNet audio event model by Google (tensorflow/models, research/audioset/yamnet), Apache License 2.0.
Trained on AudioSet by Google: J. F. Gemmeke, D. P. W. Ellis, D. Freedman, A. Jansen, W. Lawrence, R. C. Moore,
M. Plakal and M. Ritter, "Audio Set: An ontology and human-labeled dataset for audio events", ICASSP 2017;
https://research.google.com/audioset/ ; AudioSet labels licensed under CC BY 4.0.
```

**Development-time tools (never shipped).** The export and the fixture script run in a Python environment of their
own, pinned by version in `core/Tools/yamnet-export-requirements.txt`, installed only on a developer's machine and
in CI's export step (licences from each package's own metadata; none of this code reaches a Deckie program):

| Package | Version | Licence |
|---|---|---|
| `tensorflow-cpu` | 2.21.0 (TensorFlow's CPU-only build, 274 MB wheel) | Apache 2.0 |
| `tf-keras` | 2.21.0 (Keras 2, which YAMNet's code needs; installed without its dependencies, since it asks for the full `tensorflow` package) | Apache 2.0 |
| `tf2onnx` | 1.17.0 | Apache 2.0 |
| `onnx` | 1.23.2 | Apache 2.0 |
| `onnxruntime` (for Python) | 1.31.1 | MIT |
| `numpy` | 2.5.4 | BSD 3-clause and others |

They pull in, unpinned, among others protobuf 7.36.2 (BSD 3-clause), h5py 3.14.0 (BSD 3-clause) and keras 3.15.1
(Apache 2.0, unused by the export). Like section 7's, only the direct dependencies are pinned, by version; the model
that reaches Deckie is pinned by its hash and checked numerically.

**How to update:** for new weights or code, record the new URL or commit and the SHA-256 values in
`fetch-vocal-models.sh` (`WEIGHTS_*`, `SOURCE_COMMIT`, `SOURCE_SHA256`) and in `export_yamnet.py`, and here; check
the class indices `YAMNetClass` uses against the class list at the new commit; change the tool pins in
`yamnet-export-requirements.txt` (and the tf-keras line in `core-linux.yml` and in the fetch script's message); run
`fetch-vocal-models.sh --force --keep-source`, record the new model's SHA-256 in both scripts, in
`YAMNet.recordedExportSHA256` and here; regenerate the reference numbers with `make_yamnet_fixtures.py --source
core/.models/yamnet-source` and run `swift test`; re-quote the licence. CI exports again once, since the scripts and
the requirements are its cache key.

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

MPL 2.0, CC BY 4.0 and the training-data rule were added by the main session's decisions of Oct 28, 2026.

- **Ship:** MIT, BSD 2-clause and 3-clause, Apache 2.0, ISC, zlib, public domain, CC0, and MPL 2.0 (unmodified,
  with notices): any change Deckie ever makes to an MPL file is published, and an equivalent under a licence above
  is preferred where one exists (section 6).
- **Ship for model weights and data only, never code:** CC BY 4.0, with the attribution shown in the app's
  acknowledgements and in this file, and nothing added that stops the files' extraction.
- **Ship only dynamically linked** (kept as a separate library file, not built into Deckie's program), with each
  case named in this file: LGPL 2.1 and LGPL 3.
- **Never:** GPL, AGPL, CC BY-NC (non-commercial), research-only.
- **Model weights and their training data** (D15, Christopher's decision of Oct 29, 2026 on P19, replacing the Oct
  28 wording): weights ship under the licence their publisher grants. A model is refused only when the publisher's
  own terms restrict the use (madmom, Essentia, umxl) or when an owner of its training data has objected. For
  every model, this file records the training sets and their terms as disclosure, and the app's acknowledgements
  show them, together with a named replacement path (what Deckie does without the model). Christopher's words: "I
  agree with your assessment, though we should clarify that in the terms of service / use"; the attorney reviews
  the line. The reason for the change: the Oct 28 wording refused sets that say "non-commercial" while accepting
  all-rights-reserved recordings that grant nothing at all, which is most sets, YAMNet's clips and whatever Apple
  trained its own framework on, and no permissively licensed beat tracker with clean training terms exists.
- The CI check of this list is not built yet.

## How to update: on the quarterly update day, or within a week of a security advisory (track M)

1. Choose the new version and read its changelog (the publisher's list of what changed).
2. Re-record every hash here. Swift image: the `docker-content-digest` header Docker Hub returns for
   `registry-1.docker.io/v2/library/swift/manifests/<tag>`, confirmed by hashing the fetched index, then its amd64
   manifest and layers; the index digest also goes into `core-linux.yml`. Windows: the tag in `core-windows.yml` and
   the installer's hash. Actions: the tag and, once possible, the commit hash. ONNX Runtime, Beat This! and YAMNet:
   sections 6 to 8 say what to record.
3. Re-quote the licence file and check it is still on the allowlist.
4. Rerun the parity tests on both CI workflows, and ask the main session to rerun the 373-track benchmark on the Mac.
5. Update the "last checked" date above. Any new direct dependency gets a written reason here.
