#!/bin/sh
# Rebuilds core/fixtures/example.deckiecrate, the example crate (docs/architecture/crate-format.md), from five of the
# invented songs of the public lab sample (core/fixtures/lab-sample, written by core/Tools/make_lab_sample.py; nothing
# in it comes from anyone's music), chosen to differ:
#   sample-02  "Low Confidence"                                 grid from madmom (Beat This disagreed with the tag tempo)
#   sample-03  "Octave Swap"                                    octave-fixed grid (halved), 89 BPM
#   sample-04  "Fade Away Test"                                 fade-out
#   sample-05  "Tempo Ramp" (Transition Edit)                   tempo change, 100 to 112 BPM, a poorly fitting grid
#   sample-06  "Short One"                                      the shortest, 45 bars
# and core/fixtures/example-single.deckiecrate, the same crate file in its single-file form (one uncompressed zip).
# Both keep the earlier extension, .deckiecrate, on purpose: every reader takes it for good, and the tests read it.
# The crate id and the dates are fixed, so every run gives the same bytes; DeckieCrateTests checks the committed
# files are exactly what the converter makes today. Needs Swift; run from anywhere in the repository.
set -e
cd "$(dirname "$0")/.."
rm -rf fixtures/example.deckiecrate
swift run crate-from-lab --out fixtures/example.deckiecrate --name Example --crate-id example \
    --created-at 2026-10-26T00:00:00Z --analysed-at 2026-10-26T00:00:00Z --lab fixtures/lab-sample \
    --ids sample-02,sample-03,sample-04,sample-05,sample-06 \
    --single fixtures/example-single.deckiecrate
