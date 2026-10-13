#!/usr/bin/env bash
# FND-04, per push on Linux: GUT over tests/unit and tests/scenario (FND-09, with
# test_kit_sample.gd) to JUnit, then the bot self-test, which must pass in under 90 s.
# Usage: tools/build/ci_tests.sh [gut|selftest|render|all]     (default: all)
set -uo pipefail
GAME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$GAME_DIR"
WHAT="${1:-all}"
mkdir -p build/ci
status=0
if [[ "$WHAT" == gut || "$WHAT" == all ]]; then
	./tools/build/run_unit_tests.sh tests/reports/unit.xml 2>&1 | tee build/ci/gut.log | grep -aE "^Tests|Passing Tests|Failing Tests|Risky|\[Failed\]|sample final"
	# GUT's exit code counts failures; a script that does not parse also stops check_scripts.gd.
	[ "${PIPESTATUS[0]}" -eq 0 ] || status=1
	grep -aq "Failing Tests" build/ci/gut.log && status=1
	grep -aq "Passing Tests" build/ci/gut.log || status=1
fi
if [[ "$WHAT" == selftest || "$WHAT" == all ]]; then
	./tools/bots/selftest.sh > build/ci/selftest.log 2>&1 || status=1
	tail -3 build/ci/selftest.log
fi
if [[ "$WHAT" == render || "$WHAT" == all ]]; then
	./tools/build/run_render_tests.sh || status=1
fi
exit $status
