#!/usr/bin/env bash
# Enforces FND-06's determinism rules on server/, shared/ and native/src/core/:
#  1. no engine or standard-library randomness (randi, randf, RandomNumberGenerator,
#     std::rand, std::random_device, std::*_distribution, ...);
#  3. no transcendental maths in native/src/core/ (libm differs between platforms);
#  4. no iteration over std::unordered_* containers in native/src/core/ (flagged for review);
#  5. no wall-clock reads in server/ simulation code.
# A line ending with "determinism: allow" (in a comment) is exempt; give the reason beside it.
# Rule 2 (integer comparisons for seed-derived choices) is a review item.
set -uo pipefail

GAME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$GAME_DIR"
status=0

check() {
	local rule="$1" pattern="$2"; shift 2
	local hits
	hits="$(grep -rnE --include='*.gd' --include='*.cpp' --include='*.h' --include='*.hpp' "$pattern" "$@" 2>/dev/null \
		| grep -v 'determinism: allow' || true)"
	if [ -n "$hits" ]; then
		echo "FAIL rule $rule:" >&2
		echo "$hits" | sed 's/^/  /' >&2
		status=1
	fi
}

GD_DIRS=(server shared)
CORE_DIR=(native/src/core)

check "1 (GDScript randomness)" '\b(randi|randf|randi_range|randf_range|randfn|randomize|rand_from_seed|RandomNumberGenerator)\b|\bseed\(' "${GD_DIRS[@]}"
check "1 (C++ randomness)" 'std::(rand|srand|random_device|mt19937|mt19937_64|minstd_rand|default_random_engine|[a-z_]+_distribution)\b|\b(rand|srand)\(' "${CORE_DIR[@]}"
check "3 (transcendental maths)" '\b(std::)?(sin|cos|tan|asin|acos|atan|atan2|exp|exp2|log|log2|log10|pow|sinh|cosh|tanh|cbrt|hypot)f?\(' "${CORE_DIR[@]}"
check "4 (unordered iteration)" 'for \(.*:\s*[a-z_]*unordered|unordered_[a-z]+<.*>::iterator' "${CORE_DIR[@]}"
check "5 (wall clock)" '\bTime\.get_(ticks|unix|datetime|time|date)|\bOS\.get_(ticks|unix|system_time)' server

if [ "$status" -eq 0 ]; then
	echo "ok   determinism rules hold in server/, shared/ and native/src/core/"
fi
exit "$status"
