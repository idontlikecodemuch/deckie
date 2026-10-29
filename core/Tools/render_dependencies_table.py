#!/usr/bin/env python3
"""Regenerate the acknowledgements table in DEPENDENCIES.md from core/dependencies.json.

The JSON is the source: the apps read it with DeckieCrate's `Dependencies` and never parse Markdown. This script
writes the same entries as a Markdown table between two HTML-comment markers near the top of DEPENDENCIES.md and
leaves every other byte of the file as it is, so the sections written by hand (the licence quotes and the evidence)
are never touched. `Dependencies.markdownTable()` renders the same text, and DependenciesTests fails when the
committed table and the JSON differ. Needs nothing beyond Python's standard library.

  python3 -I core/Tools/render_dependencies_table.py           # rewrite the table (from anywhere)
  python3 -I core/Tools/render_dependencies_table.py --check   # exit 1 if the table is out of date, change nothing

It exits 2, changing nothing, when the JSON or the markers are not as expected.

Each row is the entry's name, version, licence, training_sets and replacement_path; a `|` in a value is escaped as
`\\|` so it cannot split a cell, and a null is an empty cell.
"""
import argparse, json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SOURCE = os.path.join(ROOT, "core", "dependencies.json")
DOC = os.path.join(ROOT, "DEPENDENCIES.md")

START = ("<!-- dependencies-table: generated from core/dependencies.json by core/Tools/render_dependencies_table.py; "
         "do not edit by hand -->")
END = "<!-- /dependencies-table -->"
HEADER = ["Entry", "Version", "Licence", "Training sets and their terms (models)", "Replacement path (models)"]
COLUMNS = ["name", "version", "licence", "training_sets", "replacement_path"]
FORMAT = 1


def fail(message):
    print(message, file=sys.stderr)
    sys.exit(2)


def cell(value):
    if value is None or value == "":
        return " "
    return " " + value.replace("|", "\\|") + " "


def table(entries):
    """The table text, each line ending in a newline; the same as Dependencies.markdownTable()."""
    lines = ["|" + "|".join(cell(h) for h in HEADER) + "|", "|" + "|".join("---" for _ in HEADER) + "|"]
    for e in entries:
        lines.append("|" + "|".join(cell(e[c]) for c in COLUMNS) + "|")
    return "".join(line + "\n" for line in lines)


def render(doc, entries):
    """`doc` with the text between the markers replaced: a blank line, the table, a blank line. The blank lines keep
    GitHub from reading the closing marker as one more table row."""
    for marker in (START, END):
        if doc.count(marker + "\n") != 1:
            fail(f"{DOC}: the line {marker!r} must appear exactly once")
    start = doc.index(START + "\n") + len(START) + 1
    end = doc.index(END + "\n")
    if end < start:
        fail(f"{DOC}: the closing marker comes before the opening one")
    return doc[:start] + "\n" + table(entries) + "\n" + doc[end:]


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="exit 1 if DEPENDENCIES.md would change; write nothing")
    args = parser.parse_args()

    with open(SOURCE, encoding="utf-8") as f:
        data = json.load(f)
    if data.get("format") != FORMAT:
        fail(f"{SOURCE}: format is {data.get('format')!r}; this script writes format {FORMAT}")
    for i, e in enumerate(data["entries"]):
        missing = [c for c in ["id"] + COLUMNS if c not in e]
        if missing:
            fail(f"{SOURCE}: entries[{i}] has no {', '.join(missing)}")

    # newline="" keeps the file's line endings exactly as they are.
    with open(DOC, encoding="utf-8", newline="") as f:
        doc = f.read()
    new = render(doc, data["entries"])
    if args.check:
        if new != doc:
            print(f"{DOC} is out of date with {SOURCE}; run: python3 core/Tools/render_dependencies_table.py",
                  file=sys.stderr)
            sys.exit(1)
        return
    if new != doc:
        with open(DOC, "w", encoding="utf-8", newline="") as f:
            f.write(new)
        print(f"rewrote the table in {DOC}")
    else:
        print(f"{DOC} is already up to date")


if __name__ == "__main__":
    main()
