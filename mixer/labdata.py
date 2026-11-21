"""Where the lab's data and the music are. Nothing here is personal and no data is committed with the code.

  DECKIE_LAB_DATA   the folder holding the lab's data: features/<id>.json, candidates.json, recs.json, the per-track
                    sheets (key_parity_keys.tsv, key_light_stft.tsv, ...) and fixtures/ (the reference numbers the
                    core's lab-parity tests read). It is private: the lab analysed a personal music library, so the
                    folder is kept outside the repository. Unset, the lab reads and writes beside its code, in
                    mixer/ itself (the old layout; .gitignore keeps those files out of commits). The public stand-in,
                    core/fixtures/lab-sample, holds invented songs in the same shape (core/Tools/make_lab_sample.py).
  DECKIE_MUSIC_ROOT the folder the audio lives in (the candidates' `path`s start with it). No default: the scripts
                    that read audio stop and ask for it.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
LAB = os.environ.get("DECKIE_LAB_DATA") or HERE
FEAT_DIR = os.path.join(LAB, "features")
CANDIDATES = os.path.join(LAB, "candidates.json")
RECS = os.path.join(LAB, "recs.json")
MODELS = os.environ.get("DECKIE_LAB_MODELS") or os.path.join(HERE, "models")


def lab_file(name):
    """A file of the lab's data folder (DECKIE_LAB_DATA, else mixer/)."""
    return os.path.join(LAB, name)


def music_root():
    """DECKIE_MUSIC_ROOT, or a plain stop when it is not set."""
    root = os.environ.get("DECKIE_MUSIC_ROOT")
    if not root:
        sys.exit("set DECKIE_MUSIC_ROOT to the folder that holds the music (see mixer/README.md)")
    return root
