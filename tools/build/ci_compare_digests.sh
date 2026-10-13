#!/usr/bin/env bash
# FND-04: FND-06's cross-platform determinism compare. Both OSes' digest files must be identical,
# byte for byte. Usage: tools/build/ci_compare_digests.sh <linux digest file> <windows digest file>
set -euo pipefail
if [ "$#" -ne 2 ] || [ ! -f "$1" ] || [ ! -f "$2" ]; then
	echo "ci_compare_digests: need two digest files" >&2
	exit 2
fi
if cmp -s "$1" "$2"; then
	echo "ok   determinism digests agree: $(cat "$1")"
else
	echo "FAIL determinism digests differ:" >&2
	echo "  $(basename "$1"): $(cat "$1")" >&2
	echo "  $(basename "$2"): $(cat "$2")" >&2
	exit 1
fi
