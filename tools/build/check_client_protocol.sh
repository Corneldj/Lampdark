#!/usr/bin/env bash
# Static audit of client-facing code (SND-01, FND-07, NET-01): nothing a client receives or
# holds may name a server entity or a sound's true source. Scans the wire protocol
# (shared/net/) and all client code. NET-08's stream audit checks the same at runtime, over the
# records clients actually receive, once NET-04 builds per-client streams.
set -uo pipefail

GAME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$GAME_DIR"
PATTERN='true_source|entity_id|EntityKind|EntityRegistry|SimEntity|LbEntityIds|LbEntityMirror|run_seed|LbRoadGraph|LbLightGrid|LbMine|SpeedModifiers|MovementSystem|step_accum|LbVision|NoiseSystem|MinerStateSystem|MinerOverlays|rock_touched|hurt_until|MinerTransitions|CreatureSystem|CreatureLog|CreatureState|CreatureTables|CreatureWindUp|HuntGate|GuardRegistry|LightSense|HearingSense|DarkSense|PullReader|DefenderRule|NowJudge|CrewCensus|ActiveCap|AloneRules|MothSleep|HeatMap|TapperHearing|HeardEvent|GrabHold|CaughtHold|SelfRescue|TapperHunt|TapperPin|TapperTaps|TapperStrike|SilentPull|Basecamp|BaseCampState|EmergencyLights|FirstLamp|Medbay|Relighter|BatteryRack|GateSystem|LeverAction|InventorySystem|HandsAndBelt|ItemWorld|TimedAction|InteractionTargets|GauzeLamp|LampSystem|FallSystem|BodyState|LampDisposition|MothAwake|MothPerception|MothMemory|LampOil|Relight\b|FeelSystem|RingSystem|RingOptions|BothHold|\bHolds\b|\bRewind\b'
hits="$(grep -rnE --include='*.gd' "$PATTERN" shared/net client 2>/dev/null | grep -v 'audit: allow' || true)"
if [ -n "$hits" ]; then
	echo "FAIL: client-facing code names server-only identity or truth:" >&2
	echo "$hits" | sed 's/^/  /' >&2
	exit 1
fi
echo "ok   client-facing code carries no entity ID, kind, run seed or true source"
