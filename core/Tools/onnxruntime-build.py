#!/usr/bin/env python3
"""The steps of .github/workflows/onnxruntime-build.yml that are the same on Linux, macOS and Windows.

That workflow builds ONNX Runtime from its pinned release without Microsoft's usage-reporting client, for Deckie's
shipped builds (DEPENDENCIES.md, section 6). Three subcommands, each run with `python -I`:

  check-source --source DIR --remote URL --tag TAG --commit SHA --version V
      Stop unless the checkout in DIR is commit SHA, the tag TAG at URL points at that same commit (so a tag moved
      since it was recorded is noticed), and the checkout's VERSION_NUMBER says V.

  fetch-dep --deps DEPS_TXT --name NAME --dest DIR
      Download the entry NAME of ONNX Runtime's cmake/deps.txt into DIR, stop if its SHA-1 differs from the one
      recorded there (nothing is unpacked then), unpack it, and print the unpacked folder (forward slashes, as CMake
      wants it, on Windows too) as the only line on standard output. Why: ONNX Runtime's CMake checks every
      dependency it downloads against deps.txt except one at v1.31.1, mp11 (Boost.Mp11, header-only), whose
      declaration in cmake/external/onnxruntime_external_deps.cmake gives no URL_HASH; the workflow fetches mp11
      with this and hands CMake the checked copy (FETCHCONTENT_SOURCE_DIR_MP11).

  package --platform {linux,macos,windows} --version V --commit SHA --source DIR --install DIR --vendored DIR
          --name NAME --stage DIR --out DIR [--official-size N] [--build-seconds N]
      Lay out the archive like Microsoft's (lib/ with the library, include/ with the three C headers Deckie
      vendors, LICENSE, ThirdPartyNotices.txt, Privacy.md, VERSION_NUMBER, GIT_COMMIT_ID) from the build's install
      tree (cmake --install) and the source checkout, strip the library as Microsoft's is stripped, check the
      headers against the vendored copies, write OUT/NAME.tgz (.zip on Windows) and NAME.tgz.sha256 beside it, and
      write the sizes, SHA-256 values and build time to the job summary.

Needs: Python 3.8 or newer and nothing outside its standard library; git; strip on Linux and macOS.
"""

import argparse
import hashlib
import os
import pathlib
import shutil
import subprocess
import sys
import tarfile
import time
import urllib.request
import zipfile

HEADERS = ("onnxruntime_c_api.h", "onnxruntime_ep_c_api.h", "onnxruntime_error_code.h")


def die(message):
    print(f"onnxruntime-build: {message}", file=sys.stderr)
    sys.exit(1)


def say(message):
    print(message, file=sys.stderr)


def git(*args):
    return subprocess.run(["git", *args], check=True, capture_output=True, text=True).stdout


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while chunk := f.read(1 << 20):
            h.update(chunk)
    return h.hexdigest()


def grouped(n):
    return f"{n:,}"


# check-source

def check_source(a):
    head = git("-C", a.source, "rev-parse", "HEAD").strip()
    if head != a.commit:
        die(f"the checkout is at {head}, expected {a.commit}")
    # An annotated tag lists the tag object and, peeled (^{}), the commit it points at; a lightweight tag lists only
    # the commit. Both patterns must be asked for: ls-remote does not show the peeled line otherwise.
    ref = f"refs/tags/{a.tag}"
    lines = git("ls-remote", "--tags", a.remote, ref, ref + "^{}").splitlines()
    listed = {name: sha for sha, name in (line.split("\t") for line in lines)}
    tagged = listed.get(ref + "^{}") or listed.get(ref)
    # Microsoft's 1.31.1 archives name 41d4d61f as their source (GIT_COMMIT_ID), but the tag v1.31.1 points at
    # 6af1a932 (found by the first run, Oct 29, 2026). Deckie builds the archives' commit, the source of the binaries
    # it was developed against, and pins the tag's commit separately, so that either moving still stops the build.
    expected_tag = a.tag_commit or a.commit
    if tagged != expected_tag:
        die(f"{a.tag} at {a.remote} points at {tagged or 'nothing'}, expected {expected_tag}")
    version = pathlib.Path(a.source, "VERSION_NUMBER").read_text(encoding="utf-8").strip()
    if version != a.version:
        die(f"VERSION_NUMBER says {version}, expected {a.version}")
    where = "that commit" if expected_tag == a.commit else f"{expected_tag} as pinned; the build uses the archives' commit {a.commit}"
    print(f"{a.tag} points at {where}, the checkout is {head}, VERSION_NUMBER says {version}")


# fetch-dep

