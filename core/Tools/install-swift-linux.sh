#!/usr/bin/env bash
# install-swift-linux.sh: install the Swift toolchain on Ubuntu 24.04 (x86_64) from the official Docker Hub image.
#
#   core/Tools/install-swift-linux.sh [VERSION] [PREFIX]
#
# VERSION defaults to 6.4.1 and PREFIX to /opt/swift-<VERSION without dots>, so 6.4.1 goes to /opt/swift-641.
# Writing under /opt needs root (or sudo). The tools end up in PREFIX/usr/bin; the script prints the PATH line.
#
# Why this route. Swift for Linux normally comes from download.swift.org, directly or through swiftly (Swift's own
# installer, which downloads from the same site). In Deckie's cloud sessions the network policy blocks that site:
# every request is refused with a 403. Ubuntu's own package archive has no Swift. Docker Hub is reachable, and the
# Swift project publishes each release there as the official image swift:<VERSION>-noble, built from
# github.com/apple/swift-docker on Ubuntu 24.04 ("noble"). An image is a stack of layers, each a .tar.gz of files.
# This script fetches the linux/amd64 layers with curl through the registry's HTTP API and unpacks them, in order,
# under PREFIX; Docker itself is not needed. The result is the image's whole Ubuntu file system, with the toolchain
# in PREFIX/usr/bin; the tools run from there against this machine's own system libraries.
#
# What it trusts. Docker Hub, reached over HTTPS, to say which image the tag names today (the "image index"); the
# script does not check any signature on that answer. From the index down, every byte is pinned by SHA-256: the
# index names the amd64 manifest by its hash, the manifest names each layer by its hash, and the script recomputes
# each of those hashes over what it received and stops at the first difference, before anything is unpacked.
#
# Where it runs. Ubuntu 24.04 on x86_64, the system the image is built for. It refuses any other processor
# architecture, and on another distribution or release it warns and carries on (the toolchain may not start there).
#
# Safety. Downloads and unpacking happen in a temporary folder next to PREFIX. PREFIX itself appears only at the
# end, in a single rename, once every layer has verified and the unpacked swift reports VERSION; a failure or
# Ctrl-C before that leaves PREFIX untouched, and the temporary folder is removed however the script ends (short of
# kill -9). Run again once installed, it only reports the version.
#
# Needs: bash, curl, python3 (to read the JSON manifests), tar with gzip, and sha256sum.

if [ -z "${BASH_VERSION:-}" ]; then echo "install-swift-linux: run this with bash" >&2; exit 1; fi
set -euo pipefail

usage="usage: install-swift-linux.sh [VERSION] [PREFIX]   (defaults: 6.4.1 and /opt/swift-<VERSION without dots>)"

say() { printf '%s\n' "$*"; }
die() { printf 'install-swift-linux: %s\n' "$*" >&2; exit 1; }

for arg in "$@"; do
  case $arg in
    -h|--help) say "$usage"; exit 0 ;;
    -*) printf '%s\n' "$usage" >&2; exit 2 ;;
  esac
