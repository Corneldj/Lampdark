#!/usr/bin/env bash
# FND-04's nightly soak slot: FND-09's M1 soak, then MOD-08's Hands never-list soak (30 minutes,
# accelerated). Both run; the slot fails if either does.
set -uo pipefail
GAME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
status=0
"$GAME_DIR/tools/bots/run_soak.sh" nightly_m1 || status=1
"$GAME_DIR/tools/bots/run_soak.sh" hands_never_list || status=1
exit $status
