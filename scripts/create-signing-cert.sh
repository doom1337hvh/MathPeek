#!/bin/bash
# Creates the "MathPeek Local Signing" certificate in the login keychain, so the permissions
# you grant MathPeek survive rebuilds. Run once.
set -euo pipefail
source "$(dirname "$0")/appshell.sh"
