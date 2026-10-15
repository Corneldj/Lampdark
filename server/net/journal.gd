class_name Journal
extends SimSystem
## NET-09 (stage RECORD, after the miners' state and the falls; Gameplay §13.11, GDD §15.10): every
## fall and death is written the tick it happens, so an abnormal end never undoes one. An entry:
## {run_uuid, after_snapshot_seq, tick, miner, kind (fall or death), cause, body_tile, lamp_end,
## marks, prev, hash}, hash-chained (prev is the last entry's hash). It goes to the host's or the
## offline disk at once, sealed (`sink`), and to every member on the control lane the same tick, so
## it never waits behind snapshot data (`broadcast`). A resume applies the entries after its
## snapshot's tick, each once: the body unconscious or dead on its tile, the belt on the body, the
## lamp where the cause left it. A revive is not journaled (Proposed): an abnormal end undoes it.
## Public runs journal nothing. Server-only.

## Every entry of the run.
var entries: Array[Dictionary] = []
## The snapshot the next entry follows (Saves sets it).
var after_seq: int = 0
## (sealed entry: PackedByteArray) -> void: the disk (Saves).
var sink: Callable = Callable()
## (sealed entry: PackedByteArray) -> void: every member (Saves).
var broadcast: Callable = Callable()
var enabled: bool = true
## miner -> kind ("fall" | "death"), cause: falls and deaths this tick, written at this stage.
var _pending: Dictionary = {}
## miner -> its lamp's uid, last seen in its hands (where the cause left it is looked up by uid).
var _lamp_uid: Dictionary = {}
var _run: RunState = null


func stage() -> int:
	return StageTable.Stage.RECORD


func order() -> int:
	return 45


func system_name() -> String:
	return "journal"


func bind(run: RunState) -> void:
	_run = run
	enabled = run.header.mode != ServerConfig.Mode.PUBLIC
	if run.miner_state != null:
		run.miner_state.state_changed.connect(func(entity: int, _old: int, new: int, cause: String) -> void:
			if new == MinerTransitions.Life.UNCONSCIOUS:
				_pending[entity] = ["fall", cause]
			elif new == MinerTransitions.Life.DEAD:
				_pending[entity] = ["death", cause])


func tick(run: RunState) -> void:
	_run = run
	var ids: Array = _pending.keys()
	ids.sort()
	for raw: Variant in ids:
		var pair: Array = _pending[raw]
		write(run, int(Variants.number(raw)), str(pair[0]), str(pair[1]))
	_pending.clear()
	if run.inventory != null:
		for raw: Variant in run.inventory.hands.keys():
			var h: HandsAndBelt = run.inventory.hands[raw]
			if h.lamp_hand != null:
				_lamp_uid[raw] = h.lamp_hand.uid


## Writes one entry now: to the disk and to every member, the same tick.
func write(run: RunState, miner: int, kind: String, cause: String) -> Dictionary:
	if not enabled:
		return {}
	var e: SimEntity = run.registry.get_entity(miner)
	var m: MinerStateSystem.Miner = run.miner_state.miner(miner) if run.miner_state != null else null
	var entry: Dictionary = {"run_uuid": run.header.run_uuid, "after_snapshot_seq": after_seq, "tick": run.tick, "miner": miner,
		"kind": kind, "cause": cause, "body_tile": e.tile() if e != null else Vector2i.ZERO,
		"lamp_end": lamp_end(run, miner), "marks": m.overlays.marks.duplicate(true) if m != null else {},
		"prev": str(entries[entries.size() - 1]["hash"]) if not entries.is_empty() else ""}
	entry["hash"] = hash_of(entry)
	entries.append(entry)
	var sealed: PackedByteArray = LbSeal.seal(var_to_bytes(entry))
	if sink.is_valid():
		sink.call(sealed)
	if broadcast.is_valid():
		broadcast.call(sealed)
	return entry


static func hash_of(entry: Dictionary) -> String:
	var plain: Dictionary = entry.duplicate(true)
	plain.erase("hash")
	var h: HashingContext = HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(LbDiffStore.encode(plain))
	return h.finish().hex_encode()


## Whether the chain holds: each entry's hash its own, each prev the last one's.
static func chain_holds(list: Array[Dictionary]) -> bool:
	var prev: String = ""
	for e: Dictionary in list:
		if str(e.get("prev", "")) != prev or str(e.get("hash", "")) != hash_of(e):
			return false
		prev = str(e["hash"])
	return true


