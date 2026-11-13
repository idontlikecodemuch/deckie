#!/usr/bin/env python3
"""Fetches the outside material for the recognition benchmark into a folder OUTSIDE the repository.

Nothing fetched here is ever committed (the repository is public): only this script and the list of what it took
(sources.tsv, written next to the data and copied into the research letter as a table of sources, licences and sizes).

What it fetches:
  songs/   full-length songs from the Internet Archive's netlabels collection, each under the Creative Commons
           licence its release states (kept per file in sources.tsv). Two buckets by the release's own subject tags:
           dance (techno, house, drum and bass, trance, electro, breakbeat, minimal, disco) and other.
  gsplus/  GiantSteps+ EDM Key Dataset audio (Zenodo 1095691): 600 two-minute dance excerpts. Annotations CC BY-SA
           4.0; the audio is commercial previews, used here for internal evaluation only (as letter R did).
  rir/     room impulse responses: OpenSLR 28 (RIRS_NOISES, Apache 2.0), the real rooms only.
  noise/   DEMAND (Zenodo 1227121, CC BY 4.0): the cafeteria, restaurant and station recordings, 16 kHz.

Usage: fetch_data.py DATA_DIR [--dance 320] [--other 160] [--skip-gsplus]
"""
import argparse, concurrent.futures as cf, hashlib, json, os, random, subprocess, sys, time, urllib.parse, urllib.request, zipfile

UA = {"User-Agent": "recognition-benchmark/1.0 (research; polite; 4 connections)"}
DANCE = '(techno OR house OR "drum and bass" OR dnb OR trance OR electro OR breakbeat OR minimal OR disco OR "tech house")'
OTHER = '(rock OR "hip hop" OR hiphop OR jazz OR folk OR pop OR reggae OR punk OR indie OR funk OR soul OR metal)'


def get(url, tries=4):
    for i in range(tries):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60) as r:
                return r.read()
        except Exception as e:  # noqa
            if i == tries - 1:
                raise
            time.sleep(2 * (i + 1))


def download(url, path, tries=12):
    if os.path.exists(path) and os.path.getsize(path) > 0:
        return
    tmp = path + ".part"
    for i in range(tries):
        # -C -: carry on from where a broken transfer stopped.
        r = subprocess.run(["curl", "-sSL", "--fail", "-m", "3600", "-C", "-", "-A", UA["User-Agent"], "-o", tmp, url])
        if r.returncode == 0:
            os.replace(tmp, path)
            return
        time.sleep(3 * (i + 1))
    raise RuntimeError("could not fetch " + url)


def search(query, rows, page):
    q = urllib.parse.urlencode({"q": query, "fl[]": "identifier", "rows": rows, "page": page, "output": "json",
                                "sort[]": "identifier asc"})
    return [d["identifier"] for d in json.loads(get("https://archive.org/advancedsearch.php?" + q))["response"]["docs"]]


def pick_song(identifier, rng):
    """One MP3 of 3 to 9 minutes from a release, or None. One song per release keeps the set varied."""
    try:
        meta = json.loads(get("https://archive.org/metadata/" + identifier))
    except Exception:
        return None
    lic = meta.get("metadata", {}).get("licenseurl", "")
    if "creativecommons.org" not in lic:
        return None
    files = []
    for f in meta.get("files", []):
        if not f.get("name", "").lower().endswith(".mp3") or f.get("source") != "original":
            continue
        try:
            length = f.get("length", "0")
            secs = float(length) if ":" not in length else sum(float(x) * 60 ** i for i, x in enumerate(reversed(length.split(":"))))
            size = int(f.get("size", 0))
        except ValueError:
            continue
        if 180 <= secs <= 540 and size < 25_000_000:
            files.append((f["name"], secs, size))
    if not files:
        return None
    name, secs, size = rng.choice(sorted(files))
    subj = meta["metadata"].get("subject", "")
    return {"identifier": identifier, "file": name, "seconds": secs, "bytes": size, "licence": lic,
            "subject": "; ".join(subj) if isinstance(subj, list) else subj}


