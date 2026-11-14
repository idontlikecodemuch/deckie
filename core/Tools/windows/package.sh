#!/usr/bin/env bash
# package.sh: assemble the Windows zip a DJ downloads, "Deckie Desk for Windows (first test)".
#
#   bash core/Tools/windows/package.sh <output folder>
#
# Run in Git Bash on a 64-bit Windows machine, from anywhere in the repository, after
#   bash core/Tools/windows/icon.sh <icon folder>         (the icon, as files a linker takes: icon.sh)
#   swift build -c release --product deckie-make          (in core/)
#   swift build -c release --product deckie-desk-engine   (in core/)
#   swift build -c release -Xlinker <icon folder>/desk.res   (in desk-shell/: deckie-desk, with its icon linked in)
#   bash core/Tools/fetch-onnxruntime.sh --deckie         (Deckie's own build of ONNX Runtime, no reporting client)
#   bash core/Tools/fetch-models.sh --no-export           (the two pinned models)
# with DECKIE_ICON set to <icon folder>. It downloads nothing and builds two things, the starters (launcher.c),
# with the clang that comes with Swift.
#
# What it makes, in <output folder>:
#   Deckie Desk for Windows (first test)/
#     READ ME FIRST.txt
#     Deckie Desk.exe              the starter for the window (core/Tools/windows/launcher.c, built with DECKIE_DESK)
#     Make Crate File.exe          the starter for the program a music folder is dropped on (the same file)
#     app/deckie-desk.exe          Desk's window (desk-shell), marked as a program that opens no console window
#     app/deckie-desk-engine.exe   Desk's engine (core/Sources/deckie-desk-engine), marked the same way, so that no
#                                  console window opens when the window starts it
#     app/desk-web/                the pages the window shows (desk-web/: index.html, desk.css, desk.js)
#     app/deckie-make.exe          the program without a window (core/Sources/deckie-make), a console program
#     app/*.dll                    Swift's runtime libraries, exactly those the three programs need (read from the
#                                  program files' own import tables by pe_imports.py), and onnxruntime.dll
#     app/models/                  beat_this_final0.onnx, yamnet.onnx
#     app/licences/                ACKNOWLEDGEMENTS.txt (from core/dependencies.json), DEPENDENCIES.md (every quote
#                                  and the models' training sets), the licence files themselves, FILES.txt (every file
#                                  here with its size and SHA-256, and what is expected from Windows)
#   Deckie-Desk-for-Windows-first-test.zip   the folder, zipped
#   package-report.md              sizes, the library list and what Windows must provide, for the workflow's summary
#
# The engine finds onnxruntime.dll and models/ beside itself (OnnxRuntime.programFolder), as deckie-make does; the
# window finds the engine and desk-web/ beside itself (desk-shell, main.swift). So everything sits in app/.
#
# No console window: "Deckie Desk.exe" is linked as a program of the "windows" kind; the copies of deckie-desk.exe
# and deckie-desk-engine.exe placed in the zip are marked so after the build (pe_kind.py says how and why), which
# leaves the builds the tests use as console programs.
#
# The icon: icon.sh makes deckie.ico from the iPad app's picture and compiles it; it is linked into deckie-desk.exe
# when that is built, and into both starters here. This script stops if a program that should carry it does not.
#
# Included since Nov 13, 2026 (the owner's yes): Microsoft's Visual C++ runtime (msvcp140.dll, msvcp140_1.dll,
# vcruntime140.dll, vcruntime140_1.dll), which Swift's runtime and ONNX Runtime both need and not every PC has. The
# copies are the ones the Swift toolchain installs beside its own runtime libraries; they come in with the import
# closure, unmodified, with their notice (core/notices/microsoft-vc-runtime; DEPENDENCIES.md, section 3).
# DECKIE_SHIP_VC_RUNTIME=0 leaves them out.
#
# Not included, and not needed in the folder: Microsoft's WebView2 Runtime, the part of Windows that shows Desk's
# window. It is on the PC or it is not (DEPENDENCIES.md, section 10); deckie-desk.exe says what to do when it is not.

if [ -z "${BASH_VERSION:-}" ]; then echo "package.sh: run this with bash" >&2; exit 1; fi
set -euo pipefail
die() { printf 'package.sh: %s\n' "$*" >&2; exit 1; }

