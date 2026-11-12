#!/bin/bash
# Records the README's clips from build/MathPeek.app, with AppShell's shared recorder. The clips
# are listed in scripts/clips.jsonc, which scripts/clip-pages.swift writes along with the pages
# they're acted out on; AppShell's scripts/record-clips.swift describes every option.
#
#   scripts/build.sh && scripts/record-clips.sh             every clip
#   scripts/build.sh && scripts/record-clips.sh settings    just these
#
# Needs Screen Recording for the terminal it runs in. Clips around a window are filmed off
# screen, so nothing shows meanwhile.
set -euo pipefail
source "$(dirname "$0")/appshell.sh"
