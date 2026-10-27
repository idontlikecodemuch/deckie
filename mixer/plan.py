"""Mix planner (research.md E.4): three ~60-minute climbing sets from the pairs graph.

Usage:  .venv/bin/python -I plan.py [--beam 160] [--hours 1,2,3]
Writes plan_1.json, plan_2.json, plan_3.json (hand-editable) and prints the tracklists.

Each hour: ~87 BPM -> ~127 BPM in three stages (hip-hop/R&B, pop/disco, dance), 4-6 Halloween
songs sprinkled across stages, beam search over directed joins (pairs.json score, or a cut when
no pair exists / an end has no trustworthy beat).  Hours are planned in order 1, 2, 3 and never
share a song.
"""
import argparse, copy, json, math, os, re, sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
SR = 44100
HOUR_S = 3600.0
PLAY_MIN, PLAY_MAX = 150.0, 215.0
HAL_MIN, HAL_MAX = 4, 6
HH_PLAY = (55.0, 95.0)      # hip-hop stretch: one verse and a hook, 60-90 s
BRIDGE_ID = "bb5a733550"    # Get Ur Freak On, Bizzon Halloween theme 70->90 transition
CO_PLAY = (85.0, 125.0)     # callouts: 1.5 - 2 minutes    # hip-hop stage: shorter plays, cut on phrase boundaries     # target seconds from cue-in to exit (natural play allowed up to PLAY_MAX)

HOURS = {
    1: {"name": "Graveyard Shift", "lean": "spooky", "hal_target": 6},
    2: {"name": "Haunted Block Party", "lean": "hiphop", "hal_target": 5},
    3: {"name": "Mirrorball Massacre", "lean": "disco", "hal_target": 5},
}

# tempo arc: (fraction of hour, target BPM)
ARC = [(0.0, 87.0), (0.30, 98.0), (0.36, 103.0), (0.64, 116.0), (0.70, 120.0), (0.90, 126.0), (1.0, 127.5)]

HIPHOP = ["50 cent", "snoop", "kanye", "notorious", "missy", "ying yang", "warren g", "coolio", "blackstreet",
          "tlc", "ginuwine", "usher", "ciara", "sexyy red", "drake", "jeremih", "tag team", "sir mix", "ol' dirty",
          "kris kross", "will smith", "jazzy jeff", "montell jordan", "mark morrison", "next", "amerie", "sisqo",
          "bell biv devoe", "shaggy", "sean paul", "cardi b", "doja cat", "destiny's child", "beyonce", "m.i.a.",
          "fugees", "pretty ricky", "outkast", "pharrell", "sza", "mariah carey", "kelis", "estelle", "rihanna",
          "flo rida", "sugababes", "lil' kim", "gnarls", "bow wow"]
HIPHOP_EXACT = {"nelly"}
DISCO = ["trammps", "rick james", "bucketheads", "moloko", "cher", "ultra nate", "robin s", "cece peniston",
         "livin' joy", "junior senior", "justin timberlake", "dua lipa", "kylie", "the weeknd", "daft punk",
         "mark ronson", "bruno mars", "lizzo", "take that", "dead or alive", "stevie wonder", "roger sanchez",
         "royksopp", "jungle", "c+c music factory", "the source", "adamski", "sonique", "gala",
         "armand van helden", "the beloved", "robyn", "lady gaga & ariana", "bee gees", "shania", "spice girls",
         "ida corr", "michael jackson", "technotronic", "hardrive", "david morales", "basement jaxx"]


def interp_arc(f):
    f = max(0.0, min(1.0, f))
    for (f0, b0), (f1, b1) in zip(ARC, ARC[1:]):
        if f <= f1:
            return b0 + (b1 - b0) * (f - f0) / (f1 - f0)
    return ARC[-1][1]


def stage_of(f):
    return 1 if f < 0.33 else (2 if f < 0.67 else 3)


def norm(s):
    s = s.lower()
    s = re.sub(r"\(.*?\)|\[.*?\]", "", s)
    s = re.sub(r"[^a-z0-9 ]+", " ", s)
    return re.sub(r"\s+", " ", s).strip()


def artist_tokens(a):
    a = a.lower()
    parts = re.split(r"\s*(?:&|,|\bfeat\.?|\bft\.?|\bvs\.?|\bx\b|\band\b|\bwith\b)\s*", a)
    return {norm(p) for p in parts if norm(p)}


SONG_ALIASES = {  # covers / remakes treated as the same song
    norm("Somebody's Watching Me"): "somebodys watching me",
    norm("Zombie"): "zombie",
}


DIFFERENT_SONGS = {"show me love", "demons"}

# ---- Chris's picks (Oct 24 evening): must-includes pre-assigned to a mix, explicit exclusions
# role: "block" = hip-hop quick-mix stretch, "flow" = dance flow, "callout" = drop-out moment
MUST = {
    # mix 1: Haunted Disco (disco-house, pop remixes, Rihanna)
    "bb5a733550": (1, "block"),    # Missy Elliott - Get Ur Freak On (Bizzon Halloween 70-90 transition): stretch entry
    "0a18673b0a": (1, "block"),    # 50 Cent - Just a Lil Bit (Bizzon club edit)
    "1cc5eb759e": (1, "block"),    # Mark Morrison - Return Of The Mack (Tall Boys Intro, off-disc copy)
    "0589898af7": (1, "block"),    # Sexyy Red & Bruno Mars - Fat Juicy & Wet (Intro)
    "065cf3ba0b": (1, "flow"),     # Kelis - Milkshake 20 (Alex Wann)
    "08d9f8922e": (1, "flow"),     # Montell Jordan - This Is How We Do It (Mahalo rework, short)
    "d403e8c7da": (1, "flow"),     # Chappell Roan - Pink Pony Club (Lincoln Baio)
    "cb633f2e6c": (1, "flow"),     # Slayyyter - Brand New Chanel$ (named by Chris)
    "da6e2527c5": (1, "flow"),     # Nelly Furtado - Maneater (Monaark)
    "c4de511f7a": (1, "flow"),     # Sam Smith & Kim Petras - Unholy
    "cb4f2a019f": (1, "flow"),     # Rihanna - Don't Stop The Music (Colin Jay)
    "a842ca9e48": (1, "flow"),     # Sam Robs & Kelvin Wood - No Scrubs (house cover, short)
    "e47c8f44a8": (1, "flow"),     # Chris Lorenzo & Kah-Lo vs Black Eyed Peas - In This Bih (MarkCutz)
    "08e45fb8ca": (1, "callout"),  # Drake - Rich Baby Daddy (Gilla Million Dollar Baby edit)
    "f068a57770": (1, "callout"),  # Doja Cat - Demons (Epiphany flip)
    # mix 2: Witching Hour Warehouse (harder house, Halloween)
    "03d09d5c4c": (2, "block"),    # Blackstreet - No Diggity (Tall Boys)
    "310b6d0f81": (2, "block"),    # Jeremih - Don't Tell 'Em (Sir Marcus & Kareem)
    "e0fc19ea05": (2, "block"),    # Jungle - PROBLEMZ
    "dbc03c2426": (2, "flow"),     # KATSEYE - GNARLY
    "a67262ebf4": (2, "flow"),     # Fcukers - If You Wanna Party
    "79e7a45d90": (2, "flow"),     # LCD Soundsystem - Daft Punk Is Playing At My House
    "da6de0ce27": (2, "flow"),     # Tiesto & Sexyy Red - OMG
    "15e073a272": (2, "flow"),     # Rihanna - Disturbia (DJ Mag Halloween)
    "a346c5561c": (2, "flow"),     # Disco Lines & Tinashe - No Broke Boys (Dirty)
    "ec7890a2d4": (2, "flow"),     # Missy Elliott - Lose Control (Matthew Topper edit)
    "10f0cba926": (2, "callout"),  # Cardi B - WAP (Lincoln Baio Addams Family intro)
    "a04a0734d0": (2, "callout"),  # Flo Rida - Low (URAI)
    "bedd2ea40c": (2, "flow"),     # Kate Bush - Running Up That Hill (Landis): Chris is keeping it
    "0a50f2d79d": (1, "flow"),     # Disco Lines - Got To Do (Extended Mix), new disco house
    "457ed7c7b3": (2, "flow"),     # Oliver Heldens & Will Clarke - Lost In Music (Extended Mix), new disco house
}
# every song heard in the approved transition sampler stays in its mix (written once from the sampler)
_keep = os.path.join(os.path.dirname(os.path.abspath(__file__)), "keep_from_sampler.json")
if os.path.exists(_keep):
    for _id, (_m, _role, _t) in json.load(open(_keep)).items():
        MUST.setdefault(_id, (_m, _role))
