#!/usr/bin/env bash
# Fails when private data is back in the tracked files (decision D45). Patterns only: this file names no private
# value. Run from anywhere in the repository; CI runs it on every push (.github/workflows/privacy-check.yml).
#
#   1. The removed private places must not be tracked again: the lab's data in mixer/, the disc pool, the party's phone
#      page, the party's disc material and memory notes, the old brief, and recognition catalogues or signatures.
#   2. No personal home folder or mounted-volume path: /Users/<name>, /home/<name>, C:\Users\<name> are allowed only
#      with the made-up or generic names the tests and docs use (dj, someone, x, c, runner, runneradmin, Shared, you).
#   3. No email address except the publisher's public contact, the commit co-author line, and those inside
#      third-party licence texts and vendored sources.
#   4. No Apple device identifier (a UDID: eight hex digits starting 0000, a dash, sixteen hex digits).
#   5. No assistant session link or id, and no scratch path that embeds a home folder.
#   6. No Apple developer team id outside the build files that need it.
#   7. No path shaped like a personal music folder (a drive's project folder, a personal playlist folder).
set -u
cd "$(dirname "$0")/.."
fail=0
say() { printf '%s\n' "$*"; fail=1; }

# 1. places
removed='^(mixer/features/|mixer/candidates\.json$|mixer/recs\.(json|md)$|mixer/plan[^/]*\.json$|mixer/mixes/|mixer/models/|mixer/mixmap\.html$|mixer/key_(light|ends)_[a-z]+\.tsv$|mixer/key_parity_keys\.tsv$|mixer/mu_bench\.tsv$|mixer/summary\.(md|tsv)$|mixer/sprint_check\.(md|tsv)$|pool/|web-player/|docs/discs/|docs/history/|docs/architecture/bench/|BRIEF\.md$)|\.shazam(catalog|signature)$'
if hits=$(git ls-files | grep -E "$removed"); then
    say "private places are tracked again (D45):"; say "$hits"
fi

# Files whose text is someone else's (licences, vendored code) or generated test output with '@' in it.
skip=(':(exclude)core/notices/**' ':(exclude)core/Sources/C*/**' ':(exclude)core/Tests/DeckieBoothTests/Fixtures/*.txt'
      ':(exclude)tools/check-private.sh' ':(exclude)*.png' ':(exclude)*.jpg' ':(exclude)*.mp3' ':(exclude)*.mp4'
      ':(exclude)*.woff2' ':(exclude)*.ico' ':(exclude)*.bin' ':(exclude)*.dkl')

# 2. home folders and volumes
allowed_names='(dj|someone|x|c|runner|runneradmin|Shared|you|me|name|user|\.\.\.|<[^>]*>)'
if hits=$(git grep -nIE '(/Users/|/home/|[Cc]:\\+Users\\+|[Cc]:/Users/)[A-Za-z0-9._-]+' -- "${skip[@]}" \
          | grep -viE "(/Users/|/home/|[Cc]:\\\\+Users\\\\+|[Cc]:/Users/)$allowed_names([/\\\\\"' ).,:;\`]|$)"); then
    say "personal home paths (use /path/to/music or a made-up name):"; say "$hits"
fi
if hits=$(git grep -nIE '/Volumes/[A-Za-z0-9]' -- "${skip[@]}" \
          | grep -vE '/Volumes/(USB|Stick|STICK|Macintosh HD|<[^>]*>|Disc|CD|Music|SSD|Drive|name)([/" ).,`]|$)'); then
    say "mounted-volume paths (use a made-up volume name):"; say "$hits"
fi

# 3. email addresses
if hits=$(git grep -nIoE '[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}' -- "${skip[@]}" \
          | grep -vE ':(info@apphold\.media|noreply@anthropic\.com|wine-bugs@list\.winehq\.org)$'); then
    say "email addresses:"; say "$hits"
fi

# 4. device identifiers
if hits=$(git grep -nIE '\b0000[0-9A-Fa-f]{4}-[0-9A-Fa-f]{16}\b' -- "${skip[@]}"); then
    say "device identifiers:"; say "$hits"
fi

# 5. assistant session links and ids, and scratch paths that carry a home folder
if hits=$(git grep -nIE 'Claude-Session:|claude\.ai/code/session_|session_[0-9A-Za-z]{20,}|-Users-[A-Za-z0-9]+-' -- "${skip[@]}"); then
    say "assistant session ids or scratch paths:"; say "$hits"
fi

# 6. an Apple developer team id outside the build files that need it (prose, scripts)
if hits=$(git grep -nIiE '(team( id)?|DEVELOPMENT_TEAM|DevelopmentTeam)[^A-Z0-9\n]{0,6}[A-Z0-9]{10}\b' -- "${skip[@]}" \
          ':(exclude)*.pbxproj' ':(exclude)*/project.yml' ':(exclude)*.xcconfig' | grep -E '[A-Z0-9]{10}\b' \
          | grep -E '[0-9][A-Z]|[A-Z][0-9]'); then
    say "an Apple team id outside the build files:"; say "$hits"
fi

# 7. a music-library folder shape: a mounted drive's project folder, or a personal music folder, in a path
if hits=$(git grep -nIiE '/Volumes/[A-Za-z0-9 _-]+/Projects/|/personal/[^ "]*(playlist|music)' -- "${skip[@]}"); then
    say "a personal music-folder path (use /path/to/music):"; say "$hits"
fi

# What this check cannot catch: it knows no private value, so it cannot see a song title or artist of a personal
# library, a person's name (in prose, in an identifier or in a file name), a private folder name, a date that only
# matters privately, or a personal remark. Those need a reviewer or a scan with the private term list (D45).

if [ "$fail" -ne 0 ]; then
    echo "check-private: FAILED (see docs/product/00-decisions.md, D45)"
    exit 1
fi
echo "check-private: no private places, home or music paths, addresses, device ids, session ids or team ids in prose"