def download(url, path):
    for attempt in range(1, 4):
        try:
            with urllib.request.urlopen(url, timeout=60) as reply, open(path, "wb") as out:
                while chunk := reply.read(1 << 20):
                    out.write(chunk)
            return
        except OSError as error:
            if attempt == 3:
                die(f"could not download {url}: {error}")
            say(f"download failed ({error}), trying again")
            time.sleep(5 * attempt)


def fetch_dep(a):
    # deps.txt is "name;url;sha1" per line, with "#" comments.
    for line in pathlib.Path(a.deps).read_text(encoding="utf-8").splitlines():
        fields = line.strip().split(";")
        if not line.startswith("#") and len(fields) == 3 and fields[0] == a.name:
            url, sha1 = fields[1], fields[2].lower()
            break
    else:
        die(f"{a.deps} has no entry {a.name}")
    if not url.startswith("https://"):
        die(f"{a.name}'s address is not https: {url}")
    dest = pathlib.Path(a.dest)
    dest.mkdir(parents=True, exist_ok=True)
    archive = dest / url.rsplit("/", 1)[-1]
    say(f"downloading {url}")
    download(url, archive)
    data = archive.read_bytes()
    got = hashlib.sha1(data).hexdigest()
    if got != sha1:
        die(f"SHA-1 mismatch for {archive.name}: deps.txt says {sha1}, got {got}; nothing was unpacked")
    say(f"{a.name}: {archive.name}, {len(data)} bytes, SHA-1 {got} as in deps.txt, SHA-256 {hashlib.sha256(data).hexdigest()}")
    unpacked = dest / f"{a.name}-src"
    if zipfile.is_zipfile(archive):
        with zipfile.ZipFile(archive) as z:
            z.extractall(unpacked)  # zipfile drops ".." and absolute paths from member names
    else:
        with tarfile.open(archive) as t:
            if hasattr(tarfile, "data_filter"):
                t.extractall(unpacked, filter="data")
            else:
                t.extractall(unpacked)
    tops = list(unpacked.iterdir())
    root = tops[0] if len(tops) == 1 and tops[0].is_dir() else unpacked
    print(root.resolve().as_posix())


# package

def library_files(platform, install, version):
    """The library's files in the install tree, the real file first, and the folder they go to in the archive."""
    if platform == "windows":
        # cmake --install puts the DLL in bin/ and its import library in lib/; Microsoft's archive has both in lib/.
        return [install / "bin" / "onnxruntime.dll", install / "lib" / "onnxruntime.lib"]
    if platform == "linux":
        libdir = next((d for d in (install / "lib", install / "lib64") if (d / f"libonnxruntime.so.{version}").exists()), install / "lib")
        real = libdir / f"libonnxruntime.so.{version}"
        others = sorted(p for p in libdir.glob("libonnxruntime.so*") if p != real)
    else:
        libdir = install / "lib"
        real = libdir / f"libonnxruntime.{version}.dylib"
        others = sorted(p for p in libdir.glob("libonnxruntime.*dylib") if p != real)
    return [real, *others]