EXCLUDE = {
    "366dc91024", "58176232a3", "5f78386ecd",        # Kate Bush Landis, Von Dutch x2, Cotton Eye Joe
    "6825448b0d", "ddaf27d9d7", "d8be9bfa4a",                      # other Return Of The Mack cuts
    "f41f1882ae",                                                   # DSTM Spryte (Colin Jay stays)
    "e46b81e5ab", "a744522f06", "e4d28920f3",                      # other Pink Pony / This Is How We Do It cuts
    "2c4bc602dc", "25c6363ebc",                                     # other No Diggity cuts
    "2991758f7f", "9546dd7347",                                     # other No Scrubs cuts
    "c73652b55e", "4098d0dece", "dcdda93217", "769c06bf8e",        # Milkshake orig, Doja Demons others, Flo Rida orig
    "5dc4f57039", "d6f9615a5b", "52922e91bc", "68fc2caf28",        # other No Broke Boys, Disturbia orig, Maneater Rogerson
    "2eb22eadd0", "e8c9259c3c", "900b47e703",                      # Rich Baby Daddy intro, GUFO orig, Lose Control rip
}
NAMED_ON_DISC = {i for i in MUST}


def flavour(r, bpm):
    a = (r.get("artist") or r["title"].split(" - ")[0]).lower()
    kind = r["kind"]
    if kind == "ambient":
        return "ambient"
    toks = artist_tokens(a)
    if any(h in a for h in HIPHOP) or toks & HIPHOP_EXACT or kind == "slow / R&B":
        return "hiphop"
    if any(d in a for d in DISCO) or "disco" in r["title"].lower():
        return "disco"
    if kind in ("dance original", "official remix", "pool edit", "rip") and bpm >= 115:
        return "dance"
    return "pop"


class Track:
    pass


def bar_t(f, bar):
    return f["grid"]["first_downbeat_s"] + (bar - 1) * f["grid"]["bar_s"]


def load_tracks():
    cands = json.load(open(os.path.join(HERE, "candidates.json")))
    disc_keys = {r["cut_key"] for r in cands if r["on_disc"]}
    sel = [r for r in cands if not r["on_disc"] and r["is_longest"] and r["cut_key"] not in disc_keys
           and (r.get("kbps") or 0) >= 200]
    # Mike's CD1 (disc "S", singalongs + Halloween remixes) is allowed with a penalty and a cap per mix;
    # CD2 (disc "M", the house remixes) is his lane and stays out
    sel += [r for r in cands if r["on_disc"] and r.get("disc") == "S" and r["is_longest"]
            and (r.get("kbps") or 0) >= 200]
    have = {r["id"] for r in sel}
    sel += [r for r in cands if r["id"] in MUST and r["id"] not in have]
    sel = [r for r in sel if r["id"] not in EXCLUDE]
    tracks = {}
    for r in sel:
        p = os.path.join(HERE, "features", r["id"] + ".json")
        if not os.path.exists(p):
            continue
        f = json.load(open(p))
        t = Track()
        t.id, t.r, t.f = r["id"], r, f
        art, song = r.get("artist") or "", r.get("song") or ""
        if (not art or not song) and " - " in r["title"]:
            art, song = r["title"].split(" - ", 1)
        t.title, t.artist, t.song = r["title"], art, song
        t.hal, t.kind, t.era = bool(r["hal"]), r["kind"], r["era"]
        g = f["grid"]
        t.bpm, t.bar_s, t.gconf, t.nbars = f["bpm"], g["bar_s"], g["confidence"], g["n_bars"]
        lt = f.get("local_tempo") or {}
        flags = set(f.get("flags") or [])
        if lt.get("intro_no_steady_beat"): flags.add("intro_no_steady_beat")
        if lt.get("outro_no_steady_beat"): flags.add("outro_no_steady_beat")
        if lt.get("tempo_change"): flags.add("tempo_change")
        t.flags = flags
        t.bpm_in = lt.get("bpm_in") or t.bpm
        t.bpm_out = lt.get("bpm_out") or t.bpm
        t.half = t.bpm > 145          # double-time track that sits in a half-time slot
        t.eff_bpm = t.bpm / 2 if t.half else t.bpm
        lowg = t.gconf < 0.5 or "low_grid_confidence" in flags
        # blends need a trustworthy grid at that end and a tempo that matches the global grid
        t.in_ok = (not lowg and lt.get("in_trusted", True) and "intro_no_steady_beat" not in flags
                   and abs(t.bpm_in / t.bpm - 1) < 0.01 and not t.half)
        t.out_ok_end = (not lowg and lt.get("out_trusted", True) and "outro_no_steady_beat" not in flags
                        and abs(t.bpm_out / t.bpm - 1) < 0.01 and not t.half)
        t.vocal = (f.get("per_bar") or {}).get("vocal_prob") or [0.8] * t.nbars
        t.fade_out = bool(f.get("fade_out"))
        t.first_sound, t.last_sound, t.dur = f["first_sound_s"], f["last_sound_s"], f["duration_s"]
        t.flav = flavour(r, t.eff_bpm)
        t.akeys = artist_tokens(art) or {norm(r["title"])}
        sk = norm(song) or norm(r["title"])
        # one entry per song title (covers and remakes count as the same song) except known title clashes
        t.song_key = (sk + "|" + sorted(t.akeys)[0]) if sk in DIFFERENT_SONGS else sk
        t.vocal_heavy = bool((f.get("vocal") or {}).get("vocal_heavy"))
        t.camelot = (f.get("key") or {}).get("camelot")
        # cue-in
        mi, mo = f["mix_in"], f["mix_out"]
        if t.in_ok:
            t.cue_bar = mi["start_bar"]
            t.cue_s = bar_t(f, t.cue_bar)
            t.in_win = mi["bars"]
        else:
            t.cue_bar = None
            t.cue_s = t.first_sound
            t.in_win = 0
        # exit (end of the mix-out window), trimmed to a phrase boundary if the play is too long
        t.exit_bar, t.out_win, t.early = mo["end_bar"], mo["bars"], False
        t.out_ok = t.out_ok_end
        play = bar_t(f, t.exit_bar) - t.cue_s
        if play > PLAY_MAX:
            e = early_exit(t)
            if e:
                t.exit_bar, t.out_win, t.early = e, 16, True
                t.out_ok = (not lowg and "tempo_change" not in flags and not t.half)
        t.exit_s = bar_t(f, t.exit_bar)
        t.play_s = t.exit_s - t.cue_s
        t.base, t.hh, t.hook_bar = t.id, False, None
        t.remix = bool((r.get("ver") or "").strip()) or t.kind in ("pool edit", "official remix")
        t.must = MUST.get(t.id)
        t.no_flow = False
        t.on_disc = bool(r["on_disc"]) and t.id not in NAMED_ON_DISC     # named picks do not count to the CD1 cap
        t.co = False
        hk = hook_bar(t) if t.in_ok else None
        t.flow_hook = hk if (hk and bar_t(f, hk) < t.exit_s - 90) else None
        t.hook_cut = (bar_t(f, t.flow_hook) - t.cue_s) if t.flow_hook else 0.0
        tracks[t.id] = t
        # callout variant: the song's best 1.5-2 minutes (from the hook), dropped into out of the flow
        if (t.eff_bpm < 112 or t.kind == "library" or t.gconf < 0.5 or (t.must and t.must[1] == "callout")) \
                and t.id != BRIDGE_ID and not (t.must and t.must[1] != "callout"):
            c = copy.copy(t)
            c.id, c.co, c.hh = t.id + "#co", True, False
            hk = hook_bar(t) if t.gconf >= 0.3 else None
            if hk:
                c.cue_bar, c.cue_s = hk, bar_t(f, hk)
            c.in_ok = False                       # callouts are entered with a cut, never blended
            e = early_exit(c, CO_PLAY[0], CO_PLAY[1])
            if e:
                c.exit_bar, c.early = e, True
            else:
                c.exit_bar = min(c.exit_bar, int((c.cue_s + 115 - f["grid"]["first_downbeat_s"]) / t.bar_s) + 1)
            c.out_ok = t.gconf >= 0.5 and "tempo_change" not in flags and not t.half
            c.exit_s = bar_t(f, c.exit_bar)
            c.play_s = c.exit_s - c.cue_s
            tracks[c.id] = c
        if t.must and t.must[1] == "callout":
            t.no_flow = True
        if not (88 <= t.eff_bpm <= 113) and t.id != BRIDGE_ID:
            continue
        # hip-hop-stage variant (hour plans; unused by the two-mix plan): quick play from an interesting element (hook / first verse) to an early
        # phrase-boundary exit, joined by cuts on the one or crossfader chops
        h = copy.copy(t)
        h.id, h.hh = t.id + "#hh", True
        mid_ok = not lowg and "tempo_change" not in flags and not t.half
        hook = hook_bar(t)
        if t.id == BRIDGE_ID:
            hook = None                         # play the Halloween-theme intro into Get Ur Freak On from the top
        if mid_ok and hook and hook >= 3:
            h.hook_bar = hook
            h.cue_bar = hook - 2                 # 2 bars of run-up (B's first audible bars in a chop = the hook)
            h.cue_s = bar_t(f, h.cue_bar)
            h.in_ok = True
        h.bpm_in = h.bpm_out = t.bpm if mid_ok else t.bpm_in
        h.exit_bar, h.out_win, h.early, h.out_ok = t.exit_bar, t.out_win, t.early, t.out_ok
        win = (80.0, 150.0) if t.id == BRIDGE_ID else HH_PLAY
        if bar_t(f, h.exit_bar) - h.cue_s > win[1]:
            e = early_exit(h, win[0], win[1])
            if e:
                h.exit_bar, h.out_win, h.early, h.out_ok = e, 16, True, mid_ok
        if h.out_ok and h.early:
            h.bpm_out = t.bpm
        h.exit_s = bar_t(f, h.exit_bar)
        h.play_s = h.exit_s - h.cue_s
        tracks[h.id] = h
    return tracks


