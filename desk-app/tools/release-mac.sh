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
#   notarise   sends the app, then the disk image, to Apple's notary service, staples both and checks them; never
#              part of a run without stage names, and needs the owner's notary profile
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
#   DECKIE_NOTARY_PROFILE   the notarytool keychain profile for the notarise stage (default: deckie-notary)
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
profile="${DECKIE_NOTARY_PROFILE:-deckie-notary}"
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
# Only when named. Written from `xcrun notarytool submit --help`, `xcrun notarytool log --help` and
# `xcrun stapler --help` (Xcode 27.2): submit with --keychain-profile and --wait, the result as JSON; on anything but
# Accepted, the submission's log; then stapler staple and stapler validate.

notary_submit() {  # file, what it is
    local file="$1" what="$2" json="$out/notary-$2.json" id status
    inside "$json"
    say "sending $what to Apple's notary service (profile $profile) and waiting for the answer"
    xcrun notarytool submit "$file" --keychain-profile "$profile" --wait --output-format json > "$json" ||
        say "notarytool ended with an error (its answer, if any, follows)"
    cat "$json"; echo
    id="$(plutil -extract id raw -o - "$json" 2>/dev/null || true)"
    status="$(plutil -extract status raw -o - "$json" 2>/dev/null || true)"
    if [ "$status" != Accepted ]; then
        if [ -n "$id" ]; then
            say "the notary service's log for $id:"
            xcrun notarytool log "$id" --keychain-profile "$profile" || true
        fi
        die "Apple did not accept $what (status: ${status:-none})"
    fi
    say "$what accepted (submission $id)"
}

stage_notarise() {
    step "notarise"
    [ -d "$app" ] || die "no $app_name.app in desk-app/build/release; run build, sign and verify first"
    codesign --verify --deep --strict "$app" 2>/dev/null || die "the app's signature does not verify"
    codesign -dvv "$app" 2>&1 | grep -q '^Authority=Developer ID Application: ' ||
        die "the app is not signed with a Developer ID Application identity; Apple notarises only those"
    codesign -dvv "$app" 2>&1 | grep -q '^Timestamp=' || die "the app's signature has no secure timestamp; sign again with DECKIE_SIGN_TIMESTAMP=1"
    xcrun notarytool history --keychain-profile "$profile" >/dev/null 2>&1 ||
        die "the notary profile \"$profile\" does not work. Make it once with
  xcrun notarytool store-credentials $profile --apple-id <the account's Apple ID> --team-id <the team>
  (it asks for an app-specific password and keeps it in the keychain), or set DECKIE_NOTARY_PROFILE."

    local zip="$out/$app_name.zip"
    fresh "$zip"
    ditto -c -k --keepParent "$app" "$zip"
    notary_submit "$zip" app
    fresh "$zip"
    xcrun stapler staple "$app" || die "stapler could not staple the app's ticket"
    xcrun stapler validate "$app" || die "the app's stapled ticket does not validate"

    # The disk image is made again from the stapled app, signed, sent, and stapled in its turn.
    stage_package
    notary_submit "$dmg" "disk-image"
    xcrun stapler staple "$dmg" || die "stapler could not staple the disk image's ticket"
    xcrun stapler validate "$dmg" || die "the disk image's stapled ticket does not validate"

    step "Gatekeeper"
    spctl -a -vv -t open --context context:primary-signature "$dmg" || die "Gatekeeper does not accept the disk image"
    spctl -a -vv "$app" || die "Gatekeeper does not accept the app"
    say "ready to hand out: $dmg ($(du -h "$dmg" | cut -f1))"
}

# --- which stages ----------------------------------------------------------------------------------------------------

stages=("$@")
[ ${#stages[@]} -gt 0 ] || stages=(build sign verify package)
for s in "${stages[@]}"; do
    case "$s" in build|sign|verify|package|notarise|notarize) ;; *) die "unknown stage $s (build, sign, verify, package, notarise)" ;; esac
done
for s in "${stages[@]}"; do
    case "$s" in
        build) stage_build ;;
        sign) stage_sign ;;
        verify) stage_verify ;;
        package) stage_package ;;
        notarise|notarize) stage_notarise ;;
    esac
done
