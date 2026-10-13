class_name InputRecord
extends RefCounted
## One tick of a miner's intent (NET-03, GDD §15.2). Intent only: direction, gait, facing,
## held controls and the wanted lamp state. Never a position, a hit, a light value or a
## result (GDD §15.11). The newest input packs into 7 bytes. A packet's redundant copies are
## consecutive, so only the packet carries a sequence number, and each copy is packed against
## the next newer one: a field mask, then only the fields that differ (1 to 8 bytes).

enum Gait { CROUCH = 0, WALK = 1, RUN = 2 }

const SIZE: int = 7
## Field-mask bits for a redundant copy packed against its newer neighbour.
const DELTA_STAMP: int = 1 << 0
const DELTA_MOVE: int = 1 << 1
const DELTA_GAIT_DESIRED: int = 1 << 2
const DELTA_FACING: int = 1 << 3
const DELTA_HOLDS: int = 1 << 4
const NO_DIRECTION: int = 255
const DIRECTIONS: int = 255  ## 0-254 map to 360 degrees

## Bits of `holds` (MNR-15 owns the full action set).
const HOLD_INTERACT: int = 1 << 0
const HOLD_CHECK_LAMP: int = 1 << 1
const HOLD_AIM: int = 1 << 2
const HOLD_BREATH: int = 1 << 3
const HOLD_SQUINT: int = 1 << 4
const HOLD_FEEL: int = 1 << 5
## MNR-04: set down (X, or A facing an empty tile) and use the selected belt slot (G or RT).
const HOLD_SET_DOWN: int = 1 << 6
const HOLD_USE: int = 1 << 7
## MNR-07: relight by flint (R or X, held).
const HOLD_RELIGHT: int = 1 << 8

## Bits of `desired`: the wanted lamp state (bits 0-2) and MNR-04's selected belt slot (bits 3-4).
const DESIRED_LAMP_MASK: int = 7
const DESIRED_SLOT_SHIFT: int = 3

## The tick sequence number (u16, wrapping); set from the packet when unpacked.
var seq: int = 0
## Ticks before the packet's shown_tick (redundant copies keep their own stamp).
var shown_delta: int = 0
## 0-254, or NO_DIRECTION.
var move_dir: int = NO_DIRECTION
var gait: Gait = Gait.WALK
## 0-65535 over 360 degrees.
var facing: int = 0
var holds: int = 0
## The wanted lamp state, sent as state so a repeat is harmless: bit 0 shutter closed,
## bits 1-2 wick step (0 down, 1 normal, 2 up); bits 3-4 the selected belt slot (MNR-04),
## state too, so a lost packet never loses a selection. 6 bits.
var desired: int = 2


func pack(out: StreamPeerBuffer) -> void:
	out.put_u8(clampi(shown_delta, 0, 255))
	out.put_u8(clampi(move_dir, 0, 255))
	out.put_u8(_gait_desired())
	out.put_u16(facing & 0xFFFF)
	out.put_u16(holds & 0xFFFF)


static func unpack(from: StreamPeerBuffer) -> InputRecord:
	var r: InputRecord = InputRecord.new()
	r.shown_delta = from.get_u8()
	r.move_dir = from.get_u8()
	var packed: int = from.get_u8()
	r.gait = (packed & 3) as Gait
	r.desired = packed >> 2
	r.facing = from.get_u16()
	r.holds = from.get_u16()
	return r


## Packs this (older) record against the next newer one. A stamp one tick older than the newer
## record's is the expected case and costs nothing.
func pack_delta(out: StreamPeerBuffer, newer: InputRecord) -> void:
	var mask: int = 0
	if shown_delta != newer.shown_delta + 1:
		mask |= DELTA_STAMP
	if move_dir != newer.move_dir:
		mask |= DELTA_MOVE
	if _gait_desired() != newer._gait_desired():
		mask |= DELTA_GAIT_DESIRED
	if facing != newer.facing:
		mask |= DELTA_FACING
	if holds != newer.holds:
		mask |= DELTA_HOLDS
	out.put_u8(mask)
	if mask & DELTA_STAMP:
		out.put_u8(clampi(shown_delta, 0, 255))
	if mask & DELTA_MOVE:
		out.put_u8(clampi(move_dir, 0, 255))
	if mask & DELTA_GAIT_DESIRED:
		out.put_u8(_gait_desired())
	if mask & DELTA_FACING:
		out.put_u16(facing & 0xFFFF)
	if mask & DELTA_HOLDS:
		out.put_u16(holds & 0xFFFF)


## The bytes a delta record needs after its mask byte; -1 for an unknown mask bit.
static func delta_size(mask: int) -> int:
	if mask & ~(DELTA_STAMP | DELTA_MOVE | DELTA_GAIT_DESIRED | DELTA_FACING | DELTA_HOLDS):
		return -1
	var n: int = 0
	n += 1 if mask & DELTA_STAMP else 0
	n += 1 if mask & DELTA_MOVE else 0
	n += 1 if mask & DELTA_GAIT_DESIRED else 0
	n += 2 if mask & DELTA_FACING else 0
	n += 2 if mask & DELTA_HOLDS else 0
	return n


## Reads a record packed with pack_delta, given its mask and the newer record.
static func unpack_delta(from: StreamPeerBuffer, mask: int, newer: InputRecord) -> InputRecord:
	var r: InputRecord = newer.duplicate_record()
	r.shown_delta = from.get_u8() if mask & DELTA_STAMP else newer.shown_delta + 1
	if mask & DELTA_MOVE:
		r.move_dir = from.get_u8()
	if mask & DELTA_GAIT_DESIRED:
		var packed: int = from.get_u8()
		r.gait = (packed & 3) as Gait
		r.desired = packed >> 2
	if mask & DELTA_FACING:
		r.facing = from.get_u16()
	if mask & DELTA_HOLDS:
		r.holds = from.get_u16()
	return r


func _gait_desired() -> int:
	return (gait & 3) | ((desired & 63) << 2)


## True when every field is in range (always checked on the server).
func is_valid() -> bool:
	return move_dir >= 0 and move_dir <= 255 and gait >= Gait.CROUCH and gait <= Gait.RUN \
		and facing >= 0 and facing <= 0xFFFF and holds >= 0 and holds <= 0xFFFF \
		and desired >= 0 and (desired & DESIRED_LAMP_MASK) <= 5 and desired < (4 << DESIRED_SLOT_SHIFT)


## Held state only: what a repeat re-applies (never a one-shot action).
func duplicate_record() -> InputRecord:
	var r: InputRecord = InputRecord.new()
	r.seq = seq
	r.shown_delta = shown_delta
	r.move_dir = move_dir
	r.gait = gait
	r.facing = facing
	r.holds = holds
	r.desired = desired
	return r


## The stop after starvation: no movement, controls released, facing and lamp state kept.
func stopped() -> InputRecord:
	var r: InputRecord = duplicate_record()
	r.move_dir = NO_DIRECTION
	r.holds = 0
	return r


func direction_radians() -> float:
	return TAU * move_dir / DIRECTIONS if move_dir != NO_DIRECTION else 0.0


func facing_radians() -> float:
	return TAU * facing / 65536.0


## The selected belt slot (0-3), MNR-04.
func selected_slot() -> int:
	return (desired >> DESIRED_SLOT_SHIFT) & 3


func set_selected_slot(slot: int) -> void:
	desired = (desired & DESIRED_LAMP_MASK) | ((slot & 3) << DESIRED_SLOT_SHIFT)