def hook_bar(t):
    """First high-energy main section (the hook/drop) within ~40 bars of the intro, else the first vocal bar."""
    f = t.f
    mi = f["mix_in"]
    start = mi["start_bar"]
    for sec in f.get("sections") or []:
        if start < sec["start_bar"] <= start + 40 and sec.get("label") == "main" and sec.get("energy") == "high":
            return sec["start_bar"]
    fv = mi.get("first_vocal_bar")
    if fv and start < fv <= start + 40:
        return fv
    return start + 8 if start + 8 < t.nbars // 2 else None


def early_exit(t, lo=None, hi=None):
    """Pick an earlier exit bar on a phrase boundary so cue-in -> exit lasts PLAY_MIN..PLAY_MAX s."""
    f = t.f
    snap = (f.get("phrase") or {}).get("snap_phase_bar") or 1
    bset = set(f.get("boundaries_bars") or [])
    cand = set(b for b in bset)
    cand |= set(range(snap, t.nbars + 1, 8))
    best, bestv = None, -1e9
    lo_bar = (t.cue_bar or 1) + 24
    for e in sorted(cand):
        if e < lo_bar or e > f["mix_out"]["end_bar"]:
            continue
        play = bar_t(f, e) - t.cue_s
        if not ((lo or PLAY_MIN - 10) <= play <= (hi or PLAY_MAX)):
            continue
        last8 = t.vocal[max(0, e - 9):e - 1]
        voc = sum(last8) / max(1, len(last8))
        v = (1.0 if e in bset else 0.0) + (1 - voc) + 0.004 * play + (0.3 if (e - snap) % 16 == 0 else 0)
        if v > bestv:
            best, bestv = e, v
    return best


def window_vocal(A, B, L):
    a = A.vocal[max(0, A.exit_bar - 1 - L):A.exit_bar - 1]
    b0 = (B.cue_bar or 1) - 1
    b = B.vocal[b0:b0 + L]
    n = min(len(a), len(b))
    if n == 0:
        return 0.5, 0.5, 0.5
    v = sum(x * y for x, y in zip(a[-n:], b[:n])) / n
    return v, sum(a[-n:]) / n, sum(b[:n]) / n


CUT_TYPES = ("brake_cut", "loop_roll", "slam", "echo_out", "reverb_out")
BLEND_TYPES = ("bass_swap_32", "bass_swap_16", "bass_swap_8", "ramped_blend", "filter_sweep", "chop")


