/*
 * chromaprint_match.c: exhaustive bit-error-rate matcher for raw Chromaprint fingerprints.
 *
 * What it is: a bench baseline only. It compares the way AcoustID's server compares two raw
 * fingerprints (popcount of XOR over aligned 32-bit frames), but against every catalogue song at
 * every offset where the whole query lies inside the song. It is never linked into a product.
 *
 * Build:  gcc -O3 -mpopcnt -o chromaprint_match chromaprint_match.c
 * Run:    chromaprint_match CAT.u32 CAT.idx Q.u32 Q.idx > out.tsv
 *   CAT.u32 / Q.u32  little-endian uint32 frames, all songs / all queries end to end
 *   CAT.idx          one line per song:  first_frame <tab> frame_count
 *   Q.idx            one line per query: first_frame <tab> frame_count <tab> true song line number (0-based, -1 = none)
 * Output, one line per query (same order):
 *   frames  best_song  best_ber  best_offset  runner_up_song  runner_up_ber  true_ber  true_offset  best_wrong_ber  milliseconds
 * (song numbers are 0-based lines of CAT.idx; -1 and ber 1 when there is nothing to report.)
 * chromaprint_baseline.py builds the inputs and reads the output.
 */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <time.h>

static uint32_t *load(const char *p, long *n) {
    FILE *f = fopen(p, "rb"); if (!f) { perror(p); exit(1); }
    fseek(f, 0, SEEK_END); long sz = ftell(f); fseek(f, 0, SEEK_SET);
    uint32_t *b = malloc(sz ? sz : 4);
    if (fread(b, 1, sz, f) != (size_t)sz) { perror(p); exit(1); }
    fclose(f); *n = sz / 4; return b;
}

int main(int argc, char **argv) {
    if (argc != 5) { fprintf(stderr, "usage: %s CAT.u32 CAT.idx Q.u32 Q.idx\n", argv[0]); return 2; }
    long nc, nq; uint32_t *cat = load(argv[1], &nc), *qs = load(argv[3], &nq);
    long cap = 1 << 16, ns = 0; long *s0 = malloc(cap * sizeof(long)), *sn = malloc(cap * sizeof(long));
    FILE *f = fopen(argv[2], "r"); if (!f) { perror(argv[2]); return 1; }
    while (ns < cap && fscanf(f, "%ld %ld", &s0[ns], &sn[ns]) == 2) ns++;
    fclose(f);
    long *best = malloc(ns * sizeof(long)), *boff = malloc(ns * sizeof(long));
    f = fopen(argv[4], "r"); if (!f) { perror(argv[4]); return 1; }
    long q0, qn, truth;
    while (fscanf(f, "%ld %ld %ld", &q0, &qn, &truth) == 3) {
        struct timespec a, b; clock_gettime(CLOCK_MONOTONIC, &a);
        const uint32_t *q = qs + q0;
        for (long s = 0; s < ns; s++) {
            long bst = 1L << 40, bo = -1; const uint32_t *c = cat + s0[s];
            for (long o = 0; qn > 0 && o + qn <= sn[s]; o++) {
                long d = 0; const uint32_t *p = c + o;
                for (long i = 0; i < qn; i++) d += __builtin_popcount(q[i] ^ p[i]);
                if (d < bst) { bst = d; bo = o; }
            }
            best[s] = bst; boff[s] = bo;
        }
        long i1 = -1, i2 = -1, iw = -1;
        for (long s = 0; s < ns; s++) {
            if (boff[s] < 0) continue;
            if (i1 < 0 || best[s] < best[i1]) { i2 = i1; i1 = s; }
            else if (i2 < 0 || best[s] < best[i2]) i2 = s;
            if (s != truth && (iw < 0 || best[s] < best[iw])) iw = s;
        }
        clock_gettime(CLOCK_MONOTONIC, &b);
        double bits = 32.0 * (qn > 0 ? qn : 1);
        printf("%ld\t%ld\t%.6f\t%ld\t%ld\t%.6f\t%.6f\t%ld\t%.6f\t%.3f\n", qn,
               i1, i1 >= 0 ? best[i1] / bits : 1.0, i1 >= 0 ? boff[i1] : -1,
               i2, i2 >= 0 ? best[i2] / bits : 1.0,
               (truth >= 0 && boff[truth] >= 0) ? best[truth] / bits : 1.0, truth >= 0 ? boff[truth] : -1,
               iw >= 0 ? best[iw] / bits : 1.0,
               (b.tv_sec - a.tv_sec) * 1e3 + (b.tv_nsec - a.tv_nsec) / 1e6);
    }
    return 0;
}