done
if (( $# > 2 )); then printf '%s\n' "$usage" >&2; exit 2; fi

version=${1:-6.4.1}
[[ $version =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || die "VERSION should look like 6.4.1, not '$version'"
prefix=$(realpath -m -- "${2:-/opt/swift-${version//./}}")
[[ $prefix != / ]] || die "PREFIX cannot be /"
path_line=$(printf 'export PATH="$PATH:%s/usr/bin"' "$prefix")

# Prints the "Swift version ..." line of `$1 --version`; fails if that does not run or has no such line.
swift_reports() {
  local out line
  out=$("$1" --version 2>&1) || return 1
  while IFS= read -r line; do
    if [[ $line == *"Swift version "* ]]; then printf '%s\n' "$line"; return 0; fi
  done <<<"$out"
  return 1
}

# Already installed? Then there is nothing to do.
reported=""
if [[ -x $prefix/usr/bin/swift ]]; then
  if reported=$(swift_reports "$prefix/usr/bin/swift") && [[ $reported == *"Swift version $version ("* ]]; then
    say "Swift $version is already installed in $prefix ($reported). Nothing to do."
    say "To use it: $path_line"
    exit 0
  fi
fi

# PREFIX must not exist yet, apart from an empty folder.
empty_prefix=0
if [[ -e $prefix || -L $prefix ]]; then
  if [[ -d $prefix && ! -L $prefix && -z $(find "$prefix" -mindepth 1 -maxdepth 1 -print -quit) ]]; then
    empty_prefix=1
  elif [[ -n $reported ]]; then
    die "$prefix already holds another Swift ($reported). Remove it first, or give another PREFIX."
  else
    die "$prefix already exists and does not hold Swift $version. Remove it first, or give another PREFIX."
  fi
fi

# The tools this script uses.
missing=()
for tool in curl python3 tar gzip sha256sum; do
  command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
done
if (( ${#missing[@]} > 0 )); then
  die "missing: ${missing[*]}. Install them first" \
      "(Ubuntu packages curl, python3, tar, gzip; sha256sum is in coreutils)."
fi

# The machine: x86_64 only; Ubuntu 24.04 expected.
arch=$(uname -m)
[[ $arch == x86_64 ]] || die "this machine is $arch; this script installs the x86_64 (amd64) toolchain only."
os="an unknown system (no /etc/os-release)"
os_id=""
if [[ -r /etc/os-release ]]; then
  os_id=$(. /etc/os-release && printf '%s %s' "${ID:-}" "${VERSION_ID:-}")
  os=$(. /etc/os-release && printf '%s' "${PRETTY_NAME:-$os_id}")
fi
if [[ $os_id != "ubuntu 24.04" ]]; then
  say "Warning: this machine runs $os, not Ubuntu 24.04. The toolchain is built for Ubuntu 24.04 and uses this"
  say "machine's system libraries, so it may not start here. Carrying on."
fi

# A temporary folder next to PREFIX (same file system, so the final rename is instant), removed on any exit.
parent=$(dirname -- "$prefix")
mkdir -p -- "$parent" 2>/dev/null && [[ -w $parent ]] ||
  die "cannot write to $parent. Run with sudo, or give a PREFIX you can write to, such as \$HOME/swift-${version//./}."
work=$(mktemp -d -- "$parent/.$(basename -- "$prefix").partial.XXXXXX")
cleanup() {
  if [[ -n ${work:-} && -d $work ]]; then
    chmod -R u+w -- "$work" 2>/dev/null || true
    rm -rf -- "$work" || printf 'install-swift-linux: could not remove %s; delete it by hand\n' "$work" >&2
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

registry=https://registry-1.docker.io
repo=library/swift
tag="$version-noble"

# An anonymous pull token for the swift repository (they expire after a few minutes, so each request gets a fresh one).
token() {
  local json
  json=$(curl -fsS --retry 3 --retry-connrefused \
    "https://auth.docker.io/token?service=registry.docker.io&scope=repository:$repo:pull") || return 1
  python3 -I -c 'import json, sys; d = json.load(sys.stdin); print(d.get("token") or d["access_token"])' <<<"$json"
}

# Fetches manifest $1 (a tag or a digest) into file $2, byte for byte, accepting the media types in $3. Docker Hub
# limits anonymous manifest requests per network address, and a cloud session's outgoing addresses are shared with
# others (its proxy spreads connections over several). When the limit is used up Docker Hub answers 429; this waits
# 20 s and tries again on a new connection, for up to five minutes.
fetch_manifest() {
  local ref=$1 out=$2 accept=$3 tok code attempt
  for attempt in $(seq 1 15); do
    tok=$(token) || die "could not get a pull token from auth.docker.io."
    code=$(curl -sS --retry 3 --retry-connrefused -o "$out" -w '%{http_code}' \
      -H "Authorization: Bearer $tok" -H "Accept: $accept" "$registry/v2/$repo/manifests/$ref") ||
      die "could not reach $registry (curl failed)."
    case $code in
      200) return 0 ;;
      404) die "Docker Hub has no swift:$ref. Check VERSION (the image tags look like 6.4.1-noble)." ;;
      429) say "Docker Hub's anonymous request limit for this network address is used up; trying again in 20 s" \
             "($attempt/15)."
           sleep 20 ;;
      *) die "Docker Hub answered HTTP $code for $repo manifest $ref." ;;
    esac
  done
  die "Docker Hub is still refusing requests from this address (rate limit). Try again in a while."
}

sha256_of() {
  local out
  out=$(sha256sum -- "$1") || return 1
  printf '%s\n' "${out%% *}"
}

mb() { printf '%d' $(( ($1 + 524288) / 1048576 )); }

check_digest() { [[ $1 =~ ^sha256:[0-9a-f]{64}$ ]] || die "unexpected digest '$1' in the $2."; }

# tar exits with status 2 after messages like "Cannot change ownership" or "Cannot utime", which some containers
# produce because they forbid changing a file's owner or timestamps. Those are harmless here (the files get the
# installing user as owner and may keep today's date); any other message, or any other non-zero status, is fatal.
harmless_re='^tar: .*: (Cannot change ownership to uid [0-9]+, gid [0-9]+|Cannot utime): '
tar_exit_re='^tar: Exiting with failure status due to previous errors$'
extract() {  # $1 archive, $2 destination folder, $3 label for messages
  local status=0 ignored=0 line others=()
  tar -xzf "$1" -C "$2" --no-same-owner 2>"$work/tar.log" || status=$?
  while IFS= read -r line; do
    if [[ $line =~ $harmless_re ]]; then ignored=$((ignored + 1))
    elif [[ ! $line =~ $tar_exit_re ]]; then others+=("$line")
    fi
  done <"$work/tar.log"
  if (( status != 0 )) && (( status != 2 || ${#others[@]} > 0 || ignored == 0 )); then
    if (( ${#others[@]} > 0 )); then printf '  %s\n' "${others[@]:0:20}" >&2; fi
    die "unpacking $3 failed (tar exit status $status). Nothing was installed."
  fi
  if (( ${#others[@]} > 0 )); then printf '  tar: %s\n' "${others[@]:0:20}"; fi
  if (( ignored > 0 )); then say "  (ignored $ignored harmless tar warnings about file owners or timestamps)"; fi
}

index_types="application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json"
manifest_types="application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json"

py_pick_amd64='
import json, sys
with open(sys.argv[1], "rb") as f:
    d = json.load(f)
kinds = ("application/vnd.oci.image.index.v1+json", "application/vnd.docker.distribution.manifest.list.v2+json")
if d.get("mediaType") not in kinds:
    sys.exit("expected a multi-platform image index, got media type %r" % d.get("mediaType"))
hits = [m for m in d.get("manifests", [])
        if (m.get("platform") or {}).get("os") == "linux" and (m.get("platform") or {}).get("architecture") == "amd64"]
if len(hits) != 1:
    sys.exit("expected one linux/amd64 entry in the image index, found %d" % len(hits))
m = hits[0]
version = (m.get("annotations") or {}).get("org.opencontainers.image.version") or "-"
print(m["digest"], int(m["size"]), m["mediaType"], version)
'
py_layers='
import json, sys
with open(sys.argv[1], "rb") as f:
    d = json.load(f)
if d.get("schemaVersion") != 2 or not d.get("layers"):
    sys.exit("not an image manifest with layers")
for layer in d["layers"]:
    print(layer["digest"], int(layer["size"]), layer["mediaType"])
'

say "Installing Swift $version (x86_64) into $prefix from the Docker Hub image swift:$tag."

# 1. The image index: which manifest is linux/amd64.
fetch_manifest "$tag" "$work/index.json" "$index_types, $manifest_types"
picked=$(python3 -I -c "$py_pick_amd64" "$work/index.json") || die "could not read the image index for swift:$tag."
read -r man_digest man_size man_type image_version <<<"$picked"
check_digest "$man_digest" "image index"
# A tag such as 6.4-noble follows the newest 6.4.x; catch that here rather than after the download.
if [[ $image_version != - && $image_version != "$tag" ]]; then
  die "swift:$tag is currently the image $image_version. Ask for that version exactly:" \
      "install-swift-linux.sh ${image_version%-noble}"
fi
say "Image index: the linux/amd64 manifest is $man_digest."

# 2. That manifest, checked against the hash and size the index gave for it.
fetch_manifest "$man_digest" "$work/manifest.json" "$man_type"
man_got="sha256:$(sha256_of "$work/manifest.json")"
[[ $man_got == "$man_digest" ]] ||
  die "the amd64 manifest's SHA-256 is $man_got, but the image index names $man_digest. Refusing to continue."
man_got_size=$(stat -c %s -- "$work/manifest.json")
[[ $man_got_size == "$man_size" ]] ||
  die "the amd64 manifest is $man_got_size bytes, but the image index says $man_size. Refusing to continue."
say "Manifest: SHA-256 matches the index."

# 3. Its layers, in order. Each is checked against its manifest hash as soon as it arrives.
listing=$(python3 -I -c "$py_layers" "$work/manifest.json") || die "could not read the layer list from the manifest."
mapfile -t layers <<<"$listing"
total=0
for entry in "${layers[@]}"; do
  read -r digest size type <<<"$entry"
  check_digest "$digest" "manifest"
  case $type in
    application/vnd.oci.image.layer.v1.tar+gzip|application/vnd.docker.image.rootfs.diff.tar.gzip) ;;
    *) die "layer $digest has media type $type; this script only unpacks gzip-compressed tar layers." ;;
  esac
  total=$((total + size))
done
n=${#layers[@]}
say "Downloading $n layers, $(mb "$total") MB in all."
if [[ -t 2 ]]; then progress=(--progress-bar); else progress=(--silent --show-error); fi
mkdir -- "$work/layers"
for i in "${!layers[@]}"; do
  read -r digest size type <<<"${layers[$i]}"
  file="$work/layers/$i.tar.gz"
  say "Layer $((i + 1))/$n: $digest ($(mb "$size") MB)"
  tok=$(token) || die "could not get a pull token from auth.docker.io."
  # The registry answers with a redirect to its download network; curl follows it (and does not pass the token on).
  curl "${progress[@]}" --fail --location --retry 5 --retry-all-errors --retry-delay 3 \
    -H "Authorization: Bearer $tok" -o "$file" "$registry/v2/$repo/blobs/$digest" ||
    die "downloading layer $((i + 1)) failed. Nothing was installed."
  got="sha256:$(sha256_of "$file")"
  [[ $got == "$digest" ]] ||
    die "layer $((i + 1)) has SHA-256 $got, but the manifest names $digest. Stopping; nothing was installed."
  say "  SHA-256 matches the manifest."
done

# 4. Before unpacking anything: Docker marks files a layer deletes with ".wh." entries ("whiteouts"), which plain tar
#    would unpack as ordinary files. The Swift images have none; if one ever does, stop rather than install a tree
#    that differs from the image.
for i in "${!layers[@]}"; do
  tar -tzf "$work/layers/$i.tar.gz" >"$work/list.txt" 2>"$work/list.err" ||
    die "layer $((i + 1)) is not a readable .tar.gz: $(head -n 3 -- "$work/list.err")"
  rc=0
  grep -q -E '(^|/)\.wh\.' -- "$work/list.txt" || rc=$?
  case $rc in
    0) die "layer $((i + 1)) deletes files from earlier layers (Docker whiteout entries), which this script" \
         "does not apply. Nothing was installed." ;;
    1) ;;
    *) die "could not read the file list of layer $((i + 1))." ;;
  esac
done
say "All layers verified."

# 5. Unpack in manifest order into the temporary folder, then check the result runs and is the right version.
mkdir -- "$work/root"
for i in "${!layers[@]}"; do
  say "Unpacking layer $((i + 1))/$n."
  extract "$work/layers/$i.tar.gz" "$work/root" "layer $((i + 1))"
done
rm -rf -- "$work/layers"
say "Removed the downloaded layers."
staged=$(swift_reports "$work/root/usr/bin/swift") ||
  die "the unpacked image has no working usr/bin/swift. Nothing was installed."
[[ $staged == *"Swift version $version ("* ]] ||
  die "the image swift:$tag reports \"$staged\", not Swift $version. Nothing was installed."

# 6. Move it into place in one step.
if (( empty_prefix )); then rmdir -- "$prefix"; fi
mv -T -- "$work/root" "$prefix"

final=$("$prefix/usr/bin/swift" --version 2>&1) || die "$prefix/usr/bin/swift --version failed after the install."
say "$final"
say "Installed Swift $version in $prefix (${SECONDS} s)."
say "To use it, run this line in your shell, or add it to your shell's start-up file (for example ~/.bashrc):"
say "  $path_line"
say "(It adds to the end of PATH: the folder also holds the image's copies of everyday tools such as bash and git,"
say "which should not take the place of this machine's own.)"
