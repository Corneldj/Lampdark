class_name Intents
extends RefCounted
## MNR-15: the intents a client sends (Gameplay §4.8, rule 10): a move direction (never a speed),
## a facing, held bits, the wanted lamp and slot state (InputRecord), and one-shot actions
## (ActionRecord): wheel picks, the rock tap, a ring choice, a shot. Never a hit, a target or a
## computed result. Hold or toggle and tap timing are resolved on the client before this.
##
## A wheel pick rides an ActionRecord: `aim` is the pick's angle (0-65535 over 360 degrees, clockwise
## from east) and `arg` either the distance or deflection in thousandths of the wheel's radius (bit
## 15 clear), or with the callout timing option (bit 15 set) the confirm press's hold in bits 0-6 and
## the gap since the previous press in bits 7-13, both in TIMING_STEP_MS units (127: none).
## SND-11 turns either into a band with its own bounds. A pick from the pad's one wheel for lamp
## signals and chalk (both bound to Y) sets COMBINED_FLAG on its distance; which slices are chalk is
## MNR-10's.

const TIMING_FLAG: int = 1 << 15
const COMBINED_FLAG: int = 1 << 14
const DISTANCE_MASK: int = 1023
const TIMING_STEP_MS: int = 10
const TIMING_NONE: int = 127


static func facing_u16(deg: float) -> int:
	return posmod(roundi(fposmod(deg, 360.0) / 360.0 * 65536.0), 65536)


static func direction_byte(deg: float) -> int:
	return posmod(roundi(fposmod(deg, 360.0) / 360.0 * InputRecord.DIRECTIONS), InputRecord.DIRECTIONS)


static func wheel_arg_distance(distance: float) -> int:
	return clampi(roundi(distance * 1000.0), 0, 1000)


static func wheel_arg_timing(hold_ms: int, gap_ms: int) -> int:
	var hold: int = clampi(roundi(hold_ms / float(TIMING_STEP_MS)), 0, TIMING_NONE - 1)
	var gap: int = TIMING_NONE if gap_ms < 0 else clampi(roundi(gap_ms / float(TIMING_STEP_MS)), 0, TIMING_NONE - 1)
	return TIMING_FLAG | hold | (gap << 7)


## {distance} or {hold_ms, gap_ms (-1: none)} from a wheel pick's arg.
static func decode_wheel_arg(arg: int) -> Dictionary:
	if (arg & TIMING_FLAG) == 0:
		return {"distance": (arg & DISTANCE_MASK) / 1000.0, "combined": (arg & COMBINED_FLAG) != 0}
	var gap: int = (arg >> 7) & 127
	return {"hold_ms": (arg & 127) * TIMING_STEP_MS, "gap_ms": -1 if gap == TIMING_NONE else gap * TIMING_STEP_MS}
