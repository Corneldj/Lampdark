#!/usr/bin/env bash
# FND-04's lint stage. gdlint (gdtoolkit 4, gdlintrc) over server/, client/ and shared/; and
# clang-format (native/.clang-format) over the C++ lines changed since <base>, never thirdparty or
# godot-cpp. Only changed lines are checked: the style has no column limit, and clang-format then
# splits short enums apart, so the existing code is not reformatted wholesale.
# Usage: tools/build/ci_lint.sh [<base commit>]     (no base: the C++ check covers the last commit)
set -euo pipefail
GAME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$GAME_DIR"
BASE="${1:-}"
status=0
gdlint server client shared || status=1
if [ -z "$BASE" ] || ! git cat-file -e "$BASE^{commit}" 2>/dev/null; then
	BASE="$(git rev-parse HEAD~1 2>/dev/null || git hash-object -t tree /dev/null)"
fi
out="$(git clang-format --binary "$(command -v clang-format)" --diff --extensions cpp,h,hpp "$BASE" -- native/src native/tests 2>&1 || true)"
case "$out" in
	*"no modified files to format"*|*"clang-format did not modify any files"*|"") echo "clang-format: changed C++ lines are formatted" ;;
	*) echo "$out"; echo "clang-format: run 'git clang-format $BASE' on the lines above" >&2; status=1 ;;
esac
exit $status