class Edges:
    """Directed joins.  Rules (revised after the first listen):
    * hip-hop stage (B is a #hh variant): no blends.  A crossfader chop (A 2 bars, B 2 bars, A 1 bar, B on)
      on every other join when both grids are trusted and the tempos are within 6 %, else a cut on the one;
      scratch stabs on the cuts.
    * pop/dance stages: a real EQ blend when the pair allows it (bass swap 16 preferred, 32 with long clean
      windows, 8 when vocals would clash over 16, tempo-ramped bass swap for 6-10 % gaps, high-pass sweep
      when B's intro is clean and A's outro is vocal); otherwise A ENDS with an effect (echo-out, reverb throw
      or loop roll) and B cuts in on the one; vinyl brake when A's end has no steady beat."""

    def __init__(self, tracks, pairs):
        self.T, self.P, self.cache = tracks, pairs, {}

    def get(self, a, b, parity=0):
        key = (a, b, parity)
        if key in self.cache:
            return self.cache[key]
        A, B = self.T[a], self.T[b]
        p = self.P.get((A.base, B.base))
        r = B.bpm_in / A.bpm_out
        stretch = (r - 1) * 100
        e = {"pair_score": p["score"] if p else None, "stretch_pct": round(stretch, 2),
             "reasons": list(p["reasons"]) if p else [], "timbre": (p or {}).get("terms", {}).get("timbre", 0.5)}
        why = []
        st = abs(stretch)
        base = p["score"] if p else 0.42
        if B.hh and not A.hh:
            # into the hip-hop stretch: echo-out (or a brake if A's end has no steady beat), B cold on the one
            tt, L, base = ("echo_out" if (A.out_ok and parity == 0) or (A.out_ok and B.id.startswith(BRIDGE_ID))
                           else "brake_cut"), 0, 0.55
        elif A.hh and not B.hh:
            # back to the dance floor: riser + slam onto B's hook / drop
            tt, L, base = "slam", 0, 0.55
            e["riser"] = True
        elif B.co or A.co:
            # callouts: drop out of the flow with an echo tail or a brake, climb back with a riser + slam
            if B.co and A.co:
                tt, L, base = "slam", 0, -9.0
            elif B.co:
                tt, L = ("echo_out" if (A.out_ok and parity == 0) else "brake_cut"), 0
                base = 0.55
            else:
                tt, L, base = ("echo_out" if A.out_ok else "slam"), 0, 0.55
                e["riser"] = True
        elif B.hh:
            if A.out_ok and B.in_ok and st <= 6 and parity == 1:
                tt, L = "chop", 5
            else:
                tt, L = "slam", 0
            base = max(base, 0.5)            # cuts are the style here, not a fallback
            if st > 12:
                base -= 0.1
        else:
            blendable = A.out_ok and B.in_ok and st <= 6
            if not A.out_ok: why.append("A end has no trustworthy beat")
            if not B.in_ok: why.append("B start has no trustworthy beat")
            if st > 6: why.append("tempo gap %.1f%%" % stretch)
            tt, L = None, 0
            if blendable:
                v8, va8, vb8 = window_vocal(A, B, 8)
                v16, va16, vb16 = window_vocal(A, B, 16)
                if st > 6:
                    pass                                  # gaps over 6 %: echo-out / brake, not a blend
                elif st > 4:
                    if v16 < 0.3:
                        tt, L = "ramped_blend", 16        # beat-only windows tolerate 4-6 %
                elif v16 < 0.25 and A.out_win >= 16 and B.in_win >= 16:
                    if A.out_win >= 32 and B.in_win >= 32 and window_vocal(A, B, 32)[0] < 0.2:
                        tt, L = "bass_swap_32", 32
                    else:
                        tt, L = "bass_swap_16", 16
                elif v8 < 0.6 and v16 < 0.45:
                    tt, L = "bass_swap_8", 8          # faster: 8 bars wherever the pair is not beat-only for 16
                elif vb16 < 0.35 and va16 >= 0.5:
                    tt, L = "filter_sweep", 16
                elif v8 < 0.6:
                    tt, L = "bass_swap_8", 8
                if tt is None:
                    why.append("vocals would clash (%.2f over 8 bars)" % v8)
            if tt is None:
                tt, L = ("echo_out" if A.out_ok else "brake_cut"), 0
            if tt in ("bass_swap_32", "bass_swap_16", "ramped_blend"):
                base += 0.08
            elif tt in ("bass_swap_8", "filter_sweep"):
                base += 0.03
            else:
                base = min(base, 0.6) - 0.05
            if st > 10:
                base -= 0.35 + 0.02 * (st - 10)   # off the arc: tempo jumps belong to the hip-hop cuts
        if stretch < -3 and not B.hh and not B.co and not A.co:
            base -= 0.15 + 0.03 * (st - 3)
        vfin = window_vocal(A, B, max(L, 4))[0]
        ks = 0
        if L and tt != "chop":
            for rr in e["reasons"]:
                m = re.search(r"pitch-shift B by ([+-]1) st", rr)
                if m:
                    ks = int(m.group(1))
        e["key_shift_st"] = ks
        e.update({"type": tt, "bars": L, "value": base, "vocal_overlap": round(vfin, 3), "cut_why": why})
        self.cache[key] = e
        return e


def overlap_s(A, B, L):
    return L * 0.5 * (A.bar_s + B.bar_s * B.bpm_in / A.bpm_out * (1 if True else 1))


def node_bonus(B, f_start, hour, st):
    """Position-dependent value of putting B at hour fraction f_start (tempo arc, flavour, lean)."""
    cfg = HOURS[hour]
    tgt = interp_arc(f_start)
    dev = abs(B.eff_bpm - tgt) / tgt
    v = -2.5 * max(0.0, dev - 0.03) - 0.6 * min(dev, 0.03)
    stage = stage_of(f_start)
    fl = B.flav
    v += {1: {"hiphop": 0.15, "pop": 0.05, "disco": 0.0, "dance": -0.05},
          2: {"hiphop": 0.03, "pop": 0.10, "disco": 0.15, "dance": 0.02},
          3: {"hiphop": -0.05, "pop": 0.0, "disco": 0.08, "dance": 0.15}}[stage].get(fl, 0)
    if fl == "ambient":
        v -= 0.3
    if cfg["lean"] == "hiphop" and fl == "hiphop": v += 0.08
    if cfg["lean"] == "disco" and fl == "disco": v += 0.08
    if not B.in_ok: v -= 0.06
    if not B.out_ok: v -= 0.06
    if B.gconf < 0.3: v -= 0.1
    if B.hh != (stage == 1):
        v -= 2.0                    # hip-hop variants only in the first stage, full versions after it
    if B.hh:
        if B.remix:
            v += 0.15               # prefer remix / edit cuts in the hip-hop stage
        elif B.song_key in REMIX_KEYS:
            v -= 0.15
    return v


REMIX_KEYS = set()


def plan_hour(hour, T, E, used_keys, beam_w, rng_pairs):
    cfg = HOURS[hour]
    ids = [t for t in T if T[t].song_key not in used_keys and T[t].flav != "ambient"]
    REMIX_KEYS.clear()
    REMIX_KEYS.update(T[t].song_key for t in ids if T[t].remix and 80 <= T[t].eff_bpm <= 106)
    # state: (score, seq, keys, start_of_last, hal_count, hal_stages, last_hal_idx, trans)
    beam = []
    for t in ids:
        B = T[t]
        if not (80 <= B.eff_bpm <= 95) or not B.hh:
            continue
        s = node_bonus(B, 0.0, hour, None)
        hal_c, hal_st, lh = 0, (), -9
        if B.hal:
            s += 0.25 + (0.1 if cfg["lean"] == "spooky" else 0)
            hal_c, hal_st, lh = 1, (1,), 0
        beam.append((s, (t,), frozenset([B.song_key]), 0.0, hal_c, hal_st, lh, ()))
    beam.sort(key=lambda x: -x[0])
    beam = beam[:beam_w]
    done = []
    for step in range(1, 40):
        nxt = []
        for (s, seq, keys, t0, hc, hst, lh, trans) in beam:
            A = T[seq[-1]]
            prevA = T[seq[-2]] if len(seq) > 1 else None
            in_L_s = overlap_s(prevA, A, trans[-1]["bars"]) if trans else 0.0
            exps = []
            for b in ids:
                B = T[b]
                if B.song_key in keys or (B.akeys & A.akeys):
                    continue
                if len(seq) > 1 and (B.akeys & T[seq[-2]].akeys):
                    continue
                e = E.get(A.id, b, len(seq) % 2)
                L = e["bars"]
                ov = overlap_s(A, B, L)
                if L and A.play_s - in_L_s - ov < 40:   # A too short for both overlaps
                    continue
                tB = t0 + A.play_s - ov
                f = tB / HOUR_S
                if f > 1.02:
                    continue
                v = e["value"] - 0.62 + node_bonus(B, f, hour, None)
                if f > 0.6 and B.eff_bpm < A.eff_bpm * 0.99:
                    v -= 0.05 * (A.eff_bpm / B.eff_bpm - 1) * 100
                nhc, nhst, nlh = hc, hst, lh
                if B.hal:
                    stg = stage_of(f)
                    if hc >= HAL_MAX:
                        v -= 0.6
                    elif hst.count(stg) >= 2:
                        v -= 0.35          # keep them spread across the three stages
                    elif hc < cfg["hal_target"]:
                        v += 0.28 + (0.08 if cfg["lean"] == "spooky" else 0)
                    if stg not in hst:
                        v += 0.2
                    if cfg["lean"] == "spooky" and not (B.in_ok and B.out_ok):
                        v += 0.12   # classic Halloween cut-ins are welcome in the spooky hour
                    if len(seq) - lh < 2:
                        v -= 0.25
                    nhc, nhst, nlh = hc + 1, hst + (stg,), len(seq)
                exps.append((s + v, b, tB, nhc, nhst, nlh, e))
            exps.sort(key=lambda x: -x[0])
            for (ns, b, tB, nhc, nhst, nlh, e) in exps[:30]:
                B = T[b]
                rec = dict(e, a=A.id, b=b, start_b=tB)
                st = (ns, seq + (b,), keys | {B.song_key}, tB, nhc, nhst, nlh, trans + (rec,))
                end = tB + B.play_s + 15
                if end >= HOUR_S - 120:
                    done.append(st)
                if end < HOUR_S - 60:
                    nxt.append(st)
        if os.environ.get("PLAN_DEBUG"):
            print("step", step, "nxt", len(nxt), "done", len(done),
                  "max t", max((x[3] for x in nxt), default=0), file=sys.stderr)
        if not nxt:
            break
        # diversity: at most 3 states per last track
        nxt.sort(key=lambda x: -x[0])
        per_last = defaultdict(int)
        beam = []
        for st in nxt:
            if per_last[st[1][-1]] >= 3:
                continue
            per_last[st[1][-1]] += 1
            beam.append(st)
            if len(beam) >= beam_w:
                break

    def final(st):
        s, seq, keys, t0, hc, hst, lh, trans = st
        B = T[seq[-1]]
        end = t0 + B.play_s + 15
        v = s - 0.004 * abs(end - HOUR_S)
        if B.eff_bpm < 125: v -= 0.6
        if B.eff_bpm > 129.5: v -= 0.4
        if T[seq[-2]].eff_bpm < 123: v -= 0.3
        if hc < HAL_MIN: v -= 0.6 * (HAL_MIN - hc)
        v -= 0.8 * (3 - len(set(hst)))
        if B.flav not in ("dance", "disco"): v -= 0.2
        return v
    if not done:
        done = list(beam)
    done.sort(key=lambda st: -final(st))
    return done[0]


