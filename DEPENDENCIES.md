# Dependencies

What Deckie's PC and Linux track relies on that it did not write itself; last checked Oct 28, 2026. The rule (charter
`docs/architecture/pc-linux-track.md`, decision P16): every dependency is pinned by version and by hash, and its
licence is quoted here before it is adopted. A hash, or digest, is a long fingerprint computed from a file's exact
bytes: change one byte and it changes, so a matching hash proves a file is the one recorded here.

**In short:** one toolchain and two GitHub Actions helpers, all used only to build and test. Deckie's Swift package
(`core/`) declares no packages from elsewhere, so it has no `Package.resolved` (Swift's list of exact package
versions), and no runtime dependency (code that would travel inside a Deckie program) ships in any product.

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

**On Windows** (the `core-windows` CI workflow) the Swift project's official installer is installed by the action
`compnerd/gha-setup-swift` (section 2), asked for `swift-version: swift-6.4-release`, `swift-build: 6.4.0-RELEASE`.
6.4.0 rather than 6.4.1 because on Oct 28, 2026 swift.org's own link for the 6.4.1 Windows installer answered
404 (not found); the probe moves to 6.4.1 when that file is back. The installer's hash is not recorded yet:
Swift's download site is blocked from this cloud session (status log entry 1).

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
library) travel with it; each will be listed here with its licence quoted before that build is released.

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
