// deckie_cover.c: the vendored stb headers switched on, cut down to what a cover needs (JPEG and PNG in, JPEG out,
// from and to memory only), and the thumbnail made from them.

#define STB_IMAGE_IMPLEMENTATION
#define STBI_ONLY_JPEG
#define STBI_ONLY_PNG
#define STBI_NO_STDIO
#define STBI_NO_LINEAR
#define STBI_NO_HDR
// stb_image's own limit is left above ours, so that a picture too large for a cover is told apart from a damaged
// one: its size is read first (stbi_info) and it is refused here, before any of it is decoded.
#define STBI_MAX_DIMENSIONS 1048576
#define STB_IMAGE_WRITE_IMPLEMENTATION
#define STBI_WRITE_NO_STDIO

#if defined(__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wunused-parameter"
#pragma clang diagnostic ignored "-Wsign-compare"
#pragma clang diagnostic ignored "-Wmissing-field-initializers"
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif
#include "stb_image.h"
#include "stb_image_write.h"
#if defined(__clang__)
#pragma clang diagnostic pop
#endif

#include "deckie_cover.h"
#include <stdlib.h>
#include <string.h>

typedef struct {
    uint8_t *bytes;
    size_t length, capacity;
    int failed;
} sink;

static void append(void *context, void *data, int size) {
    sink *s = (sink *)context;
    if (s->failed || size <= 0) return;
    if (s->length + (size_t)size > s->capacity) {
        size_t bigger = s->capacity ? s->capacity * 2 : 16384;
        while (bigger < s->length + (size_t)size) bigger *= 2;
        uint8_t *grown = (uint8_t *)realloc(s->bytes, bigger);
        if (!grown) { s->failed = 1; return; }
        s->bytes = grown;
        s->capacity = bigger;
    }
    memcpy(s->bytes + s->length, data, (size_t)size);
    s->length += (size_t)size;
}

// Scales `w` x `h` RGB down to `tw` x `th` by area averaging in whole numbers: each new pixel is the mean of the old
// pixels it covers, an old pixel on an edge counted by the share of it that falls inside. Along one line, old pixel
// j covers [j*tw, (j+1)*tw) and new pixel i covers [i*w, (i+1)*w) on a common ruler of w*tw units, so every weight is
// a whole number and the weights of one new pixel add up to w. No floating point, so every machine gives the same
// bytes.
static uint8_t *scale(const uint8_t *rgb, int w, int h, int tw, int th) {
    uint32_t *wide = (uint32_t *)malloc((size_t)tw * (size_t)h * 3 * sizeof(uint32_t));
    uint8_t *out = (uint8_t *)malloc((size_t)tw * (size_t)th * 3);
    if (!wide || !out) { free(wide); free(out); return NULL; }
    for (int y = 0; y < h; y++) {
        const uint8_t *row = rgb + (size_t)y * (size_t)w * 3;
        uint32_t *to = wide + (size_t)y * (size_t)tw * 3;
        for (int i = 0; i < tw; i++) {
            uint64_t from = (uint64_t)i * (uint64_t)w, until = from + (uint64_t)w;
            uint64_t sum[3] = {0, 0, 0};
            for (uint64_t j = from / (uint64_t)tw; j * (uint64_t)tw < until; j++) {
                uint64_t a = j * (uint64_t)tw, b = a + (uint64_t)tw;
                uint64_t share = (b < until ? b : until) - (a > from ? a : from);
                for (int c = 0; c < 3; c++) sum[c] += share * row[j * 3 + (uint64_t)c];
            }
            for (int c = 0; c < 3; c++) to[i * 3 + c] = (uint32_t)sum[c];  // at most w * 255
        }
    }
    uint64_t area = (uint64_t)w * (uint64_t)h;
    for (int i = 0; i < th; i++) {
        uint64_t from = (uint64_t)i * (uint64_t)h, until = from + (uint64_t)h;
        for (int x = 0; x < tw; x++) {
            uint64_t sum[3] = {0, 0, 0};
            for (uint64_t j = from / (uint64_t)th; j * (uint64_t)th < until; j++) {
                uint64_t a = j * (uint64_t)th, b = a + (uint64_t)th;
                uint64_t share = (b < until ? b : until) - (a > from ? a : from);
                const uint32_t *p = wide + (j * (uint64_t)tw + (uint64_t)x) * 3;
                for (int c = 0; c < 3; c++) sum[c] += share * p[c];
            }
            uint8_t *q = out + ((size_t)i * (size_t)tw + (size_t)x) * 3;
            for (int c = 0; c < 3; c++) q[c] = (uint8_t)((sum[c] + area / 2) / area);
        }
    }
    free(wide);
    return out;
}

int deckie_cover_thumbnail(const uint8_t *bytes, size_t length, int side, int quality,
                           uint8_t **jpeg, size_t *jpeg_length, int *width, int *height,
                           int *source_width, int *source_height) {
    *jpeg = NULL; *jpeg_length = 0; *width = 0; *height = 0; *source_width = 0; *source_height = 0;
    if (length == 0 || length > 0x7FFFFFFF || side < 1) return 1;
    int w = 0, h = 0, n = 0;
    if (!stbi_info_from_memory(bytes, (int)length, &w, &h, &n) || w < 1 || h < 1) return 1;
    *source_width = w; *source_height = h;
    if (w > DECKIE_COVER_MAX_SOURCE_SIDE || h > DECKIE_COVER_MAX_SOURCE_SIDE) return 2;
    uint8_t *rgba = stbi_load_from_memory(bytes, (int)length, &w, &h, &n, 4);
    if (!rgba) return 1;
    // Laid over white, in place, into three values a pixel.
    size_t pixels = (size_t)w * (size_t)h;
    for (size_t i = 0; i < pixels; i++) {
        unsigned a = rgba[i * 4 + 3];
        for (int c = 0; c < 3; c++) {
            unsigned v = rgba[i * 4 + (size_t)c];
            rgba[i * 3 + (size_t)c] = (uint8_t)((v * a + 255 * (255 - a) + 127) / 255);
        }
    }
    int tw = w, th = h;
    if (w > side || h > side) {
        if (w >= h) { tw = side; th = (int)(((int64_t)h * side + w / 2) / w); }
        else { th = side; tw = (int)(((int64_t)w * side + h / 2) / h); }
        if (tw < 1) tw = 1;
        if (th < 1) th = 1;
    }
    uint8_t *small = rgba;
    if (tw != w || th != h) {
        small = scale(rgba, w, h, tw, th);
        stbi_image_free(rgba);
        if (!small) return 3;
    }
    sink s = {NULL, 0, 0, 0};
    int ok = stbi_write_jpg_to_func(append, &s, tw, th, 3, small, quality);
    if (small == rgba) stbi_image_free(rgba); else free(small);
    if (!ok || s.failed || s.length == 0) { free(s.bytes); return 3; }
    *jpeg = s.bytes; *jpeg_length = s.length; *width = tw; *height = th;
    return 0;
}

void deckie_cover_free(uint8_t *jpeg) { free(jpeg); }
