#!/usr/bin/env bash
# FND-09: no scenario-kit or bot code path initialises Steam, opens a microphone or renders.
# Scans the kit (tests/scenario/kit/), the bot harness (tools/bots/) and the support files they
# use. Exits 1 on a violation. Bots also log "bot mode: display=headless audio=Dummy" at start.
set -uo pipefail

GAME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$GAME_DIR"
pattern='Steam|steam_|AudioStreamMicrophone|AudioEffectCapture|AudioEffectRecord|RenderingServer|DisplayServer\.window|CanvasItem|Camera2D|Sprite2D|TextureRect|Control\.new|Label\.new|add_child\('
hits="$(grep -nE "$pattern" -r tests/scenario/kit tools/bots tests/support --include='*.gd' | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' | grep -v '# bot-paths: allow' || true)"
if [ -n "$hits" ]; then
	echo "FAIL: kit or bot code touches Steam, the microphone or rendering:" >&2
	echo "$hits" | sed 's/^/  /' >&2
	exit 1
fi
echo "ok   kit and bot code never touch Steam, a microphone or rendering"