def package(a):
    install, source, stage = pathlib.Path(a.install), pathlib.Path(a.source), pathlib.Path(a.stage) / a.name
    out = pathlib.Path(a.out)
    if stage.exists():
        shutil.rmtree(stage)
    (stage / "lib").mkdir(parents=True)
    (stage / "include").mkdir()
    out.mkdir(parents=True, exist_ok=True)

    files = library_files(a.platform, install, a.version)
    for f in files:
        if not os.path.lexists(f):
            die(f"the install tree has no {f}")
    if files[0].is_symlink() or not files[0].is_file():
        die(f"{files[0]} is not a regular file")
    for f in files:
        shutil.copy2(f, stage / "lib" / f.name, follow_symlinks=False)  # the .so and .dylib links stay links
    library = stage / "lib" / files[0].name
    # Microsoft's Linux library is stripped of its symbol table and its macOS one of debug symbols (strip -S, in
    # tools/ci_build/github/linux/copy_strip_binary.sh); a Windows DLL keeps its debug information apart already.
    if a.platform == "linux":
        subprocess.run(["strip", str(library)], check=True)
    elif a.platform == "macos":
        subprocess.run(["strip", "-S", str(library)], check=True)

    for h in HEADERS:
        built = install / "include" / "onnxruntime" / h
        if not built.is_file():
            die(f"the install tree has no {built}")
        shutil.copy2(built, stage / "include" / h)
        # Windows checks the sources out with Windows line endings; the vendored copies have Unix ones.
        if built.read_bytes().replace(b"\r\n", b"\n") != pathlib.Path(a.vendored, h).read_bytes().replace(b"\r\n", b"\n"):
            die(f"{h} differs from the vendored copy in {a.vendored}")

    for name, src in (("LICENSE", "LICENSE"), ("ThirdPartyNotices.txt", "ThirdPartyNotices.txt"),
                      ("Privacy.md", "docs/Privacy.md"), ("VERSION_NUMBER", "VERSION_NUMBER")):
        shutil.copy2(source / src, stage / name)
    if (stage / "VERSION_NUMBER").read_text(encoding="utf-8").strip() != a.version:
        die(f"VERSION_NUMBER is not {a.version}")
    commit = git("-C", str(source), "rev-parse", "HEAD").strip()
    if commit != a.commit:
        die(f"the source is at {commit}, expected {a.commit}")
    (stage / "GIT_COMMIT_ID").write_bytes(f"{commit}\n".encode())

    if a.platform == "windows":
        archive = out / f"{a.name}.zip"
        with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as z:
            for p in sorted(stage.rglob("*")):
                z.write(p, p.relative_to(stage.parent).as_posix())
    else:
        archive = out / f"{a.name}.tgz"

        def owned_by_root(info):
            info.uid = info.gid = 0
            info.uname = info.gname = "root"
            return info

        with tarfile.open(archive, "w:gz") as t:
            t.add(stage, arcname=a.name, filter=owned_by_root)
    archive_sha = sha256(archive)
    pathlib.Path(f"{archive}.sha256").write_bytes(f"{archive_sha}  {archive.name}\n".encode())

    lib_size, lib_sha = library.stat().st_size, sha256(library)
    arc_size = archive.stat().st_size
    try:
        cmake = subprocess.run(["cmake", "--version"], capture_output=True, text=True).stdout.splitlines()[0]
    except (OSError, IndexError):
        cmake = "cmake version unknown"
    lines = [
        f"## {a.name}",
        "",
        f"ONNX Runtime {a.version} at commit `{a.commit}`, built with `--no_telemetry` on "
        f"{os.environ.get('RUNNER_OS', sys.platform)} {os.environ.get('RUNNER_ARCH', '')} with {os.cpu_count()} cores, {cmake}.",
        "",
        "| | Bytes | SHA-256 |",
        "|---|---:|---|",
        f"| Library `lib/{library.name}` | {grouped(lib_size)} | `{lib_sha}` |",
        f"| Archive `{archive.name}` | {grouped(arc_size)} | `{archive_sha}` |",
        "",
    ]
    if a.build_seconds is not None:
        s = int(a.build_seconds)
        lines.append(f"Build time, wall clock (configure, dependency downloads, compile): {s // 3600} h {s % 3600 // 60} min {s % 60} s.")
        lines.append("")
    if a.official_size:
        diff = lib_size - a.official_size
        lines.append(f"Against Microsoft's official library ({grouped(a.official_size)} bytes): "
                     f"{grouped(abs(diff))} bytes {'smaller' if diff < 0 else 'larger'} ({diff / a.official_size:+.1%}).")
    else:
        lines.append("Microsoft's official library for this platform is not recorded in DEPENDENCIES.md, so no size comparison.")
    lines += ["", "In the archive:", ""]
    for p in sorted(stage.rglob("*")):
        rel = p.relative_to(stage).as_posix()
        if p.is_symlink():
            lines.append(f"- `{rel}` -> `{os.readlink(p)}`")
        elif p.is_file():
            lines.append(f"- `{rel}`, {grouped(p.stat().st_size)} bytes, SHA-256 `{sha256(p)}`")
    lines.append("")
    text = "\n".join(lines) + "\n"
    print(text)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as f:
            f.write(text)


def main():
    parser = argparse.ArgumentParser(description="The shared steps of onnxruntime-build.yml.")
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("check-source")
    for arg in ("--source", "--remote", "--tag", "--commit", "--version"):
        p.add_argument(arg, required=True)
    p.add_argument("--tag-commit", default=None, help="the commit the tag must point at, when that is not --commit")
    p = sub.add_parser("fetch-dep")
    for arg in ("--deps", "--name", "--dest"):
        p.add_argument(arg, required=True)
    p = sub.add_parser("package")
    p.add_argument("--platform", required=True, choices=["linux", "macos", "windows"])
    for arg in ("--version", "--commit", "--source", "--install", "--vendored", "--name", "--stage", "--out"):
        p.add_argument(arg, required=True)
    p.add_argument("--official-size", type=int)
    p.add_argument("--build-seconds", type=int)
    a = parser.parse_args()
    {"check-source": check_source, "fetch-dep": fetch_dep, "package": package}[a.command](a)


if __name__ == "__main__":
    main()
