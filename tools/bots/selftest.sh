#!/usr/bin/env bash
# The per-push self-test (FND-09): 60 s, 1 server, 2 bots, loopback; must pass in under 90 s.
# --record-fixture also copies the server's applied-input log to tests/fixtures/kit/, where
# test_soak_replay.gd replays it in-process.
set -euo pipefail
GAME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RECORD=0
if [[ "${1:-}" == "--record-fixture" ]]; then RECORD=1; shift; fi
START=$(date +%s)
"$GAME_DIR/tools/bots/run_soak.sh" selftest "$@"
ELAPSED=$(( $(date +%s) - START ))
echo "selftest finished in ${ELAPSED} s"
if (( ELAPSED >= 90 )); then
	echo "FAIL: the self-test must finish in under 90 s" >&2
	exit 1
fi
if (( RECORD )); then
	cp "$GAME_DIR/build/soaks/selftest/server_0.inputs.jsonl" "$GAME_DIR/tests/fixtures/kit/selftest_inputs.jsonl"
	echo "recorded tests/fixtures/kit/selftest_inputs.jsonl"
fi
