class_name LampDisposition
extends RefCounted
## RSC-01: where the fallen miner's lamp ends, by cause (Gameplay §11.2). "The lamp" is the light
## in the lamp hand or on the belt hook: a gauze lamp (MNR-06), an electric lamp (MNR-08) or a lit
## candle (MNR-09, Proposed). A lamp in a belt slot is a belt item and stays on the body. "Beside
## you" is the miner's own tile (Proposed); "at the wall" is the floor at the pinning wall's foot,
## which is where the pinned miner lies.
##
## | Cause | The lamp ends |
## | MOTH_SMOTHER | gauze: with the Moth (ctx.moth_takes_lamp), snuffed; else beside, snuffed. Electric: beside, lit |
## | DRAG | as the drag left it (it dropped the lamp at the grab point); if still held, there, snuffed |
## | PIN | at the wall, burning if it was open (the Tapper drops it first; else beside, as it was) |
## | BLAST, BLACKDAMP, ROOF_FALL, FRIENDLY_HIT, SHOT_DEAD | beside, as the cause left it |
## | HATCH | beside, smothered by the brood |

const TAKEN: String = "taken_by_moth"
const BESIDE: String = "beside"
const BESIDE_SNUFFED: String = "beside_snuffed"
const AT_GRAB_POINT: String = "at_grab_point_snuffed"
const AT_WALL: String = "at_wall"
const NO_LAMP: String = "no_lamp"


## Moves the lamp and returns its outcome (fall payload's lamp_outcome).
static func resolve(run: RunState, miner: int, cause: int, ctx: Dictionary) -> String:
	if run.inventory == null or not run.inventory.hands.has(miner):
		return NO_LAMP
	var h: HandsAndBelt = run.inventory.hands[miner]
	var lamp: Item = h.lamp_hand
	if lamp == null:
		return NO_LAMP
	var me: SimEntity = run.registry.get_entity(miner)
	var beside: Vector2i = me.tile()
	match cause:
		FallCause.Cause.MOTH_SMOTHER:
			var moth: int = int(Variants.number(ctx.get("moth_takes_lamp", 0)))
			if lamp.kind == ItemKinds.Kind.GAUZE_LAMP and moth != 0 and run.lamps != null:
				var l: GauzeLamp = run.lamps.lamp_of_item(lamp)
				if l != null and run.lamps.take_by_moth(run, l, moth):
					return TAKEN
			return _drop(run, h, lamp, beside, lamp.kind != ItemKinds.Kind.ELECTRIC_LAMP, "smother")
		FallCause.Cause.DRAG:
			var at: Vector2i = ctx.get("grab_point", beside)
			_drop(run, h, lamp, at, true, "drag")
			return AT_GRAB_POINT
		FallCause.Cause.PIN:
			_drop(run, h, lamp, beside, false, "")
			return AT_WALL
		FallCause.Cause.HATCH:
			return _drop(run, h, lamp, beside, lamp.kind != ItemKinds.Kind.ELECTRIC_LAMP, "brood")
	return _drop(run, h, lamp, beside, false, "")


## Lays the lamp on a tile, snuffing a flame if `snuff`.
static func _drop(run: RunState, h: HandsAndBelt, lamp: Item, tile: Vector2i, snuff: bool, cause: String) -> String:
	if lamp.kind == ItemKinds.Kind.GAUZE_LAMP and run.lamps != null and run.lamps.lamp_of_item(lamp) != null:
		var l: GauzeLamp = run.lamps.lamp_of_item(lamp)
		run.lamps.drop(run, l, tile)
		if snuff and l.burning():
			run.lamps.snuff(run, l, cause)
	else:
		h.lamp_hand = null
		h.hooked = false
		if snuff and lamp.state.has("lit"):
			lamp.state["lit"] = false
		run.inventory.world.put(run, lamp, Vector2(tile) + Vector2(0.5, 0.5), &"drop", h.owner)
		run.inventory.changed.emit(h.owner)
	return BESIDE_SNUFFED if snuff else BESIDE
