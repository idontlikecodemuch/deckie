#!/bin/bash
# release-mac.sh: Deckie Desk for Mac made ready to hand to testers: a Release build, a Developer ID signature with
# the hardened runtime, a disk image, and (only when asked for by name) Apple's notarisation and stapling.
#
#   desk-app/tools/release-mac.sh [stage ...]
#
#   build      a clean Release build for Apple silicon, with the learned key reader and Deckie's own ONNX Runtime
#   sign       signs every piece of code in the app from the inside out, then the app, with the hardened runtime
#   verify     checks the signature and prints its flags, its entitlements and Gatekeeper's answer
#   package    makes "Deckie Desk.dmg" (the app, an Applications alias, Desk's icon on the volume), signs it and
#              checks it mounts
#   notarise   sends the app to Apple's notary service through the account signed in to Xcode, then does what
#              notarise-finish does; never part of a run without stage names
#   notarise-finish   waits for the notarised, stapled app from Xcode, checks it, makes the disk image and the zip
#   notarise-check    the archive and a local export with nothing sent to Apple
#
# With no stage named it runs build, sign, verify and package, in that order. Stages can be run alone, in order; each
# checks that what it needs from the stage before is there.
#
# Everything it makes is in desk-app/build/release/ (git-ignored), and it refuses to delete or write anywhere else,
# with two exceptions that the everyday build in desk-app/README.md makes too: xcodegen writes the generated project
# desk-app/Desk.xcodeproj, and, when the learned key reader's two files are missing from desk-app/Vendor/models, the
# repository's own fetch script puts them there, checked against their pinned hashes (both git-ignored).
#
# Environment:
#   DECKIE_SIGN_IDENTITY    the signing identity, by name or hash, as codesign takes it. By default the keychain's one
#                           "Developer ID Application" identity, found by name when the script runs; none is written
#                           in this repository.
#   DECKIE_NOTARY_INTERVAL, DECKIE_NOTARY_MINUTES   how often (seconds, default 60) and how long (minutes, default 60)
#                           notarise-finish asks Xcode for the notarised app
#   DECKIE_SIGN_TIMESTAMP   1 (default) asks Apple's timestamp server for a secure timestamp, which notarisation
#                           requires; 0 leaves it out, for trial signatures when the server cannot be reached
#   DECKIE_ONNXRUNTIME_ARCHIVE   where to get Deckie's own ONNX Runtime archive for macOS, any address curl takes
#                           (file:// included); by default this repository's release, checked by its pinned hash
#
# What the owner does once, and the commands, are in desk-app/README.md ("Releasing Desk for Mac").

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
desk="$(cd "$here/.." && pwd -P)"
repo="$(cd "$desk/.." && pwd -P)"
out="$desk/build/release"
app_name="Deckie Desk"
app="$out/$app_name.app"
dmg="$out/$app_name.dmg"
entitlements="$desk/Desk/Desk.entitlements"
timestamp="${DECKIE_SIGN_TIMESTAMP:-1}"

# Deckie's own build of ONNX Runtime 1.31.1 for macOS arm64, made without Microsoft's usage-reporting client and
# published Oct 29, 2026 on the release onnxruntime-1.31.1-deckie-no-telemetry (DEPENDENCIES.md, section 6, the table
# of Deckie's own build). A shipped build carries this library, as the Windows zip carries Deckie's own DLL.
ORT_VERSION="1.31.1"
ORT_ARCHIVE="onnxruntime-osx-arm64-${ORT_VERSION}-deckie-no-telemetry.tgz"
ORT_ARCHIVE_SHA256="f6f5b2909767ab8c032e0d60b757c5853f1fd4866261d016ceb1003c3fcc9d43"
ORT_LIB="libonnxruntime.${ORT_VERSION}.dylib"
ORT_LIB_SHA256="11aaad020b6da108e1ba24393d77a431884cf1a9b4097198e3c48f7c31b0f7c1"
ORT_URL="${DECKIE_ONNXRUNTIME_ARCHIVE:-https://github.com/idontlikecodemuch/deckie/releases/download/onnxruntime-${ORT_VERSION}-deckie-no-telemetry/${ORT_ARCHIVE}}"

say() { printf '%s\n' "$*"; }
step() { printf '\n== %s\n' "$*"; }
die() { printf 'release-mac: %s\n' "$*" >&2; exit 1; }
sha256() { shasum -a 256 "$1" | cut -d' ' -f1; }

# --- The one place it writes -----------------------------------------------------------------------------------------

# desk-app/build must be a real folder in this checkout, not a link to somewhere else.
mkdir -p "$desk/build"
[ ! -L "$desk/build" ] || die "desk-app/build is a link; refusing to write through it"
[ "$(cd "$desk/build" && pwd -P)" = "$desk/build" ] || die "desk-app/build is not inside this checkout"
mkdir -p "$out"
[ ! -L "$out" ] && [ "$(cd "$out" && pwd -P)" = "$out" ] || die "desk-app/build/release is not a plain folder here"

