// deckie_mf.h: audio files decoded by Windows' own Media Foundation (AAC and Apple Lossless in .m4a), for
// DeckieDecode on Windows. On every other system the one function reports that it is not available.
#ifndef DECKIE_MF_H
#define DECKIE_MF_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/// What `deckie_mf_decode` gives back. `samples` is interleaved 32-bit float, `frames` sample frames of `channels`
/// values each, at `sample_rate`; free it with `deckie_mf_free`.
typedef struct {
    float *samples;
    uint64_t frames;
    uint32_t sample_rate;
    uint32_t channels;
    /// The time stamp Media Foundation gave the first block of samples, in units of 100 nanoseconds.
    int64_t first_timestamp;
    /// How many blocks were read.
    uint32_t blocks;
} deckie_mf_audio;

/// Decodes the audio file at `path` (UTF-16, NUL-terminated) to float samples at the file's own rate and channel
/// count. Returns 0 on success. Otherwise: 1 when Media Foundation is not on this machine (not Windows, or a
/// Windows edition without media features), 2 when the file could not be opened or decoded; `message` (if not NULL)
/// then holds a short ASCII reason.
int deckie_mf_decode(const uint16_t *path, deckie_mf_audio *out, char *message, size_t message_size);

void deckie_mf_free(deckie_mf_audio *audio);

#ifdef __cplusplus
}
#endif

#endif