MIXES_CFG = {
    1: {"name": "Haunted Disco", "lean": "disco-house and pop remixes", "hal_target": 5},
    2: {"name": "Witching Hour Warehouse", "lean": "harder house and Halloween", "hal_target": 6},
}
MIX_S = 72 * 60.0
MIX_ARC = [(0.0, 119.0), (0.3, 122.0), (0.6, 125.0), (0.85, 127.5), (1.0, 129.0)]
ON_DISC_CAP = 4


def mix_arc(f):
    f = max(0.0, min(1.0, f))
    for (f0, b0), (f1, b1) in zip(MIX_ARC, MIX_ARC[1:]):
        if f <= f1:
            return b0 + (b1 - b0) * (f - f0) / (f1 - f0)
    return MIX_ARC[-1][1]


def mix_node(B, f, mix):
    """Value of B at mix fraction f: flow tracks follow the 118-130 arc and lean remix-forward."""
    if B.co:
        v = 0.0
        if B.hal: v += 0.1
        if B.on_disc: v += 0.08                  # CD1 singalongs make good callouts
        if B.kind in ("pop original", "slow / R&B", "library") or B.hal: v += 0.08
        if B.gconf < 0.3 and not B.hal: v -= 0.1
        return v
    tgt = mix_arc(f)
    dev = abs(B.eff_bpm - tgt) / tgt
    v = -2.5 * max(0.0, dev - 0.03) - 0.6 * min(dev, 0.03)
    if B.remix: v += 0.18
    elif B.kind == "dance original": v += 0.08
    elif B.kind == "pop original": v -= 0.15
    elif B.kind in ("slow / R&B", "library"): v -= 0.5
    if B.flav == "hiphop" and not B.remix: v -= 0.3       # hip-hop originals only as callouts
    if B.flav == "ambient": v -= 0.3
    if B.on_disc: v -= 0.12
    if mix == 1:
        if B.flav == "disco": v += 0.12
        if B.flav == "pop" and B.remix: v += 0.08
    else:
        if B.flav == "dance": v += 0.12
        if B.eff_bpm >= 125: v += 0.05
    if not B.in_ok: v -= 0.1
    if not B.out_ok: v -= 0.1
    return v


def plan_mix(mix, T, E, used_keys, beam_w):
    cfg = MIXES_CFG[mix]
    ids = [t for t in T if T[t].song_key not in used_keys
           and (T[t].co or T[t].hh or T[t].flav != "ambient") and not (T[t].no_flow and not T[t].co)
           and not (T[t].must and T[t].must[0] != mix)]
    # state: score, seq, keys, t0, hal_count, hal_thirds, last_hal, trans, n_callouts, last_callout, n_disc
    beam = []
    for t in ids:
        B = T[t]
        if B.co or B.hh or not (116 <= B.eff_bpm <= 122):
            continue
        s = mix_node(B, 0.0, mix)
        hc, hst, lh = (1, (1,), 0) if B.hal else (0, (), -9)
        beam.append((s, (t,), frozenset([B.song_key]), 0.0, hc, hst, lh, (), 0, -9, int(B.on_disc), B.play_s, 0, 0.0))
    beam.sort(key=lambda x: -x[0])
    beam = beam[:beam_w]
    done = []
    for step in range(1, 45):
        nxt = []
        for (s, seq, keys, t0, hc, hst, lh, trans, nco, lco, nd, lp, ph, bs) in beam:
            A = T[seq[-1]]
            prevA = T[seq[-2]] if len(seq) > 1 else None
            in_L_s = overlap_s(prevA, A, trans[-1]["bars"]) if trans else 0.0
            exps = []
            for b in ids:
                B = T[b]
                if B.song_key in keys or (B.akeys & A.akeys):
                    continue
                if len(seq) > 1 and (B.akeys & T[seq[-2]].akeys):
                    continue
                if B.on_disc and nd >= ON_DISC_CAP:
                    continue
                if B.co and (A.co or A.hh or ph == 1 or nco >= 4 or len(seq) < 3 or len(seq) - lco < 4):
                    continue
                if B.hh and (ph == 2 or A.co or not (90 <= B.eff_bpm <= 113 or B.id.startswith(BRIDGE_ID))):
                    continue
                e = E.get(A.id, b, len(seq) % 2)
                L = e["bars"]
                ov = overlap_s(A, B, L)
                if L and lp - in_L_s - ov < 40:
                    continue
                tB = t0 + lp - ov
                f = tB / MIX_S
                if f > 1.02 or (B.co and not (0.1 <= f <= 0.85)):
                    continue
                # hip-hop stretch: one per mix, entered between 25 % and 60 %, 8-10.5 minutes long
                nph, nbs = ph, bs
                if ph == 0 and B.hh:
                    if not (0.25 <= f <= 0.6):
                        continue
                    nph, nbs = 1, tB
                elif ph == 1:
                    dur = tB - bs
                    if B.hh and dur > 600:
                        continue
                    if not B.hh and dur < 480:
                        continue
                    if not B.hh:
                        nph = 2
                v = e["value"] - 0.62 + (block_node(B, tB - nbs, mix) if B.hh else mix_node(B, f, mix))
                if B.must:
                    v += 0.8
                if B.co:
                    v += 0.6 if nco < 3 else 0.3     # 3-4 callouts per mix
                    v += 0.07                         # offsets the two cut joins around it
                elif not A.co and not A.hh and not B.hh and B.eff_bpm < A.eff_bpm * 0.985:
                    v -= 0.05 * (A.eff_bpm / B.eff_bpm - 1) * 100
                nhc, nhst, nlh = hc, hst, lh
                if B.hal:
                    stg = stage_of(f)
                    if hc >= HAL_MAX:
                        v -= 1.5
                    elif hst.count(stg) >= 2 + (1 if mix == 2 else 0):
                        v -= 0.35
                    elif hc < cfg["hal_target"]:
                        v += 0.28 + (0.08 if mix == 2 else 0)
                    if stg not in hst:
                        v += 0.2
                    if len(seq) - lh < 2:
                        v -= 0.25
                    nhc, nhst, nlh = hc + 1, hst + (stg,), len(seq)
                exps.append((s + v, b, tB, nhc, nhst, nlh, e, nph, nbs))
            exps.sort(key=lambda x: -x[0])
            for (ns, b, tB, nhc, nhst, nlh, e, nph, nbs) in exps[:30]:
                B = T[b]
                rec = dict(e, a=A.id, b=b, start_b=tB)
                bp = B.play_s - (B.hook_cut if ((A.co or A.hh) and not B.co and not B.hh) else 0.0)
                st = (ns, seq + (b,), keys | {B.song_key}, tB, nhc, nhst, nlh, trans + (rec,),
                      nco + (1 if B.co else 0), (len(seq) if B.co else lco), nd + int(B.on_disc), bp, nph, nbs)
                end = tB + bp + 15
                end_full = tB + (B.last_sound - B.cue_s)     # the last song plays to its end
                if MIX_S - 120 <= end_full <= MIX_S + 120 and not B.co and nph == 2:
                    done.append(st)
                if end < MIX_S - 60:
                    nxt.append(st)
        if os.environ.get("PLAN_DEBUG"):
            from collections import Counter
            print("step", step, len(nxt), "done", len(done), Counter(x[12] for x in nxt),
                  "max t", round(max((x[3] for x in nxt), default=0)), file=sys.stderr)
        if not nxt:
            break
        nxt.sort(key=lambda x: -x[0])
        per_last = defaultdict(int)
        per_phase = defaultdict(int)
        beam = []
        for st in nxt:                       # keep a full beam per phase so the hip-hop stretch survives
            if per_last[(st[12], st[1][-1])] >= 3 or per_phase[st[12]] >= beam_w:
                continue
            per_last[(st[12], st[1][-1])] += 1
            per_phase[st[12]] += 1
            beam.append(st)

    def final(st):
        s, seq, keys, t0, hc, hst, lh, trans, nco, lco, nd, lp, ph, bs = st
        B = T[seq[-1]]
        end = t0 + (B.last_sound - B.cue_s)
        if end > MIX_S + 120: s -= 2.0
        v = s - 0.004 * abs(end - MIX_S)
        if B.eff_bpm < 125: v -= 0.6
        if B.eff_bpm > 131: v -= 0.4
        if hc < cfg["hal_target"]: v -= 0.6 * (cfg["hal_target"] - hc)
        v -= 0.8 * (3 - len(set(hst)))
        if nco < 3: v -= 0.8 * (3 - nco)
        return v
    done.sort(key=lambda st: -final(st))
    return done[0]


