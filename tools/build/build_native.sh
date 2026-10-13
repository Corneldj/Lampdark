#!/usr/bin/env bash
# Builds lampblack_core for this host (FND-02): template_debug and template_release, plus the
# doctest runner, into native/bin/. Release symbols are split into native/bin/symbols/
# (archived by CI, never shipped).
# Usage: tools/build/build_native.sh [--platform linux|windows] [--targets "template_debug template_release"]
#        [--test] [-- extra scons args]
#   --platform windows on Linux cross-compiles with MinGW (use_mingw=yes).
#   --test     runs the doctest runner of each target after building.
set -euo pipefail

GAME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NATIVE="$GAME_DIR/native"
PLATFORM="linux"
TARGETS="template_debug template_release"
RUN_TESTS=0
EXTRA=()
while [ "$#" -gt 0 ]; do
	case "$1" in
		--platform) PLATFORM="$2"; shift 2 ;;
		--targets) TARGETS="$2"; shift 2 ;;
		--test) RUN_TESTS=1; shift ;;
		--) shift; EXTRA=("$@"); break ;;
		*) echo "build_native: unknown argument $1" >&2; exit 2 ;;
	esac
done

# Bootstrap: the submodule, and a .gdignore so Godot never scans godot-cpp's test project.
if [ ! -f "$NATIVE/godot-cpp/SConstruct" ]; then
	git -C "$GAME_DIR" submodule update --init native/godot-cpp
fi
touch "$NATIVE/godot-cpp/.gdignore"

# A user-local toolchain (RPMs unpacked without root; see the README), used when present.
TOOLCHAIN="${LB_TOOLCHAIN:-$HOME/.local/opt/lampblack-toolchain}"
if [ -d "$TOOLCHAIN/root/usr/bin" ]; then
	export PATH="$TOOLCHAIN/root/usr/bin:$PATH"
	if [ "$PLATFORM" = "linux" ]; then
		export LB_EXTRA_LIBPATH="$TOOLCHAIN/root/usr/lib/gcc/x86_64-redhat-linux/16${LB_EXTRA_LIBPATH:+:$LB_EXTRA_LIBPATH}"
	fi
	echo "build_native: using the toolchain in $TOOLCHAIN"
fi

JOBS="$(nproc 2>/dev/null || echo 4)"
MINGW=()
[[ "$PLATFORM" == "windows" && "$(uname -s)" != MINGW* ]] && MINGW=(use_mingw=yes)

for target in $TARGETS; do
	symbols=()
	[ "$target" = "template_release" ] && symbols=(debug_symbols=yes)
	scons -C "$NATIVE" -j"$JOBS" platform="$PLATFORM" target="$target" arch=x86_64 tests=yes \
		"${MINGW[@]}" "${symbols[@]}" "${EXTRA[@]}"

	suffix="$PLATFORM.$target.x86_64"
	if [ "$PLATFORM" = "linux" ]; then
		lib="$NATIVE/bin/liblampblack_core.$suffix.so"
		runner="$NATIVE/bin/lampblack_core_tests.$suffix"
	else
		lib="$NATIVE/bin/liblampblack_core.$suffix.dll"
		runner="$NATIVE/bin/lampblack_core_tests.$suffix.exe"
	fi
	if [ "$target" = "template_release" ]; then
		mkdir -p "$NATIVE/bin/symbols"
		objcopy_bin="objcopy"
		[ "$PLATFORM" = "windows" ] && objcopy_bin="x86_64-w64-mingw32-objcopy"
		debug_file="$NATIVE/bin/symbols/$(basename "$lib").debug"
		"$objcopy_bin" --only-keep-debug "$lib" "$debug_file"
		"$objcopy_bin" --strip-debug --strip-unneeded "$lib"
		"$objcopy_bin" --add-gnu-debuglink="$debug_file" "$lib"
		echo "build_native: symbols split to $debug_file"
	fi
	if [ "$RUN_TESTS" -eq 1 ]; then
		if [ "$PLATFORM" = "linux" ]; then
			"$runner" --reporters=junit --out="$NATIVE/bin/doctest.$suffix.xml"
			"$runner"
		else
			"${WINE:-wine}" "$runner"
		fi
	fi
done
