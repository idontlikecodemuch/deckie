#!/usr/bin/env python3
"""pe_imports.py: which library files (DLLs) a Windows program needs, read from the program file itself.

    python pe_imports.py <file.exe or .dll> ...          prints each file's imports, one per line
    python pe_imports.py --closure <dir> <file> ...      the files, and every DLL found in <dir> (several --closure
                                                         allowed) that they need, and those need, and so on; prints
                                                         "copy <path>" for each such DLL and "system <name>" for
                                                         every DLL that must come from Windows itself

A Windows program file (the "PE" format) lists the DLLs it loads when it starts in its import table, and those it
loads on first use in its delay-import table; both are read here. Python's standard library only. package.sh uses it
to copy exactly the Swift runtime libraries the program needs, and to write down what is expected from Windows.
"""
import os
import struct
import sys


def imports(path):
    data = open(path, "rb").read()
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    if data[pe:pe + 4] != b"PE\0\0":
        raise ValueError(f"{path} is not a Windows program file")
    sections_count = struct.unpack_from("<H", data, pe + 6)[0]
    optional_size = struct.unpack_from("<H", data, pe + 20)[0]
    optional = pe + 24
    magic = struct.unpack_from("<H", data, optional)[0]
    directories = optional + (112 if magic == 0x20B else 96)
    sections = []
    at = optional + optional_size
    for _ in range(sections_count):
        vsize, vaddr, rsize, raw = struct.unpack_from("<IIII", data, at + 8)
        sections.append((vaddr, max(vsize, rsize), raw))
        at += 40

    def offset(rva):
        for vaddr, size, raw in sections:
            if vaddr <= rva < vaddr + size:
                return raw + rva - vaddr
        return None

    def name_at(rva):
        o = offset(rva)
        if o is None:
            return None
        return data[o:data.index(b"\0", o)].decode("ascii", "replace")

    names = []
    # Directory 1: imports (20-byte entries, the name's address at +12). Directory 13: delay imports (32-byte
    # entries, the name's address at +4).
    for index, size, name_field in ((1, 20, 12), (13, 32, 4)):
        rva = struct.unpack_from("<I", data, directories + 8 * index)[0]
        o = offset(rva) if rva else None
        while o is not None and o + size <= len(data):
            entry = data[o:o + size]
            if entry == b"\0" * size:
                break
            name = name_at(struct.unpack_from("<I", entry, name_field)[0])
            if name:
                names.append(name)
            o += size
    return names


def main():
    args = sys.argv[1:]
    folders = []
    while args and args[0] == "--closure":
        folders.append(args[1])
        args = args[2:]
    if not args:
        sys.exit(__doc__)
    if not folders:
        for path in args:
            for name in imports(path):
                print(f"{os.path.basename(path)}: {name}")
        return
    available = {}
    for folder in folders:
        for name in os.listdir(folder):
            if name.lower().endswith(".dll"):
                available.setdefault(name.lower(), os.path.join(folder, name))
    given = {os.path.basename(p).lower() for p in args}
    queue = list(args)
    copy, system = {}, set()
    while queue:
        for name in imports(queue.pop()):
            key = name.lower()
            if key in given or key in copy:
                continue
            if key in available:
                copy[key] = available[key]
                queue.append(available[key])
            else:
                system.add(name)
    for key in sorted(copy):
        print(f"copy {copy[key]}")
    for name in sorted(system, key=str.lower):
        print(f"system {name}")


if __name__ == "__main__":
    main()