def block_node(B, t_in_block, mix):
    """Value of a record inside the hip-hop stretch: tempo rising ~96 -> 106 BPM, remixes first, Chris's picks."""
    if B.id.startswith(BRIDGE_ID):
        return 0.6 if t_in_block < 1 else -2.0       # the Bizzon transition opens the stretch
    tgt = 96.0 + 10.0 * min(1.0, t_in_block / 600.0)
    dev = abs(B.eff_bpm - tgt) / tgt
    v = -2.0 * max(0.0, dev - 0.04) - 0.5 * min(dev, 0.04)
    if B.remix: v += 0.15
    if B.flav == "hiphop": v += 0.12
    if B.kind == "ambient": v -= 0.5
    if B.on_disc: v -= 0.12
    if not B.in_ok: v -= 0.1
    if "missy elliott" in B.artist.lower(): v += 0.3
    return v


def build_mix_plan(mix, st, T):
    s, seq, keys, t0, hc, hst, lh, trans, nco, lco, nd, lp, ph, bs = st
    plan = build_plan(mix, (s, seq, keys, t0, hc, hst, lh, trans), T)
    cfg = MIXES_CFG[mix]
    plan.update({"hour": mix, "mix": mix, "name": cfg["name"], "lean": cfg["lean"], "arc": MIX_ARC,
                 "callouts": nco, "on_disc_tracks": nd})
    for i, (sng, tid) in enumerate(zip(plan["songs"], seq)):
        t = T[tid]
        prev = T[seq[i - 1]] if i > 0 else None
        if prev is not None and (prev.co or prev.hh) and not t.co and not t.hh and t.flow_hook:
            sng["cue_in"] = {"bar": t.flow_hook, "time_s": round(bar_t(t.f, t.flow_hook), 3),
                             "mode": "downbeat on the hook / drop (slammed in after a callout or the hip-hop stretch)"}
        sng["callout"] = t.co
        sng["hiphop_stretch"] = t.hh
        sng["must"] = bool(t.must)
        sng["on_disc"] = t.on_disc
        sng["version"] = (t.r.get("ver") or "").strip()
        sng["stage"] = 0
    # recompute exit textures: only flow joins rotate echo / loop roll / reverb; callout joins keep theirs
    k = 0
    nscr = 0
    nin = 0
    for j, e in zip(plan["joins"], trans):
        A, B = T[e["a"]], T[e["b"]]
        j["riser"] = bool(e.get("riser")) or e["type"] in ("brake_cut", "loop_roll")
        j["scratch"] = False
        j["backspin"] = False
        j["type"] = e["type"]
        if B.co:
            # into a callout: rotate brake / echo tail / backspin / slam (brake whenever A's end has no steady beat)
            choice = ("brake_cut", "echo_out", "brake_cut", "slam")[nin % 4]
            if not A.out_ok:
                choice = "brake_cut"
            j["type"] = choice
            j["backspin"] = choice == "brake_cut" and nin % 4 == 2
            j["riser"] = False
            nin += 1
        elif e["type"] == "echo_out" and not A.co and not B.hh:
            j["type"] = ("echo_out", "loop_roll", "reverb_out")[k % 3]
            k += 1
            j["riser"] = j["type"] == "loop_roll"
        if A.co and e["type"] == "slam" and nscr < 1 and j["n"] > 6:
            j["scratch"] = True            # one scratch stab per mix, on a climb back out of a callout
            nscr += 1
        if A.co and j["type"] == "echo_out":
            j["riser"] = True
        if A.hh and B.hh:
            j["scratch"] = True            # scratch stab on every cut inside the hip-hop stretch
        # teaser: stabs of B's drums gated into A on bars 4, 2 and 1 before the join (about half the joins,
        # every cut in the hip-hop stretch); only where B's tempo is within 8 % of A's
        close = abs(j["stretch_pct"]) <= 8
        if j["type"] == "chop" or B.co or not close:
            j["teaser"] = False
        elif A.hh or B.hh:
            j["teaser"] = True
        else:
            j["teaser"] = (j["n"] % 2 == 0)
        if B.hh and not A.hh:
            role = "into the hip-hop stretch: "
        elif A.hh and B.hh:
            role = "hip-hop: "
        elif A.hh:
            role = "back to the floor: "
        else:
            role = "into callout: " if B.co else ("back out of callout: " if A.co else "")
        j["name"] = role + MIX_NAMES.get(j["type"], j["type"]) + (" (backspin)" if j["backspin"] else "") + (" + riser" if j["riser"] and j["type"] in ("slam", "echo_out") else "") + (
            " + scratch stab" if j["scratch"] else "") + (" + key shift %+d st" % j["key_shift_st"] if j.get("key_shift_st") else "") + (
            " [teaser]" if j.get("teaser") else "")
    return plan


MIX_NAMES = {
    "bass_swap_32": "32-bar bass-swap blend", "bass_swap_16": "16-bar bass-swap blend",
    "bass_swap_8": "8-bar bass-swap blend", "ramped_blend": "16-bar tempo-ramped bass-swap blend",
    "filter_sweep": "16-bar high-pass sweep blend", "echo_out": "echo-out, cut in on the one",
    "reverb_out": "reverb throw, cut in on the one", "loop_roll": "loop roll + riser, cut in on the one",
    "slam": "slam on the one", "brake_cut": "vinyl brake, cut in", "chop": "chop A2/B2/A1/B",
}


