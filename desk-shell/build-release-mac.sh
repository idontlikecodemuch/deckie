#!/bin/bash
# Builds Deckie Desk's window and engine for a timing test on the Mac, in release: `deckie-desk-engine` (core/) and
# `deckie-desk` (desk-shell/). Timing tests use release builds: a debug build analyses a song several times slower
# (no optimisation, the plain loops), so its times say nothing about what a DJ waits for.
#
# Gentle on a Mac that is doing something else (a CD being read in another Desk): low priority, at most 4 jobs.
#
#   desk-shell/build-release-mac.sh
#   DECKIE_CHECKOUT=<this repository> DECKIE_DESK_HOME=<scratch folder> DECKIE_DJ_HOME=<empty folder> \
#       desk-shell/.build/release/deckie-desk
#
# A release build carries no path of the machine that built it, so DECKIE_CHECKOUT names the checkout (the last
# line below prints the command with it). The window finds the release engine in the checkout's core/.build/release
# (`--engine` names another), and the engine, which inherits the variable, finds ONNX Runtime and the two models as a
# debug build does (DECKIE_ONNXRUNTIME_LIB, DECKIE_BEAT_THIS_MODEL, DECKIE_YAMNET_MODEL, else core/.deps and
# core/.models in the checkout). The learned key reader's file is optional and
# found the same way (DECKIE_KEY_MODEL, else core/.models: core/Tools/fetch-key-model.sh); the last lines say whether
# it is there, and the engine's own line in the window's log says which key reader it uses.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
jobs="${DECKIE_BUILD_JOBS:-4}"
cd "$here/../core"
nice -n 10 swift build -c release -j "$jobs" --product deckie-desk-engine
cd "$here"
nice -n 10 swift build -c release -j "$jobs"
echo "engine: $here/../core/.build/release/deckie-desk-engine"
echo "window: $here/.build/release/deckie-desk"
echo "start:  DECKIE_CHECKOUT=\"$(cd "$here/.." && pwd)\" DECKIE_DESK_HOME=<scratch folder> DECKIE_DJ_HOME=<empty folder> $here/.build/release/deckie-desk"
if [ -n "${DECKIE_KEY_MODEL:-}" ]; then echo "key reader's file: DECKIE_KEY_MODEL=$DECKIE_KEY_MODEL (its hash is checked when the engine loads it)"
else bash "$here/../core/Tools/fetch-key-model.sh" --check || true; fi
