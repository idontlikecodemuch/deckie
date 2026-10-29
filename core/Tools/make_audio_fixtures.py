#!/usr/bin/env python3
"""Write the audio files the DeckieDecode tests decode. The audio is generated here, never downloaded, so it is
Deckie's own and carries no licence question.

  python3 core/Tools/make_audio_fixtures.py      # from anywhere; needs numpy and ffmpeg built with libmp3lame

The signal: 4 s of stereo. Left, a 440 Hz sine at -6 dBFS (peak); right, a 1000 Hz sine at -12 dBFS; on both
channels one full-scale single-sample click at exactly 2.000 s (where both sines are zero).

Outputs, in core/Tests/DeckieDecodeTests/Fixtures/:
  tone.wav       the signal at 44.1 kHz as 16-bit PCM, written with Python's wave module (the reference)
  tone48k.wav    the same signal computed at 48 kHz (click at sample 96000), 16-bit PCM
  tone.mp3       tone.wav through ffmpeg with libmp3lame, 192 kbps, 44.1 kHz (the LAME tag records delay and padding)
  tone48k.mp3    tone48k.wav the same way at 48 kHz, 192 kbps
  tone_mono.mp3  the signal's channel mean (440 Hz at -12 dBFS, 1000 Hz at -18 dBFS, the click at full scale), at
                 44.1 kHz as 16-bit PCM in a temporary file, then through libmp3lame as mono, 128 kbps
  tone.m4a       tone.wav through ffmpeg's native AAC encoder, 160 kbps, 44.1 kHz (the MP4 edit list records priming)
  tone.aiff      tone.wav through ffmpeg as AIFF, 16-bit big-endian PCM (the same samples, byte-swapped)
  tone_sowt.aifc tone.wav through ffmpeg as AIFF-C with compression type 'sowt', 16-bit little-endian PCM, the way
                 macOS writes AIFF-C
  tone.flac      tone.wav through ffmpeg's FLAC encoder, 16-bit (lossless: the same samples as tone.wav)
  tone24.flac    the signal at 44.1 kHz as 24-bit PCM (full scale 8388607) in a temporary file, then through ffmpeg's
                 FLAC encoder as 24-bit (ffmpeg takes 24-bit input as 32-bit samples, -sample_fmt s32, and writes
                 them back as 24 bits)
  tone.oga       tone.wav through ffmpeg's FLAC encoder into an Ogg container (Ogg-FLAC), 16-bit
  protected.m4p  no audio: a few hundred bytes written here, shaped like an iTunes Store or Apple Music file locked
                 by FairPlay (major brand "M4P ", an audio sample entry "drms" holding a "sinf" box, an empty mdat),
                 for the "protected, cannot be read" report; nothing in it is a real key or a real account

The ffmpeg command-line program is a development tool here and nothing else: no Deckie code links ffmpeg
(DEPENDENCIES.md, "Checked and rejected"). The same ffmpeg build gives the same bytes on every run: version strings
and metadata are left out (bitexact; ffmpeg's AIFF writer adds no ID3 chunk unless asked). ffmpeg's FLAC writers
always add a Vorbis comment block, which holds the writer's name; bitexact makes it the constant "ffmpeg", with no
version and no comments, and the native FLAC files leave out the 8 KB padding block ffmpeg otherwise adds. The FLAC
files use compression level 12, ffmpeg's highest (tone24.flac is 254 KB at that level, 435 KB at the default, 5).
FFMPEG=/path/to/ffmpeg picks another ffmpeg; the default is /usr/bin/ffmpeg.
"""
import hashlib, os, struct, subprocess, tempfile, wave
import numpy as np

SECONDS = 4
CLICK_S = 2.0
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Tests", "DeckieDecodeTests", "Fixtures")
FFMPEG = os.environ.get("FFMPEG", "/usr/bin/ffmpeg")

FLAC = ["-c:a", "flac", "-compression_level", "12"]
NO_PADDING = ["-metadata_header_padding", "0"]  # a format option: native FLAC only, the Ogg writer adds none

# name, source (a fixture name, or "mono" or "24bit" for the temporary files), ffmpeg output arguments
ENCODES = [
    ("tone.mp3", "tone.wav", ["-c:a", "libmp3lame", "-b:a", "192k", "-ar", "44100"]),
    ("tone48k.mp3", "tone48k.wav", ["-c:a", "libmp3lame", "-b:a", "192k", "-ar", "48000"]),
    ("tone_mono.mp3", "mono", ["-c:a", "libmp3lame", "-b:a", "128k", "-ar", "44100", "-ac", "1"]),
    ("tone.m4a", "tone.wav", ["-c:a", "aac", "-b:a", "160k", "-ar", "44100"]),
    ("tone.aiff", "tone.wav", ["-c:a", "pcm_s16be", "-f", "aiff"]),
    ("tone_sowt.aifc", "tone.wav", ["-c:a", "pcm_s16le", "-f", "aiff"]),  # little-endian PCM makes ffmpeg write 'sowt'
    ("tone.flac", "tone.wav", FLAC + NO_PADDING),
    ("tone24.flac", "24bit", ["-sample_fmt", "s32"] + FLAC + NO_PADDING),
    ("tone.oga", "tone.wav", FLAC + ["-f", "ogg"]),
]


def signal(rate):
    """The test signal at `rate` as float64, shape (frames, 2), full scale 1.0."""
    t = np.arange(rate * SECONDS) / rate
    left = 10 ** (-6 / 20) * np.sin(2 * np.pi * 440 * t)
    right = 10 ** (-12 / 20) * np.sin(2 * np.pi * 1000 * t)
    y = np.stack([left, right], axis=1)
    y[int(round(CLICK_S * rate)), :] = 1.0
    return y