def write_mix_tracklist(p):
    lines = ["Mix %d: %s (%s) - %d songs, about %d min, %d Halloween (H), %d callouts (C), Q = hip-hop quick-mix stretch, ! = Chris's pick, %d other tracks from Mike's CD1 (*)" % (
        p["mix"], p["name"], p["lean"], p["n_songs"], round(p["planned_duration_s"] / 60), p["halloween"],
        p["callouts"], p["on_disc_tracks"]), ""]
    for i, s in enumerate(p["songs"]):
        m, sec = divmod(int(s["planned_start_s"]), 60)
        how = "start" if i == 0 else p["joins"][i - 1]["name"]
        title = s["title"] + ((" [" + s["version"] + "]") if s["version"] else "")
        lines.append("%2d. %2d:%02d  %s%s%s%s %-70s %5.1f BPM   <- %s" % (
            s["pos"], m, sec, "H" if s["hal"] else " ", "C" if s["callout"] else ("Q" if s["hiphop_stretch"] else " "),
            "*" if s["on_disc"] else " ", "!" if s["must"] else " ",
            title[:70], s["bpm"], how))
    os.makedirs(os.path.join(HERE, "mixes"), exist_ok=True)
    with open(os.path.join(HERE, "mixes", "mix_%d_tracklist.txt" % p["mix"]), "w") as fh:
        fh.write("\n".join(lines) + "\n")
    print("\n".join(lines))


def build_plan(hour, st, T):
    s, seq, keys, t0, hc, hst, lh, trans = st
    songs = []
    for i, tid in enumerate(seq):
        t = T[tid]
        start = 0.0 if i == 0 else trans[i - 1]["start_b"]
        last = i == len(seq) - 1
        cue_bar, cue_s, cue_mode = t.cue_bar, t.cue_s, ("downbeat" if t.cue_bar else "cold (first sound)")
        if i > 0 and t.hh and trans[i - 1]["type"] == "slam" and t.hook_bar:
            cue_bar, cue_s, cue_mode = t.hook_bar, bar_t(t.f, t.hook_bar), "downbeat on the hook"
        elif t.hh and t.hook_bar and i > 0:
            cue_mode = "2 bars before the hook"
        songs.append({
            "pos": i + 1, "id": t.base, "stage_mode": "hip-hop cut" if t.hh else "blend", "title": t.title, "artist": t.artist, "path": t.r["path"],
            "bpm": round(t.bpm, 2), "bpm_in": round(t.bpm_in, 2), "bpm_out": round(t.bpm_out, 2),
            "key": t.camelot, "hal": t.hal, "flavour": t.flav, "kind": t.kind, "era": t.era,
            "stage": stage_of(start / HOUR_S), "planned_start_s": round(start, 1),
            "first_downbeat_s": t.f["grid"]["first_downbeat_s"], "bar_s": t.bar_s, "n_bars": t.nbars,
            "cue_in": {"bar": cue_bar, "time_s": round(cue_s, 3), "mode": cue_mode},
            "exit": ({"bar": None, "time_s": round(t.last_sound, 3), "mode": "play to end"} if last else
                     {"bar": t.exit_bar, "time_s": round(t.exit_s, 3),
                      "mode": "early exit on phrase boundary" if t.early else
                      ("mix-out end (before fade)" if t.fade_out else "mix-out end")}),
            "first_sound_s": t.first_sound, "last_sound_s": t.last_sound, "fade_out": t.fade_out,
            "in_trusted": t.in_ok, "out_trusted": t.out_ok,
            "transient_mode": "smooth" if (t.flav in ("pop", "hiphop") and t.vocal_heavy) else "crisp",
            "flags": sorted(t.flags),
        })
    joins = []
    for i, e in enumerate(trans):
        A, B = T[e["a"]], T[e["b"]]
        L = e["bars"]
        st_pct = e["stretch_pct"]
        if e["type"] == "chop":
            side, carry = "B runs at A's tempo through the chop, then jumps to its own tempo", "B"
        elif L == 0:
            side, carry = "none (cut on the one, no beat-match)", None
        elif abs(st_pct) < 0.05:
            side, carry = "none (tempos equal)", "none"
        else:
            side, carry = ("both, ramped bar by bar from %.2f to %.2f BPM across the overlap" % (A.bpm_out, B.bpm_in)), "ramp"
        A_cue_out = (A.exit_bar - L) if L else A.exit_bar
        joins.append({
            "n": i + 1, "from": A.base, "to": B.base, "from_title": A.title, "to_title": B.title,
            "type": e["type"], "overlap_bars": L,
            "a_overlap_start_bar": A_cue_out, "a_exit_bar": A.exit_bar,
            "b_cue_bar": B.cue_bar, "b_overlap_end_bar": (B.cue_bar + L) if (B.cue_bar and L) else B.cue_bar,
            "overlap_s": round(overlap_s(A, B, L), 2),
            "stretch_pct": st_pct, "stretch_mode": carry, "stretch_side": side,
            "pair_score": e["pair_score"], "join_value": round(e["value"], 3),
            "vocal_overlap": e["vocal_overlap"], "timbre": e["timbre"],
            "dip_out_mids": bool(e["timbre"] is not None and e["timbre"] < 0.5),
            "riser": e["type"] in ("brake_cut", "loop_roll"), "impact": e["type"] in CUT_TYPES,
            "key_shift_st": e.get("key_shift_st", 0),
            "reasons": e["reasons"] + (["cut: " + "; ".join(e["cut_why"])] if e["cut_why"] else []),
            "planned_time_s": round(e["start_b"], 1),
        })
    # exit textures: A ENDS with an effect on every non-blend join outside the hip-hop stage, rotating
    # echo-out / loop roll / reverb throw; scratch stabs on every hip-hop cut; backspin on every other brake
    k = 0
    for j in joins:
        j["reverb_wash"] = False
        j["scratch"] = j["type"] in ("slam", "chop")
        j["backspin"] = False
        if j["type"] == "echo_out":
            j["type"] = ("echo_out", "loop_roll", "reverb_out")[k % 3]
            k += 1
            j["riser"] = j["type"] == "loop_roll"
        elif j["type"] == "brake_cut":
            j["backspin"] = j["n"] % 2 == 0
        j["name"] = TRANSITION_NAMES.get(j["type"], j["type"]) + (" (backspin)" if j["backspin"] else "") + (
            " + key shift %+d st" % j["key_shift_st"] if j.get("key_shift_st") else "")
    end = trans[-1]["start_b"] + T[seq[-1]].last_sound - T[seq[-1]].cue_s if trans else 0
    return {"hour": hour, "name": HOURS[hour]["name"], "lean": HOURS[hour]["lean"],
            "planned_duration_s": round(end, 1), "n_songs": len(seq), "halloween": hc,
            "arc": ARC, "songs": songs, "joins": joins,
            "notes": "Edit cue/exit bars or join types by hand; render.py recomputes geometry from these fields."}


TRANSITION_NAMES = {
    "bass_swap_32": "32-bar bass-swap blend", "bass_swap_16": "16-bar bass-swap blend",
    "bass_swap_8": "8-bar bass-swap blend", "ramped_blend": "16-bar tempo-ramped bass-swap blend",
    "filter_sweep": "16-bar high-pass sweep blend", "echo_out": "echo-out, next song cuts in on the one",
    "reverb_out": "reverb throw, next song cuts in on the one", "loop_roll": "loop roll, next song cuts in on the one",
    "slam": "cut on the one + scratch stab", "chop": "chop: A 2 bars / B 2 bars / A 1 bar / B + scratch",
    "brake_cut": "vinyl brake + riser, next song cuts in",
}


def write_tracklist(p):
    lines = ["Hour %d: %s (%s lean) - %d songs, about %d min, %d Halloween (H)" % (
        p["hour"], p["name"], p["lean"], p["n_songs"], round(p["planned_duration_s"] / 60), p["halloween"]), ""]
    stage_names = {1: "Stage 1 - hip-hop / R&B (quick cuts)", 2: "Stage 2 - pop / disco", 3: "Stage 3 - dance"}
    cur = None
    for i, s in enumerate(p["songs"]):
        if s["stage"] != cur:
            cur = s["stage"]
            lines += ["", stage_names[cur]]
        m, sec = divmod(int(s["planned_start_s"]), 60)
        how = "start" if i == 0 else p["joins"][i - 1]["name"]
        lines.append("%2d. %2d:%02d  %s %-58s %5.1f BPM   <- %s" % (
            s["pos"], m, sec, "H" if s["hal"] else " ", s["title"][:58], s["bpm"], how))
    os.makedirs(os.path.join(HERE, "mixes"), exist_ok=True)
    out = os.path.join(HERE, "mixes", "plan_%d_tracklist.txt" % p["hour"])
    with open(out, "w") as fh:
        fh.write("\n".join(lines) + "\n")


