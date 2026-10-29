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

// ------------------------------------------------------------------------------------------------------------------
// Deckie's damaged-frame check (include/deckie_mp3.h), here because it calls dr_mp3's internal functions, which are
// static to this file; dr_mp3.h itself is not touched.
//
// What dr_mp3 does with a damaged granule. A layer III granule's main data is part_2_3_length bits (scale factors,
// then Huffman codes), read from the frame's side information. drmp3_L3_decode (dr_mp3.h line 1841) computes the
// granule's end, layer3gr_limit = s->bs.pos + part_23_length, and passes it to drmp3_L3_huffman (line 1339). Its big
// values loop (lines 1375 to 1447) never looks at the limit: it decodes all big_values pairs whatever bits follow.
// Only the count1 loop checks it (line 1458: a quad whose code runs past the limit is dropped, which is also how a
// correct granule ends), and then line 1473 sets bs->pos = layer3gr_limit whatever was read. So when damaged codes
// decode as large values and run on past the granule's end, dr_mp3 neither notices nor zeroes anything: it outputs
// them, and the next granule's bits after them decoded as more big values, escapes and all, which is how a damaged
// frame becomes a loud burst. mpg123 (the lab's decoder) catches exactly the overrun: after its big values and count1
// loops, more bits read than part_2_3_length is an error ("Can't rewind stream", layer3.c lines 1014 to 1020 in
// mpg123 1.32.10), the frame's decoding stops there and libmpg123 fills the rest of the frame with zeros ("broken
// frame", libmpg123.c lines 913 to 952). Its count1 loop never reads past the end (it stops on the limit), so only
// the big values (or scale factors longer than the whole granule) can trigger it. ffmpeg stops its big values loop at
// the granule's end instead, silently, and keeps what it decoded up to there: the damaged codes' burst, less the part
// past the end.
//
// The check finds the same thing in dr_mp3 with dr_mp3's own code, without changing it: after dr_mp3 has decoded a
// frame, the frame's main data is rebuilt from the bit reservoir as it was before the frame, and each granule's
// Huffman codes are decoded twice by drmp3_L3_huffman, once from the real bits and once from a copy in which every
// bit from the granule's end on is inverted. The decoder reads a bit only if it uses it (a code's bits pick the
// value pair, an escape's bits its size, a sign bit is read only for a value that is not zero), so the big values
// come out the same both times exactly when none of them read a bit past the granule's end. That is mpg123's test,
// big values only: the count1 values are left out of the comparison, so a last quad whose sign bits run past the
// end (which ffmpeg says some encoders write, and which mpg123 accepts) does not flag a frame.

#ifndef DR_MP3_FLOAT_OUTPUT
#error "deckie_mp3_decode_frame writes float samples"
#endif

#include <stdlib.h>
#include "deckie_mp3.h"

// The largest main data dr_mp3 assembles for one frame (drmp3dec_scratch.maindata).
#define DECKIE_MAIN_DATA_BYTES (DRMP3_MAX_BITRESERVOIR_BYTES + DRMP3_MAX_L3_FRAME_PAYLOAD_BYTES)
// Room after the main data for a Huffman decoder that runs on into whatever follows: from where a granule starts it
// reads at most 288 pairs of at most 19 code bits, 2 x 13 escape bits and 2 sign bits, then at most 144 quads of at
// most 10 bits, under 1,900 bytes, plus the 4 bytes it reads ahead.
#define DECKIE_READ_AHEAD_BYTES 4096

struct deckie_mp3_check
{
    drmp3dec before;            // the decoder's state before the frame: only the part before `scratch` is copied
    drmp3dec_scratch frame;     // the frame's side information, main data and scale factors, rebuilt for the check
    drmp3_uint8 data[DECKIE_MAIN_DATA_BYTES + DECKIE_READ_AHEAD_BYTES];     // the main data as read, then zeros
    drmp3_uint8 flipped[DECKIE_MAIN_DATA_BYTES + DECKIE_READ_AHEAD_BYTES];  // the same, inverted from flipped_from on
    int flipped_from;
    float values[2][576 + 32];  // one granule of one channel decoded both ways (576 values, and room to spare)
};