# Every path the script removes or writes goes through this: it must be below desk-app/build/release/.
inside() {
    local p="$1"
    case "$p" in *"/../"*|*"/.."|*"/./"*) die "refusing a path with . or .. in it: $p" ;; esac
    case "$p" in "$out"/?*) return 0 ;; *) die "refusing to touch $p: only desk-app/build/release/ is written" ;; esac
}
fresh() { inside "$1"; rm -rf "$1"; }

# --- The identity, looked up when the script runs ---------------------------------------------------------------------

identity=""
find_identity() {
    [ -z "$identity" ] || return 0
    if [ -n "${DECKIE_SIGN_IDENTITY:-}" ]; then
        identity="$DECKIE_SIGN_IDENTITY"
        security find-identity -v -p codesigning | grep -F -- "$identity" >/dev/null ||
            die "no valid code-signing identity in the keychain matches DECKIE_SIGN_IDENTITY ($identity)"
        return 0
    fi
    local found
    found="$(security find-identity -v -p codesigning | sed -n 's/^ *[0-9][0-9]*) [0-9A-F]\{40\} "\(Developer ID Application: .*\)"$/\1/p')"
    case "$(printf '%s' "$found" | grep -c .)" in
        0) die "there is no \"Developer ID Application\" identity in the keychain, and DECKIE_SIGN_IDENTITY names none.
  A tester's Mac opens Desk only with that certificate. Make it once: Xcode > Settings > Accounts > the team >
  Manage Certificates > + > Developer ID Application (desk-app/README.md, \"Releasing Desk for Mac\").
  For a trial signature with another identity, set DECKIE_SIGN_IDENTITY to its name." ;;
        1) identity="$found" ;;
        *) die "more than one \"Developer ID Application\" identity is in the keychain; set DECKIE_SIGN_IDENTITY to the one to use" ;;
    esac
}

# Desk run from this script never touches real storage or looks in a real home folder.
run_desk() {
    local scratch="$out/scratch"
    mkdir -p "$scratch/home" "$scratch/dj" "$scratch/drives"
    env -u DECKIE_ONNXRUNTIME_LIB -u DECKIE_BEAT_MODEL -u DECKIE_YAMNET_MODEL -u DECKIE_KEY_MODEL \
        DECKIE_DESK_HOME="$scratch/home" DECKIE_DJ_HOME="$scratch/dj" DECKIE_DESK_DRIVES="$scratch/drives" \
        DECKIE_LOOKUP_OFF=1 DECKIE_NO_BOXES=1 "$1/Contents/MacOS/$app_name" "${@:2}"
}

# Every file in a bundle that is code, found by looking at it, not by name.
code_files() {
    find "$1" -type f -print0 | while IFS= read -r -d '' f; do
        case "$(file -b "$f")" in *Mach-O*) printf '%s\n' "$f" ;; esac
    done
}
# Folders inside a bundle that are bundles of code themselves, deepest first.
nested_bundles() {
    find "$1/Contents" -type d \( -name '*.framework' -o -name '*.bundle' -o -name '*.app' -o -name '*.appex' \
        -o -name '*.xpc' -o -name '*.plugin' \) -print | awk '{ print gsub("/", "/"), $0 }' |
        sort -rn | cut -d' ' -f2-
}
by_depth() { awk '{ print gsub("/", "/"), $0 }' | sort -rn | cut -d' ' -f2-; }

# --- build -----------------------------------------------------------------------------------------------------------