def print_plan(p):
    print("\n=== Hour %d: %s (%d songs, %.1f min, %d Halloween) ===" % (
        p["hour"], p["name"], p["n_songs"], p["planned_duration_s"] / 60, p["halloween"]))
    for i, s in enumerate(p["songs"]):
        m, sec = divmod(int(s["planned_start_s"]), 60)
        j = p["joins"][i - 1] if i else None
        jt = ("%-16s %+5.1f%% %2db" % (j["type"], j["stretch_pct"], j["overlap_bars"])) if j else "(start)"
        print("%2d %2d:%02d  %6.1f  %-4s %s %-7s %-55s  <- %s" % (
            s["pos"], m, sec, s["bpm"], s["key"] or "?", "H" if s["hal"] else " ", s["flavour"],
            s["title"][:55], jt))


def build_full():
    """One continuous file: mix 1 runs into mix 2 through a planned seam join -> plan_full.json."""
    p1 = json.load(open(os.path.join(HERE, "plan_mix1.json")))
    p2 = json.load(open(os.path.join(HERE, "plan_mix2.json")))
    T = load_tracks()
    base_ids = {t.base for t in T.values()}
    P = {(p["a"], p["b"]): p for p in json.load(open(os.path.join(HERE, "pairs.json")))["pairs"]
         if p["a"] in base_ids and p["b"] in base_ids}
    E = Edges(T, P)
    A, B = T[p1["songs"][-1]["id"]], T[p2["songs"][0]["id"]]
    e = E.get(A.id, B.id, 0)
    typ, L = e["type"], e["bars"]
    if L == 0:
        # gear change between the halves: a loop roll + riser when A has a steady beat, else a brake
        typ = "loop_roll" if A.out_ok else "brake_cut"
    songs = [dict(s_) for s_ in p1["songs"]] + [dict(s_) for s_ in p2["songs"]]
    last = songs[len(p1["songs"]) - 1]
    last["exit"] = {"bar": A.exit_bar, "time_s": round(A.exit_s, 3), "mode": "mix-out end (seam into mix 2)"}
    first2 = songs[len(p1["songs"])]
    if first2["cue_in"]["bar"] is None and B.cue_bar:
        first2["cue_in"] = {"bar": B.cue_bar, "time_s": round(B.cue_s, 3), "mode": "downbeat"}
    seam_t = p1["songs"][-1]["planned_start_s"] + A.play_s - (overlap_s(A, B, L) if L else 0)
    seam = {
        "from": A.base, "to": B.base, "from_title": A.title, "to_title": B.title, "type": typ, "overlap_bars": L,
        "a_overlap_start_bar": (A.exit_bar - L) if L else A.exit_bar, "a_exit_bar": A.exit_bar,
        "b_cue_bar": B.cue_bar, "b_overlap_end_bar": (B.cue_bar + L) if (B.cue_bar and L) else B.cue_bar,
        "overlap_s": round(overlap_s(A, B, L), 2) if L else 0.0, "stretch_pct": e["stretch_pct"],
        "stretch_mode": "ramp" if L else None,
        "stretch_side": "both, ramped" if L else "none (cut on the one, no beat-match)",
        "pair_score": e["pair_score"], "join_value": round(e["value"], 3), "vocal_overlap": e["vocal_overlap"],
        "timbre": e["timbre"], "dip_out_mids": bool(e["timbre"] is not None and e["timbre"] < 0.5),
        "riser": typ in ("loop_roll", "brake_cut"), "impact": typ in CUT_TYPES, "key_shift_st": e.get("key_shift_st", 0),
        "reasons": e["reasons"] + ["seam: end of mix 1 into the start of mix 2"],
        "planned_time_s": round(seam_t, 1), "reverb_wash": False, "scratch": False, "backspin": False,
        "teaser": abs(e["stretch_pct"]) <= 8,
    }
    seam["name"] = "SEAM (mix 1 -> mix 2): " + MIX_NAMES.get(typ, typ) + (" [teaser]" if seam["teaser"] else "")
    joins = [dict(j) for j in p1["joins"]] + [seam] + [dict(j) for j in p2["joins"]]
    off = seam_t
    for k, s_ in enumerate(songs):
        s_["pos"] = k + 1
        if k >= len(p1["songs"]):
            s_["planned_start_s"] = round(s_["planned_start_s"] + off, 1)
    for k, j in enumerate(joins):
        j["n"] = k + 1
        if k > len(p1["joins"]):
            j["planned_time_s"] = round(j.get("planned_time_s", 0) + off, 1)
    full = {"hour": 3, "mix": 0, "name": "Halloween Mix - full", "out_base": "Halloween Mix - full",
            "lean": "mix 1 (%s) into mix 2 (%s)" % (p1["lean"], p2["lean"]),
            "planned_duration_s": round(off + p2["planned_duration_s"], 1), "n_songs": len(songs),
            "halloween": p1["halloween"] + p2["halloween"], "callouts": p1["callouts"] + p2["callouts"],
            "on_disc_tracks": p1["on_disc_tracks"] + p2["on_disc_tracks"], "arc": p1["arc"],
            "songs": songs, "joins": joins, "seam_join": len(p1["joins"]) + 1}
    with open(os.path.join(HERE, "plan_full.json"), "w") as fh:
        json.dump(full, fh, indent=1)
    full["mix"] = "full"
    print("seam: %s -> %s: %s (stretch %+.1f%%) at %.1f min; full plan %.1f min, %d songs" % (
        A.title, B.title, seam["name"], e["stretch_pct"], seam_t / 60, full["planned_duration_s"] / 60, len(songs)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--beam", type=int, default=160)
    ap.add_argument("--hours", default=None, help="old three-hour plans (e.g. 1,2,3) instead of the two mixes")
    ap.add_argument("--full", action="store_true", help="join plan_mix1 and plan_mix2 into plan_full.json")
    a = ap.parse_args()
    if a.full:
        build_full()
        return
    T = load_tracks()
    print("eligible tracks (incl. callout variants):", len(T), file=sys.stderr)
    base_ids = {t.base for t in T.values()}
    P = {}
    for p in json.load(open(os.path.join(HERE, "pairs.json")))["pairs"]:
        if p["a"] in base_ids and p["b"] in base_ids:
            P[(p["a"], p["b"])] = p
    print("pairs among eligible:", len(P), file=sys.stderr)
    E = Edges(T, P)
    used = set()
    if a.hours:
        for h in [int(x) for x in a.hours.split(",")]:
            st = plan_hour(h, T, E, used, a.beam, None)
            plan = build_plan(h, st, T)
            for sng in plan["songs"]:
                used.add(T[sng["id"]].song_key)
            with open(os.path.join(HERE, "plan_%d.json" % h), "w") as fh:
                json.dump(plan, fh, indent=1)
            print_plan(plan)
            write_tracklist(plan)
        return
    for m in (1, 2):
        st = plan_mix(m, T, E, used, a.beam)
        plan = build_mix_plan(m, st, T)
        for sng in plan["songs"]:
            used.add(T[sng["id"]].song_key)
        out = os.path.join(HERE, "plan_mix%d.json" % m)
        with open(out + ".tmp", "w") as fh:
            json.dump(plan, fh, indent=1)
        os.replace(out + ".tmp", out)
        write_mix_tracklist(plan)
        print()


if __name__ == "__main__":
    main()
