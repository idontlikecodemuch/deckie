#!/bin/sh
# Rebuilds core/fixtures/example.deckiecrate, the example crate (docs/architecture/crate-format.md), from five of the
# lab's committed feature files, chosen to differ:
#   0327cf1c94  Michael Jackson - Thriller            grid from madmom, low grid confidence
#   0692b134c9  Ricky Martin - Livin' La Vida Loca    octave-fixed grid
#   04c326848f  Eiffel 65 - Blue (Da Ba Dee)          fade-out; the end of its steady beat is clamped to the grid
#   334614c3a0  Drake - NOKIA                         tempo change (a transition edit, 12 percent drift)
#   08e45fb8ca  Drake - Rich Baby Daddy               the shortest, 44 bars
# The crate id and the dates are fixed, so every run gives the same bytes; DeckieCrateTests checks the committed
# files are exactly what the converter makes today. Needs Swift; run from anywhere in the repository.
set -e
cd "$(dirname "$0")/.."
rm -rf fixtures/example.deckiecrate
swift run crate-from-lab --out fixtures/example.deckiecrate --name Example --crate-id example \
    --created-at 2026-10-26T00:00:00Z --analysed-at 2026-10-26T00:00:00Z \
    --ids 0327cf1c94,0692b134c9,04c326848f,334614c3a0,08e45fb8ca
