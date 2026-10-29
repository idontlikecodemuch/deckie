# Track M: the core language, and what to build versus depend on

Dated Oct 28, 2026. Answers Christopher's question: "I want to do research on if Rust is the best option and why.
And wouldn't some dependencies not be a bad thing? Since they will be managed and improved by others." It reviews the
language choice in `docs/architecture/pc-linux-track.md` (the charter, which proposes a Rust core) and decision P16
("our own DSP written once as a Rust core called from Swift"). It does not take the charter's choice as given.
Sources are listed in section 8; [inf] marks inference; nothing here is legal advice. Effort figures assume one owner
directing AI coding agents (Claude Code, Codex), measured in agent-assisted weeks of the owner's attention.

## 1. Summary (one page)

**What is actually being shared.** The shared core is smaller than "a second app". It is Deckie's own DSP (DSP,
digital signal processing: arithmetic on lists of audio numbers) and scoring: the beat-grid fit, tempo and key
segments, the 8-bar lattice, mix windows, Camelot mapping, the key estimator, and the pair score. Plus reading and
writing the crate file. In the lab that is about 1,740 lines of Python (`analyze.py` 885, `score.py` 441,
`key_light.py` 223, `local_tempo.py` 191), mostly glue around small numeric routines. The heavy machinery (decoding
MP3 and AAC, running the Beat This! model, loudness) is done by Apple's frameworks on Apple. On Windows and Linux
only, it is done by libraries we pick. So the question is about roughly 3,000 lines of our own code and which
language they live in.

**Recommendation: Swift everywhere for Deckie's own code, with C libraries as the dependencies on Windows and
Linux.** Write the DSP, scoring and crate code once, as a plain Swift package. Plain means it imports no Apple-only
framework. The Apple apps then use it with no translation layer. On Windows and Linux the same package builds with
Swift 6.4.1, which installs on Windows x86_64 and arm64 and on Linux. Swift calls C libraries directly, with no
binding generator (a tool that writes the glue code between two languages). So the Windows and Linux pieces are
reached the same way from Swift as from Rust: ONNX Runtime's C interface for the model (ONNX Runtime is
Microsoft's MIT-licensed engine for running trained models), dr_mp3 for MP3, Windows' own AAC decoder, libebur128
for loudness and PocketFFT for the FFT (Fast Fourier Transform, the step that turns sound into frequencies). The
reasons:

1. One language for the whole project, which the owner and agents already work in for the apps.
2. No foreign-function boundary in the primary product. A foreign-function boundary is the seam where one
   language calls another, and it needs its own glue, build steps and debugging.
3. The Windows and Linux builder is decided as "after the trials" (P17). So its risk should not tax the Mac and
   iPad product now.
4. The decision can be undone. If Swift on Windows disappoints, about 3,000 lines with a parity test suite port to
   Rust in an estimated 4 to 6 weeks [inf]. A parity test is a test that the port gives the same numbers as the lab.

The guard is a two-week spike before stage 2: the grid fit, Camelot and `score.py` in the Swift package, built and
tested on Linux in the cloud and on a Windows CI runner (CI, continuous integration: a machine that builds and
tests every commit), matching `mixer/pairs.json`.

**Runner-up: the charter's Rust core, called from Swift.** It is the industry-proven pattern (Mozilla's Firefox
apps, Signal's libsignal). Rust has first-class Windows and Linux support and the best dependency-hygiene tooling
of any candidate. It wins if the Swift spike fails its Windows gate, if an Android app becomes real, or if Desk Lite
needs a GUI soon. Rust's cost is a second language and toolchain, forever, for a seam that today only one
secondary platform needs.

**The dependency policy in five lines:**

1. Depend on standards and heavy machinery: decoders, FFT, model runtime, loudness, XML, model weights. Own
   Deckie's ideas: the DJ DSP, the key estimator, the scoring and the crate format.