[ $# -eq 1 ] || die "usage: package.sh <output folder>"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
core="$(cd "$here/../.." && pwd)"
repo="$(cd "$core/.." && pwd)"
mkdir -p "$1"
out="$(cd "$1" && pwd)"
name="Deckie Desk for Windows (first test)"
root="$out/$name"
app="$root/app"
py="$(command -v python || command -v python3)" || die "needs Python"

exe="$core/.build/release/deckie-make.exe"
[ -f "$exe" ] || die "build first: swift build -c release --product deckie-make (looked for $exe)"
engine="$core/.build/release/deckie-desk-engine.exe"
[ -f "$engine" ] || die "build first: swift build -c release --product deckie-desk-engine (looked for $engine)"
window="$repo/desk-shell/.build/release/deckie-desk.exe"
[ -f "$window" ] || die "build first, in desk-shell: swift build -c release -Xlinker <icon folder>/desk.res (looked for $window)"
pages="$repo/desk-web"
[ -f "$pages/index.html" ] || die "the pages are not at $pages"
icon="${DECKIE_ICON:-}"
[ -n "$icon" ] && [ -s "$icon/desk.res" ] && [ -s "$icon/make.res" ] \
    || die "make the icon first: bash core/Tools/windows/icon.sh <folder>, and set DECKIE_ICON to that folder"
icon="$(cd "$icon" && pwd)"
ort="$core/.deps/onnxruntime"
[ -f "$ort/lib/onnxruntime.dll" ] || die "fetch ONNX Runtime first: bash core/Tools/fetch-onnxruntime.sh --deckie"
grep -q "deckie-no-telemetry" "$ort/.fetched-archive" \
    || die "core/.deps/onnxruntime holds Microsoft's build; a shipped zip carries Deckie's own: fetch-onnxruntime.sh --deckie"
bash "$core/Tools/fetch-models.sh" --check >/dev/null || die "the two pinned models are not in core/.models: bash core/Tools/fetch-models.sh --no-export"

rm -rf "$root"
mkdir -p "$app/models" "$app/licences"
cp "$exe" "$app/deckie-make.exe"
cp "$engine" "$app/deckie-desk-engine.exe"
cp "$window" "$app/deckie-desk.exe"
mkdir -p "$app/desk-web"
cp "$pages/index.html" "$pages/desk.css" "$pages/desk.js" "$app/desk-web/"
# The window and its engine open no console window (pe_kind.py); deckie-make stays a console program.
"$py" "$here/pe_kind.py" --set window "$app/deckie-desk.exe" "$app/deckie-desk-engine.exe" >/dev/null
cp "$ort/lib/onnxruntime.dll" "$app/onnxruntime.dll"
cp "$core/.models/beat_this_final0.onnx" "$core/.models/yamnet.onnx" "$app/models/"

# Swift's runtime libraries: every folder on PATH that holds one, then the closure of what the program imports.
closure=()
IFS=':' read -r -a dirs <<< "$PATH"
for d in "${dirs[@]}"; do
    if [ -n "$d" ] && { [ -f "$d/swiftCore.dll" ] || [ -f "$d/Foundation.dll" ]; }; then closure+=(--closure "$d"); fi
done
[ ${#closure[@]} -gt 0 ] || die "Swift's runtime libraries (swiftCore.dll) are not on PATH"
"$py" "$here/pe_imports.py" "${closure[@]}" "$app/deckie-make.exe" "$app/deckie-desk.exe" "$app/deckie-desk-engine.exe" \
    "$app/onnxruntime.dll" | tr -d '\r' > "$out/imports.txt"
ship_vc="${DECKIE_SHIP_VC_RUNTIME:-1}"
vc_names='^(msvcp140|vcruntime140|concrt140)'
if [ "$ship_vc" != 1 ]; then
    # Left out: those lines become "system" lines, expected from Windows.
    sed -i -E 's/^copy .*[\\/]((msvcp140|vcruntime140|concrt140)[^\\/]*\.dll)$/system \1/I' "$out/imports.txt"
    sort -u -o "$out/imports.txt" "$out/imports.txt"
fi
grep '^copy ' "$out/imports.txt" | sed 's/^copy //' | while IFS= read -r dll; do cp "$dll" "$app/"; done
if [ "$ship_vc" = 1 ]; then
    for f in msvcp140.dll msvcp140_1.dll vcruntime140.dll vcruntime140_1.dll; do
        [ -f "$app/$f" ] || die "Microsoft's $f was not found beside Swift's runtime libraries, so the zip would not start on a PC without it"
    done
elif ls "$app" | grep -q -i -E "$vc_names"; then
    die "Microsoft's Visual C++ runtime got into the zip"
fi
ls "$app"/swiftCore.dll >/dev/null 2>&1 || die "swiftCore.dll was not found among the program's imports; see $out/imports.txt"

# The starters: Windows' kernel32 only, and user32 for the window starter's message box; no C runtime (launcher.c
# says why). Each carries the icon. The linker options are spelled with a dash so that Git Bash does not take them
# for paths; the resource files are named the Windows way for the same reason.
starter() {   # starter <file name> <resource file> <subsystem> [more clang options]
    local target="$root/$1" res="$2" kind="$3"
    shift 3
    clang -O1 -ffreestanding -fno-builtin -fno-stack-protector -nostdlib -Wall "$@" \
        -o "$target" "$here/launcher.c" \
        -Xlinker "$(cygpath -m "$res" 2>/dev/null || echo "$res")" \
        -Xlinker -entry:entry -Xlinker "-subsystem:$kind" -Xlinker -nodefaultlib -lkernel32 -luser32
    rm -f "${target%.exe}.lib" "${target%.exe}.exp"
}
starter "Make Crate File.exe" "$icon/make.res" console
starter "Deckie Desk.exe" "$icon/desk.res" windows -DDECKIE_DESK

# What each program is, checked: Deckie Desk, its window and its engine open no console window; the two starters
# and the window carry the icon.
"$py" "$here/pe_kind.py" "$root/Deckie Desk.exe" "$root/Make Crate File.exe" "$app/deckie-desk.exe" \
    "$app/deckie-desk-engine.exe" "$app/deckie-make.exe" | tr -d '\r' > "$out/kinds.txt"
cat "$out/kinds.txt"
for want in "Deckie Desk.exe: window icon" "Make Crate File.exe: console icon" "deckie-desk.exe: window icon" \
            "deckie-desk-engine.exe: window" "deckie-make.exe: console"; do
    grep -q -F "$want" "$out/kinds.txt" || die "expected \"$want\" (see above); deckie-desk must be built with -Xlinker <icon folder>/desk.res"
done

# The words, with Windows line endings so every Notepad shows them as written.
sed 's/\r$//; s/$/\r/' "$here/READ ME FIRST.txt" > "$root/READ ME FIRST.txt"

# Licences and acknowledgements (DEPENDENCIES.md, section 3 and the table at its top).
lic="$app/licences"
cp "$repo/DEPENDENCIES.md" "$lic/DEPENDENCIES.md"
cp "$core/notices/swift/swift-LICENSE.txt" "$core/notices/swift/swift-foundation-LICENSE.md" \
   "$core/notices/swift/swift-corelibs-foundation-and-libdispatch-LICENSE.txt" "$core/notices/swift/ICU-76.1-LICENSE.txt" "$lic/"
cp "$ort/LICENSE" "$lic/onnxruntime-LICENSE.txt"
cp "$ort/ThirdPartyNotices.txt" "$lic/onnxruntime-ThirdPartyNotices.txt"
if [ "$ship_vc" = 1 ]; then cp "$core/notices/microsoft-vc-runtime/NOTICE.txt" "$lic/Microsoft-Visual-C++-runtime-NOTICE.txt"; fi
# Desk's window (DEPENDENCIES.md, sections 9 and 10): the webview library's licence, and the licence of Microsoft's
# WebView2 SDK header, both compiled into deckie-desk.exe.
vendor="$repo/desk-shell/Sources/CDeskShell/vendor"
cp "$vendor/webview/LICENSE" "$lic/webview-LICENSE.txt"
cp "$vendor/WebView2/LICENSE.txt" "$lic/Microsoft-WebView2-SDK-LICENSE.txt"
mkdir -p "$lic/eigen-patches"
cp "$core/notices/eigen/"* "$lic/eigen-patches/"
"$py" - "$core/dependencies.json" > "$lic/ACKNOWLEDGEMENTS.txt" <<'PY'
import json, sys
entries = json.load(open(sys.argv[1], encoding="utf-8"))["entries"]
print("Deckie Desk for Windows: acknowledgements")
print("========================================")
print()
print("Deckie is made with the work of others. Each part below ships in this folder under")
print("its own licence. The full licence texts are the files beside this one;")
print("DEPENDENCIES.md has every quote, where each part came from, and for the two models,")
print("the sets they were trained on and their terms.")
print()
for e in entries:
    print(f"{e['name']}, {e['version']}")
    print(f"  Licence: {e['licence']}")
    if e.get("training_sets"):
        print(f"  Trained on: {e['training_sets']}")
    if e.get("replacement_path"):
        print(f"  Without it: {e['replacement_path']}")
    print()
print("Eigen (inside ONNX Runtime) is under the Mozilla Public License 2.0; its notice is in")
print("onnxruntime-ThirdPartyNotices.txt, and the two patches ONNX Runtime's build applies to")
print("it are in eigen-patches. Eigen's source: https://gitlab.com/libeigen/eigen")
print()
print("ICU (inside Foundation) is under the Unicode License V3: ICU-76.1-LICENSE.txt.")
print()
print("Microsoft's Visual C++ runtime (four files) is Microsoft's own, not open source, and is")
print("included unmodified under Microsoft's terms: Microsoft-Visual-C++-runtime-NOTICE.txt.")
print()
print("Deckie Desk's window is made with the webview library (webview-LICENSE.txt) and compiled")
print("against Microsoft's WebView2 SDK header (Microsoft-WebView2-SDK-LICENSE.txt). The window")
print("itself is drawn by Microsoft's WebView2 Runtime, a part of Windows that is not in this")
print("folder and stays under Microsoft's own terms.")
PY

# Every file with its size and hash, and what must come from Windows.
{
    echo "Files in this folder, with their sizes in bytes and SHA-256 hashes"
    echo
    (cd "$root" && find . -type f ! -name FILES.txt | sort | while IFS= read -r f; do
        printf '%s  %10d  %s\n' "$(sha256sum "$f" | cut -d' ' -f1)" "$(wc -c < "$f")" "${f#./}"
    done)
    echo
    echo "Library files the program expects from Windows itself (not in this folder):"
    grep '^system ' "$out/imports.txt" | sed 's/^system /  /'
    echo
    echo "Names that start with api-ms-win-crt are Windows 10 and 11's own C runtime; the rest are parts of every Windows."
    echo
    echo "Deckie Desk's window also needs Microsoft's WebView2 Runtime, which is part of Windows 11 and on most"
    echo "Windows 10 PCs. It is not in this folder. Without it, Deckie Desk says so and Make Crate File still works."
} > "$lic/FILES.txt"

# The zip (compressed, for the download; nothing to do with the crate file's own uncompressed form).
zip="$out/Deckie-Desk-for-Windows-first-test.zip"
rm -f "$zip"
"$py" - "$out" "$name" "$zip" <<'PY'
import os, sys, zipfile
out, name, target = sys.argv[1:4]
with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for folder, _, files in sorted(os.walk(os.path.join(out, name))):
        for f in sorted(files):
            full = os.path.join(folder, f)
            z.write(full, os.path.relpath(full, out).replace(os.sep, "/"))
PY

{
    echo "| | |"
    echo "|---|---|"
    echo "| The zip | \`$(basename "$zip")\`, $(wc -c < "$zip") bytes, SHA-256 \`$(sha256sum "$zip" | cut -d' ' -f1)\` |"
    echo "| Unzipped | $(cd "$root" && find . -type f | wc -l) files, $(du -sb "$root" | cut -f1) bytes |"
    echo "| The window | \`app/deckie-desk.exe\`, $(wc -c < "$app/deckie-desk.exe") bytes |"
    echo "| The engine | \`app/deckie-desk-engine.exe\`, $(wc -c < "$app/deckie-desk-engine.exe") bytes |"
    echo "| The pages | \`app/desk-web\`, $(du -sb "$app/desk-web" | cut -f1) bytes |"
    echo "| The program without a window | \`app/deckie-make.exe\`, $(wc -c < "$app/deckie-make.exe") bytes |"
    echo "| The starters | \`Deckie Desk.exe\`, $(wc -c < "$root/Deckie Desk.exe") bytes; \`Make Crate File.exe\`, $(wc -c < "$root/Make Crate File.exe") bytes |"
    echo "| Console window or not, icon or not | $(tr '\n' ';' < "$out/kinds.txt" | sed 's/;$//; s/;/; /g') |"
    echo "| The icon | \`deckie.ico\`, $(wc -c < "$icon/deckie.ico") bytes, SHA-256 \`$(sha256sum "$icon/deckie.ico" | cut -d' ' -f1)\` (made in this run, not committed) |"
    echo "| Swift runtime libraries copied | $(grep -c '^copy ' "$out/imports.txt"): $(grep '^copy ' "$out/imports.txt" | sed 's/.*[\\/]//' | tr '\n' ' ') |"
    echo "| Expected from Windows | $(grep '^system ' "$out/imports.txt" | sed 's/^system //' | tr '\n' ' ') |"
    if [ "$ship_vc" = 1 ]; then
        for f in msvcp140.dll msvcp140_1.dll vcruntime140.dll vcruntime140_1.dll; do
            version="$(powershell -NoProfile -Command "(Get-Item '$(cygpath -w "$app/$f")').VersionInfo.FileVersion" 2>/dev/null | tr -d '\r' || true)"
            echo "| Microsoft's \`$f\` | $(wc -c < "$app/$f") bytes, version $version, SHA-256 \`$(sha256sum "$app/$f" | cut -d' ' -f1)\` |"
        done
    fi
} > "$out/package-report.md"
cat "$out/package-report.md"
