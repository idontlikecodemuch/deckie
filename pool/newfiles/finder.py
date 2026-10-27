import os, re, unicodedata
ROOT = '/Users/christophershannon/personal/90s2000 playlist'
F = {
 "COLL": "dance-hits-collection-90th-1990-2000_20230206",
 "SUB":  "dance-hits-collection-90th-1990-2000_20230206/Dance Hits Collection 90th (1990-2000)",
 "90S":  "Various Artists - 90s HITS 100 Greatest Songs of the 1990s (2023) Mp3 320kbps [PMEDIA] ⭐️",
 "F90":  "VA - NOW That's What I Call Music Forever 90s (2020) Mp3 320kbps [PMEDIA] ⭐️",
 "E90":  "VA - Ministry Of Sound Anthems Electronic 90S (2019) Mp3 (320 kbps) [Hunter]",
 "00D":  "VA - 2000s Dance Party Essentials (2021) Mp3 320kbps [PMEDIA] ⭐️",
 "00G":  "Various Artists - 00s music greatest hits (2024) Mp3 320kbps [PMEDIA] ⭐️",
 "10D":  "VA - 2010s Dance Party Essentials (2021) Mp3 320kbps [PMEDIA] ⭐️",
 "HAL":  "VA - NOW That's What I Call Halloween (2020) Mp3 320kbps [PMEDIA] ⭐️",
 "PCA":  "PARTY CD'S/HALLOWEEN PARTY ADULT", "PCK": "PARTY CD'S/HALLOWEEN PARTY KIDS", "PCM": "PARTY CD'S/HALLOWEEN PARTY MIXED",
 "TOP":  ".",
 "MAY":  "Lady Gaga - MAYHEM (2025) Mp3 320kbps [PMEDIA] ⭐️",
 "SCA":  "Doja Cat - Scarlet (2023) Mp3 320kbps [PMEDIA] ⭐️",
 "ROB":  "ROBYN - DISCOGRAPHY (1997-14) [CHANNEL NEO]",
 "SP":   "NOW That's What I Call A Summer Party (2024) Mp3 320kbps [PMEDIA] ⭐️",
}

def find(key, match):
    base = os.path.join(ROOT, F[key])
    if key == "E90":
        d, n = match.split("/"); n = n.rstrip(".")
        pat = re.compile(rf"Disc {d}/{n}\.(?!\d)")
        hits = [os.path.join(dp, f) for dp, _, fs in os.walk(base) for f in fs if pat.search(os.path.relpath(os.path.join(dp, f), base)) and f.lower().endswith(".mp3")]
    elif key in ("ROB", "SP"):
        hits = [os.path.join(dp, f) for dp, _, fs in os.walk(base) for f in fs if f.lower().endswith(".mp3") and match.lower() in os.path.relpath(os.path.join(dp, f), base).lower()]
    elif key == "TOP":
        hits = [os.path.join(base, f) for f in os.listdir(base) if match.lower() in f.lower() and f.lower().endswith(".mp3")]
        exact = [h for h in hits if os.path.basename(h).lower() == match.lower() + ".mp3"]
        hits = exact or hits
    elif key in ("PCA", "PCK", "PCM"):
        hits = [os.path.join(base, f) for f in os.listdir(base) if match.lower() in f.lower() and f.lower().endswith(".mp3")]
    else:
        hits = [os.path.join(base, f) for f in os.listdir(base) if f.startswith(match) and f.lower().endswith(".mp3")]
    assert len(hits) == 1, f"{key} {match!r}: {len(hits)} hits {hits[:3]}"
    return hits[0]


def safe(name):
    n = unicodedata.normalize("NFKD", name).encode("ascii", "ignore").decode()
    n = re.sub(r'[/\\:*?"<>|!]', "", n).replace("&", "and")
    n = re.sub(r"\s+", " ", n).strip()
    if len(n) > 56:
        n2 = re.sub(r"\s*\(.*?\)", "", n).strip()
        n = n2 if 10 < len(n2) <= 56 else n[:56].rstrip(" -")
    return n