2. Use the platform first (Apple's frameworks, Windows Media Foundation), then a permissive C library with active
   maintainers. Never a GPL, AGPL or non-commercial one.
3. Pin every dependency by version and hash. List each in one `DEPENDENCIES.md` with its licence quote, its
   upstream, and how we would replace it. A CI job refuses any licence outside the allowlist.
4. Vendor small leaf libraries (copy them into the repo; under about 5,000 lines, public domain or MIT). Take
   large ones as pinned binaries. Allow no dependency that runs code or downloads anything at build time.
5. Hold one update day a quarter: bump versions, read changelogs, rerun parity tests and the 373-track benchmark.
   Apply security advisories within a week. Every new direct dependency needs a written reason.

**What we would regret.** With Swift: Swift on Windows has a small community. When the toolchain breaks there, we
may be first to hit it, and Foundation (Swift's standard library of everyday types) does not yet link statically
on Windows. With Rust: paying a translation-layer tax on every Mac and iPad build, starting now, for a platform not
yet proven to be wanted. With either: skipping the parity fixtures. Neither compiler catches the bugs that matter
here (a threshold off by one bar, decibels confused with power); only tests against the lab's numbers do. Also
regrettable: letting a one-person wrapper (the 7-star `beat-this-rs`) into the tree instead of owning its few
hundred lines.

## 2. The candidates compared

How to read the table. "From Swift on iOS" is the cost of the Apple apps calling the core. "Agents" draws on the
one small cross-language benchmark found, plus inference. "Usage" is the share of the 2025 Stack Overflow survey's
respondents who used the language for extensive work in the past year, a proxy for community and hiring.

| Candidate | From Swift on iOS | Numerics, FFT (licence) | ONNX Runtime | Decoding without GPL | Windows and Linux build, packaging | Size added [inf] | Agents, strictness, tests | Usage 2025 | Licence hygiene tooling | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|
| **Swift (cross-platform)** | Native: no seam at all | No Accelerate (Apple's maths library) off Apple. PocketFFT (BSD-3) or KissFFT (BSD-3) via C. Standard `SIMD` types. swift-numerics (Apache 2.0) has no FFT | The C API is called directly. Microsoft's Swift package is Apple-only and failed to build on Linux at Swift Package Index (Feb and Apr 2026), so we write a small system-library target (a declaration that tells Swift where a C library lives) | dr_mp3 (public domain), Media Foundation through a small C shim, ffmpeg (LGPL, dynamic) on Linux | 6.4.1 on Windows (x86_64, arm64; needs Visual Studio 2022 components) and Linux. Windows workgroup formed Jan 2026. Static runtime on Windows lacks Foundation (ICU clash), so ship DLLs | Mac and iPad: about 0. Windows: about 20 MB of runtime and ICU DLLs (older figure) | Incept5 (Oct 2026, 48 tasks): Swift weakest for most models. Swift 6 checks data races at compile time; Swift Testing runs on Linux and Windows | 5.4% | Weak. SwiftPM has `Package.resolved` (a lockfile: the exact versions in use) but no `cargo-deny`; scanners partly support Swift licences | **Recommended** |
| **Rust** | C ABI (a C-shaped calling convention) through `cbindgen`, or UniFFI (Mozilla's binding generator), packed as an xcframework (an Apple bundle of builds for device and simulator). iOS is Tier 2 ("guaranteed to build", tests not always run) | RustFFT (MIT or Apache 2.0, NEON and AVX), realfft; ndarray | `ort` 2.0.0-rc.14: still a release candidate, one organisation. Or pure-Rust `rten` (MIT or Apache 2.0, CPU only) | Symphonia (MPL 2.0, AAC-LC "Great", HE-AAC unfinished; patent question per track L), minimp3 bindings, Media Foundation via the `windows` crate | Windows MSVC and Linux are Tier 1 ("guaranteed to work"). `cargo` builds everything | 1 to 3 MB static library plus the runtime | Incept5: close behind Swift, and "Most failed Rust attempts don't compile", so the compiler catches them. Strictest compiler of the set; `cargo test` built in | 14.8%; most admired (72%) | Best: `cargo-deny` (licences, bans, advisories, sources), `cargo-audit` (RustSec database), `Cargo.lock` | **Runner-up** |
| **C++** (CMake plus vcpkg or Conan; vcpkg and Conan are C++ package managers) | Swift's C++ interop calls it directly, supported on all Swift platforms | PocketFFT, KissFFT, PFFFT (BSD-style); Eigen (MPL 2.0) | Native C++ API, official | dr_mp3, platform decoders | Mature everywhere, but CMake and toolchain upkeep is real work | Small | No memory safety: agents' mistakes become crashes, not compile errors. GoogleTest or Catch2 | 23.5% | vcpkg baselines and overrides pin versions; no built-in licence gate | Possible, not wise for this team |
| **C plus a thin layer** | Direct, the simplest seam | Same C FFT libraries | C API, official | Same | Easy to compile; everything else by hand | Smallest | Least strict; the agent's errors surface at run time | 22% | None built in | No |
| **Kotlin Multiplatform** (Kotlin compiled to native code) | Through an Objective-C header; Swift Export is Alpha in Kotlin 2.4 | No mature native numerics or FFT | No Kotlin/Native binding; Java binding only | Would need C | Windows (`mingwX64`) is Tier 3: "not guaranteed to be tested on CI" | Runtime plus garbage collector | Good on Android, weak here | 10.8% | Gradle lockfiles | No: Windows is Tier 3 |
| **Go** | `gomobile` or cgo (Go's bridge to C) with Go's runtime and garbage collector inside the iOS app | gonum (BSD-3); weak SIMD | Third-party cgo wrapper needing a shared library, a poor fit for iOS | Via C | Easy on Windows and Linux | Several MB of runtime | Agents good; types simple | 16.4% | `go.sum`, `govulncheck` | No |
| **Zig** | C ABI, easy | Few libraries | Via C | Via C | Good cross-compiler | Small | Pre-1.0. 0.16 (2026) rewrote I/O and broke existing code; thin agent training data | 2.1% | Minimal | No |
| **Python packaged** (PyInstaller, Nuitka, BeeWare) as Desk Lite only | Not used on Apple (Swift there), so this is the two-implementations path | numpy and scipy (BSD); careful, python-soxr is LGPL | Official wheels | Via libraries | Track A: PyInstaller bundles of the lab ran 0.5 to 1.5 GB with signing trouble; leaner with only numpy, scipy and onnxruntime | Hundreds of MB | Agents strongest here; type checking optional | 57.9% | `pip-audit`, `pip-licenses` | Only as a stopgap prototype |
| **Dart** (Flutter) | `dart:ffi`; would bring Flutter UI | Weak | Community packages | Via C | Good GUI on Windows and Linux | Large | Fine | 5.9% | `pubspec.lock` | No |
| **.NET** (C#) | NativeAOT (compiled ahead of time) to iOS works but heavy; C exports to Swift | MathNet (MIT) | Official `Microsoft.ML.OnnxRuntime` | Media Foundation natively | Excellent on Windows | Tens of MB | Agents good | 27.8% | NuGet lockfile, `dotnet list package --vulnerable` | Only if Desk Lite were Windows-only and a second implementation |

Four points the table compresses:

- **The dependencies are C in every case.** ONNX Runtime, libebur128, dr_mp3, PocketFFT, ffmpeg and Media
  Foundation are C or C-shaped. Rust reaches them through crates (Rust's packages) that wrap C, plus a few pure-Rust
  replacements. Swift reaches them by importing the C header. So Rust's ecosystem advantage is real but narrower
  here than it looks: RustFFT, Symphonia, `ebur128` and `rten` save little over the C originals when the C ones are
  small and stable [inf].
- **Compiler strictness matters less for this code than it sounds.** Swift and Rust both check array bounds and
  trap on integer overflow, so neither lets an agent corrupt memory silently. Rust's compiler is stricter still
  about ownership and threads. The DSP is single-threaded arithmetic, so that extra strictness buys little here.
  The defects that move picks are numeric: the wrong window, the wrong unit, an off-by-one bar. No type system
  catches them, but the port plan's parity tests do (grid BPM within 0.01 percent, identical mix-window bars and
  Camelot codes).
- **Agents.** The only public cross-language result found is small: Incept5's 48 tasks, Oct 2026, run mostly on
  open models. It found Swift the weakest language for most models and Rust close behind, with Rust's failures
  mostly compile errors. A compile error is the better failure, because the agent sees it and fixes it in the loop.
  For a one-owner team, the bigger factor is reviewing one language rather than two [inf].
- **Hiring and community.** Rust has nearly three times Swift's usage and far more people doing cross-platform
  native work. Swift on Windows is a few companies and the new workgroup. If Deckie ever hires, a Rust engineer
  is easier to find than a "Swift on Windows" engineer. An iOS engineer is easier still, and only Swift uses them.

## 3. Build versus depend

### 3.1 Which pieces

| Piece | Depend or own | Apple | Windows and Linux | Why |
|---|---|---|---|---|
| MP3 and AAC decoding | Depend | AVFoundation | dr_mp3 (public domain, vendored); Media Foundation's AAC decoder on Windows; ffmpeg LGPL as DLLs on Linux | A solved, patent-laden problem. The platform decoder avoids the AAC patent question (track L) |
| Resampling to 44.1 kHz | Depend | AVAudioConverter | libsamplerate (BSD-2) [inf: confirm licence file] | soxr is LGPL; resampling quality is a specialist field |
| FFT | Depend | Accelerate vDSP | PocketFFT (BSD-3), vendored | Fast FFTs take years to tune; the interface is tiny, so swapping is cheap |
| Model runtime | Depend | Core ML | ONNX Runtime C API, pinned binary | Huge, Microsoft-maintained, MIT |
| Beat model | Depend (weights), own the wrapper | Beat This! small in Core ML | Beat This! ONNX export | The model is the research; the mel front end and peak picking around it are a few hundred lines we already describe in track A |
| Loudness (EBU R128) | Depend | Music Understanding, plus our own per-bar K-weighting | libebur128 (MIT), vendored | A published standard with a reference implementation; ours would only reproduce it |
| XML (rekordbox import) | Depend for parsing, own the mapping | Foundation `XMLParser` | Foundation's XML (libxml2, MIT) | Parsing is solved; the mapping to Deckie's fields is product logic |
| JSON | Depend | Foundation `JSONEncoder` | the same | Standard library |
| Vocal tagger model | Depend | Music Understanding | EfficientAT (MIT) or YAMNet (Apache 2.0) on ONNX Runtime | Track J |
| Grid fit, local tempo, lattice, mix windows, fade, flags | **Own** | shared package | shared package | Deckie's ideas, tuned on the 373 tracks; no library does this |
| Key estimator (chroma, EDMA profile, hysteresis) | **Own** | second vote | primary | Every stronger open key detector is GPL, AGPL or non-commercial (track L) |
| Camelot, scoring, transitions, reasons | **Own** | shared package | shared package | The product |
| Crate format | **Own** | shared package | shared package | D13: Deckie's own format |

### 3.2 The real costs on each side

A dependency's costs, each with an example from this year:

- **Supply chain.** An attacker can slip code into a package everyone trusts. On Aug 20, 2026 the Rust Security
  Response Team removed a malicious `arrayref` 0.3.10 and look-alike crates. The malicious build script fetched
  malware from a remote server; `arrayref` has over 245 million downloads. Every ecosystem has this. The defence
  is fewer dependencies, pinned hashes, and no build-time code from the network.
- **Licence drift.** A project can relicense or add a non-commercial model. Track A's Python stack sank this way:
  madmom's models are CC BY-NC-SA, Essentia is AGPL, the EffNet embedding is NonCommercial.
- **Breaking changes.** Mixxx's move from Qt 5 to Qt 6 forced it to raise its minimum OS to macOS 11 and Windows 10
  1809. Zig 0.16 changed every I/O function. `ort` has been a 2.0 release candidate through at least 14 candidates.
- **Abandonment and bus factor.** Bus factor means how many maintainers could vanish before a project stalls.
  `beat-this-rs` is one person with 7 stars. Demucs is archived. Arc for Windows retires on Dec 22, 2026; it was
  built in Swift.

Own code's costs:

- **Bugs.** Our own FFT or MP3 decoder would have bugs that the libraries fixed a decade ago.
- **Maintenance.** Every line we own we must update when the platform changes.
- **Re-deriving solved problems.** EBU R128 has a reference implementation; rewriting it buys nothing.

The balance [inf]: depend where the problem is a standard or a large engine and the interface is narrow. Own where
the code is the product, or where every available library is unshippable. Christopher's instinct is right for
decoders, FFT, model runtime, loudness and XML. It is wrong for the DJ logic, because no maintained library does it.

### 3.3 Managing dependencies, by ecosystem

| | Swift (SwiftPM) | Rust (Cargo) | C/C++ (vcpkg, Conan) |
|---|---|---|---|
| Lockfile | `Package.resolved` (revision per package); `--force-resolved-versions` in CI | `Cargo.lock` with checksums | vcpkg `builtin-baseline` plus `overrides`; Conan lockfiles |
| Vendoring | Copy C sources into a target; no built-in command | `cargo vendor` | Copy sources; common practice |
| Licence gate | None built in; community tools read `Package.resolved` | `cargo-deny licenses` | None built in |
| Advisories | OWASP Dependency-Check (experimental) | `cargo-audit`, `cargo-deny advisories` (RustSec) | Scanners such as Trivy |
| Build-time code | Package plugins (opt-in, sandboxed on macOS) | `build.rs` runs arbitrary code | CMake runs arbitrary code |

Swift's tooling is the weakest of the three. With Swift, Deckie's few dependencies are mostly vendored C. A
50-line CI script can check a hand-kept `DEPENDENCIES.md` against the vendored licence files. With Rust,
`cargo-deny` does the same out of the box, but the transitive tree (the dependencies of dependencies) is larger, so
there is more to check [inf].

### 3.4 A dependency policy for Deckie

The five lines in section 1, plus the details:

- **Allowlist.** MIT, BSD-2, BSD-3, Apache 2.0, ISC, zlib, public domain and CC0 ship. LGPL ships only as a
  separately loaded library (a DLL), never linked into our binary. MPL 2.0 (file-level copyleft: changes to those
  files must be published) ships unmodified with notices, decided Oct 28 (note on D14); Symphonia and Eigen are MPL. GPL, AGPL, any NonCommercial and
  research-only licences never ship. Model weights get their own licence line. Their training-data caveat is
  recorded (Beat This!'s maintainers: "we are not lawyers").
- **Admission test for a new dependency.** It does something we should not own. It has a licence on the allowlist,
  quoted from its file. It has more than one active maintainer or is small enough to vendor and own. It has a
  stable interface we wrap behind one small Deckie protocol, so replacing it touches one file.
- **Pinning.** Exact versions plus hashes. Model weights pinned by SHA-256 and recorded in the crate's engine
  record (track L's `engine.models[]`), so a crate always says which weights produced it.
- **Cadence.** Quarterly update day as in section 1. Advisory checks on every CI run. A dependency with no release
  in 18 months gets an owner's review: vendor it, replace it, or accept it.
- **Agents.** Agents may not add a dependency without the admission note in the same commit. The CI licence and
  allowlist job is the backstop.

## 4. Prior art

What public sources show, which is thin. Most DJ companies do not publish their stacks.

| Product | Written in (public evidence) | What it cost or bought |
|---|---|---|
| **Mixxx** | C++ with Qt, CMake; GPL-2 | One codebase on Windows, macOS and Linux for two decades. The Qt 6 move (2.5, Dec 2024) forced macOS 11, Windows 10 1809 and Ubuntu 22.04 minimums and a C++20 compiler: a framework dependency setting the product's floor |
| **Serato** | C++: 2026 Auckland job ads for "C++ music production applications", senior and principal C++ roles | A native C++ core across Mac and Windows; hiring C++ audio engineers is a standing cost (they run a graduate programme) [inf] |
| **VirtualDJ** | Plugin SDK in C++ with Mac and Windows branches (Atomix). The core's language is not published (C++ [inf]) | Long-lived native app on both platforms |
| **rekordbox** | Not published. One user forum post says it uses JUCE (a C++ audio app framework); unverified | |
| **DJ.Studio** | Electron (a desktop app built from web technology): v37, and v41 in "Next", per Desktop Insights' scan | Fast cross-platform UI; the audio engine is not disclosed |
| **Lexicon** | Electron v32 with FFmpeg and SQLite, per the same scan; grew from a web app, Rekordcloud | Windows and Mac from one codebase; leans on FFmpeg for decoding |
| **Mixed In Key** | Began as a C# .NET Windows app built on a **licensed** key detector from zplane | The key market leader bought its core algorithm as a dependency rather than building it |
| **Arc / Dia** (not DJ, but the largest Swift-on-Windows effort) | Swift on Windows, with their own WinRT bindings | Arc shared most of its code with Mac; Arc is being retired and Dia reached Windows in Oct 2026, more than a year after Mac. A company with dedicated toolchain engineers still found Windows slow [inf] |
| **Firefox, Signal** (not DJ) | Rust core with Swift and Kotlin bindings (UniFFI; libsignal) | The proven shared-core pattern, run by teams with build engineers |

Lessons [inf]. The DJ engines are C++ because they predate Rust. The library tools (Lexicon, DJ.Studio) chose web
shells plus FFmpeg, trading size for speed. None publishes a Rust or cross-platform Swift core. Mixed In Key shows
that licensing a commercial key detector is a real option for Deckie's weakest block off Apple. The shared-core
pattern works at Mozilla and Signal, but they amortise the build plumbing over far more code than Deckie's 3,000
lines.

## 5. One shared core called from Swift, versus two implementations

Three shapes, costed over three years (agent-assisted weeks of the owner's attention, all [inf]):

| | A. Swift everywhere (one core, no seam) | B. Rust core called from Swift (the charter) | C. Two implementations (Swift on Apple, Rust or Python on Windows), held together by the benchmark |
|---|---|---|---|
| Upfront | 1 to 2 weeks: a portable package, C module maps for ONNX Runtime and the FFT, Linux and Windows CI | 3 to 4 weeks: C ABI or UniFFI, xcframework build, two CIs, Swift wrapper types | 0 now; 6 to 8 weeks later to port DSP and scoring a second time |
| Every DSP or scoring change | once | once in Rust, plus the binding when a type changes | twice, plus a check that the two still agree |
| Ongoing per year | 2 to 3 weeks: Windows toolchain bumps, DLL packaging | 3 to 5 weeks: two toolchains, Rust and Xcode version pairs, cross-language debugging, two dependency audits | 4 to 8 weeks while tuning is active (the port plan makes `score.py`'s constants into `Profile` parameters; every retune happens twice) |
| Risk event | Swift on Windows stalls: port to Rust, 4 to 6 weeks, maybe 1 in 4 [inf] | xcframework or App Store friction; small | Silent drift: the two engines disagree on picks and only the Mac benchmark notices |
| Three-year total | about 9 to 12 | about 13 to 19 | about 18 to 32 |

Why C loses even though it looks free today. The benchmark runs only on Christopher's Mac, because the audio
cannot leave it. So agreement between two implementations is checked rarely and late. The synthetic fixtures in
the cloud catch numeric drift, but not "the picks changed". Track L already proposes a picks-level test (top-8
lists overlap at least 6 of 8). With two implementations that test would have to pass after every change on both
sides.

Why A beats B for this team. B's seam lies across the primary product. Every Mac and iPad build compiles Rust for
four Apple targets (device, simulator, two Mac architectures). A crash in the DSP shows in Xcode as a frame inside
a foreign library. Every change to a shared type, such as a new crate field, touches both languages. B's benefits
(Rust's Windows maturity, `cargo-deny`, a GUI through Tauri, a Rust desktop-app framework, and Kotlin bindings for
Android) arrive only when Desk Lite or Android ships. P17 places both after the trials. A also defers nothing
irreversible: the package boundary is the same one B would have. Only the language inside differs.

What would flip it to B: the spike fails (section 6, question 1); Android moves from "on demand" to planned;
Desk Lite needs a GUI rather than the command line plus the iPad as its face; or Swift's Windows release cadence
slips (watch the 6.5 and 7.0 Windows toolchains).

## 6. Whether Swift everywhere is realistic now

Yes for a command-line crate-builder, with eyes open [inf from the sources below]:

- **Supported.** Swift 6.4.1 installs on Windows 10 and 11 (x86_64, arm64) and on Linux. Swift Testing lists
  Linux and Windows as supported with automated testing. Swift 6 unified Foundation on one Swift implementation
  across platforms. Swift 6.4 (Sept 2026) made Swift Build the default build system on Linux, macOS and Windows. A
  Windows workgroup has run since Jan 2026, and Swift 6.3 shipped the first official Swift SDK for Android.
- **Rough edges.** The Windows workgroup's own goals include making Foundation and Dispatch fit Windows
  conventions and establishing "best practices for shipping Swift libraries with Windows apps". So those are not
  settled. The static Windows SDK (2025) lacked Foundation because of an ICU clash (ICU is the Unicode library
  Foundation uses). So a Windows build ships runtime DLLs, about 20 MB by an older forum count. Microsoft's
  ONNX Runtime Swift package does not build off Apple, so we wrap the C API ourselves (a few hundred lines). Media
  Foundation from Swift goes through the WinSDK module or a small C shim. Tooling on Windows centres on VS Code.
- **Speed.** Without Accelerate, the FFT and filters run on PocketFFT and Swift's compiler. The Beat This! model
  dominates the time (track L: 4.6 s of a 4:32 track in the Rust port), and that runs in ONNX Runtime whichever
  language calls it. So the language barely moves the total [inf].
- **The cloud session.** Swift on Linux is the most mature off-Apple target (server-side Swift has run there for
  years). The PC and Linux session can work as chartered, only in Swift.

Recommended changes to the charter if Christopher accepts: `core/` becomes a Swift package (working name
`DeckieKit`) with targets `DeckieDSP` (pure, Foundation-free maths), `DeckieCrate`, `DeckieEngineOSS` (Windows and
Linux only; C dependencies as vendored targets) and an executable `deckie-desk-lite`. The Apple `DeckieAnalysis`
and `DeckieCore` packages depend on `DeckieDSP` and `DeckieCrate` directly. P16 is restated as "our own DSP written
once, in Swift, portable". Charter step 6 (the C ABI) disappears.

## 7. Open questions

1. **The spike.** Do the grid fit, Camelot and `score.py` in a plain Swift package match `pairs.json` on Linux and
   on a GitHub Actions Windows runner within two weeks? Pass: identical scores to 1e-6, and both CIs green across
   one Swift point release.
2. **Packaging on Windows.** How large is a signed Desk Lite folder with the Swift runtime, ICU and ONNX Runtime,
   and does an installer (MSI, via the toolchain's merge module) behave on a clean Windows 11 PC?
3. **Speed off Apple.** PocketFFT plus Swift for the spectral front end on a mid-range Windows laptop, against the
   Rust port's numbers, on ten tracks.
4. **Desk Lite's face.** A command line plus the iPad, or a GUI? A GUI on Windows in Swift is hard (WinUI bindings
   are early); in Rust, Tauri is easy. This could move the answer to B.
5. **Key off Apple.** Mixed In Key licensed zplane's detector. Is a commercial key-detector licence cheaper than
   closing the 75-versus-83 gap ourselves (track L, question 4)?
6. **MPL 2.0.** Is it on the allowlist? It decides Symphonia and Eigen.
7. **Agent quality, measured.** Run the same port task (one block, e.g. A22 mix windows) in Swift and Rust with
   both agents and count review rounds to parity. The public benchmark is too small to settle it.
8. **Android.** If it becomes real, does `swift-java` give the scorer to a Kotlin app as easily as UniFFI would?

## 8. Sources

Swift: Windows install https://www.swift.org/install/windows/ ; Windows workgroup (Jan 26, 2026)
https://www.swift.org/blog/announcing-windows-workgroup/ ; Android SDK
https://www.swift.org/blog/nightly-swift-sdk-for-android/ and WWDC26 "What's new in Swift"
https://developer.apple.com/videos/play/wwdc2026/262/ ; Swift 6.4 coverage
https://www.infoq.com/news/2026/09/swift-6-4-released/ ; Windows static SDK and Foundation
https://forums.swift.org/t/upcoming-changes-to-windows-swift-sdks/81313 ; Windows DLL sizes
https://forums.swift.org/t/swift-required-dlls-on-windows-10/49000 ; C++ interop status
https://swift.org/documentation/cxx-interop/status/ ; Swift Testing https://github.com/swiftlang/swift-testing ;
ONNX Runtime Swift package https://swiftpackageregistry.com/microsoft/onnxruntime-swift-package-manager and its
Linux build log https://swiftpackageindex.com/builds/84008C8D-E78B-401E-90F8-C52EFE499EB1 ; Package.resolved
pinning https://github.com/apple/swift-evolution/blob/master/proposals/0145-package-manager-version-pinning.md ;
SwiftPM licence-scanning gaps https://docs.fossa.com/docs/project-setup/supported-languages/ios/swift and
https://gitlab.com/groups/gitlab-org/-/epics/15540 ; Swift and WinRT https://speakinginswift.substack.com/p/swift-meet-winrt ;
Interop on Windows https://swift.org/blog/swift-everywhere-windows-interop/ .

Rust: platform tiers https://doc.rust-lang.org/rustc/platform-support.html ; `ort` https://ort.pyke.io/ ; `rten`
https://github.com/robertknight/rten ; `beat-this-rs` https://github.com/danigb/beat-this-rs ; RustFFT
https://docs.rs/crate/rustfft/latest ; Symphonia https://github.com/pdeljanov/Symphonia ; UniFFI
https://mozilla.github.io/uniffi-rs/next/swift/xcode.html ; `cargo-deny` https://github.com/EmbarkStudios/cargo-deny ;
RustSec and `cargo-audit` https://rustsec.org/ ; the arrayref attack
https://blog.rust-lang.org/2026/08/20/supply-chain-attack-on-arrayref/ ; libsignal
https://github.com/signalapp/libsignal .

Other candidates: Kotlin/Native tiers https://kotlinlang.org/docs/native-target-support.html ; Swift Export status
https://hiflylabs.com/blog/2026/7/9/kmp-kotlinconf-2026-native-where-it-matters-shared-where-it-counts ; Zig 0.16
https://byteiota.com/zig-0-16-0-juicy-main-i-o-interfaces-what-breaks/ ; vcpkg versioning
https://learn.microsoft.com/en-us/vcpkg/users/versioning ; FFT licences: PocketFFT
https://github.com/mreineck/pocketfft , KissFFT https://github.com/mborgerding/kissfft , PFFFT
https://github.com/marton78/pffft .

Agents and community: Incept5 languages benchmark https://github.com/Incept5-AI/languages-benchmark ; Stack
Overflow 2025 survey https://survey.stackoverflow.co/2025/technology/ .

Prior art: Mixxx https://github.com/mixxxdj/mixxx and 2.5 notes https://mixxx.org/news/2024-12-24-mixxx-2_5-released ;
Serato C++ roles https://serato-limited.breezy.hr/p/91c4bbd49c58-senior-software-engineer-c and
https://www.ziprecruiter.nz/jobs/569659361-junior-c-audio-software-engineer-at-serato ; VirtualDJ SDK
https://virtualdj.com/wiki/Plugins_SDKv8.html ; rekordbox JUCE claim (user post)
https://forums.pioneerdj.com/hc/en-us/community/posts/21178104152601-Rekordbox-update-for-Apple-s-M2-Max-chip-be-available ;
DJ.Studio https://desktopinsights.com/apps/dj-studio ; Lexicon https://desktopinsights.com/apps/lexicon and
https://rekord.cloud/blog/lexicon-the-idea--vision ; Mixed In Key https://en.wikipedia.org/wiki/Mixed_In_Key ; Arc
for Windows https://techcrunch.com/2024/04/30/the-browser-company-releases-arc-for-windows and Dia on Windows
https://piunikaweb.com/2026/10/07/dia-browser-windows-launch/ .

In this repo: `docs/architecture/pc-linux-track.md`, `docs/research/l-non-apple.md` (sections 2.3, 3, 5),
`docs/architecture/analysis-port-plan.md` (sections 1, 2, 4, 5), `docs/product/00-decisions.md` (D3, D11, D13,
P16, P17), `docs/research/a-on-device-analysis.md` section 4, `docs/research/j-vocal-tool.md` section 6, and the
lab files `mixer/analyze.py`, `local_tempo.py`, `score.py`, `key_light.py`.