deckie_mp3_check *deckie_mp3_check_new(void)
{
    return (deckie_mp3_check *)calloc(1, sizeof(deckie_mp3_check));
}

void deckie_mp3_check_free(deckie_mp3_check *check)
{
    free(check);
}

// Whether drmp3dec_decode_frame will take mp3 as the next frame of the stream it decoded last, rather than clear the
// decoder and search for a frame: the test at its start (dr_mp3.h lines 2326 to 2333), copied.
static int deckie_mp3_continues(const drmp3dec *dec, const drmp3_uint8 *mp3, int mp3_bytes)
{
    int frame_size = 0;
    if (mp3_bytes > 4 && dec->header[0] == 0xff && drmp3_hdr_compare(dec->header, mp3))
    {
        frame_size = drmp3_hdr_frame_bytes(mp3, dec->free_format_bytes) + drmp3_hdr_padding(mp3);
        if (frame_size != mp3_bytes && (frame_size + DRMP3_HDR_SIZE > mp3_bytes || !drmp3_hdr_compare(mp3, mp3 + frame_size)))
        {
            frame_size = 0;
        }
    }
    return frame_size != 0;
}

// Makes `flipped` equal to `data` before bit `bit` (counted from the first byte's most significant bit, as dr_mp3
// reads them) and inverted from it on. Within a frame the granules' ends only move forward.
static void deckie_mp3_flip_from(deckie_mp3_check *c, int bit)
{
    int i;
    for (i = c->flipped_from >> 3; i < (bit >> 3); i++)
    {
        c->flipped[i] = c->data[i];
    }
    c->flipped[bit >> 3] = (drmp3_uint8)(c->data[bit >> 3] ^ (0xFF >> (bit & 7)));
    c->flipped_from = bit;
}

