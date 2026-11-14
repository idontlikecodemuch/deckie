#!/usr/bin/env python3
"""Read single members of a large zip over HTTP range requests, so a few gigabytes of a data set need not be fetched
to use a part of it. Standard library only (urllib, zlib, struct); handles zip64."""
import struct, zlib, urllib.request, time

class RemoteZip:
    def __init__(self, url):
        self.url = url
        req = urllib.request.Request(url, method="HEAD")
        with urllib.request.urlopen(req) as r: self.size = int(r.headers["Content-Length"]); self.url = r.geturl()
        tail = self._get(max(0, self.size - 70000), self.size - 1)
        i = tail.rfind(b"PK\x05\x06"); n, cd_size, cd_off = struct.unpack("<HII", tail[i + 10:i + 20])
        if cd_off == 0xFFFFFFFF or cd_size == 0xFFFFFFFF or n == 0xFFFF:
            j = tail.rfind(b"PK\x06\x06"); n, cd_size, cd_off = struct.unpack("<QQQ", tail[j + 32:j + 56])
        cd = self._get(cd_off, cd_off + cd_size - 1); self.members = {}; p = 0
        while p < len(cd) and cd[p:p + 4] == b"PK\x01\x02":
            method, = struct.unpack("<H", cd[p + 10:p + 12])
            csize, usize, nl, el, cl = struct.unpack("<IIHHH", cd[p + 20:p + 34]); off, = struct.unpack("<I", cd[p + 42:p + 46])
            name = cd[p + 46:p + 46 + nl].decode("utf-8", "replace"); extra = cd[p + 46 + nl:p + 46 + nl + el]; q = 0
            while q + 4 <= len(extra):
                hid, hl = struct.unpack("<HH", extra[q:q + 4]); body = extra[q + 4:q + 4 + hl]
                if hid == 1:
                    b = 0
                    if usize == 0xFFFFFFFF: usize, = struct.unpack("<Q", body[b:b + 8]); b += 8
                    if csize == 0xFFFFFFFF: csize, = struct.unpack("<Q", body[b:b + 8]); b += 8
                    if off == 0xFFFFFFFF: off, = struct.unpack("<Q", body[b:b + 8]); b += 8
                q += 4 + hl
            self.members[name] = (off, csize, usize, method); p += 46 + nl + el + cl

    def _get(self, a, b, tries=5):
        for k in range(tries):
            try:
                req = urllib.request.Request(self.url, headers={"Range": f"bytes={a}-{b}"})
                with urllib.request.urlopen(req, timeout=120) as r: return r.read()
            except Exception:
                if k == tries - 1: raise
                time.sleep(2 * (k + 1))

    def read(self, name):
        off, csize, usize, method = self.members[name]
        head = self._get(off, off + 29); nl, el = struct.unpack("<HH", head[26:30])
        data = self._get(off + 30 + nl + el, off + 30 + nl + el + csize - 1) if csize else b""
        return data if method == 0 else zlib.decompress(data, -15)
