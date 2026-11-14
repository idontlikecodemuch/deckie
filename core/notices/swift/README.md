# The Swift runtime's licences, for a build that carries it

A Windows or Linux program built from `core/` travels with Swift's runtime libraries (DEPENDENCIES.md, sections 1
and 3): the standard library and its companions, Foundation, the dispatch library, and Foundation's copy of ICU, the
Unicode Consortium's text-handling library (version 76.1 in Swift 6.4.1: `U_ICU_VERSION` in swift-foundation-icu's
`uvernum.h` at the release tag). These are their licence texts, unchanged, as the Windows zip carries them.

| File | Bytes | SHA-256 | Source, fetched Nov 13, 2026 |
|---|---|---|---|
| `swift-LICENSE.txt` | 11,751 | `770af8291f708538d8ff885a0bbc4e045cd700531741c4f99528d435c14d7f55` | `swiftlang/swift`, tag `swift-6.4.1-RELEASE`, `LICENSE.txt`; identical to the toolchain's own `usr/share/swift/LICENSE.txt` |
| `swift-foundation-LICENSE.md` | 11,750 | `2245a990b635558be210fb3eb4f8a6f7a49aebc0fefbf5859146a65ddc7ddcf3` | `swiftlang/swift-foundation` and `swiftlang/swift-foundation-icu` (the same bytes in both), same tag, `LICENSE.md` |
| `swift-corelibs-foundation-and-libdispatch-LICENSE.txt` | 11,759 | `0ca84095d1de77cad1a866ebbad28f8db98a0826c6055d92b0608c5baa1643e2` | `swiftlang/swift-corelibs-foundation` and `swiftlang/swift-corelibs-libdispatch` (the same bytes in both), same tag, `LICENSE` |
| `ICU-76.1-LICENSE.txt` | 26,487 | `01edac20612b1e590c1c1cfb02b7218c6adc7b0a944eda7a1e03aeee10725aed` | `unicode-org/icu`, tag `release-76-1`, `LICENSE` |

All fetched from `https://raw.githubusercontent.com/<repository>/<tag>/<file>`.

The first three are Apache 2.0 with the Runtime Library Exception, on the allowlist. ICU's is the **Unicode License
V3**, a short permissive licence in the family of MIT (keep the copyright and permission notice; no other
condition), followed by the notices of the pieces ICU carries (BSD, MIT and similar). It is **not on the allowlist
word for word**; it was named in the acknowledgements table from the start ("Swift runtime and Foundation (with
ICU)") with its listing put off until the first PC build. That build now exists as a workflow artifact, so this is
the moment for the main session to say yes or no (DEPENDENCIES.md, section 3).

swift-foundation-icu has no ICU licence file of its own at the tag (only the Apache file above), so ICU's text is
taken from the ICU project's release of the same version.