int deckie_mp3_decode_frame(deckie_mp3_check *c, drmp3dec *dec, const drmp3_uint8 *mp3, int mp3_bytes,
                            float *pcm, drmp3dec_frame_info *info, int conceal, int *damaged)
{
    int samples, continues, frame_size, main_data_begin, bytes, granules, channels, igr, ch, i;
    const drmp3_uint8 *frame;
    drmp3_bs side, bs;

    *damaged = 0;
    continues = deckie_mp3_continues(dec, mp3, mp3_bytes);
    DRMP3_COPY_MEMORY(&c->before, dec, offsetof(drmp3dec, scratch));
    samples = drmp3dec_decode_frame(dec, mp3, mp3_bytes, pcm, info);
    if (samples == 0 || info->layer != 3)
    {
        return samples;
    }
    if (!continues)
    {
        // drmp3dec_decode_frame cleared the decoder before it searched for this frame.
        DRMP3_ZERO_MEMORY(&c->before, offsetof(drmp3dec, scratch));
    }

    // The frame it decoded ends info->frame_bytes into mp3; its header is now the decoder's.
    frame_size = drmp3_hdr_frame_bytes(dec->header, dec->free_format_bytes) + drmp3_hdr_padding(dec->header);
    frame = mp3 + info->frame_bytes - frame_size;
    granules = DRMP3_HDR_TEST_MPEG1(frame) ? 2 : 1;
    channels = DRMP3_HDR_IS_MONO(frame) ? 1 : 2;

    // Its side information and main data, as drmp3dec_decode_frame read them, from the reservoir as it was before.
    drmp3_bs_init(&side, frame + DRMP3_HDR_SIZE, frame_size - DRMP3_HDR_SIZE);
    if (DRMP3_HDR_IS_CRC(frame))
    {
        drmp3_bs_get_bits(&side, 16);
    }
    main_data_begin = drmp3_L3_read_side_info(&side, c->frame.gr_info, frame);
    if (main_data_begin < 0 || side.pos > side.limit ||
        !drmp3_L3_restore_reservoir(&c->before, &side, &c->frame, main_data_begin))
    {
        return samples;  // not reached: dr_mp3 decoded this frame, so all of this held for it too
    }
    bytes = c->frame.bs.limit/8;
    DRMP3_COPY_MEMORY(c->data, c->frame.maindata, bytes);
    DRMP3_ZERO_MEMORY(c->data + bytes, DECKIE_READ_AHEAD_BYTES);
    for (i = 0; i < bytes + DECKIE_READ_AHEAD_BYTES; i++)
    {
        c->flipped[i] = (drmp3_uint8)~c->data[i];
    }
    c->flipped_from = 0;

    // Each granule of each channel in turn, in drmp3_L3_decode's order.
    bs = c->frame.bs;
    bs.buf = c->data;
    for (igr = 0; igr < granules && !*damaged; igr++)
    {
        for (ch = 0; ch < channels && !*damaged; ch++)
        {
            const drmp3_L3_gr_info *gr = c->frame.gr_info + igr*channels + ch;
            int limit = bs.pos + gr->part_23_length;
            drmp3_bs real, flipped;

            drmp3_L3_decode_scalefactors(frame, c->frame.ist_pos[ch], &bs, gr, c->frame.scf, ch);
            // Scale factors longer than the whole granule: mpg123's test fails before any Huffman code is read.
            if (gr->part_23_length > 0 && bs.pos > limit)
            {
                *damaged = 1;
            }
            deckie_mp3_flip_from(c, limit);
            real = bs;
            flipped = bs;
            flipped.buf = c->flipped;
            DRMP3_ZERO_MEMORY(c->values, sizeof(c->values));
            drmp3_L3_huffman(c->values[0], &real, gr, c->frame.scf, limit);
            drmp3_L3_huffman(c->values[1], &flipped, gr, c->frame.scf, limit);
            if (memcmp(c->values[0], c->values[1], sizeof(float)*2*gr->big_values) != 0)
            {
                *damaged = 1;
            }
            bs.pos = limit;
        }
    }

    if (*damaged && conceal)
    {
        // The frame again from the state before it, every spectral value zero. On zeros dr_mp3's reordering,
        // antialiasing and stereo steps change nothing, so what is left of drmp3_L3_decode is the inverse transform
        // (which outputs the previous granule's overlap through this granule's window and leaves no overlap) and the
        // sign change, then the synthesis filter bank, as drmp3dec_decode_frame runs them.
        for (igr = 0; igr < granules; igr++)
        {
            DRMP3_ZERO_MEMORY(dec->scratch.grbuf[0], 576*2*sizeof(float));
            for (ch = 0; ch < channels; ch++)
            {
                const drmp3_L3_gr_info *gr = c->frame.gr_info + igr*channels + ch;
                int n_long_bands = (gr->mixed_block_flag ? 2 : 0) << (int)(DRMP3_HDR_GET_MY_SAMPLE_RATE(frame) == 2);
                drmp3_L3_imdct_gr(dec->scratch.grbuf[ch], c->before.mdct_overlap[ch], gr->block_type, (unsigned)n_long_bands);
                drmp3_L3_change_sign(dec->scratch.grbuf[ch]);
            }
            drmp3d_synth_granule(c->before.qmf_state, dec->scratch.grbuf[0], 18, channels, pcm + 576*channels*igr,
                                 dec->scratch.syn[0]);
        }
        DRMP3_COPY_MEMORY(dec->mdct_overlap, c->before.mdct_overlap, sizeof(dec->mdct_overlap));
        DRMP3_COPY_MEMORY(dec->qmf_state, c->before.qmf_state, sizeof(dec->qmf_state));
    }
    return samples;
}
