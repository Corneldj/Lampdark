class_name LampSignals
extends SimSystem
## SND-12 (stage MINERS, before the lamps): lamp signals (Gameplay §6.6). ActionRecord.Kind.LAMP_SIGNAL
## picks STOP, COME, OK, HELP or POINT from the wheel. It needs an open lamp in the lamp hand and the
## lamp capability (a Caught miner may; Grabbed, unconscious or dead may not), and none while
## carrying anything (a body, a load or the can: §4.3, Proposed) or during the Aside.
##
## STOP, COME and OK last lamp.signal_duration_s; HELP lamp.help_duration_s, really blinking the
## lamp off and on three times (2 Hz), so the light grid, the Moth and the Flicker see it; POINT
## lamp.point_duration_s, lighting one tile to lamp.point_light: along the facing up to
## lamp.point_max_tiles, the last open tile in the maker's line of sight (Proposed: the wheel takes
## the aim, so the facing points). The kind rides in the maker's flame byte (LampSignalKind), sent
## only with identity, so only a watcher who sees the maker (cone, line of sight, light, within
## lamp.signal_range_tiles) gets it. Hired Hands among them get `signal_seen`; every awake Moth has
## the lamp as a beacon (moth.signal_sight_tiles); `signalled` goes to creature perception (CRT-03's
## heap stir, CRT-07's Flicker). A signal is never heard and makes no Road Graph event. Server-only.

## MOD-08: a Hired Hand saw a signal (POINT with its tile).
signal signal_seen(hand: int, kind: LampSignalKind.Kind, point_tile: Vector2i)
## CRT-03, CRT-07: a signal began (server-only perception).
signal signalled(miner: int, kind: LampSignalKind.Kind, point_tile: Vector2i, source: int)

## miner -> {kind, start, until, uid, point_tile, spot}
var active: Dictionary = {}
## Every signal, refused ones included: {tick, miner, kind, refused, why, watchers}.
var history: Array[Dictionary] = []


func stage() -> int:
	return StageTable.Stage.MINERS


func order() -> int:
	return 28


func system_name() -> String:
	return "lamp_signals"


func bind(run: RunState) -> void:
	if run.lamps != null:
		run.lamps.dark_now = func(uid: int) -> bool: return blink_dark(run, uid)
	if run.electric != null:
		run.electric.dark_now = func(uid: int) -> bool: return blink_dark(run, uid)


func tick(run: RunState) -> void:
	for raw: Variant in active.keys():
		var a: Dictionary = active[raw]
		if run.tick >= int(Variants.number(a["until"])):
			active.erase(raw)
	if run.movement == null:
		return
	for slot: int in run.movement.miner_slots():
		var c: InputBuffer.Consumed = run.input_for(slot)
		if c == null:
			continue
		var miner: int = run.movement.miner(slot).entity_id
		for a: ActionRecord in c.actions:
			if a.kind != ActionRecord.Kind.LAMP_SIGNAL:
				continue
			var pick: Dictionary = Intents.decode_wheel_arg(a.arg)
			var count: int = LampSignalKind.WHEEL.size() + (CHALK_SLICES if Variants.flag(pick.get("combined", false)) else 0)
			var index: int = CalloutLines.slice(float(a.aim) / 65536.0 * 360.0, count)
			if index >= 0 and index < LampSignalKind.WHEEL.size():
				make(run, miner, slot, LampSignalKind.WHEEL[index])
	for raw: Variant in active.keys():
		var a: Dictionary = active[raw]
		_beacon(run, int(Variants.number(raw)), a)


## MNR-10's chalk slices after the signals on the pad's combined wheel.
const CHALK_SLICES: int = 13


## Makes a signal now if allowed; the reason it was refused otherwise ("" when made).
func make(run: RunState, miner: int, slot: int, kind: LampSignalKind.Kind) -> String:
	var why: String = refusal(run, miner, slot)
	var row: Dictionary = {"tick": run.tick, "miner": miner, "kind": kind, "refused": not why.is_empty(), "why": why, "watchers": []}
	history.append(row)
	if not why.is_empty():
		return why
	var l: GauzeLamp = run.lamps.lamp_in_hand(miner)
	var electric: Item = _electric_in_hand(run, miner)
	_clear(run, miner)
	var hz: float = Tuning.f(&"net.tick_hz")
	var seconds: float = Tuning.f(&"lamp.signal_duration_s")
	if kind == LampSignalKind.Kind.HELP:
		seconds = Tuning.f(&"lamp.help_duration_s")
	elif kind == LampSignalKind.Kind.POINT:
		seconds = Tuning.f(&"lamp.point_duration_s")
	var uid: int = l.uid if l != null else (electric.uid if electric != null else 0)
	var a: Dictionary = {"kind": kind, "start": run.tick, "until": run.tick + roundi(seconds * hz), "uid": uid,
		"point_tile": Vector2i(-1, -1), "spot": 0}
	if kind == LampSignalKind.Kind.POINT:
		var t: Vector2i = point_target(run, miner, slot)
		a["point_tile"] = t
		if run.light != null:
			a["spot"] = run.light.grid.add_spot(miner, t, Tuning.f(&"lamp.point_light"), roundi(seconds * hz))
	active[miner] = a
	var watchers: Array[int] = watchers_of(run, miner)
	row["watchers"] = watchers
	for w: int in watchers:
		if run.crew != null and Variants.flag(run.crew.is_hand_driven.call(w)):
			signal_seen.emit(w, kind, a["point_tile"])
	signalled.emit(miner, kind, a["point_tile"], l.source if l != null else 0)
	return ""


