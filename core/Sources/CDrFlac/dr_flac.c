// dr_flac's implementation, compiled once, for DeckieDecode's FLAC backend (Sources/DeckieDecode/FLACReader.swift).
// include/dr_flac.h is the vendored file, unmodified; its version, SHA-256 and licence are in DEPENDENCIES.md.
//
// DR_FLAC_NO_STDIO: DeckieDecode hands dr_flac the file's bytes in memory, so the functions that open files (and the
// stdio and wchar headers they need) are left out. Plain C with no platform condition: Windows builds it too.
// No other option: Ogg-FLAC stays on (dr_flac's default), and so do the frame checksums, which FLACReader relies on
// to notice a damaged frame.
#define DR_FLAC_IMPLEMENTATION
#define DR_FLAC_NO_STDIO
#include "dr_flac.h"
