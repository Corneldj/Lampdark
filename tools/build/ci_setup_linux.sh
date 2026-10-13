#!/usr/bin/env bash
# FND-04: installs what the Linux CI jobs need on an Ubuntu 24.04 runner (or container): SCons,
# GCC, the MinGW-w64 cross-compiler (POSIX threads, as FND-02's Fedora toolchain), ffmpeg and NumPy for
# the voice check (SND-13), Xvfb and Mesa for the render tests (VIS-05) and the X libraries Godot loads.
# Usage: tools/build/ci_setup_linux.sh [native|tests|all]     (default: all)
set -euo pipefail
WHAT="${1:-all}"
SUDO=()
[ "$(id -u)" -ne 0 ] && SUDO=(sudo)
pkgs=(git git-lfs python3 python3-venv ca-certificates)
case "$WHAT" in
	native|all) pkgs+=(scons g++ binutils g++-mingw-w64-x86-64-posix binutils-mingw-w64-x86-64) ;;&
	tests|all) pkgs+=(ffmpeg python3-numpy xvfb xauth libgl1 libgl1-mesa-dri libegl1 libxcursor1 libxinerama1 libxrandr2 libxi6 \
		libxkbcommon0 libwayland-client0 libfontconfig1 libasound2t64 libpulse0) ;;
esac
export DEBIAN_FRONTEND=noninteractive
"${SUDO[@]}" apt-get update -qq
"${SUDO[@]}" apt-get install -y -qq --no-install-recommends "${pkgs[@]}" >/dev/null
if [ "$WHAT" != "tests" ]; then
	# The POSIX-thread MinGW, so std::thread and std::mutex work as in the Fedora toolchain.
	for tool in gcc g++; do
		"${SUDO[@]}" update-alternatives --set "x86_64-w64-mingw32-$tool" "/usr/bin/x86_64-w64-mingw32-$tool-posix"
	done
fi
echo "ci_setup_linux: $WHAT ready"