## Why `miner` may not signal now ("" if it may).
func refusal(run: RunState, miner: int, slot: int) -> String:
	if run.lamps == null or run.inventory == null:
		return "no lamps"
	var l: GauzeLamp = run.lamps.lamp_in_hand(miner)
	# MNR-08: an electric lamp switched on signals too.
	if (l == null or not l.burning() or l.shutter_closed) and not ElectricLamps.is_on(_electric_in_hand(run, miner)):
		return "no open lamp in hand"
	if run.miner_state != null and run.miner_state.miner(miner) != null and not Variants.flag(run.miner_state.capabilities(miner)["lamp"]):
		return "cannot use the lamp"
	var h: HandsAndBelt = run.inventory.hands_of(miner)
	if h.two_handed or h.hooked or (h.free_hand != null and h.free_hand.kind == ItemKinds.Kind.PARAFFIN_CAN):
		return "carrying"
	if run.voice != null and int(Variants.number(run.voice.route_of.get(slot, VoiceRoutes.Route.NORMAL))) == VoiceRoutes.Route.ASIDE:
		return "the Aside"
	return ""


static func _electric_in_hand(run: RunState, miner: int) -> Item:
	if run.inventory == null or not run.inventory.hands.has(miner):
		return null
	var it: Item = run.inventory.hands_of(miner).lamp_hand
	return it if it != null and it.kind == ItemKinds.Kind.ELECTRIC_LAMP else null


## POINT's tile: along the facing, up to lamp.point_max_tiles, the last open tile before rock.
func point_target(run: RunState, miner: int, slot: int) -> Vector2i:
	var me: SimEntity = run.registry.get_entity(miner)
	var u: PackedFloat64Array = LbDetMath.unit(float(run.movement.facing_of(slot)) / 65536.0)
	var dir: Vector2 = Vector2(u[0], u[1])
	var last: Vector2i = me.tile()
	var reach: float = Tuning.f(&"lamp.point_max_tiles")
	for i: int in range(1, ceili(reach / 0.1) + 1):
		var p: Vector2 = me.position + dir * minf(i * 0.1, reach)
		var t: Vector2i = Vector2i(floori(p.x), floori(p.y))
		if t != last and run.mine != null and not run.mine.native.is_walkable(t, false):
			break
		last = t
	return last


## The miners who see `miner`'s signal: identity (cone, line of sight, lit: its own open lamp lights
## it) within lamp.signal_range_tiles. Hired Hands included.
func watchers_of(run: RunState, miner: int) -> Array[int]:
	var out: Array[int] = []
	if run.vision == null or run.movement == null:
		return out
	var me: SimEntity = run.registry.get_entity(miner)
	for slot: int in run.movement.miner_slots():
		var w: int = run.movement.miner(slot).entity_id
		if w == miner:
			continue
		var them: SimEntity = run.registry.get_entity(w)
		if them == null or them.position.distance_to(me.position) > Tuning.f(&"lamp.signal_range_tiles"):
			continue
		if run.vision.native.sees_entity(slot, miner) == 2:
			out.append(w)
	return out


## The signal under way for `miner` (NONE if none): what its flame byte carries.
func kind_of(miner: int) -> LampSignalKind.Kind:
	var a: Dictionary = active.get(miner, {})
	return LampSignalKind.Kind.NONE if a.is_empty() else (int(Variants.number(a["kind"])) as LampSignalKind.Kind)


## HELP's blinks: the lamp dark for 5 ticks in every 10, three times (2 Hz, under 3 Hz).
func blink_dark(run: RunState, uid: int) -> bool:
	for raw: Variant in active.keys():
		var a: Dictionary = active[raw]
		if int(Variants.number(a["kind"])) != LampSignalKind.Kind.HELP or int(Variants.number(a["uid"])) != uid:
			continue
		var e: int = run.tick - int(Variants.number(a["start"]))
		var half: int = maxi(1, roundi(Tuning.f(&"lamp.help_duration_s") * Tuning.f(&"net.tick_hz") / 6.0))
		return e >= 0 and e < half * 6 and (e / half) % 2 == 0
	return false


func _clear(run: RunState, miner: int) -> void:
	var a: Dictionary = active.get(miner, {})
	if not a.is_empty() and int(Variants.number(a["spot"])) != 0 and run.light != null:
		run.light.grid.remove_source(int(Variants.number(a["spot"])))
	active.erase(miner)


## CRT-04: an awake Moth sees a signalling lamp from moth.signal_sight_tiles.
func _beacon(run: RunState, miner: int, a: Dictionary) -> void:
	if run.creatures == null or run.lamps == null:
		return
	var l: GauzeLamp = run.lamps.lamp_in_hand(miner)
	if l == null or l.source == 0:
		return
	for c: Creature in run.creatures.creatures:
		var moth: Moth = c as Moth
		if moth != null:
			moth.awake.perception.beacons[l.source] = {"kind": &"signal", "source": l.source, "until": int(Variants.number(a["until"]))}


func write_state(writer: SimStateWriter) -> void:
	var ids: Array = active.keys()
	ids.sort()
	writer.put_i64(ids.size())
	for raw: Variant in ids:
		var a: Dictionary = active[raw]
		writer.put_i64(int(Variants.number(raw)))
		writer.put_i64(int(Variants.number(a["kind"])))
		writer.put_i64(int(Variants.number(a["until"])))