def write_wav(path, y, rate, bits=16):
    """16-bit (full scale 32767) or 24-bit (8388607) little-endian PCM."""
    top = (1 << (bits - 1)) - 1
    pcm = np.clip(np.round(y * top), -top - 1, top).astype("<i4")
    data = pcm.astype("<i2").tobytes() if bits == 16 else pcm.view(np.uint8).reshape(-1, 4)[:, :3].tobytes()
    with wave.open(path, "wb") as w:
        w.setnchannels(y.shape[1])
        w.setsampwidth(bits // 8)
        w.setframerate(rate)
        w.writeframes(data)


def encode(src, name, args):
    subprocess.run([FFMPEG, "-nostdin", "-hide_banner", "-loglevel", "error", "-y", "-i", src,
                    "-map_metadata", "-1", "-fflags", "+bitexact", "-flags:a", "+bitexact", *args,
                    os.path.join(OUT, name)], check=True)


def box(kind, *parts):
    """An MP4 box: 32-bit size, four-letter type, body."""
    body = b"".join(parts)
    return struct.pack(">I", 8 + len(body)) + kind + body


def full_box(kind, *parts, version=0, flags=0):
    """A box whose body starts with a version byte and 24 bits of flags."""
    return box(kind, struct.pack(">I", version << 24 | flags), *parts)


def protected_mp4():
    """The smallest file shaped like a FairPlay-protected iTunes purchase: ftyp, then moov down to one audio sample
    entry "drms" (an "mp4a" entry renamed, as FairPlay does) with its "sinf" box (original format "mp4a", scheme
    "itun", the scheme's boxes zeroed), then an empty mdat. No samples, no keys."""
    unity = struct.pack(">9I", 0x10000, 0, 0, 0, 0x10000, 0, 0, 0, 0x40000000)  # the identity matrix
    esds = full_box(b"esds", bytes([
        0x03, 25, 0, 1, 0,  # ES descriptor: id 1, no flags
        0x04, 17, 0x40, 0x15, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  # MPEG-4 audio; buffer size, peak and mean bit rate 0
        0x05, 2, 0x12, 0x10,  # AAC LC, 44.1 kHz, stereo
        0x06, 1, 2]))  # SL config: predefined 2
    sinf = box(b"sinf", box(b"frma", b"mp4a"), full_box(b"schm", b"itun", struct.pack(">I", 0)),
               box(b"schi", box(b"user", bytes(4)), box(b"key ", bytes(4)), box(b"iviv", bytes(16))))
    drms = box(b"drms", bytes(6), struct.pack(">HQHHHHI", 1, 0, 2, 16, 0, 0, 44100 << 16), esds, sinf)
    stbl = box(b"stbl", full_box(b"stsd", struct.pack(">I", 1), drms), full_box(b"stts", bytes(4)),
               full_box(b"stsc", bytes(4)), full_box(b"stsz", bytes(8)), full_box(b"stco", bytes(4)))
    minf = box(b"minf", full_box(b"smhd", bytes(4)),
               box(b"dinf", full_box(b"dref", struct.pack(">I", 1), full_box(b"url ", flags=1))), stbl)
    mdia = box(b"mdia", full_box(b"mdhd", struct.pack(">IIIIHH", 0, 0, 44100, 0, 0x55C4, 0)),  # language "und"
               full_box(b"hdlr", bytes(4), b"soun", bytes(12), b"\0"), minf)
    trak = box(b"trak", full_box(b"tkhd", struct.pack(">IIIIIQHHHH", 0, 0, 1, 0, 0, 0, 0, 0, 0x100, 0), unity,
                                 bytes(8), flags=7), mdia)
    moov = box(b"moov", full_box(b"mvhd", struct.pack(">IIIIIH", 0, 0, 44100, 0, 0x10000, 0x100), bytes(10), unity,
                                 bytes(24), struct.pack(">I", 2)), trak)
    return box(b"ftyp", b"M4P ", struct.pack(">I", 0), b"M4P ", b"mp42", b"isom") + moov + box(b"mdat")


def main():
    os.makedirs(OUT, exist_ok=True)
    write_wav(os.path.join(OUT, "tone.wav"), signal(44100), 44100)
    write_wav(os.path.join(OUT, "tone48k.wav"), signal(48000), 48000)
    with tempfile.TemporaryDirectory() as tmp:
        temporary = {"mono": os.path.join(tmp, "tone_mono.wav"), "24bit": os.path.join(tmp, "tone24.wav")}
        write_wav(temporary["mono"], signal(44100).mean(axis=1, keepdims=True), 44100)
        write_wav(temporary["24bit"], signal(44100), 44100, bits=24)
        for name, source, args in ENCODES:
            encode(temporary.get(source, os.path.join(OUT, source)), name, args)
    with open(os.path.join(OUT, "protected.m4p"), "wb") as f:
        f.write(protected_mp4())
    version = subprocess.run([FFMPEG, "-version"], capture_output=True, text=True, check=True).stdout.splitlines()[0]
    print(version)
    total = 0
    for name in ["tone.wav", "tone48k.wav"] + [e[0] for e in ENCODES] + ["protected.m4p"]:
        p = os.path.join(OUT, name)
        size = os.path.getsize(p)
        total += size
        with open(p, "rb") as f:
            print(f"{hashlib.sha256(f.read()).hexdigest()}  {name}  {size} bytes")
    print(f"total {total} bytes")


if __name__ == "__main__":
    main()
