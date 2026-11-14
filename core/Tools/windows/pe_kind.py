#!/usr/bin/env python3
"""pe_kind.py: whether a Windows program opens a console window, and whether it carries an icon; and a way to set
the first.

    python pe_kind.py <file.exe> ...                 prints, for each: its name, "window" or "console", and
                                                     "icon" or "no-icon"
    python pe_kind.py --set window <file.exe> ...    marks each program as one that opens no console window
    python pe_kind.py --set console <file.exe> ...   the opposite

A Windows program file (the "PE" format) says in one two-byte field of its header, the "subsystem", what Windows
should give it when it starts: 3 means a console (the black text window; Windows opens one if the program was not
started from one), 2 means none, which is what a program with a window of its own wants. Nothing else in the file
differs for programs like Deckie's, so the field can be set after the program is built; Microsoft's own `editbin
/SUBSYSTEM` does the same. package.sh uses this for the copies of `deckie-desk.exe` and `deckie-desk-engine.exe`
that go into the zip (the builds the tests use stay console programs, so their messages show), and the workflow uses
it to check every program in the zip.

The icon: a program's icon is a resource of the kind "group icon" (number 14) in its resource table; this only says
whether one is there. Python's standard library only.
"""
import os
import struct
import sys

NAMES = {2: "window", 3: "console"}


def layout(data, path):
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    if data[:2] != b"MZ" or data[pe:pe + 4] != b"PE\0\0":
        raise SystemExit(f"pe_kind: {path} is not a Windows program file")
    optional = pe + 24
    magic = struct.unpack_from("<H", data, optional)[0]
    if magic not in (0x10B, 0x20B):
        raise SystemExit(f"pe_kind: {path} has a header this does not know")
    return pe, optional, magic


def has_icon(data, pe, optional, magic):
    directories = optional + (112 if magic == 0x20B else 96)
    rva = struct.unpack_from("<I", data, directories + 8 * 2)[0]      # directory 2: resources
    if not rva:
        return False
    sections_count = struct.unpack_from("<H", data, pe + 6)[0]
    at = optional + struct.unpack_from("<H", data, pe + 20)[0]
    start = None
    for _ in range(sections_count):
        vsize, vaddr, rsize, raw = struct.unpack_from("<IIII", data, at + 8)
        if vaddr <= rva < vaddr + max(vsize, rsize):
            start = raw + rva - vaddr
        at += 40
    if start is None:
        return False
    named, numbered = struct.unpack_from("<HH", data, start + 12)
    for i in range(named + numbered):
        kind = struct.unpack_from("<I", data, start + 16 + 8 * i)[0]
        if kind == 14:                                               # RT_GROUP_ICON
            return True
    return False


def main():
    args = sys.argv[1:]
    want = None
    if args[:1] == ["--set"]:
        if len(args) < 3 or args[1] not in ("window", "console"):
            sys.exit(__doc__)
        want = 2 if args[1] == "window" else 3
        args = args[2:]
    if not args:
        sys.exit(__doc__)
    for path in args:
        data = bytearray(open(path, "rb").read())
        pe, optional, magic = layout(data, path)
        field = optional + 68
        now = struct.unpack_from("<H", data, field)[0]
        if want is not None and now != want:
            if now not in NAMES:
                raise SystemExit(f"pe_kind: {path} is neither a window nor a console program (subsystem {now})")
            struct.pack_into("<H", data, field, want)
            open(path, "wb").write(data)
            now = want
        print(f"{os.path.basename(path)}: {NAMES.get(now, 'subsystem ' + str(now))} "
              f"{'icon' if has_icon(data, pe, optional, magic) else 'no-icon'}")


if __name__ == "__main__":
    main()