stage_build() {
    step "build"
    for tool in xcodegen xcodebuild curl shasum; do command -v "$tool" >/dev/null || die "needs $tool"; done
    local free; free="$(df -g / | awk 'NR == 2 { print $4 }')"
    [ "${free:-0}" -ge 30 ] || die "only ${free} GB free on the start-up disk; a build here needs at least 30 GB free"

    local v="$desk/Vendor"
    for f in "$ORT_LIB" models/beat_this_final0.onnx models/yamnet.onnx; do
        [ -f "$v/$f" ] || die "desk-app/Vendor/$f is missing; the build copies it into the app (desk-app/README.md, Build)"
    done

    # The learned key reader, as the Windows zip ships it (pc-package.yml: KEY_MODEL required since Nov 21, 2026):
    # its file and its credit list, both checked against their pinned hashes by the repository's own script.
    if ! bash "$repo/core/Tools/fetch-key-model.sh" --check --into "$v/models"; then
        say "fetching the learned key reader's two files into desk-app/Vendor/models (checked by hash)"
        bash "$repo/core/Tools/fetch-key-model.sh" --require --into "$v/models" ||
            die "the learned key reader's file or its credit list could not be had with the pinned hashes. A release reads
  keys with the learned reader, as the Windows zip does. Fetch them (bash core/Tools/fetch-key-model.sh --into
  desk-app/Vendor/models) or say what went wrong."
    fi

    # Deckie's own ONNX Runtime, fetched into build/release/onnxruntime and checked by its two pinned hashes.
    local ort="$out/onnxruntime"
    if [ ! -f "$ort/$ORT_LIB" ] || [ "$(sha256 "$ort/$ORT_LIB")" != "$ORT_LIB_SHA256" ]; then
        fresh "$ort"; mkdir -p "$ort/unpacked"
        say "downloading $ORT_URL"
        curl -fsSL --retry 3 -o "$ort/$ORT_ARCHIVE" "$ORT_URL" || die "could not download Deckie's ONNX Runtime from $ORT_URL"
        [ "$(sha256 "$ort/$ORT_ARCHIVE")" = "$ORT_ARCHIVE_SHA256" ] ||
            die "$ORT_ARCHIVE does not have the pinned SHA-256 $ORT_ARCHIVE_SHA256; nothing was unpacked"
        tar -xzf "$ort/$ORT_ARCHIVE" -C "$ort/unpacked" --strip-components=1
        [ -f "$ort/unpacked/lib/$ORT_LIB" ] || die "$ORT_ARCHIVE has no lib/$ORT_LIB"
        cp -f "$ort/unpacked/lib/$ORT_LIB" "$ort/$ORT_LIB"
        [ "$(sha256 "$ort/$ORT_LIB")" = "$ORT_LIB_SHA256" ] || die "lib/$ORT_LIB in the archive does not have the pinned SHA-256"
    fi
    say "ONNX Runtime: Deckie's own build, SHA-256 $ORT_LIB_SHA256"
    bash "$repo/core/Tools/scan-onnxruntime.sh" "$ort/$ORT_LIB" || die "the ONNX Runtime library carries the usage-reporting client"

    (cd "$desk" && xcodegen generate --quiet)
    local dd="$out/DerivedData"
    fresh "$dd"; fresh "$app"
    say "building (Release, Apple silicon, 2 jobs, nice 19); the log is $out/build.log"
    if ! (cd "$desk" && nice -n 19 xcodebuild -project Desk.xcodeproj -scheme Desk -configuration Release \
            -destination 'platform=macOS,arch=arm64' -derivedDataPath "$dd" -jobs 2 \
            ARCHS=arm64 ONLY_ACTIVE_ARCH=NO clean build) > "$out/build.log" 2>&1; then
        tail -40 "$out/build.log"; die "the build failed; the whole log is $out/build.log"
    fi
    local built="$dd/Build/Products/Release/$app_name.app"
    [ -d "$built" ] || die "the build made no $app_name.app"
    ditto "$built" "$app"

    # The library the app ships is Deckie's own, in place of the one in Vendor/ (often Microsoft's, for development).
    cp -f "$ort/$ORT_LIB" "$app/Contents/Frameworks/$ORT_LIB"

    local key; key="$(sed -n 's/^ *public static let pinnedName = "\([a-z0-9-]*\)"$/\1/p' "$repo/core/Sources/DeckieCore/Key/LearnedKey.swift")"
    [ -f "$app/Contents/Resources/models/$key.f16" ] || die "the app has no Contents/Resources/models/$key.f16"
    [ -f "$app/Contents/Resources/licences/$key-credits.tsv" ] || die "the app has no Contents/Resources/licences/$key-credits.tsv"
    local arch; arch="$(lipo -archs "$app/Contents/MacOS/$app_name")"
    [ "$arch" = arm64 ] || die "the app's program is built for \"$arch\", not arm64 alone"
    say "engine check (scratch storage):"
    run_desk "$app" --check-engine
    say "built: $app ($(du -sh "$app" | cut -f1))"
}

# --- sign ------------------------------------------------------------------------------------------------------------

