#!/usr/bin/env bash
# scan-onnxruntime.sh: look for Microsoft's usage-reporting client ("telemetry") in ONNX Runtime library files.
#
#   core/Tools/scan-onnxruntime.sh LIBRARY...   exit 0 when no file carries a trace, 1 when any does, 2 on an error
#   core/Tools/scan-onnxruntime.sh --list       print the marker texts, one per line
#
# This is the gate in .github/workflows/onnxruntime-build.yml on Linux and macOS: the library Deckie builds with
# --no_telemetry is not uploaded if this finds any trace of the client in it (DEPENDENCIES.md, section 6).
# scan-onnxruntime.ps1 is the same scan for Windows.
#
# The markers. The source of truth is OnnxRuntime.ReportingClientScan.markers in
# core/Sources/DeckieInference/ReportingClientScan.swift, which the Swift release test scans with; the list below is
# a copy, so that the gate needs no Swift toolchain on the build machines. Keep this list, the one in
# scan-onnxruntime.ps1 and the Swift one equal, in the same order (the workflow's first job checks that they are).
#
# How it looks. Each marker's text is searched for as plain bytes anywhere in the file (grep -F, the C locale, binary
# read as text), as the Swift scan does: no symbol tables, no decoding, so it works on .so, .dylib and .dll alike.
#
# Needs: bash, grep, wc.

if [ -z "${BASH_VERSION:-}" ]; then echo "scan-onnxruntime: run this with bash" >&2; exit 2; fi
set -uo pipefail

# Each entry is "text|name"; no text contains "|".
markers=(
    "mobile.events.data.microsoft.com|the reporting address"
    "Microsoft12Applications6Events|the 1DS client's namespace"
    "telemetry_1ds|ONNX Runtime's 1DS source file"
    "OneDsTelemetry|ONNX Runtime's 1DS provider class"
    "CurlHttpOperation|the 1DS client's curl transport"
    "https://curl.se/docs/|curl's documentation address"
    "SQLite format 3|SQLite's file header"
    "mbedtls_ssl_|mbedTLS's TLS functions"
    "Microsoft.ML.ONNXRuntime|the Windows event-tracing provider"
)

usage() { echo "usage: scan-onnxruntime.sh LIBRARY... | --list" >&2; exit 2; }

[ $# -ge 1 ] || usage
if [ "$1" = "--list" ]; then
    [ $# -eq 1 ] || usage
    for m in "${markers[@]}"; do printf '%s\n' "${m%%|*}"; done
    exit 0
fi

export LC_ALL=C
carrying=0
for lib in "$@"; do
    if [ ! -f "$lib" ] || [ ! -r "$lib" ]; then
        echo "scan-onnxruntime: $lib: not a readable file" >&2
        exit 2
    fi
    size=$(wc -c < "$lib" | tr -d ' ')
    found=()
    for m in "${markers[@]}"; do
        text="${m%%|*}"
        grep -q -a -F -e "$text" -- "$lib"
        case $? in
            0) found+=("$m") ;;
            1) ;;
            *) echo "scan-onnxruntime: could not read $lib" >&2; exit 2 ;;
        esac
    done
    if [ ${#found[@]} -eq 0 ]; then
        echo "$lib ($size bytes): no trace of the reporting client (0 of ${#markers[@]} markers)"
    else
        carrying=1
        echo "$lib ($size bytes): REPORTING CLIENT FOUND, ${#found[@]} of ${#markers[@]} markers:"
        for m in "${found[@]}"; do echo "  ${m#*|}: ${m%%|*}"; done
    fi
done
exit $carrying
