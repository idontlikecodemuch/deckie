#!/usr/bin/env bash
# package.sh: assemble the Windows zip a DJ downloads, "Deckie for PC (first test)".
#
#   bash core/Tools/windows/package.sh <output folder>
#
# Run in Git Bash on a 64-bit Windows machine, from anywhere in the repository, after
#   swift build -c release --product deckie-make        (in core/)
#   bash core/Tools/fetch-onnxruntime.sh --deckie       (Deckie's own build of ONNX Runtime, no reporting client)
#   bash core/Tools/fetch-models.sh --no-export         (the two pinned models)
# It downloads nothing and builds one thing, the starter (launcher.c), with the clang that comes with Swift.
#
# What it makes, in <output folder>:
#   Deckie for PC (first test)/
#     READ ME FIRST.txt
#     Make Crate File.exe          the starter (core/Tools/windows/launcher.c)
#     app/deckie-make.exe          the program (core/Sources/deckie-make)
#     app/*.dll                    Swift's runtime libraries, exactly those the program needs (read from the program
#                                  file's own import tables by pe_imports.py), and onnxruntime.dll
#     app/models/                  beat_this_final0.onnx, yamnet.onnx
#     app/licences/                ACKNOWLEDGEMENTS.txt (from core/dependencies.json), DEPENDENCIES.md (every quote
#                                  and the models' training sets), the licence files themselves, FILES.txt (every file
#                                  here with its size and SHA-256, and what is expected from Windows)
#   Deckie-for-PC-first-test.zip   the folder, zipped
#   package-report.md              sizes, the library list and what Windows must provide, for the workflow's summary
#
# Not included, on purpose: Microsoft's Visual C++ runtime (MSVCP140.dll, MSVCP140_1.dll, VCRUNTIME140.dll,
# VCRUNTIME140_1.dll), which Swift's runtime and ONNX Runtime both need. Its licence is Microsoft's own, not on the
# allowlist (DEPENDENCIES.md), so shipping it is the owner's decision; the starter says in plain words what to
# install when a PC does not have it.

if [ -z "${BASH_VERSION:-}" ]; then echo "package.sh: run this with bash" >&2; exit 1; fi
set -euo pipefail
die() { printf 'package.sh: %s\n' "$*" >&2; exit 1; }

