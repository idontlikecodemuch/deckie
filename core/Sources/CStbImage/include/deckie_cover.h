// deckie_cover.h: a cover picture (JPEG or PNG bytes) made into a small JPEG thumbnail, the same bytes on every
// system: decoded by the vendored stb_image, scaled by exact whole-number area averaging written here, encoded by
// the vendored stb_image_write (DEPENDENCIES.md, section 11).
#ifndef DECKIE_COVER_H
#define DECKIE_COVER_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// The largest picture that is decoded at all: this many pixels a side.
#define DECKIE_COVER_MAX_SOURCE_SIDE 8192

/// Makes the thumbnail of the picture in `bytes`: its longest side scaled down to `side` pixels (never up), its
/// shape kept, anything see-through laid over white, written as a baseline JPEG at `quality` (1 to 100).
/// Returns 0 and fills `jpeg` (free it with `deckie_cover_free`), its length and the thumbnail's and the source's
/// sizes in pixels. Returns 1 when the bytes are not a JPEG or PNG that can be decoded (damaged, another format), 2
/// when the picture is wider or taller than DECKIE_COVER_MAX_SOURCE_SIDE, 3 when memory ran out.
int deckie_cover_thumbnail(const uint8_t *bytes, size_t length, int side, int quality,
                           uint8_t **jpeg, size_t *jpeg_length, int *width, int *height,
                           int *source_width, int *source_height);

void deckie_cover_free(uint8_t *jpeg);

#ifdef __cplusplus
}
#endif

#endif
