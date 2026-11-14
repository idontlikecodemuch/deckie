#!/usr/bin/env bash
# icon.sh: Deckie's icon for Windows, ready to be linked into the programs.
#
#   bash core/Tools/windows/icon.sh <output folder>
#
# Run in Git Bash on a Windows machine with the Swift toolchain (or on Linux with llvm-rc, to try it). It downloads
# nothing. It makes, in <output folder>:
#   deckie.ico    the icon file, from the iPad app's picture (deck-app/.../AppIcon.appiconset/icon1024.png) by
#                 make_ico.py: 16, 20, 24, 32, 40, 48, 64 and 256 pixels, corners rounded as site/icon.svg has them
#   desk.res      the icon and the program's description ("Deckie Desk") as a compiled resource file, the form a
#                 linker takes, for "Deckie Desk.exe" and deckie-desk.exe
#   make.res      the same for "Make Crate File.exe"
# No .ico is committed: it is made here each time. A resource file is made by a resource compiler: llvm-rc when the
# toolchain on PATH has one, else Microsoft's rc.exe from the Windows SDK the Swift toolchain needs anyway.
#
# The resource number of the icon is 1: Windows shows a program's lowest-numbered icon in Explorer, and the shell
# loads number 1 for its window (desk-shell/Sources/CDeskShell/deskshell.cc).

if [ -z "${BASH_VERSION:-}" ]; then echo "icon.sh: run this with bash" >&2; exit 1; fi
set -euo pipefail
die() { printf 'icon.sh: %s\n' "$*" >&2; exit 1; }

[ $# -eq 1 ] || die "usage: icon.sh <output folder>"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
core="$(cd "$here/../.." && pwd)"
repo="$(cd "$core/.." && pwd)"
mkdir -p "$1"
out="$(cd "$1" && pwd)"
py="$(command -v python || command -v python3)" || die "needs Python"
picture="$repo/deck-app/Deck/Assets.xcassets/AppIcon.appiconset/icon1024.png"
[ -f "$picture" ] || die "the app's icon picture is not at $picture"

"$py" "$here/make_ico.py" "$picture" "$out/deckie.ico"

# The version shown in a program's Properties: the PC program's own (core/Sources/DeckiePC/PCBuild.swift).
version="$(sed -n 's/.*public static let version = "\([0-9][0-9.]*\)".*/\1/p' "$core/Sources/DeckiePC/PCBuild.swift" | head -1)"
[ -n "$version" ] || die "could not read the version from PCBuild.swift"
commas="$(printf '%s' "$version" | tr '.' ','),0"

# A resource script: the icon as number 1, and the few words Windows shows about a program (Task Manager and the
# file's Properties show the description). Numbers, not names, so no Windows header is needed to read it.
script() {   # script <file> <description> <program file name>
    cat > "$1" <<RC
1 ICON "deckie.ico"

1 VERSIONINFO
FILEVERSION $commas
PRODUCTVERSION $commas
FILEFLAGSMASK 0x3fL
FILEFLAGS 0x0L
FILEOS 0x40004L
FILETYPE 0x1L
FILESUBTYPE 0x0L
BEGIN
    BLOCK "StringFileInfo"
    BEGIN
        BLOCK "040904b0"
        BEGIN
            VALUE "FileDescription", "$2"
            VALUE "FileVersion", "$version"
            VALUE "InternalName", "$3"
            VALUE "OriginalFilename", "$3"
            VALUE "ProductName", "Deckie"
            VALUE "ProductVersion", "$version (first test)"
        END
    END
    BLOCK "VarFileInfo"
    BEGIN
        VALUE "Translation", 0x409, 1200
    END
END
RC
}
script "$out/desk.rc" "Deckie Desk" "Deckie Desk.exe"
script "$out/make.rc" "Deckie: make crate file" "Make Crate File.exe"

# The resource compiler. Options are spelled with a dash so that Git Bash does not take them for paths.
compile() {   # compile <name>: <name>.rc to <name>.res, run in the output folder so the script finds deckie.ico
    if command -v llvm-rc >/dev/null 2>&1; then
        (cd "$out" && llvm-rc -no-preprocess -fo "$1.res" "$1.rc")
    else
        local rc=""
        for kits in "/c/Program Files (x86)/Windows Kits/10/bin" "/c/Program Files/Windows Kits/10/bin"; do
            [ -d "$kits" ] || continue
            rc="$(ls -d "$kits"/*/x64/rc.exe 2>/dev/null | sort -V | tail -1)"
            [ -n "$rc" ] && break
        done
        [ -n "$rc" ] || die "no resource compiler: neither llvm-rc on PATH nor rc.exe in the Windows SDK"
        (cd "$out" && "$rc" -nologo -fo "$1.res" "$1.rc")
    fi
    [ -s "$out/$1.res" ] || die "the resource compiler wrote no $1.res"
}
compile desk
compile make
if command -v llvm-rc >/dev/null 2>&1; then echo "icon.sh: compiled with llvm-rc"; else echo "icon.sh: compiled with rc.exe"; fi
ls -l "$out"
