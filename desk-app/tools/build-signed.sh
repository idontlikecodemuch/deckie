#!/bin/zsh
# Deckie Desk for Mac, built as the README says and then signed with this Mac's own code-signing certificate instead
# of ad hoc, for local runs that need a macOS privacy grant (Screen Recording, for the window server's pictures).
#
# Why: macOS ties a privacy grant to the app's designated requirement. An ad hoc signature's requirement is the
# binary's hash, so every rebuild loses the grant; a certificate's is the bundle id plus the certificate, so the grant
# survives rebuilds (and holds for a signed build in any checkout, since it names no path).
#
# The committed settings stay ad hoc (project.yml); this script changes none of them. It builds with them, then signs
# the built app again, inside out: the embedded ONNX Runtime library (which the post-build step signs ad hoc), any
# other nested code, then the app, keeping its entitlements.
#
#   desk-app/tools/build-signed.sh            the one valid code-signing identity in the keychain
#   DECKIE_SIGN_IDENTITY=<sha-1 or name> desk-app/tools/build-signed.sh    a chosen one
#   DECKIE_SIGN_ONLY=1 ...                    sign the app already built, without building
#
# The app: desk-app/build/Build/Products/Release/Deckie Desk.app. The build runs at nice 19 with 2 jobs.
set -euo pipefail
desk="$(cd "$(dirname "$0")/.." && pwd)"
cd "$desk"
app="$desk/build/Build/Products/Release/Deckie Desk.app"

id="${DECKIE_SIGN_IDENTITY:-}"
if [[ -z "$id" ]]; then
  ids=(${(f)"$(security find-identity -v -p codesigning | sed -n 's/^ *[0-9][0-9]*) \([0-9A-F]\{40\}\) .*/\1/p')"})
  if (( ${#ids} != 1 )); then
    echo "build-signed: found ${#ids} valid code-signing identities; name one with DECKIE_SIGN_IDENTITY" >&2
    exit 1
  fi
  id="${ids[1]}"
  echo "build-signed: signing with the keychain's one valid code-signing identity"
else
  echo "build-signed: signing with DECKIE_SIGN_IDENTITY"
fi

if [[ "${DECKIE_SIGN_ONLY:-}" != 1 ]]; then
  [[ -f Vendor/libonnxruntime.1.31.1.dylib ]] || { echo "build-signed: Vendor/ is missing (README, Build)" >&2; exit 1; }
  xcodegen generate --quiet
  mkdir -p build
  log="$desk/build/build-signed.log"
  echo "build-signed: building (log: build/build-signed.log)"
  if ! nice -n 19 xcodebuild -project Desk.xcodeproj -scheme Desk -configuration Release -destination 'platform=macOS' \
       -derivedDataPath build -jobs 2 build > "$log" 2>&1; then
    grep -E "error:|BUILD FAILED" "$log" | tail -20 >&2
    exit 1
  fi
fi
[[ -d "$app" ]] || { echo "build-signed: no app at $app" >&2; exit 1; }

sign() { codesign --force --sign "$id" --timestamp=none "$@" }
# Nested code first, deepest first: libraries and frameworks, then plug-ins and helpers.
for d in Contents/Frameworks Contents/PlugIns Contents/XPCServices Contents/Helpers Contents/Library; do
  [[ -d "$app/$d" ]] || continue
  find "$app/$d" -depth \( -name '*.dylib' -o -name '*.framework' -o -name '*.appex' -o -name '*.xpc' -o -name '*.app' \) \
    -print0 | while IFS= read -r -d '' f; do sign --preserve-metadata=entitlements "$f"; done
done
sign --preserve-metadata=entitlements,flags "$app"

codesign --verify --deep --strict "$app"
req="$(codesign -d -r- "$app" 2>&1 | sed -n 's/^designated => //p')"
if [[ -z "$req" || "$req" == *cdhash* ]]; then
  echo "build-signed: the designated requirement is a hash, so a grant would not survive a rebuild" >&2
  exit 1
fi
# The requirement's shape, with the certificate's names left out.
echo "build-signed: verified; designated requirement: $(print -r -- "$req" | sed -E 's/= "[^"]*"/= "…"/g')"
echo "build-signed: $app"