sign_one() {  # path [entitlements]
    local args=(--force --sign "$identity" --options runtime)
    [ "$timestamp" = 0 ] && args+=(--timestamp=none) || args+=(--timestamp)
    [ $# -ge 2 ] && args+=(--entitlements "$2")
    codesign "${args[@]}" "$1" || die "codesign failed on $1 (if the keychain is locked or asked for a password, unlock it yourself and run this stage again)"
}

stage_sign() {
    step "sign"
    [ -d "$app" ] || die "no $app_name.app in desk-app/build/release; run the build stage first"
    [ -f "$entitlements" ] || die "the entitlements file is missing: $entitlements"
    plutil -lint "$entitlements" >/dev/null || die "the entitlements file is not a valid property list"
    find_identity
    say "identity: $identity"
    [ "$timestamp" = 0 ] && say "no secure timestamp (DECKIE_SIGN_TIMESTAMP=0): notarisation will refuse this signature"
    inside "$app"
    local main="$app/Contents/MacOS/$app_name" f n=0
    # Loose code first, deepest first: every Mach-O file but the app's own program.
    while IFS= read -r f; do
        [ "$f" = "$main" ] && continue
        say "  code: ${f#$app/}"; sign_one "$f"; n=$((n + 1))
    done < <(code_files "$app" | by_depth)
    # Then any bundle of code inside the app, deepest first (none today; signed whole if one comes).
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        say "  bundle: ${f#$app/}"; sign_one "$f"; n=$((n + 1))
    done < <(nested_bundles "$app")
    say "  the app, with $(basename "$entitlements")"
    sign_one "$app" "$entitlements"
    say "signed $n piece(s) of code inside the app, then the app"
}

# --- verify ----------------------------------------------------------------------------------------------------------

stage_verify() {
    step "verify"
    [ -d "$app" ] || die "no $app_name.app in desk-app/build/release; run build and sign first"
    codesign --verify --deep --strict --verbose=2 "$app" 2>&1 || die "the app's signature does not verify"
    local info; info="$(codesign -dvv "$app" 2>&1)"
    printf '%s\n' "$info" | grep -E '^(Identifier|Format|CodeDirectory|Authority|Timestamp|TeamIdentifier|Runtime Version)' || true
    printf '%s\n' "$info" | grep -q 'flags=0x[0-9a-f]*(runtime)' || die "the app is not signed with the hardened runtime"
    say "hardened runtime: on"
    local team; team="$(printf '%s\n' "$info" | sed -n 's/^TeamIdentifier=//p')"
    say "entitlements:"
    codesign -d --entitlements - --xml "$app" 2>/dev/null | plutil -p - || die "could not read the app's entitlements"
    # Library validation: every piece of code inside must carry the runtime flag and the app's own team.
    local f finfo fteam bad=0
    while IFS= read -r f; do
        finfo="$(codesign -dvv "$f" 2>&1)"; fteam="$(printf '%s\n' "$finfo" | sed -n 's/^TeamIdentifier=//p')"
        codesign --verify --strict "$f" 2>/dev/null || { say "  does not verify: ${f#$app/}"; bad=1; }
        printf '%s\n' "$finfo" | grep -q '(runtime)' || { say "  no hardened runtime: ${f#$app/}"; bad=1; }
        [ "$fteam" = "$team" ] || { say "  another team than the app's: ${f#$app/}"; bad=1; }
        say "  ${f#$app/}: $(printf '%s\n' "$finfo" | sed -n 's/^CodeDirectory .*flags=\(0x[0-9a-f]*([a-z,-]*)\).*/flags=\1/p'), same team as the app: $([ "$fteam" = "$team" ] && echo yes || echo no)"
    done < <(code_files "$app" | by_depth)
    [ "$bad" = 0 ] || die "some code inside the app is not signed as the app is"
    say "Gatekeeper (spctl -a -vv):"
    if spctl -a -vv "$app" 2>&1; then say "Gatekeeper accepts the app"
    else say "Gatekeeper rejects the app for now; until Apple notarises a Developer ID signature, that is expected"; fi
    say "size: $(du -sh "$app" | cut -f1)"
}

# --- package ---------------------------------------------------------------------------------------------------------

stage_package() {
    step "package"
    [ -d "$app" ] || die "no $app_name.app in desk-app/build/release; run build and sign first"
    codesign --verify --deep --strict "$app" 2>/dev/null || die "the app's signature does not verify; run the sign stage first"
    find_identity
    local root="$out/dmg-root" mnt="$out/mnt" rw="$out/dmg-rw.dmg" iconset="$out/volume.iconset"
    fresh "$root"; fresh "$dmg"; fresh "$rw"; fresh "$iconset"; mkdir -p "$root" "$iconset"
    ditto "$app" "$root/$app_name.app"
    ln -s /Applications "$root/Applications"
    # The volume's icon is Desk's own: .VolumeIcon.icns at the top of the volume, made from the icon set's pictures,
    # and the volume's custom-icon flag. hdiutil does not carry the flag over from a folder, so the image is made
    # writable first, the flag set on it mounted, then the image compressed.
    # iconutil wants the 2x pictures named "@2x"; the icon set names them "-2x", because a file name with "@" in it
    # reads as an email address to tools/check-private.sh.
    local p
    for p in "$desk/Desk/Assets.xcassets/AppIcon.appiconset/"icon_*.png; do
        cp "$p" "$iconset/$(basename "$p" | sed 's/-2x\.png$/@2x.png/')"
    done
    iconutil -c icns -o "$root/.VolumeIcon.icns" "$iconset" || die "iconutil could not make the volume icon"
    fresh "$iconset"
    hdiutil create -quiet -volname "$app_name" -srcfolder "$root" -fs HFS+ -format UDRW -ov "$rw" || die "hdiutil could not make the disk image"
    fresh "$root"
    fresh "$mnt"; mkdir -p "$mnt"
    hdiutil attach -quiet -nobrowse -readwrite -noautoopen -mountpoint "$mnt" "$rw" || die "the writable disk image does not mount"
    if command -v SetFile >/dev/null; then SetFile -a C "$mnt" || say "  SetFile could not set the volume's custom-icon flag"
    else say "  no SetFile (Xcode's command line tools): the volume keeps the plain disk icon"; fi
    hdiutil detach -quiet "$mnt" || hdiutil detach -quiet -force "$mnt"
    hdiutil convert -quiet "$rw" -format UDZO -ov -o "$dmg" || die "hdiutil could not compress the disk image"
    fresh "$rw"
    local args=(--force --sign "$identity")
    [ "$timestamp" = 0 ] && args+=(--timestamp=none) || args+=(--timestamp)
    codesign "${args[@]}" "$dmg" || die "codesign failed on the disk image"
    codesign --verify --strict --verbose=2 "$dmg" 2>&1 || die "the disk image's signature does not verify"

    say "mounting it to check what is inside:"
    fresh "$mnt"; mkdir -p "$mnt"
    hdiutil attach -quiet -nobrowse -readonly -noautoopen -mountpoint "$mnt" "$dmg" || die "the disk image does not mount"
    local ok=1
    ls -l "$mnt" | sed 's/^/  /'
    [ "$(readlink "$mnt/Applications")" = /Applications ] || { say "  no Applications alias"; ok=0; }
    if [ -f "$mnt/.VolumeIcon.icns" ] && GetFileInfo -a "$mnt" 2>/dev/null | grep -q C; then say "  volume icon: Desk's"
    else say "  volume icon: the plain disk icon"; fi
    codesign --verify --deep --strict --verbose=2 "$mnt/$app_name.app" 2>&1 | sed 's/^/  /' || ok=0
    codesign --verify --deep --strict "$mnt/$app_name.app" 2>/dev/null || ok=0
    hdiutil detach -quiet "$mnt" || hdiutil detach -quiet -force "$mnt"
    rmdir "$mnt" 2>/dev/null || true
    [ "$ok" = 1 ] || die "the app inside the disk image does not verify"
    say "disk image: $dmg ($(du -h "$dmg" | cut -f1))"
}

# --- notarise --------------------------------------------------------------------------------------------------------
# Only when named. Through Xcode's own signed-in account (Xcode > Settings > Accounts), not a notarytool profile:
# decided Nov 25, 2026, with no app-specific password and no API key. Written from `xcodebuild -help` (Xcode 27.2):
#
#   notarise-check   local only: the archive, the export options, and an export with destination "export", to see
#                    what Xcode's manual Developer ID re-sign does; nothing is sent to Apple
#   notarise         the archive, then `xcodebuild -exportArchive` with method developer-id and destination upload,
#                    which sends the app to Apple's notary service; then what notarise-finish does
#   notarise-finish  tries `xcodebuild -exportNotarizedApp` every DECKIE_NOTARY_INTERVAL seconds (default 60) for at
#                    most DECKIE_NOTARY_MINUTES minutes (default 60) until Apple has notarised the app and Xcode hands
#                    it back stapled; checks it strictly; puts it in place of the app; makes and signs the disk image
#                    from it (Xcode notarises the app only, so the image is signed, not notarised); makes the zip; and
#                    checks a copy of the image marked as downloaded, as a tester's Mac would see it
#
# The archive is made by hand around the app already built, signed and verified here, not by `xcodebuild archive`: a
# real archive builds the app again (ad hoc, as project.yml signs everyday builds) and its app would have to be
# swapped for this one anyway, leaving an archive whose Info.plist describes another signature. A hand-made archive is
# the folder layout and the Info.plist keys every Xcode archive has (ArchiveVersion 2, ApplicationProperties), filled
# from this app; notarise-check shows that Xcode exports it.

archive="$out/$app_name.xcarchive"
sent_mark="$out/$app_name.xcarchive-sent"   # written once the upload went, so notarise-finish never asks about an archive that was not sent
notary_interval="${DECKIE_NOTARY_INTERVAL:-60}"
notary_minutes="${DECKIE_NOTARY_MINUTES:-60}"
account_help="Xcode could not use the account. Unlock the login keychain (Keychain Access, or log in again), and make
  sure the team's account is signed in at Xcode > Settings > Accounts, then run this stage again."

team_of() { codesign -dvv "$1" 2>&1 | sed -n 's/^TeamIdentifier=//p'; }
flags_of() { sed -n 's/^CodeDirectory .*\(flags=0x[0-9a-f]*([a-z,-]*)\).*/\1/p'; }

# What a release app must be, checked without trusting how it was signed. With "notarised", also its stapled ticket
# and Gatekeeper's yes.
check_release_app() {  # app, label, [notarised]
    local a="$1" label="$2" info team ents f finfo bad=0
    say "checking $label: $a"
    codesign --verify --deep --strict --verbose=2 "$a" 2>&1 | sed 's/^/  /'
    codesign --verify --deep --strict "$a" 2>/dev/null || die "$label: the signature does not verify"
    info="$(codesign -dvv "$a" 2>&1)"
    printf '%s\n' "$info" | grep -q '^Authority=Developer ID Application: ' || die "$label: not signed by a Developer ID Application identity"
    printf '%s\n' "$info" | grep -q 'flags=0x[0-9a-f]*(runtime)' || die "$label: the hardened runtime flag is gone"
    printf '%s\n' "$info" | grep -q '^Timestamp=' || die "$label: no secure timestamp"
    team="$(printf '%s\n' "$info" | sed -n 's/^TeamIdentifier=//p')"
    [ -n "$team" ] && [ "$team" != "not set" ] || die "$label: no team in the signature"
    say "  Developer ID: yes; $(printf '%s\n' "$info" | flags_of); $(printf '%s\n' "$info" | grep '^Timestamp=')"
    ents="$(codesign -d --entitlements - --xml "$a" 2>/dev/null | plutil -convert json -o - - 2>/dev/null || true)"
    say "  entitlements: $ents"
    [ "$ents" = '{"com.apple.security.device.audio-input":true}' ] ||
        die "$label: the entitlements are not exactly the microphone (com.apple.security.device.audio-input) alone"
    while IFS= read -r f; do
        finfo="$(codesign -dvv "$f" 2>&1)"
        codesign --verify --strict "$f" 2>/dev/null || { say "  does not verify: ${f#$a/}"; bad=1; }
        printf '%s\n' "$finfo" | grep -q '(runtime)' || { say "  no hardened runtime: ${f#$a/}"; bad=1; }
        printf '%s\n' "$finfo" | grep -q '^Timestamp=' || { say "  no secure timestamp: ${f#$a/}"; bad=1; }
        [ "$(printf '%s\n' "$finfo" | sed -n 's/^TeamIdentifier=//p')" = "$team" ] || { say "  another team: ${f#$a/}"; bad=1; }
        say "  ${f#$a/}: $(printf '%s\n' "$finfo" | flags_of), timestamp $(printf '%s\n' "$finfo" | grep -q '^Timestamp=' && echo yes || echo no), same team: $([ "$(printf '%s\n' "$finfo" | sed -n 's/^TeamIdentifier=//p')" = "$team" ] && echo yes || echo no)"
    done < <(code_files "$a" | by_depth)
    [ "$bad" = 0 ] || die "$label: some code inside is not signed as the app is"
    check_onnxruntime "$a/Contents/Frameworks/$ORT_LIB" "$label"
    if [ "${3:-}" = notarised ]; then
        xcrun stapler validate "$a" || die "$label: the stapled ticket does not validate"
        local g; g="$(spctl -a -vv "$a" 2>&1 || true)"; printf '%s\n' "$g" | sed 's/^/  /'
        printf '%s\n' "$g" | grep -q 'accepted' && printf '%s\n' "$g" | grep -q 'source=Notarized Developer ID' ||
            die "$label: Gatekeeper does not accept it as Notarized Developer ID"
    fi
}

# The ONNX Runtime library must still be Deckie's own after any re-sign: no trace of the reporting client, and, when
# the pinned original is at hand (the build stage keeps it in build/release/onnxruntime), the same bytes once both
# signatures are taken off.
check_onnxruntime() {  # library, label
    local lib="$1" label="$2" orig="$out/onnxruntime/$ORT_LIB" cmp="$out/ort-compare"
    [ -f "$lib" ] || die "$label: no $ORT_LIB in Contents/Frameworks"
    bash "$repo/core/Tools/scan-onnxruntime.sh" "$lib" | sed 's/^/  /'
    [ "${PIPESTATUS[0]}" = 0 ] || die "$label: the ONNX Runtime library carries the usage-reporting client"
    if [ -f "$orig" ] && [ "$(sha256 "$orig")" = "$ORT_LIB_SHA256" ]; then
        fresh "$cmp"; mkdir -p "$cmp"
        cp "$orig" "$cmp/pinned"; cp "$lib" "$cmp/shipped"
        codesign --remove-signature "$cmp/pinned" 2>/dev/null || true
        codesign --remove-signature "$cmp/shipped" 2>/dev/null || true
        # Taking a signature off leaves one field behind that depends on the signature that was there: the size in
        # memory of the __LINKEDIT segment. So the two unsigned files must be the same length, differ in no byte after
        # the load commands, and their load commands may differ only in that one line.
        local hdr lc_diff late
        hdr="$(otool -h "$cmp/pinned" | awk 'NR == 4 { print $7 + 32 }')"
        lc_diff="$(diff <(otool -l "$cmp/pinned" | sed 1d) <(otool -l "$cmp/shipped" | sed 1d) | grep '^[<>]' | grep -v '^[<>]    vmsize 0x' || true)"
        late="$(cmp -l "$cmp/pinned" "$cmp/shipped" 2>/dev/null | awk -v h="$hdr" '$1 > h' | wc -l | tr -d ' ' || true)"
        if [ -n "$hdr" ] && [ "$(stat -f %z "$cmp/pinned")" = "$(stat -f %z "$cmp/shipped")" ] && [ -z "$lc_diff" ] && [ "$late" = 0 ]; then
            say "  $ORT_LIB: the pinned library (SHA-256 $ORT_LIB_SHA256 as published), the same code once the signatures are taken off"
        else die "$label: $ORT_LIB is not the pinned library once the signatures are taken off"; fi
        fresh "$cmp"
    else
        say "  $ORT_LIB: the pinned original is not in build/release/onnxruntime (the build stage puts it there), so only the scan was made"
    fi
}

# The archive Xcode exports from, around the app in build/release.
make_archive() {
    [ -d "$app" ] || die "no $app_name.app in desk-app/build/release; run build, sign and verify first"
    check_release_app "$app" "the signed app"
    local info="$app/Contents/Info.plist" signer team
    signer="$(codesign -dvv "$app" 2>&1 | sed -n 's/^Authority=\(Developer ID Application: .*\)$/\1/p' | head -1)"
    team="$(team_of "$app")"
    fresh "$archive"; fresh "$sent_mark"
    mkdir -p "$archive/Products/Applications" "$archive/dSYMs"
    ditto "$app" "$archive/Products/Applications/$app_name.app"
    local dsym="$out/DerivedData/Build/Products/Release/$app_name.app.dSYM"
    if [ -d "$dsym" ]; then ditto "$dsym" "$archive/dSYMs/$app_name.app.dSYM"; fi
    cat > "$archive/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>ApplicationProperties</key>
	<dict>
		<key>ApplicationPath</key>
		<string>Applications/$app_name.app</string>
		<key>Architectures</key>
		<array>
			<string>arm64</string>
		</array>
		<key>CFBundleIdentifier</key>
		<string>$(plutil -extract CFBundleIdentifier raw -o - "$info")</string>
		<key>CFBundleShortVersionString</key>
		<string>$(plutil -extract CFBundleShortVersionString raw -o - "$info")</string>
		<key>CFBundleVersion</key>
		<string>$(plutil -extract CFBundleVersion raw -o - "$info")</string>
		<key>SigningIdentity</key>
		<string>$signer</string>
		<key>Team</key>
		<string>$team</string>
	</dict>
	<key>ArchiveVersion</key>
	<integer>2</integer>
	<key>CreationDate</key>
	<date>$(date -u +%Y-%m-%dT%H:%M:%SZ)</date>
	<key>Name</key>
	<string>$app_name</string>
	<key>SchemeName</key>
	<string>Desk</string>
</dict>
</plist>
PLIST
    plutil -lint "$archive/Info.plist" >/dev/null || die "the archive's Info.plist is not valid"
    say "archive: $archive"
}

# Export options, written when the script runs, with the team read from the signed app.
export_options() {  # destination (upload or export), file
    local file="$2" team; team="$(team_of "$app")"
    inside "$file"
    cat > "$file" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>developer-id</string>
	<key>destination</key>
	<string>$1</string>
	<key>signingStyle</key>
	<string>manual</string>
	<key>signingCertificate</key>
	<string>Developer ID Application</string>
	<key>teamID</key>
	<string>$team</string>
</dict>
</plist>
PLIST
    plutil -lint "$file" || die "the export options are not a valid property list"
    say "export options, the team left out here:"
    plutil -p "$file" | sed 's/\("teamID" => \).*/\1<the team in the signed app>/'
}

stage_notarise_check() {
    step "notarise-check (local only, nothing is sent)"
    make_archive
    local opts="$out/ExportOptions-check.plist" dest="$out/export-check" log="$out/export-check.log"
    export_options export "$opts"
    fresh "$dest"
    say "exporting with destination export (Xcode's manual Developer ID re-sign, here only)"
    xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist "$opts" -exportPath "$dest" > "$log" 2>&1 ||
        { tail -30 "$log"; die "the local export failed; its log is $log. $account_help"; }
    [ -d "$dest/$app_name.app" ] || die "the export made no $app_name.app (log: $log)"
    check_release_app "$dest/$app_name.app" "the app Xcode re-signed"
    say "the local export works: Xcode re-signs the archive with Developer ID, keeping the runtime and the one entitlement"
}

stage_notarise() {
    step "notarise: the upload"
    make_archive
    local opts="$out/ExportOptions-upload.plist" dest="$out/upload" log="$out/upload.log"
    export_options upload "$opts"
    fresh "$dest"
    say "sending the app to Apple's notary service through the account signed in to Xcode"
    if ! xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist "$opts" -exportPath "$dest" \
            -allowProvisioningUpdates > "$log" 2>&1; then
        tail -30 "$log"; die "the upload failed; its log is $log.
  $account_help"
    fi
    tail -5 "$log"
    date -u +%Y-%m-%dT%H:%M:%SZ > "$sent_mark"
    say "sent. The answer usually takes a few minutes; this waits for it (or run the notarise-finish stage later)."
    stage_notarise_finish
}

stage_notarise_finish() {
    step "notarise-finish: waiting for Apple's answer"
    [ -d "$archive" ] && [ -f "$sent_mark" ] ||
        die "no archive sent to Apple in desk-app/build/release; the notarise stage makes it and sends it (notarise-check's archive is never sent)"
    local dest="$out/notarised" log="$out/notarised.log" got="" tries=0 deadline
    deadline=$(( $(date +%s) + notary_minutes * 60 ))
    while :; do
        tries=$((tries + 1))
        fresh "$dest"
        if xcodebuild -exportNotarizedApp -archivePath "$archive" -exportPath "$dest" > "$log" 2>&1 && [ -d "$dest/$app_name.app" ]; then
            got="$dest/$app_name.app"; break
        fi
        # The account first: Xcode's own words for a missing sign-in include "Invalid credentials in keychain", which
        # must not be read as Apple refusing the app (seen Nov 25, 2026, when the account was signed out mid-wait).
        if grep -qiE 'keychain|not signed in|no accounts?\b|authenticat|credential' "$log"; then
            tail -15 "$log"; die "$account_help
  The upload already went: once the account is back, run the notarise-finish stage, not notarise."
        fi
        if grep -qiE 'invalid|rejected|not accepted' "$log"; then
            cat "$log"; die "Apple did not notarise the app; what Xcode said is above (and in $log)"
        fi
        if [ "$(date +%s)" -ge "$deadline" ]; then
            tail -15 "$log"; die "no notarised app after $notary_minutes minutes ($tries tries). Apple may still be working: run
  the notarise-finish stage again later (DECKIE_NOTARY_MINUTES sets how long it waits). Xcode's last answer is in $log."
        fi
        say "  try $tries: not ready yet ($(grep -iE 'error|progress|status|pending' "$log" | tail -1 | cut -c1-160)); trying again in $notary_interval s"
        sleep "$notary_interval"
    done
    say "Apple notarised the app; Xcode handed it back stapled"
    check_release_app "$got" "the notarised app" notarised

    # The notarised app takes the place of the one built here, and the disk image is made from it.
    fresh "$app"; ditto "$got" "$app"
    stage_package
    say "the disk image is signed with Developer ID but not itself notarised (Xcode notarises the app only); the app inside is notarised and stapled"
    local zip="$out/$app_name.zip"
    fresh "$zip"; ditto -c -k --keepParent "$app" "$zip"
    say "zip, the fallback hand-out: $zip ($(du -h "$zip" | cut -f1))"
    downloaded_check
    say "ready to hand out: $dmg ($(du -h "$dmg" | cut -f1)), or $zip"
}

# As far as this Mac can stand in for a tester's: a copy of the image marked as a browser marks a download.
downloaded_check() {
    step "the image as a download (a copy, marked with the quarantine flag a browser sets)"
    local q="$out/as-downloaded" mnt="$out/as-downloaded-mnt"
    fresh "$q"; fresh "$mnt"; mkdir -p "$q" "$mnt"
    cp "$dmg" "$q/$app_name.dmg"
    xattr -w com.apple.quarantine "0083;$(printf '%x' "$(date +%s)");Safari;$(uuidgen)" "$q/$app_name.dmg"
    say "the image: spctl -a -vv -t open --context context:primary-signature"
    local g; g="$(spctl -a -vv -t open --context context:primary-signature "$q/$app_name.dmg" 2>&1 || true)"
    printf '%s\n' "$g" | sed 's/^/  /'
    if printf '%s\n' "$g" | grep -q 'Unnotarized'; then
        say "  Gatekeeper rejects the image itself: it is signed but not notarised, and Xcode notarises only the app.
  Whether a tester's Mac then refuses to open the image, or only checks the notarised app inside, can only be seen on
  a second Mac; until then the zip (the stapled app alone) is the safer hand-out."
    fi
    if hdiutil attach -quiet -nobrowse -readonly -noautoopen -mountpoint "$mnt" "$q/$app_name.dmg"; then
        say "the app inside it, mounted: spctl -a -vv"
        spctl -a -vv "$mnt/$app_name.app" 2>&1 | sed 's/^/  /' || true
        if xattr -p com.apple.quarantine "$mnt/$app_name.app" >/dev/null 2>&1; then say "  (the app inside carries the quarantine flag too)"; fi
        hdiutil detach -quiet "$mnt" || hdiutil detach -quiet -force "$mnt"
    else
        say "  the marked copy did not mount"
    fi
    rmdir "$mnt" 2>/dev/null || true
    fresh "$q"
}

# --- which stages ----------------------------------------------------------------------------------------------------

stages=("$@")
[ ${#stages[@]} -gt 0 ] || stages=(build sign verify package)
for s in "${stages[@]}"; do
    case "$s" in build|sign|verify|package|notarise|notarize|notarise-finish|notarize-finish|notarise-check|notarize-check) ;;
        *) die "unknown stage $s (build, sign, verify, package, notarise, notarise-finish, notarise-check)" ;; esac
done
for s in "${stages[@]}"; do
    case "$s" in
        build) stage_build ;;
        sign) stage_sign ;;
        verify) stage_verify ;;
        package) stage_package ;;
        notarise|notarize) stage_notarise ;;
        notarise-finish|notarize-finish) stage_notarise_finish ;;
        notarise-check|notarize-check) stage_notarise_check ;;
    esac
done