## Where the miner's lamp is now: {where (hand | hook | free | slot | floor | none), slot, tile, item,
## uid}. "none": nowhere a miner or the floor holds it (a Moth carried it off).
func lamp_end(run: RunState, miner: int) -> Dictionary:
	if run.inventory == null:
		return {"where": "none"}
	var h: HandsAndBelt = run.inventory.hands_of(miner)
	if h.lamp_hand != null and ItemKinds.is_lamp(h.lamp_hand.kind):
		_mirror(run, h.lamp_hand)
		return {"where": "hook" if h.hooked else "hand", "item": StateDicts.item_to(h.lamp_hand)}
	var uid: int = int(Variants.number(_lamp_uid.get(miner, 0)))
	if uid != 0:
		for kind: ItemKinds.Kind in [ItemKinds.Kind.GAUZE_LAMP, ItemKinds.Kind.ELECTRIC_LAMP]:
			for place: Dictionary in ItemPlaces.of_kind(run, kind):
				var it: Item = place["item"]
				if it.uid == uid:
					_mirror(run, it)
					var at: Vector2 = place["position"]
					var where: String = str(place["where"]) if int(Variants.number(place["holder"])) == miner else "floor"
					return {"where": "hand" if where == "lamp" else where, "slot": int(Variants.number(place["slot"])),
						"tile": Vector2i(floori(at.x), floori(at.y)), "item": StateDicts.item_to(it), "uid": uid}
	return {"where": "none", "uid": uid}


static func _mirror(run: RunState, it: Item) -> void:
	if run.lamps != null and run.lamps.lamps.has(it.uid):
		var l: GauzeLamp = run.lamps.lamps[it.uid]
		run.lamps.mirror(l)


## A resume: the entries after the snapshot's tick, each once, on top of its state.
static func apply_after(run: RunState, list: Array[Dictionary], snapshot_tick: int) -> int:
	var applied: int = 0
	for e: Dictionary in list:
		if int(Variants.number(e["tick"])) <= snapshot_tick:
			continue
		apply(run, e)
		applied += 1
	return applied


## One fall or death as recorded: the body on its tile, unconscious or dead, the belt on it, the
## lamp where the cause left it, the marks it had.
static func apply(run: RunState, e: Dictionary) -> void:
	var miner: int = int(Variants.number(e["miner"]))
	if run.miner_state == null or run.miner_state.miner(miner) == null:
		return
	var m: MinerStateSystem.Miner = run.miner_state.miner(miner)
	var dead: bool = str(e["kind"]) == "death"
	m.life = MinerTransitions.Life.DEAD if dead else MinerTransitions.Life.UNCONSCIOUS
	StateDicts.put(m.overlays, {"marks": Variants.dict(e.get("marks", {})).duplicate(true)})
	var tile: Vector2i = e["body_tile"]
	var at: Vector2 = Vector2(tile) + Vector2(0.5, 0.5)
	if run.movement != null and run.movement.miner(m.slot) != null:
		run.movement.place(run, miner, at)
	else:
		run.registry.move(miner, at)
	if run.falls != null:
		var b: BodyState = run.falls.ensure_body(miner)
		b.dead = dead
		b.on_floor = true
	var lamp: Dictionary = Variants.dict(e.get("lamp_end", {}))
	var it: Item = StateDicts.item_from(lamp.get("item", null))
	var uid: int = it.uid if it != null else int(Variants.number(lamp.get("uid", 0)))
	if uid == 0 or run.inventory == null:
		return
	var h: HandsAndBelt = run.inventory.hands_of(miner)
	# Wherever the snapshot had it, the lamp goes where the cause left it (nowhere, if carried off).
	if h.lamp_hand != null and h.lamp_hand.uid == uid:
		h.lamp_hand = null
		h.hooked = false
	if h.free_hand != null and h.free_hand.uid == uid:
		h.free_hand = null
	for i: int in h.slots.size():
		if h.slots[i] != null and h.slots[i].uid == uid:
			h.slots[i] = null
	for raw: Variant in run.inventory.world.items.keys():
		var lying: Item = run.inventory.world.items[raw]
		if lying.uid == uid:
			run.inventory.world.lift(run, int(Variants.number(raw)), &"journal")
			break
	if it != null:
		match str(lamp["where"]):
			"hand", "hook":
				h.lamp_hand = it
				h.hooked = str(lamp["where"]) == "hook"
			"free":
				h.free_hand = it
			"slot":
				var slot: int = int(Variants.number(lamp.get("slot", -1)))
				if slot >= 0 and slot < h.slots.size():
					h.slots[slot] = it
			"floor":
				var t: Vector2i = lamp["tile"]
				run.inventory.world.put(run, it, Vector2(t) + Vector2(0.5, 0.5), &"journal")
	run.inventory.changed.emit(miner)


func write_state(writer: SimStateWriter) -> void:
	writer.put_i64(entries.size())
