#!/usr/bin/env bash
# FND-04's nightly slots. Runs a slot's entry script once its tool exists; until then the slot
# reports "not implemented yet" and passes. A real failure fails the slot.
# Usage: tools/build/ci_nightly_slot.sh soak|stream_audit|seed_harness|probes|record
set -uo pipefail
GAME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$GAME_DIR"
case "${1:-}" in
	soak) entry=(tools/bots/run_nightly_soaks.sh); owner=FND-09 ;;
	stream_audit) entry=(tools/stream_audit/run.sh nightly); owner=NET-08 ;;
	seed_harness) entry=(tools/seed_harness/run.sh --seeds "${LB_SEEDS:-10000}" --machine ci --report build/seed_harness --gates "${LB_HARNESS_GATES:-enforce}"); owner=GEN-14 ;;
	probes) entry=(tools/bots/run_probes.sh); owner=NET-12 ;;
	record) entry=(tools/bots/run_soak.sh record_budget_nightly --accelerated --out build/soaks/record_budget_nightly); owner=NET-07 ;;
	*) echo "usage: ci_nightly_slot.sh soak|stream_audit|seed_harness|probes|record" >&2; exit 2 ;;
esac
if [ ! -x "${entry[0]}" ]; then
	echo "nightly slot $1: not implemented yet (${entry[0]}, $owner)"
	exit 0
fi
echo "nightly slot $1: ${entry[*]}"
# A fresh clone has no .godot/ cache: import first, so every class_name resolves (as ci_tests.sh).
mkdir -p build/ci
"${GODOT:-godot}" --headless --path . --import > build/ci/import_nightly_$1.log 2>&1 || true
"${entry[@]}"
code=$?
[ "$code" -eq 0 ] && echo "nightly slot $1: passed" || echo "nightly slot $1: FAILED (exit $code)"
exit $code