def fetch_songs(data, bucket, query, want, seed):
    rng = random.Random(seed)
    out = os.path.join(data, "songs", bucket)
    os.makedirs(out, exist_ok=True)
    listing = os.path.join(data, f"songs_{bucket}.json")
    got = json.load(open(listing)) if os.path.exists(listing) else []
    seen = {g["identifier"] for g in got}
    # Pages spread across the whole result list (sorted by identifier), so no one label dominates.
    pages = list(range(1, 60))
    rng.shuffle(pages)
    for page in pages:
        if len(got) >= want:
            break
        try:
            ids = [i for i in search(f"collection:netlabels AND mediatype:audio AND subject:{query} AND licenseurl:*creativecommons*", 100, page) if i not in seen]
        except Exception as e:
            print("search failed", e, file=sys.stderr)
            continue
        rng.shuffle(ids)
        ids = ids[:25]  # at most 25 releases from one stretch of the alphabet
        with cf.ThreadPoolExecutor(4) as ex:
            picks = [p for p in ex.map(lambda i: pick_song(i, random.Random(seed + hash(i) % 1000)), ids) if p]

        def grab(p):
            ident = p["identifier"]
            p["id"] = bucket[0] + hashlib.sha1(ident.encode()).hexdigest()[:10]
            path = os.path.join(out, p["id"] + ".mp3")
            try:
                download(f"https://archive.org/download/{urllib.parse.quote(ident)}/{urllib.parse.quote(p['file'])}", path)
                return p
            except Exception as e:
                print("skip", ident, e, file=sys.stderr)
                return None
        with cf.ThreadPoolExecutor(4) as ex:
            for p in ex.map(grab, picks):
                if p and len(got) < want:
                    got.append(p); seen.add(p["identifier"])
        json.dump(got, open(listing, "w"), indent=1)
        print(bucket, len(got), "of", want, flush=True)
    return got


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("data")
    ap.add_argument("--dance", type=int, default=320)
    ap.add_argument("--other", type=int, default=160)
    ap.add_argument("--skip-gsplus", action="store_true")
    ap.add_argument("--part", choices=["small", "songs", "gsplus"], help="fetch one part only (the parts can run side by side)")
    a = ap.parse_args()
    data = a.data
    os.makedirs(data, exist_ok=True)

    if a.part in (None, "small"):
        fetch_small(data)
    if a.part in (None, "songs"):
        fetch_songs(data, "dance", DANCE, a.dance, 1)
        fetch_songs(data, "other", f"{OTHER} AND NOT subject:{DANCE}", a.other, 2)
    if a.part in (None, "gsplus") and not a.skip_gsplus:
        os.makedirs(os.path.join(data, "gsplus"), exist_ok=True)
        z = os.path.join(data, "gsplus", "audio.zip")
        if not os.path.isdir(os.path.join(data, "gsplus", "audio")):
            download("https://zenodo.org/records/1095691/files/audio.zip?download=1", z)
            zipfile.ZipFile(z).extractall(os.path.join(data, "gsplus"))
            os.remove(z)
    print("fetched", a.part or "all", flush=True)


def fetch_small(data):
    os.makedirs(os.path.join(data, "noise"), exist_ok=True)
    for name in ["PCAFETER_16k", "PRESTO_16k", "PSTATION_16k"]:
        z = os.path.join(data, "noise", name + ".zip")
        download(f"https://zenodo.org/records/1227121/files/{name}.zip?download=1", z)
        if not os.path.isdir(os.path.join(data, "noise", name.split("_")[0])):
            zipfile.ZipFile(z).extractall(os.path.join(data, "noise"))
    os.makedirs(os.path.join(data, "rir"), exist_ok=True)
    z = os.path.join(data, "rir", "rirs_noises.zip")
    if not os.path.isdir(os.path.join(data, "rir", "RIRS_NOISES")):
        download("https://www.openslr.org/resources/28/rirs_noises.zip", z)
        with zipfile.ZipFile(z) as zf:
            zf.extractall(os.path.join(data, "rir"), [n for n in zf.namelist() if "real_rirs_isotropic_noises" in n and n.endswith((".wav", ".txt", "rir_list"))])
        os.remove(z)
    print("rir and noise ready", flush=True)


if __name__ == "__main__":
    main()
