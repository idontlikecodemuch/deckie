// Deckie's damaged-frame check for MP3, beside the vendored dr_mp3 (which stays unmodified). The code is in
// ../dr_mp3.c, after dr_mp3's implementation, whose internal functions it calls; MP3Reader.swift drives it.
#ifndef DECKIE_MP3_H
#define DECKIE_MP3_H

#include "dr_mp3.h"

#ifdef __cplusplus
extern "C" {
#endif

// The check's working memory (the decoder's state before a frame, the frame's main data twice over, two granules of
// Huffman output), about 70 KB, made once per file.
typedef struct deckie_mp3_check deckie_mp3_check;

deckie_mp3_check *deckie_mp3_check_new(void);
void deckie_mp3_check_free(deckie_mp3_check *check);

// Decodes the next frame exactly as drmp3dec_decode_frame(dec, mp3, mp3_bytes, pcm, info) does and returns what it
// returns. Then, when that decoded a layer III frame, checks each granule of each channel as mpg123 does: did the
// Huffman decoding of the granule's big values read past the granule's declared length (its part_2_3_length, in
// the frame's side information)? If any did, *damaged is set to 1, else 0; with conceal set to 1 the frame's output
// in pcm is then silence: the frame is decoded again from the decoder's state before it with every spectral value
// zero, so the previous frame's last half block fades out through the decoder's own windows and filter bank, and the
// decoder carries nothing of the damaged values into the next frame. A frame not flagged is left exactly as dr_mp3
// decoded it. pcm must not be NULL.
int deckie_mp3_decode_frame(deckie_mp3_check *check, drmp3dec *dec, const drmp3_uint8 *mp3, int mp3_bytes,
                            float *pcm, drmp3dec_frame_info *info, int conceal, int *damaged);

#ifdef __cplusplus
}
#endif

#endif
