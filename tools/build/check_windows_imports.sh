#!/usr/bin/env bash
# The Windows native libraries need nothing a clean Windows install lacks (FND-02): no Visual
# C++ redistributable, no MinGW runtime. Lists every DLL each lampblack_core .dll imports and
# fails on anything outside the system allowlist.
# Usage: tools/build/check_windows_imports.sh [dir ...]   (default: native/bin and build/*)
set -uo pipefail

GAME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OBJDUMP="$(command -v x86_64-w64-mingw32-objdump || true)"
[ -z "$OBJDUMP" ] && [ -x "$HOME/.local/opt/lampblack-toolchain/root/usr/bin/x86_64-w64-mingw32-objdump" ] && OBJDUMP="$HOME/.local/opt/lampblack-toolchain/root/usr/bin/x86_64-w64-mingw32-objdump"
[ -z "$OBJDUMP" ] && OBJDUMP="objdump"
# DLLs every Windows 10/11 install (and Proton) provides.
ALLOWED="KERNEL32.dll msvcrt.dll WINMM.dll USER32.dll ADVAPI32.dll ole32.dll SHELL32.dll WS2_32.dll ucrtbase.dll"

dirs=("$@")
[ "${#dirs[@]}" -eq 0 ] && dirs=("$GAME_DIR/native/bin" "$GAME_DIR"/build/windows-*)
status=0
found=0
while IFS= read -r -d '' dll; do
	found=$((found + 1))
	imports="$("$OBJDUMP" -p "$dll" | sed -n 's/^\s*DLL Name: //p' | sort -u)"
	bad=""
	for name in $imports; do
		ok=0
		for allowed in $ALLOWED; do
			[ "${name,,}" = "${allowed,,}" ] && ok=1
		done
		[ "$ok" -eq 0 ] && bad="$bad $name"
	done
	if [ -n "$bad" ]; then
		echo "FAIL $(basename "$dll") needs:$bad" >&2
		status=1
	else
		echo "ok   $(basename "$dll") imports only: $(echo $imports)"
	fi
done < <(find "${dirs[@]}" -name 'liblampblack_core.windows.*.dll' -print0 2>/dev/null)
if [ "$found" -eq 0 ]; then
	echo "check_windows_imports: no Windows libraries found" >&2
	exit 1
fi
exit "$status"
