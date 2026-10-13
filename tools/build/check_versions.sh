#!/usr/bin/env bash
# FND-04: verifies downloaded engine files against versions.json's SHA-512 checksums.
# Usage: tools/build/check_versions.sh <file> [<file> ...]     (exit 1 on any mismatch)
set -euo pipefail
exec python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fetch_godot.py" --verify "$@"
