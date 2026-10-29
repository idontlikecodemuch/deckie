#!/usr/bin/env python3
"""Write tone_damaged.mp3, the MP3 the DeckieDecode tests decode to check the damaged-frame concealment: tone.mp3
(core/Tools/make_audio_fixtures.py) with the Huffman-coded main data of one frame overwritten, so that the decoder
reads past the end of the granule, as on a damaged or badly spliced file. Nothing else changes: every frame header
and all side information stay as they were, the file keeps its length, and every other frame decodes as before.

  python3 core/Tools/make_damaged_mp3_fixture.py      # from anywhere; needs only Python 3

Where a frame's main data is. A layer III frame (MPEG-1, stereo here) is a 4-byte header, 32 bytes of side
information, then main data. The side information gives main_data_begin (9 bits: how many bytes before this frame's
own main data starts, in the main data of the frames before it, the "bit reservoir") and, for each of the two
granules and two channels, part_2_3_length (12 bits: the granule's scale factors and Huffman codes, in bits). The
main data of all frames, read one after another with headers and side information left out, is one stream: frame
k's starts main_data_begin bytes before the place in that stream where frame k's own main data begins, and its
granules follow one another, part_2_3_length bits each, granule 0 channel 0 first. Its scale factors come first
(long blocks: slen1 bits for each of bands 0 to 10, slen2 for bands 11 to 20, slen1 and slen2 from
scalefac_compress, ISO 11172-3 2.4.2.7; in granule 1 a group of bands whose scfsi bit is set is not sent); the
Huffman codes follow, the "big values" pairs first.

The damage: the bytes lying wholly inside the Huffman codes of granule GRANULE, channel CHANNEL of frame FRAME are
all set to PATTERN, so that the big values read past the granule's end into the next granule's bits. That is what
the concealment must find: dr_mp3 decodes those bits as big values and makes a burst; mpg123 says "dequantization
failed!" and plays the granule as zeros. Which damage does that depends on the granule: tone.mp3 spends most of its
bits on small values (a granule of frame 40 has 20 big-value pairs in 618 bits of codes), so 0xFF, 0x00, 0x55, 0xAA
and noise over granule 0, channel 0 of frame 40 all decoded within the granule (a dull frame, no burst, nothing to
find). Every byte value was then tried over each long-block granule with at least 40 big-value pairs in frames 4 to 17
and 50 to 110, with the check in core/Sources/CDrMp3/dr_mp3.c: many overran, and 0x33 over granule 1, channel 0 of
frame 60 (61 pairs in 569 bits) made the largest burst, a peak of 2.73 where the tone peaks at 0.49 (the left
channel's -6 dBFS sine), in that frame and 2.20 in the next, whose first half carries the damaged granule's overlap.

The frame is FRAME = 60 of the audio frames (the Info tag frame not counted): decoded, it starts 60 x 1152 = 69,120
samples into the stream, which after the gapless trim (576 + 529 samples, as MP3Reader trims) is 68,015 samples,
1.542290 s, into the track; it lasts 1152 samples, 26.122 ms. Its main data lies in the frame before it (main_data_begin
274). The script prints where the main data and the damage are, and the output's SHA-256.
"""
import hashlib, os

FIXTURES = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Tests", "DeckieDecodeTests",
                        "Fixtures")
SOURCE, OUTPUT = "tone.mp3", "tone_damaged.mp3"
FRAME, GRANULE, CHANNEL = 60, 1, 0  # audio frames counted from 0, the Info tag frame not counted
PATTERN = 0x33

KBPS = [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320]  # MPEG-1 layer III
RATES = [44100, 48000, 32000]
SLEN = [(0, 0), (0, 1), (0, 2), (0, 3), (3, 0), (1, 1), (1, 2), (1, 3), (2, 1), (2, 2), (2, 3), (3, 1), (3, 2),
        (3, 3), (4, 2), (4, 3)]


class Bits:
    """Reads bits most significant first, as MPEG audio stores them."""

    def __init__(self, data):
        self.data, self.pos = data, 0

    def get(self, n):
        v = 0
        for _ in range(n):
            v = v << 1 | (self.data[self.pos >> 3] >> (7 - (self.pos & 7))) & 1
            self.pos += 1
        return v