[ $# -eq 1 ] || die "usage: package.sh <output folder>"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
core="$(cd "$here/../.." && pwd)"
repo="$(cd "$core/.." && pwd)"
mkdir -p "$1"
out="$(cd "$1" && pwd)"
name="Deckie for PC (first test)"
root="$out/$name"
app="$root/app"
py="$(command -v python || command -v python3)" || die "needs Python"

exe="$core/.build/release/deckie-make.exe"
[ -f "$exe" ] || die "build first: swift build -c release --product deckie-make (looked for $exe)"
ort="$core/.deps/onnxruntime"
[ -f "$ort/lib/onnxruntime.dll" ] || die "fetch ONNX Runtime first: bash core/Tools/fetch-onnxruntime.sh --deckie"
grep -q "deckie-no-telemetry" "$ort/.fetched-archive" \
    || die "core/.deps/onnxruntime holds Microsoft's build; a shipped zip carries Deckie's own: fetch-onnxruntime.sh --deckie"
bash "$core/Tools/fetch-models.sh" --check >/dev/null || die "the two pinned models are not in core/.models: bash core/Tools/fetch-models.sh --no-export"

rm -rf "$root"
mkdir -p "$app/models" "$app/licences"
cp "$exe" "$app/deckie-make.exe"
cp "$ort/lib/onnxruntime.dll" "$app/onnxruntime.dll"
cp "$core/.models/beat_this_final0.onnx" "$core/.models/yamnet.onnx" "$app/models/"

# Swift's runtime libraries: every folder on PATH that holds one, then the closure of what the program imports.
closure=()
IFS=':' read -r -a dirs <<< "$PATH"
for d in "${dirs[@]}"; do
    if [ -n "$d" ] && { [ -f "$d/swiftCore.dll" ] || [ -f "$d/Foundation.dll" ]; }; then closure+=(--closure "$d"); fi
done
[ ${#closure[@]} -gt 0 ] || die "Swift's runtime libraries (swiftCore.dll) are not on PATH"
"$py" "$here/pe_imports.py" "${closure[@]}" "$app/deckie-make.exe" "$app/onnxruntime.dll" | tr -d '\r' > "$out/imports.txt"
grep '^copy ' "$out/imports.txt" | sed 's/^copy //' | while IFS= read -r dll; do cp "$dll" "$app/"; done
ls "$app"/swiftCore.dll >/dev/null 2>&1 || die "swiftCore.dll was not found among the program's imports; see $out/imports.txt"

# The starter: Windows' kernel32 only, no C runtime (launcher.c says why). The linker options are spelled with a
# dash so that Git Bash does not take them for paths.
clang -O1 -ffreestanding -fno-builtin -fno-stack-protector -nostdlib -Wall \
    -o "$root/Make Crate File.exe" "$here/launcher.c" \
    -Xlinker -entry:entry -Xlinker -subsystem:console -Xlinker -nodefaultlib -lkernel32
rm -f "$root/Make Crate File.lib" "$root/Make Crate File.exp"

# The words, with Windows line endings so every Notepad shows them as written.
sed 's/\r$//; s/$/\r/' "$here/READ ME FIRST.txt" > "$root/READ ME FIRST.txt"

# Licences and acknowledgements (DEPENDENCIES.md, section 3 and the table at its top).
lic="$app/licences"
cp "$repo/DEPENDENCIES.md" "$lic/DEPENDENCIES.md"
cp "$core/notices/swift/swift-LICENSE.txt" "$core/notices/swift/swift-foundation-LICENSE.md" \
   "$core/notices/swift/swift-corelibs-foundation-and-libdispatch-LICENSE.txt" "$core/notices/swift/ICU-76.1-LICENSE.txt" "$lic/"
cp "$ort/LICENSE" "$lic/onnxruntime-LICENSE.txt"
cp "$ort/ThirdPartyNotices.txt" "$lic/onnxruntime-ThirdPartyNotices.txt"
mkdir -p "$lic/eigen-patches"
cp "$core/notices/eigen/"* "$lic/eigen-patches/"
"$py" - "$core/dependencies.json" > "$lic/ACKNOWLEDGEMENTS.txt" <<'PY'
import json, sys
entries = json.load(open(sys.argv[1], encoding="utf-8"))["entries"]
print("Deckie for PC: acknowledgements")
print("===============================")
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
print("Not in this folder: Microsoft's Visual C++ runtime, which Windows or another program")
print("provides on most PCs.")
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
    echo "Of those, MSVCP140.dll, MSVCP140_1.dll, VCRUNTIME140.dll and VCRUNTIME140_1.dll are Microsoft's Visual C++"
    echo "runtime, which is not part of every Windows; names that start with api-ms-win-crt are Windows 10 and 11's own"
    echo "C runtime; the rest are parts of every Windows."
} > "$lic/FILES.txt"

# The zip (compressed, for the download; nothing to do with the crate file's own uncompressed form).
zip="$out/Deckie-for-PC-first-test.zip"
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
    echo "| The program | \`app/deckie-make.exe\`, $(wc -c < "$app/deckie-make.exe") bytes |"
    echo "| The starter | \`Make Crate File.exe\`, $(wc -c < "$root/Make Crate File.exe") bytes |"
    echo "| Swift runtime libraries copied | $(grep -c '^copy ' "$out/imports.txt"): $(grep '^copy ' "$out/imports.txt" | sed 's/.*[\\/]//' | tr '\n' ' ') |"
    echo "| Expected from Windows | $(grep '^system ' "$out/imports.txt" | sed 's/^system //' | tr '\n' ' ') |"
} > "$out/package-report.md"
cat "$out/package-report.md"
