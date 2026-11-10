#!/bin/bash
# Builds MathPeek.app into ./build, with AppShell's shared build script. Needs only the Xcode
# Command Line Tools.
#
#   scripts/build.sh            build ./build/MathPeek.app
#   scripts/build.sh --install  also copy it to ~/Applications and launch it
#
# MathPeek's own build steps, if any, go in scripts/hooks/ (see AppShell's scripts/build.sh).
set -euo pipefail
source "$(dirname "$0")/appshell.sh"
