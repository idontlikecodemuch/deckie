// dr_mp3's implementation, compiled once, for DeckieDecode's MP3 backend (Sources/DeckieDecode/MP3Reader.swift).
// include/dr_mp3.h is the vendored file, unmodified; its version, SHA-256 and licence are in DEPENDENCIES.md.
//
// DR_MP3_NO_STDIO: DeckieDecode hands dr_mp3 the file's bytes in memory, so the functions that open files (and the
// stdio and wchar headers they need) are left out. Plain C with no platform condition: Windows builds it too.
// DR_MP3_FLOAT_OUTPUT: decode straight to 32-bit float. Without it dr_mp3 rounds every sample to 16 bits first and
// converts back to float afterwards; measured on tone.mp3 against the lab's decoder (libsndfile through mpg123,
// which decodes to float), that rounding put samples up to 2.0e-5 off (RMS 8.8e-6), against 1.3e-6 (RMS 7.9e-8)
// with float output. The option comes from minimp3, which dr_mp3 is built on.
#define DR_MP3_IMPLEMENTATION
#define DR_MP3_NO_STDIO
#define DR_MP3_FLOAT_OUTPUT
#include "dr_mp3.h"