def frames(b):
    """Each frame of an MPEG-1 layer III stream after its ID3v2 tag: (offset, length, side information offset,
    main data offset, side information as a dict)."""
    o = 0
    if b[:3] == b"ID3":
        o = 10 + (b[6] << 21 | b[7] << 14 | b[8] << 7 | b[9])
    out = []
    while o + 4 <= len(b):
        h = b[o:o + 4]
        assert h[0] == 0xFF and h[1] & 0xFE == 0xFA, f"not an MPEG-1 layer III header at byte {o}"
        length = 144000 * KBPS[h[2] >> 4] // RATES[(h[2] >> 2) & 3] + ((h[2] >> 1) & 1)
        mono = h[3] >> 6 == 3
        side = o + 4 + (0 if h[1] & 1 else 2)  # a CRC follows the header when the protection bit is 0
        bits = Bits(b[side:side + 32])
        info = {"main_data_begin": bits.get(9)}
        bits.get(5 if mono else 3)  # private bits
        info["scfsi"] = [bits.get(4) for _ in range(1 if mono else 2)]
        granules = []
        for _ in range(2):
            channels = []
            for _ in range(1 if mono else 2):
                g = {"part_2_3_length": bits.get(12), "big_values": bits.get(9), "global_gain": bits.get(8),
                     "scalefac_compress": bits.get(4), "window_switching": bits.get(1)}
                if g["window_switching"]:
                    g["block_type"], g["mixed_block"] = bits.get(2), bits.get(1)
                    bits.get(10 + 9)  # two table selects, three subblock gains
                else:
                    g["block_type"], g["mixed_block"] = 0, 0
                    bits.get(15 + 4 + 3)  # three table selects, two region counts
                bits.get(3)  # preflag, scalefac_scale, count1table_select
                channels.append(g)
            granules.append(channels)
        info["granules"] = granules
        out.append((o, length, side, side + (17 if mono else 32), info))
        o += length
    return out


def main():
    with open(os.path.join(FIXTURES, SOURCE), "rb") as f:
        b = bytearray(f.read())
    fs = frames(b)
    # The main data stream: file offsets of its bytes, in order.
    stream, starts = [], []
    for (o, length, side, main, info) in fs:
        starts.append(len(stream))
        stream.extend(range(main, o + length))
    k = FRAME + 1  # the Info tag frame is frame 0 of the file
    o, length, side, main, info = fs[k]
    # The granule's first bit in the stream: the frame's main data start, then the granules before it in order.
    begin = (starts[k] - info["main_data_begin"]) * 8
    order = [(gr, ch) for gr in range(2) for ch in range(len(info["granules"][gr]))]
    for gr, ch in order[:order.index((GRANULE, CHANNEL))]:
        begin += info["granules"][gr][ch]["part_2_3_length"]
    g = info["granules"][GRANULE][CHANNEL]
    assert g["block_type"] == 0, "the damaged granule is expected to use long blocks"
    slen1, slen2 = SLEN[g["scalefac_compress"]]
    # Long blocks: bands 0-5 and 6-10 take slen1 bits each, 11-15 and 16-20 slen2; in granule 1 a group whose scfsi
    # bit is set reuses granule 0's scale factors and is not sent.
    groups = [6 * slen1, 5 * slen1, 5 * slen2, 5 * slen2]
    scfsi = info["scfsi"][CHANNEL] if GRANULE == 1 else 0
    scale_bits = sum(n for i, n in enumerate(groups) if not scfsi & (8 >> i))
    huffman = (begin + scale_bits, begin + g["part_2_3_length"])
    first, last = (huffman[0] + 7) // 8, huffman[1] // 8  # whole bytes only
    for i in range(first, last):
        b[stream[i]] = PATTERN
    with open(os.path.join(FIXTURES, OUTPUT), "wb") as f:
        f.write(b)
    print(f"{SOURCE}: {len(fs)} frames; frame {FRAME} (file frame {k}) at byte {o}, main_data_begin "
          f"{info['main_data_begin']}, granule {GRANULE} channel {CHANNEL}: part_2_3_length {g['part_2_3_length']}, "
          f"big_values {g['big_values']}, scale factors {scale_bits} bits")
    print(f"damaged: main data bytes {first - starts[k] + info['main_data_begin']} to "
          f"{last - starts[k] + info['main_data_begin']} of the frame's (file bytes {stream[first]} to "
          f"{stream[last - 1]}), {last - first} bytes set to 0x{PATTERN:02X}")
    print(f"{hashlib.sha256(bytes(b)).hexdigest()}  {OUTPUT}  {len(b)} bytes")


if __name__ == "__main__":
    main()
