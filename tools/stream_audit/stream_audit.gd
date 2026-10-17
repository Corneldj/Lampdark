extends RefCounted
## NET-08's stream audit (GDD §15.3, §9.2, §15.7): it proves no client was sent anything its miner
## could not perceive. Attached to a run (a scenario, or a dev or QA server started with
## --stream-audit), it sees every message the server sends (a filter on its transport) and judges
## each record at the moment it is sent, against an independent reference (LbAuditReference: its own
## line of sight, light, cone, margin, reach and rock line; it never calls VIS-02 to VIS-04 or
## SND-01). Rules, one per record type (rules.gd's registry):
##   frame: tiles seen (line of sight, the 110° cone, lit to 0.12) inside the detail rectangle, with
##     the reference's light and colour, decals at their thresholds; geometry on seen or margin tiles,
##     as the mine has it; identity at 0.30, tokens in the fringe by size class, margin tokens within 1
##     tile beyond the own light's edge or in NET-12's turn band; the glow bucket for bucket; nothing
##     but the own block while blinded; dust only within reach of a Moth whose tell plays;
##   events: an audio record the delivery stage handed over for this client (or a logged illusion to
##     it), whose reach from the event's origins the reference confirms, at the delivered position; a
##     diffuse tell never at a creature; VIS-09's puffs and bursts beside lit tiles the viewer sees; an
##     illusion never to a second client;
##   voice: a stream the forwarder opened to this listener, in the band's range by road (never through
##     a closed air door or a shut gate) or through 2 tiles of rock or fewer at half range (never brick
##     or a door), a phone line, or a shared channel; never to a deafened listener;
##   control: each message's exact layout (decoded and re-encoded byte for byte) and its recipient
##     (Check Lamp's oil only while held; Deafened only to the deafened; knocks only after a fall);
##     debug-lane messages never from a release server and never off the debug lane; any unknown or
##     client-only type fails;
##   secrets (MOD-03): no message carries the run seed (its eight bytes either way round), a run of
##     the plan's bytes or a drawn variant's or condition's name; the staging level, a small number no
##     byte search could tell from another, rides nothing because every layout above is checked exactly.
## Records are judged when first sent; frames are decoded per client against their own baselines, so a
## resend of a record sent earlier is judged as sent again (it reflects this tick's state).
## Legality is judged with the truth the production stages used: entities as mirrored at stage 6, the
## light grid's sources as summed at stage 10, the facing stamped on the input. Server-only and never
## in a release pack.

const Rules = preload("res://tools/stream_audit/rules.gd")
const CLASSES: String = "res://data/world/perception_classes.json"
const SIZES: Dictionary = {"none": 0, "miner": 1, "large": 2, "small": 4}
const CREATURE_KINDS: Array[String] = ["STYTHE", "MOTH", "TAPPER", "TAPPER_ARM", "BESS"]
## How many violations are kept in full (all are counted).
const KEEP_MAX: int = 200

## A filter on the server's transport: every send is judged before it leaves.
class AuditFilter:
	extends TransportFilter
	var audit: RefCounted

	func _init(wrapped: Transport, owner: RefCounted) -> void:
		super(wrapped)
		audit = owner

	func filter_send(peer: int, lane: int, data: PackedByteArray) -> Error:
		audit.call(&"on_send", peer, lane, data)
		return super(peer, lane, data)


## Snapshots at the stage points production reads them.
class Hook:
	extends SimSystem
	var fn: Callable
	var at_stage: int
	var at_order: int
	var label: String

	func _init(f: Callable, stage_id: int, order_id: int, name_text: String) -> void:
		fn = f
		at_stage = stage_id
		at_order = order_id
		label = name_text

	func stage() -> int:
		return at_stage

	func order() -> int:
		return at_order

	func system_name() -> String:
		return label

	func hashed() -> bool:
		return false

	func tick(run: RunState) -> void:
		fn.call(run)


## {tick, client, record, rule, detail}
var violations: Array[Dictionary] = []
var violation_count: int = 0
## rule -> records judged
var checked: Dictionary = {}
var run: RunState = null
var net: ServerNet = null
var ref: LbAuditReference = LbAuditReference.new()
## Truth not yet wired on the server (VIS-10's bite, decals, identity overrides, VIS-03's clamp): the
## owning ticket sets these when it lands, and tests plant them.
var bite_tiles: Callable = func(_slot: int) -> Array[Vector2i]:
	return run.vision.bite_now if run != null and run.vision != null else [] as Array[Vector2i]
var decals: Callable = func() -> Dictionary: return run.vision.decal_bits() if run != null and run.vision != null else {}
## MNR-10: the chalk glyphs on each floor tile (five bytes), what a chalked tile's record must carry.
var chalk_truth: Callable = func() -> Dictionary: return run.vision.chalk if run != null and run.vision != null else {}
var identity_overrides: Callable = func() -> Dictionary: return {}
## slot -> FrameDecoder
var _decoders: Dictionary = {}
## slot -> this tick's expectations (LbAuditReference.evaluate's dictionary)
var _expected: Dictionary = {}
var _expected_tick: int = -1
## The entities as the native mirror holds them this tick: [{id, kind, flags, position}]
var _entities: Array[Dictionary] = []
var _entity_by_id: Dictionary = {}
## kind -> {size, footprint, identity_min, motionless}
var _classes: Dictionary = {}
var _motionless_flag: int = 1
## slot -> {number: true}: events judged at first send
var _events_seen: Dictionary = {}
## slot -> [{start_tick, type, apparent, event_id}]: records the delivery stage handed over
var _delivered: Dictionary = {}
## tick -> slot -> the observer's tile (the reach rule reads the listener where it was)
var _tiles_at: Dictionary = {}
## noise event id -> NoiseSystem.Event
var _events_by_id: Dictionary = {}
var _events_indexed: int = 0
## illusion id -> slot
var _illusion_target: Dictionary = {}
## "slot|type|start_tick|apparent" -> the illusion's event, for every illusion logged
var _illusions_logged: Dictionary = {}


## Attaches to a run before its first tick: a scenario's, or a dev or QA server's (--stream-audit).
func attach(target: RunState, server_net: ServerNet) -> void:
	run = target
	net = server_net
	if run.mine != null:
		ref.attach(run.mine.native)  # without a mine nothing is seen: frames may carry only the own block
	ref.set_vision_defs({"cone_deg": Tuning.f(&"vision.cone_deg"), "seen_min": Tuning.f(&"vision.seen_light_min"),
		"identity_min": Tuning.f(&"vision.identity_light_min"), "small_min": Tuning.f(&"vision.small_thing_light_min"),
		"trail_min": Tuning.f(&"vision.trail_light_min"), "range": Tuning.f(&"vision.los_range_tiles"),
		"view_w": Tuning.f(&"camera.view_tiles_wide"), "view_h": Tuning.f(&"camera.view_tiles_high"),
		"squint_lead": Tuning.f(&"camera.squint_lead_tiles"), "detail_widen": Tuning.f(&"vision.detail_widen_tiles"),
		"bucket_deg": Tuning.f(&"vision.edge_glow_bucket_deg"), "margin_geometry": Tuning.f(&"vision.margin_geometry_tiles"),
		"margin_entity": Tuning.f(&"vision.margin_entity_tiles")})
	ref.set_light_defs({"core_fraction": Tuning.f(&"light.core_fraction"), "core_value": Tuning.f(&"light.core_value"),
		"edge_value": Tuning.f(&"light.edge_value"), "cap": Tuning.f(&"light.cap"), "value_scale": Tuning.f(&"light.value_scale")})
	_load_classes()
	# Entities as RunState pushed them to the native mirror at stage 6 (nothing in stage 6 moves one);
	# the light as pass 2 summed it; expectations last before vision (stage 12 changes nothing they read).
	run.add_system(Hook.new(_snapshot_entities, StageTable.Stage.LIGHT_PASS_1, 900, "audit_entities"))
	run.add_system(Hook.new(_snapshot_light, StageTable.Stage.LIGHT_PASS_2, 1000, "audit_light"))
	run.add_system(Hook.new(_expect, StageTable.Stage.ROAD_GRAPH, 1000, "audit_expect"))
	if run.audio != null:
		var forward: Callable = run.audio.sink
		run.audio.sink = func(slot: int, r: AudioRecord) -> void:
			_on_delivered(slot, r)
			if forward.is_valid():
				forward.call(slot, r)
	net.transport = AuditFilter.new(net.transport, self)


## A summary for reports and CI: {violations (count), rules: {rule: judged}, first: [...]}.
func report() -> Dictionary:
	return {"violations": violation_count, "checked": checked.duplicate(), "first": violations.duplicate(true)}


func by_rule(rule: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for v: Dictionary in violations:
		if str(v["rule"]) == rule:
			out.append(v)
	return out


#region Snapshots

func _load_classes() -> void:
	var doc: Dictionary = Variants.dict(JSON.parse_string(FileAccess.get_file_as_string(CLASSES)))
	_motionless_flag = int(Variants.number(Variants.dict(doc.get("flags", {})).get("motionless", 1)))
	var classes: Dictionary = Variants.dict(doc.get("classes", {}))
	for raw: Variant in classes.keys():
		var name: String = str(raw)
		if not WorldIds.EntityKind.has(name):
			continue
		var c: Dictionary = Variants.dict(classes[raw])
		_classes[int(Variants.number(WorldIds.EntityKind[name]))] = {"size": int(Variants.number(SIZES.get(str(c.get("size", "none")), 0))),
			"footprint": int(Variants.number(c.get("footprint", 1))), "identity_min": float(Variants.number(c.get("identity_min", -1.0))),
			"motionless": Variants.flag(c.get("motionless", false))}


## Stage 6, first: the registry exactly as RunState just pushed it to the native mirror.
func _snapshot_entities(r: RunState) -> void:
	var m: Dictionary = r.registry.packed_mirror()
	var ids: Array = m["ids"]
	var kinds: PackedInt32Array = m["kinds"]
	var xy: PackedFloat64Array = m["xy"]
	var flags: PackedInt32Array = m["flags"]
	_entities.clear()
	_entity_by_id.clear()
	for i: int in ids.size():
		var e: Dictionary = {"id": int(Variants.number(ids[i])), "kind": kinds[i], "flags": flags[i], "position": Vector2(xy[2 * i], xy[2 * i + 1])}
		_entities.append(e)
		_entity_by_id[e["id"]] = e


## Stage 10, last: the light grid's sources as pass 2 summed them, and the reference's light.
func _snapshot_light(r: RunState) -> void:
	if r.light == null:
		return
	var reach: int = roundi(Tuning.f(&"vision.los_range_tiles")) + 1
	var rects: Array = []
	for slot: int in _observers(r):
		var e: SimEntity = r.registry.get_entity(r.vision.watched_entity(slot))
		var t: Vector2i = e.tile()
		rects.append(Rect2i(t - Vector2i(reach, reach), Vector2i(2 * reach + 1, 2 * reach + 1)))
	ref.snapshot_light(r.light.grid, rects)


## The end of stage 11, just before vision: what each observer may perceive this tick.
func _expect(r: RunState) -> void:
	_expected.clear()
	_expected_tick = r.tick
	var tiles: Dictionary = {}
	var overrides: Dictionary = identity_overrides.call()
	var ents: Array = []
	for e: Dictionary in _entities:
		var kind: int = int(Variants.number(e["kind"]))
		var c: Dictionary = Variants.dict(_classes.get(kind, {"size": 0, "footprint": 1, "identity_min": -1.0, "motionless": false}))
		var size: int = int(Variants.number(c["size"]))
		var token_class: int = size
		if size == SeenKind.Size.LARGE and (Variants.flag(c["motionless"]) or (int(Variants.number(e["flags"])) & _motionless_flag) != 0):
			token_class = SeenKind.Size.LARGE_MOTIONLESS
		var identity: float = float(Variants.number(overrides.get(e["id"], c["identity_min"])))
		ents.append({"id": e["id"], "size": size, "token_class": token_class, "footprint": c["footprint"], "identity_min": identity,
			"position": e["position"]})
	for slot: int in _observers(r):
		var self_id: int = r.vision.watched_entity(slot)
		var me: SimEntity = r.registry.get_entity(self_id)
		var life: int = r.miner_state.life(self_id) if r.miner_state != null else MinerTransitions.Life.UPRIGHT
		# RSC-04: the fallen see nothing, but their own cone within rescue.window_sight_tiles coming round.
		var coming_round: bool = life == MinerTransitions.Life.UNCONSCIOUS and r.dark != null and r.dark.in_window(self_id)
		var observer: Dictionary = {"self": self_id, "position": me.position, "facing": _facing_of(r, slot),
			"blinded": (life == MinerTransitions.Life.UNCONSCIOUS or life == MinerTransitions.Life.DEAD) and not coming_round,
			"clamp": Tuning.f(&"rescue.window_sight_tiles") if coming_round else 0.0,
			"turn_band": _turn_band(float(Variants.number(r.vision.rtt_ms.call(slot)))), "bite": bite_tiles.call(slot)}
		_expected[slot] = ref.evaluate(observer, ents)
		tiles[slot] = me.tile()
	_tiles_at[r.tick] = tiles
	_tiles_at.erase(r.tick - 400)


func _observers(r: RunState) -> Array[int]:
	var out: Array[int] = []
	if r.vision == null:
		return out
	for session: Sessions.Session in net.sessions.welcomed():
		var id: int = r.vision.watched_entity(session.slot)
		if id != 0 and r.registry.has(id):
			out.append(session.slot)
	out.sort()
	return out


## The authoritative facing (MNR-01's, from the stamped input), as VIS-03 reads it.
func _facing_of(r: RunState, slot: int) -> int:
	if r.movement != null and r.movement.miner(slot) != null:
		return r.movement.facing_of(slot)
	var c: InputBuffer.Consumed = r.input_for(slot)
	return c.record.facing if c != null else 0


## GDD §5.6: how far the miner can turn before a frame computed now arrives, at most the cap.
func _turn_band(rtt_ms: float) -> float:
	var hz: float = Tuning.f(&"net.tick_hz")
	var lag: float = rtt_ms / 1000.0 + Tuning.f(&"net.input_buffer_target_ticks") / hz + 1.0 / hz + Tuning.f(&"vision.turn_band_extra_s")
	return minf(Tuning.f(&"movement.turn_rate_deg_s") * lag, Tuning.f(&"vision.turn_band_max_deg"))


func _on_delivered(slot: int, r: AudioRecord) -> void:
	var log: Array[Dictionary] = run.audio.deliveries
	var event_id: int = int(Variants.number(log.back()["event_id"])) if not log.is_empty() else -1
	var list: Array = Variants.array(_delivered.get(slot, []))
	list.append({"start_tick": r.start_tick, "type": r.type, "apparent": r.apparent, "event_id": event_id, "flags": r.flags,
		"points": r.points.duplicate()})
	if list.size() > 2048:
		list = list.slice(list.size() - 1024)
	_delivered[slot] = list


## The own status: exactly what OwnStatus says of the receiving slot's own miner, nobody else's.
func _check_status(slot: int, payload: PackedByteArray) -> void:
	var d: Dictionary = StatusWire.decode(payload)
	if d.is_empty() or StatusWire.encode(d) != payload:
		_fail(slot, "STATUS", "status", "malformed")
		return
	var m: MovementSystem.Miner = run.movement.miner(slot) if run.movement != null else null
	if m == null or StatusWire.encode(OwnStatus.of(run, m.entity_id)) != payload:
		_fail(slot, "STATUS", "status", "not exactly the receiving miner's own status")


## LFT-14: a sheet's ops (LFT-03: SELECT names the sheet for the ops after it). Only server ops,
## whole; strokes as made (PEN) alone on the frames lane and only to a client whose miner reads that
## sheet; everything else on the bulk lane; nothing to a client whose miner is unconscious or dead
## unless the sheet is frozen (the map card); a label's author only in a public lobby (STM-08's
## filter); FREEZE only for the map table, once frozen.
const SHEET_CLIENT_OPS: Array[int] = [SheetCodec.Op.COMMIT_STROKE, SheetCodec.Op.COMMIT_LABEL, SheetCodec.Op.RUB,
	SheetCodec.Op.SKETCH, SheetCodec.Op.RESYNC]


func _check_sheet(slot: int, lane: int, payload: PackedByteArray) -> void:
	var ops: Array[Dictionary] = SheetCodec.decode(payload)
	if ops.is_empty():
		_fail(slot, "SHEET", "sheet", "malformed")
		return
	var frozen: bool = run.sheets != null and run.sheets.table.frozen
	var m: MovementSystem.Miner = run.movement.miner(slot) if run.movement != null else null
	var reader: int = m.entity_id if m != null else 0
	if not frozen and (reader == 0 or run.miner_state == null
			or not [MinerTransitions.Life.UPRIGHT, MinerTransitions.Life.CAUGHT, MinerTransitions.Life.GRABBED].has(run.miner_state.life(reader))):
		_fail(slot, "SHEET", "sheet", "sheet data to a client whose miner is not conscious")
	var parts: Dictionary = SheetCodec.by_sheet(ops)
	var pen: bool = false
	for raw: Variant in parts.keys():
		var kind: int = int(Variants.number(raw))
		var list: Array[Dictionary] = parts[raw]
		for d: Dictionary in list:
			var op: int = int(Variants.number(d["op"]))
			if op == SheetCodec.Op.PEN:
				pen = true
				if list.size() != 1 or parts.size() != 1 or run.closeups == null or run.closeups.kind_of(reader) != SheetKind.close_up(kind):
					_fail(slot, "SHEET", "sheet", "a stroke as made to a client not reading its sheet")
			elif SHEET_CLIENT_OPS.has(op):
				_fail(slot, "SHEET", "sheet", "a client's op sent to a client")
			elif op == SheetCodec.Op.ADD_LABEL and not str(d["author"]).is_empty() and run.header.mode != ServerConfig.Mode.PUBLIC:
				_fail(slot, "SHEET", "sheet", "a label's author outside a public lobby")
			elif op == SheetCodec.Op.FREEZE and (not frozen or kind != SheetKind.Kind.MAP_TABLE):
				_fail(slot, "SHEET", "sheet", "a map card's digest before the map table froze")
	_lane(slot, lane, Lane.Id.FRAMES if pen else Lane.Id.BULK, Protocol.Msg.SHEET)


## LFT-03: the repair list as the Manual prints it: exactly the run's kind, can count and jobs, in
## the Company's order, to a client whose miner reads the Manual. Never the seed, a place or a done
## flag: the layout has room for none.
func _check_manual(slot: int, lane: int, payload: PackedByteArray) -> void:
	_lane(slot, lane, Lane.Id.CONTROL, Protocol.Msg.MANUAL)
	var d: Dictionary = RepairJobs.decode(payload)
	var m: MovementSystem.Miner = run.movement.miner(slot) if run.movement != null else null
	if d.is_empty() or run.repair == null or run.repair.list == null:
		_fail(slot, "MANUAL", "manual", "malformed, or no list")
		return
	var l: RepairList = run.repair.list
	if RepairJobs.encode(l.kind, l.cans_required, l.jobs) != payload:
		_fail(slot, "MANUAL", "manual", "not exactly the run's list")
	if m == null or run.closeups == null or run.closeups.kind_of(m.entity_id) != CloseupKind.Kind.MANUAL:
		_fail(slot, "MANUAL", "manual", "to a client whose miner is not reading the Manual")


## RSC-06: Lamp Check's opening only once the run has ended, exactly as Lamp Check made it for this
## client (its own miner's outcome, nobody else's), and its end only once it has ended. Never a
## Ready (the client's own message). No outcome, nor who is below, travels before the run's end.
func _check_lamp_check(slot: int, lane: int, payload: PackedByteArray) -> void:
	_lane(slot, lane, Lane.Id.CONTROL, Protocol.Msg.LAMP_CHECK)
	var d: Dictionary = LampCheckWire.read(payload)
	var lc: LampCheck = run.lamp_check
	if d.is_empty() or lc == null:
		_fail(slot, "LAMP_CHECK", "lamp_check", "malformed, or no Lamp Check")
		return
	match str(d["kind"]):
		LampCheckWire.OPEN:
			if lc.state != LampCheck.State.OPEN and lc.state != LampCheck.State.ENDED:
				_fail(slot, "LAMP_CHECK", "lamp_check", "an opening before the run's end")
			elif payload != lc.opening_for(run, slot):
				_fail(slot, "LAMP_CHECK", "lamp_check", "not exactly Lamp Check's opening for this client")
		LampCheckWire.END:
			if lc.state != LampCheck.State.ENDED:
				_fail(slot, "LAMP_CHECK", "lamp_check", "an end before Lamp Check ended")
		_:
			_fail(slot, "LAMP_CHECK", "lamp_check", "a Ready sent to a client")


## NET-09: saves reach members as opaque sealed bytes. Never in a public run; a snapshot's data on
## bulk with a plain header of versions and chain fields only (and MOD-05's resume line: the list,
## the run time and the deepest ring, all of them things the crew has seen), a journal entry on control.
const SAVE_HEADER_KEYS: Array[String] = ["build", "bundle", "deepest", "generator", "kind", "list", "mode", "parent_hash", "run_time_s",
	"run_uuid", "seq", "templates"]


func _check_save(slot: int, lane: int, type: int, payload: PackedByteArray) -> void:
	var name: String = str(Protocol.Msg.find_key(type))
	if run.header.mode == ServerConfig.Mode.PUBLIC:
		_fail(slot, name, "save", "save data sent in a public run")
	if type == Protocol.Msg.JOURNAL:
		_lane(slot, lane, Lane.Id.CONTROL, type)
		if SaveWire.read_journal(payload).is_empty():
			_fail(slot, name, "save", "malformed")
		return
	_lane(slot, lane, Lane.Id.BULK, type)
	var d: Dictionary = SaveWire.read_save_data(payload)
	if d.is_empty():
		_fail(slot, name, "save", "malformed")
		return
	var keys: Array = Variants.dict(d["header"]).keys()
	keys.sort()
	if keys != SAVE_HEADER_KEYS:
		_fail(slot, name, "save", "a plain header beyond versions and chain fields: %s" % str(keys))

#endregion

#region Sends

func on_send(peer: int, lane: int, data: PackedByteArray) -> void:
	var session: Sessions.Session = net.sessions.for_peer(peer)
	var slot: int = session.slot if session != null else -1
	var message: Dictionary = Protocol.unframe(data)
	if message.is_empty():
		_fail(slot, "message", "registry", "an unframed send on lane %d" % lane)
		return
	var type: int = int(Variants.number(message["type"]))
	var payload: PackedByteArray = message["payload"]
	var rule: String = Rules.rule_of_message(type)
	_count(rule if not rule.is_empty() else "registry")
	_check_secrets(slot, type, data)
	match rule:
		"":
			_fail(slot, "message %d" % type, "registry", "a record type with no audit rule")
		"client_only":
			_fail(slot, str(Protocol.Msg.find_key(type)), "registry", "a client-to-server message sent to a client")
		"handshake":
			_lane(slot, lane, Lane.Id.CONTROL, type)
			if type == Protocol.Msg.WELCOME:
				_check_welcome(slot, payload)
		"frame":
			_lane(slot, lane, Lane.Id.FRAMES, type)
			_check_frame(slot, payload)
		"voice":
			_lane(slot, lane, Lane.Id.VOICE, type)
			_check_voice(slot, payload)
		"inventory":
			_lane(slot, lane, Lane.Id.CONTROL, type)
			_check_inventory(slot, payload)
		"feel":
			_lane(slot, lane, Lane.Id.CONTROL, type)
			_check_feel(slot, payload)
		"ring":
			_lane(slot, lane, Lane.Id.CONTROL, type)
			var d: Dictionary = RingMessages.decode(payload)
			var options: Array[String] = []
			for o: Variant in Variants.array(d.get("options", [])):
				options.append(str(o))
			if d.is_empty() or RingMessages.encode(Variants.flag(d["open"]), options, int(Variants.number(d["chosen"])),
					Variants.array(d["belt"])) != payload:
				_fail(slot, "RING", "ring", "not exactly {open, chosen, options, belt}: extra or malformed bytes")
		"ambient":
			_lane(slot, lane, Lane.Id.CONTROL, type)
			var d: Dictionary = AmbientMessages.decode(payload)
			if d.is_empty() or AmbientMessages.encode(StringName(str(d["layer"])), Variants.flag(d["start"]), float(Variants.number(d["fade_s"]))) != payload:
				_fail(slot, "AMBIENT", "ambient", "not exactly {layer, start, fade_s}")
		"deafened":
			_lane(slot, lane, Lane.Id.CONTROL, type)
			var d: Dictionary = DeafenedMessages.decode(payload)
			if d.is_empty() or DeafenedMessages.encode(float(Variants.number(d["duration_s"])), float(Variants.number(d["dip_db"]))) != payload:
				_fail(slot, "DEAFENED", "deafened", "not exactly {duration_s, dip_db}")
			elif run.deafen == null or not run.deafen.is_deafened(slot):
				_fail(slot, "DEAFENED", "deafened", "to a client whose miner is not deafened")
		"watch", "replay":
			_lane(slot, lane, Lane.Id.CONTROL, type)
			_check_dark(slot, type, payload)
		"save":
			_check_save(slot, lane, type, payload)
		"status":
			_lane(slot, lane, Lane.Id.CONTROL, type)
			_check_status(slot, payload)
		"sheet":
			_check_sheet(slot, lane, payload)
		"manual":
			_check_manual(slot, lane, payload)
		"lamp_check":
			_check_lamp_check(slot, lane, payload)
		"callout":
			_lane(slot, lane, Lane.Id.CONTROL, type)
			var r: CalloutRecord = CalloutRecord.decode(payload)
			if r == null or r.encode() != payload:
				_fail(slot, "CALLOUT", "callout", "not exactly {voice, line, band, apparent, gain, muffle, flags, mask}")
			elif run.callouts == null or not run.callouts.sent.any(func(s: Array) -> bool: return int(Variants.number(s[0])) == slot and s[1] == payload):
				_fail(slot, "CALLOUT", "callout", "a callout the server did not deliver to this client this tick")
		"closeup":
			_lane(slot, lane, Lane.Id.CONTROL, type)
			var c: Dictionary = CloseupKind.decode(payload)
			var reader: int = run.vision.watched_entity(slot) if run.vision != null else 0
			if c.is_empty() or CloseupKind.encode(int(Variants.number(c["kind"])) as CloseupKind.Kind,
					int(Variants.number(c["seat"])) as CloseupKind.Seat) != payload:
				_fail(slot, "CLOSE_UP", "closeup", "not exactly {kind, seat}")
			elif run.closeups == null or int(Variants.number(c["kind"])) != run.closeups.kind_of(reader):
				_fail(slot, "CLOSE_UP", "closeup", "a close-up this client's miner is not reading")
		"board":
			# LFT-13: exactly the board as it stands (flaps, cord, awake: never a place, a caller or a
			# cause), to the client whose miner sits at it, and no one else.
			_lane(slot, lane, Lane.Id.CONTROL, type)
			var board: Dictionary = BoardWire.decode(payload)
			var me: MovementSystem.Miner = run.movement.miner(slot) if run.movement != null else null
			if board.is_empty():
				_fail(slot, "BOARD", "board", "malformed")
			elif me == null or run.closeups == null or run.closeups.operator() != me.entity_id:
				_fail(slot, "BOARD", "board", "the board to a client whose miner is not its operator")
			elif run.switchboard == null or run.switchboard.view(run) != payload:
				_fail(slot, "BOARD", "board", "not exactly the board as it stands")
		"knocks":
			_lane(slot, lane, Lane.Id.CONTROL, type)
			if not payload.is_empty():
				_fail(slot, "KNOCKS", "knocks", "the knocks carry %d bytes; they carry nothing" % payload.size())
			elif run.fall_audio == null or not run.fall_audio.outbox.has(slot):
				_fail(slot, "KNOCKS", "knocks", "knocks with no fall behind them")
		"debug":
			if net.flavour == BuildInfo.Flavour.RELEASE:
				_fail(slot, str(Protocol.Msg.find_key(type)), "debug", "a debug record (QA illusion ids, truth) from a release server")
			if lane != Lane.Id.DEBUG:
				_fail(slot, str(Protocol.Msg.find_key(type)), "debug", "a debug record off the debug lane")
	if lane == Lane.Id.DEBUG and rule != "debug":
		_fail(slot, str(Protocol.Msg.find_key(type)), "registry", "a game record on the debug lane")


## MOD-03: the seed, the plan and the draw never leave the server (NET-09's saves carry the seed
## sealed). A seed below 2^40 (a test's) or a plan run of few distinct bytes is too plain to search for.
func _check_secrets(slot: int, type: int, data: PackedByteArray) -> void:
	_count("secrets")
	var hex: String = data.hex_encode()
	var name: String = str(Protocol.Msg.find_key(type))
	for pattern: Array in _secret_patterns():
		if _has_aligned(hex, str(pattern[1])):
			_fail(slot, name, "secrets", "carries the run's %s" % pattern[0])


## [what, hex] for each secret worth a search.
func _secret_patterns() -> Array[Array]:
	var out: Array[Array] = []
	var seed_value: int = run.header.run_seed
	if seed_value < 0 or seed_value >= (1 << 40):
		var le: PackedByteArray = PackedByteArray()
		le.resize(8)
		le.encode_s64(0, seed_value)
		var be: PackedByteArray = le.duplicate()
		be.reverse()
		out.append(["seed", le.hex_encode()])
		out.append(["seed", be.hex_encode()])
	var plan: PackedByteArray = run.header.plan
	if plan.size() >= 64:
		var run_of: PackedByteArray = plan.slice(plan.size() / 2, plan.size() / 2 + 24)
		var distinct: Dictionary = {}
		for b: int in run_of:
			distinct[b] = true
		if distinct.size() >= 12:
			out.append(["plan", run_of.hex_encode()])
	for drawn: String in run.header.draw:
		if drawn.length() >= 4:
			out.append(["draw (%s)" % drawn, drawn.to_utf8_buffer().hex_encode()])
	return out


static func _has_aligned(hex: String, pattern: String) -> bool:
	var at: int = hex.find(pattern)
	while at >= 0:
		if at % 2 == 0:
			return true
		at = hex.find(pattern, at + 1)
	return false


## RSC-04: WATCH and REPLAY go only to a fallen or dead client. A watch carries frames at least
## rescue.watch_delay_s old; a replay only the client's own frames from before its fall.
func _check_dark(slot: int, type: int, payload: PackedByteArray) -> void:
	var name: String = str(Protocol.Msg.find_key(type))
	var rule: String = name.to_lower()
	var d: Dictionary = DarkMessages.decode(payload)
	var f: DarkSystem.Fallen = run.dark.of_slot(slot) if run.dark != null else null
	if d.is_empty():
		_fail(slot, name, rule, "malformed")
		return
	if f == null:
		_fail(slot, name, rule, "to a client whose miner is not in the Dark")
		return
	var newest: int = run.tick - 1 - roundi(Tuning.f(&"rescue.watch_delay_s") * Tuning.f(&"net.tick_hz"))
	for raw: Variant in Variants.array(d["frames"]):
		var t: int = Variants.array(raw)[0]
		if type == Protocol.Msg.WATCH and t > newest:
			_fail(slot, name, rule, "frame %d is not %.0f s old" % [t, Tuning.f(&"rescue.watch_delay_s")])
		if type == Protocol.Msg.REPLAY and t > f.fell_tick:
			_fail(slot, name, rule, "frame %d is after the fall (%d)" % [t, f.fell_tick])


func _lane(slot: int, lane: int, want: int, type: int) -> void:
	if lane != want:
		_fail(slot, str(Protocol.Msg.find_key(type)), "registry", "on lane %d, not %d" % [lane, want])


func _check_welcome(slot: int, payload: PackedByteArray) -> void:
	var w: Protocol.Welcome = Protocol.Welcome.decode(payload)
	if w == null:
		_fail(slot, "WELCOME", "handshake", "malformed")
		return
	# Exactly the welcome's fields (slot, token, tick rate and clock, phase, client tuning, the debug
	# grant): no field for a seed or anything else can ride it.
	if w.encode() != Protocol.frame(Protocol.Msg.WELCOME, payload):
		_fail(slot, "WELCOME", "handshake", "not exactly the welcome's fields")


func _check_inventory(slot: int, payload: PackedByteArray) -> void:
	var d: Dictionary = InventoryWire.decode(payload)
	if d.is_empty() or InventoryWire.encode(d) != payload:
		_fail(slot, "INVENTORY", "inventory", "not exactly the owner's hands and belt")
		return
	if d.has("check"):
		var c: InputBuffer.Consumed = run.input_for(slot)
		if c == null or (c.record.holds & InputRecord.HOLD_CHECK_LAMP) == 0:
			_fail(slot, "INVENTORY", "inventory", "the lamp's oil and notches while Check Lamp is not held")


func _check_feel(slot: int, payload: PackedByteArray) -> void:
	var d: Dictionary = FeelMessages.decode(payload)
	var again: PackedByteArray = PackedByteArray()
	if not d.is_empty():
		if int(Variants.number(d["kind"])) == FeelMessages.Kind.BUMP:
			again = FeelMessages.bump(str(d["caption_key"]))
		else:
			again = FeelMessages.feel(str(d["caption_key"]), int(Variants.number(d["bearing_q"])), str(d["verb_key"]))
	if d.is_empty() or again != payload:
		_fail(slot, "FEEL", "feel", "not exactly {caption_key, bearing_q, verb_key}: a position, token or distance rides it")
	elif d.has("bearing_q") and int(Variants.number(d["bearing_q"])) > 15 and int(Variants.number(d["bearing_q"])) != FeelMessages.NO_BEARING:
		_fail(slot, "FEEL", "feel", "a bearing finer than the 16 steps")

#endregion

#region Frames

func _check_frame(slot: int, payload: PackedByteArray) -> void:
	if not _decoders.has(slot):
		_decoders[slot] = FrameDecoder.new()
	var decoder: FrameDecoder = _decoders[slot]
	var d: FrameDecoder.Decoded = decoder.decode(payload)
	if not d.ok:
		_fail(slot, "FRAME", "frame", "undecodable (no baseline, short or trailing bytes)")
		return
	var x: Dictionary = Variants.dict(_expected.get(slot, {})) if _expected_tick == run.tick else {}
	var view: ReceivedView = d.view
	if d.view.dust:
		_check_dust(slot)
	if x.is_empty() or Variants.flag(x.get("blinded", false)):
		# No observer, or blinded: nothing but the own block.
		var why: String = "blinded" if not x.is_empty() else "no observer"
		if not d.tiles_sent.is_empty() or not d.geometry_sent.is_empty() or not d.tokens_sent.is_empty() or (d.glow_sent and view.glow_mask != 0):
			_fail(slot, "FRAME", "frame", "%s, yet %d tiles, %d geometry, %d entities" % [why, d.tiles_sent.size(), d.geometry_sent.size(), d.tokens_sent.size()])
	else:
		_check_tiles(slot, d, x)
		_check_geometry(slot, d, x)
		_check_entities(slot, d, x)
		if d.glow_sent:
			_check_glow(slot, view, x)
	_note_illusions()
	for ev: Dictionary in d.events:
		var seen: Dictionary = Variants.dict(_events_seen.get(slot, {}))
		var number: int = int(Variants.number(ev["number"]))
		if seen.has(number):
			continue
		seen[number] = true
		_events_seen[slot] = seen
		if VisualEvents.is_visual(int(Variants.number(ev["type"]))):
			_check_visual(slot, ev, x)
		else:
			_check_audio(slot, ev)


func _check_tiles(slot: int, d: FrameDecoder.Decoded, x: Dictionary) -> void:
	var detail: Dictionary = x["detail"]
	var truth: Dictionary = decals.call()
	for t: Vector2i in d.tiles_sent:
		_count("tile")
		var rec: PackedByteArray = d.view.tiles[t]
		if not detail.has(t):
			_fail(slot, "tile %s" % t, "tile", "not seen in the detail region (line of sight, the cone, 0.12)")
			continue
		var packed: int = int(Variants.number(detail[t]))
		var value: int = packed >> 4
		var want: int = clampi((value * 255 + 500) / 1000, 0, 255)
		var colour: int = rec[1] & ~TileBits.COLOUR_HATCH_BIT
		if rec[0] != want or colour != (packed & 15):
			_fail(slot, "tile %s" % t, "tile", "light %d colour %d; the reference has %d and %d" % [rec[0], colour, want, packed & 15])
		if (rec[1] & TileBits.COLOUR_HATCH_BIT) != 0 and not _hatching(t, packed & 15):
			_fail(slot, "tile %s" % t, "tile", "the hatch bit on a tile no hatching egg-glow lights")
		# VIS-10: a trail's direction rides only with its blood, and is the trail's own.
		var dir: int = (rec[2] & TileBits.DECAL_DIR_MASK) >> TileBits.DECAL_DIR_SHIFT
		var truth_dir: int = (int(Variants.number(truth.get(t, 0))) & TileBits.DECAL_DIR_MASK) >> TileBits.DECAL_DIR_SHIFT
		if (dir != 0 and (rec[2] & TileBits.DECAL_BLOOD) == 0) or ((rec[2] & TileBits.DECAL_BLOOD) != 0 and dir != truth_dir):
			_fail(slot, "tile %s" % t, "tile", "trail direction %d; the trail has %d" % [dir, truth_dir])
		var bits: int = rec[2] & 7
		var have: int = int(Variants.number(truth.get(t, 0)))
		var allowed: int = 0
		if (have & 1) != 0 and value >= roundi(Tuning.f(&"vision.trail_light_min") * 1000.0):
			allowed |= 1
		if value >= roundi(Tuning.f(&"vision.small_thing_light_min") * 1000.0):
			allowed |= have & 6
		if bits & ~allowed:
			_fail(slot, "tile %s" % t, "tile", "decals %d; only %d are lit enough (blood 0.12, chalk and numbers 0.30)" % [bits, allowed])
		# MNR-10: glyphs ride only with the chalk bit, and are the tile's own.
		if (rec[2] & TileBits.DECAL_CHALK) == 0:
			if rec.size() != 3:
				_fail(slot, "tile %s" % t, "tile", "chalk glyphs without the chalk bit")
		else:
			var want_glyphs: PackedByteArray = Variants.dict(chalk_truth.call()).get(t, PackedByteArray())
			if rec.slice(3) != want_glyphs:
				_fail(slot, "tile %s" % t, "tile", "chalk %s; the tile has %s" % [rec.slice(3), want_glyphs])


## VIS-10: the hatch bit belongs on an egg-glow tile whose brightest source has the hatch tell.
func _hatching(tile: Vector2i, colour: int) -> bool:
	if colour != LbLightGrid.COLOUR_EGG_GLOW or run.light == null:
		return false
	var src: int = int(Variants.number(run.light.grid.brightest_source(tile).get("id", 0)))
	return src != 0 and (int(Variants.number(run.light.grid.source_info(src).get("flags", 0))) & LbLightGrid.FLAG_HATCH_TELL) != 0


func _check_geometry(slot: int, d: FrameDecoder.Decoded, x: Dictionary) -> void:
	var detail: Dictionary = x["detail"]
	var margin: Dictionary = x["margin"]
	for t: Vector2i in d.geometry_sent:
		_count("geometry")
		if not detail.has(t) and not margin.has(t):
			_fail(slot, "geometry %s" % t, "geometry", "neither seen nor in the margin (2 tiles beyond the own light, in the cone)")
			continue
		var rec: PackedByteArray = d.view.geometry[t]
		if rec[0] != run.mine.native.material_at(t) or rec[1] != run.mine.native.state_at(t):
			_fail(slot, "geometry %s" % t, "geometry", "material %d state %d; the mine has %d and %d" % [rec[0], rec[1],
				run.mine.native.material_at(t), run.mine.native.state_at(t)])


func _check_entities(slot: int, d: FrameDecoder.Decoded, x: Dictionary) -> void:
	if d.tokens_sent.is_empty():
		return
	var expected: Dictionary = x["entities"]
	var by_token: Dictionary = {}
	for e: Dictionary in _entities:
		var token: int = run.replication.native.token_of(slot, int(Variants.number(e["id"])))
		if token != 0:
			by_token[token] = e
	for token: int in d.tokens_sent:
		var rec: Dictionary = d.view.entities[token]
		var level: int = int(Variants.number(rec["level"]))
		var record: String = "entity token %d" % token
		_count("entity")
		if not by_token.has(token):
			_fail(slot, record, "entity", "a token this client was never issued (a server id, or nothing)")
			continue
		var e: Dictionary = by_token[token]
		var id: int = int(Variants.number(e["id"]))
		var want: int = int(Variants.number(expected.get(id, 0)))
		var want_level: int = want >> 8
		var want_class: int = want & 255
		match level:
			2:
				if want_level != LbAuditReference.LEVEL_IDENTITY:
					_fail(slot, record, "entity", "identity for entity %d; the reference has level %d (identity needs 0.30)" % [id, want_level])
				elif int(Variants.number(rec["size_or_kind"])) != _seen_kind(int(Variants.number(e["kind"]))):
					_fail(slot, record, "entity", "kind %d; the entity is %d" % [rec["size_or_kind"], _seen_kind(int(Variants.number(e["kind"])))])
			1:
				if want_level != LbAuditReference.LEVEL_TOKEN or int(Variants.number(rec["size_or_kind"])) != want_class:
					_fail(slot, record, "entity", "a fringe token for entity %d; the reference has level %d class %d" % [id, want_level, want_class])
			3:
				if want_level != LbAuditReference.LEVEL_MARGIN or int(Variants.number(rec["size_or_kind"])) != want_class:
					_fail(slot, record, "entity", "a margin token for entity %d; the reference has level %d (1 tile beyond the own light, or the turn band)"
						% [id, want_level])
			_:
				_fail(slot, record, "entity", "level %d" % level)
		var at: Vector2 = rec["position"]
		var truth: Vector2 = e["position"]
		if absf(at.x - truth.x) > 1.0 / 128.0 + 1e-6 or absf(at.y - truth.y) > 1.0 / 128.0 + 1e-6:
			_fail(slot, record, "entity", "at %s; entity %d is at %s" % [at, id, truth])


func _seen_kind(kind: int) -> int:
	var name: Variant = WorldIds.EntityKind.find_key(kind)
	return int(Variants.number(SeenKind.Kind.get(str(name), 0))) if name != null else 0


func _check_glow(slot: int, view: ReceivedView, x: Dictionary) -> void:
	_count("glow")
	var glow: PackedInt32Array = x["glow"]
	var mask: int = 0
	for b: int in glow.size():
		if glow[b] >= 0:
			mask |= 1 << b
	if view.glow_mask != mask:
		_fail(slot, "glow", "glow", "mask %x; the reference has %x" % [view.glow_mask, mask])
		return
	for b: int in glow.size():
		if glow[b] >= 0 and view.glow_colour[b] != glow[b]:
			_fail(slot, "glow", "glow", "bucket %d colour %d; the reference has %d" % [b, view.glow_colour[b], glow[b]])


func _check_dust(slot: int) -> void:
	_count("dust")
	var m: MovementSystem.Miner = run.movement.miner(slot) if run.movement != null else null
	if m == null or run.creatures == null:
		_fail(slot, "dust", "dust", "dust with no miner or no creatures")
		return
	var at: Vector2 = Vector2(m.state.x, m.state.y)
	for c: Creature in run.creatures.creatures:
		var moth: Moth = c as Moth
		if moth != null and moth.tell_active() and at.distance_to(moth.position(run)) <= Tuning.f(&"moth.tell_reach_tiles") + 1e-9:
			return
	_fail(slot, "dust", "dust", "dust with no Moth's tell within reach")

#endregion

#region Events

func _check_audio(slot: int, ev: Dictionary) -> void:
	_count("audio")
	var number: int = int(Variants.number(ev["number"]))
	var record: String = "event %d type %d" % [number, ev["type"]]
	if _is_illusion_to(slot, ev):
		return
	# RSC-04's unconscious stream: game sound reaches the fallen only round their body, muffled.
	var reader: int = run.vision.watched_entity(slot) if run.vision != null else 0
	if run.miner_state != null and run.miner_state.life(reader) == MinerTransitions.Life.UNCONSCIOUS \
			and (int(Variants.number(ev.get("flags", 0))) & AudioRecord.MUFFLED) == 0:
		_fail(slot, record, "audio", "to an unconscious client, not muffled")
	var at: Vector2 = ev["apparent"]
	var match_rec: Dictionary = {}
	for raw: Variant in Variants.array(_delivered.get(slot, [])):
		var r: Dictionary = raw
		var r_at: Vector2 = r["apparent"]
		if int(Variants.number(r["start_tick"])) == int(Variants.number(ev["start_tick"])) and int(Variants.number(r["type"])) == int(Variants.number(ev["type"])) \
				and r_at.distance_to(at) <= 1.0 / 16.0 + 1e-6:
			match_rec = r
			break
	if match_rec.is_empty():
		_fail(slot, record, "audio", "no delivery to this client and no logged illusion")
		return
	var event_id: int = int(Variants.number(match_rec["event_id"]))
	if event_id < 0:
		# A local emitter or a diffuse tell: never placed at a creature.
		var points: Array = ev["points"]
		for raw_p: Variant in points:
			var p: Vector2 = raw_p
			for e: Dictionary in _entities:
				var e_at: Vector2 = e["position"]
				if CREATURE_KINDS.has(str(WorldIds.EntityKind.find_key(int(Variants.number(e["kind"]))))) and p.distance_to(e_at) <= 0.5:
					_fail(slot, record, "audio", "a tell point on a creature (entity %d)" % e["id"])
					return
		return
	_index_events()
	var event: NoiseSystem.Event = _events_by_id.get(event_id, null)
	if event == null:
		_fail(slot, record, "audio", "noise event %d is not in the true-world log" % event_id)
		return
	var listener: Vector2i = Variants.dict(_tiles_at.get(event.tick, {})).get(slot, Vector2i(-99999, -99999))
	if listener.x == -99999:
		return  # the listener was not observing then (no frame expectation): nothing to measure from
	var budget: float = event.level_np - Tuning.f(&"noise.player_threshold")
	var cost: float = ref.reach_cost(event.origins, listener, budget, event.mode == RoadGraphService.MODE_VOICE, Tuning.f(&"noise.closed_portal_cost"))
	if cost < 0.0 and event.type == NoiseTypes.Type.ROCK_TAP and _tap_through_rock(event, listener, at):
		return  # SND-12: a rock tap through the rock to a teammate the air did not reach
	if cost < 0.0:
		var road: String = "-"
		for raw: Variant in event.deliveries:
			var dl: Dictionary = Variants.dict(raw)
			if int(Variants.number(dl.get("listener", -1))) == slot:
				road = "path %s tiles, %s closed, remaining %s, via %s" % [dl.get("path_tiles"), dl.get("closed_portals"), dl.get("remaining_np"), dl.get("via")]
		_fail(slot, record, "audio", "the reference cannot reach %s from %s at %.0f np (the Road Graph: %s)" % [listener, event.origins,
			event.level_np, road])
		return
	for raw: Variant in event.deliveries:
		var dl: Dictionary = Variants.dict(raw)
		if int(Variants.number(dl.get("listener", -1))) == slot:
			var dl_at: Vector2 = dl.get("apparent", at)
			if dl_at.distance_to(at) > 1.0 / 16.0 + 1e-6:
				_fail(slot, record, "audio", "at %s; the Road Graph delivered it at %s (a true source?)" % [at, dl.get("apparent")])
			return


func _check_visual(slot: int, ev: Dictionary, x: Dictionary) -> void:
	_count("visual")
	var record: String = "visual %d type %d" % [ev["number"], ev["type"]]
	if x.is_empty() or int(Variants.number(ev["start_tick"])) != _expected_tick:
		_fail(slot, record, "visual", "outside the tick it was made, or to a client with no view")
		return
	var detail: Dictionary = x["detail"]
	var min_q: int = roundi(Tuning.f(&"light.dust_min_light") * 255.0)
	var at: Vector2 = ev["apparent"]
	var reach: float = 1.0 if int(Variants.number(ev["type"])) == VisualEvents.Type.PUFF else float(Variants.number(ev["level_np"])) + 0.5
	for raw: Variant in detail.keys():
		var t: Vector2i = raw
		var q: int = clampi(((int(Variants.number(detail[raw])) >> 4) * 255 + 500) / 1000, 0, 255)
		if q >= min_q and (Vector2(t) + Vector2(0.5, 0.5)).distance_to(at) <= reach + 1e-6:
			return
	_fail(slot, record, "visual", "no lit tile the viewer sees beside it")


func _index_events() -> void:
	var log: Array[NoiseSystem.Event] = run.noise.event_log
	while _events_indexed < log.size():
		var e: NoiseSystem.Event = log[_events_indexed]
		_events_by_id[e.id] = e
		_events_indexed += 1


## The illusion stage's records this tick (CRT-10's lie log, as Replication holds them before the
## frames are numbered): each to its one target; one illusion on a second client fails.
func _note_illusions() -> void:
	for raw: Variant in run.replication._illusions:
		var item: Array = raw
		var target: int = int(Variants.number(item[0]))
		var ev: Dictionary = Variants.dict(item[1])
		var id: int = int(Variants.number(item[2]))
		var key: String = "%d|%d|%d|%s" % [target, int(Variants.number(ev.get("type", 0))), int(Variants.number(ev.get("start_tick", 0))),
			ev.get("apparent", Vector2.ZERO)]
		if _illusions_logged.has(key):
			continue
		_illusions_logged[key] = ev
		if id >= 0:
			if _illusion_target.has(id) and int(Variants.number(_illusion_target[id])) != target:
				_fail(target, "illusion %d" % id, "illusion", "an illusion reached a second client (first %d)" % _illusion_target[id])
			else:
				_illusion_target[id] = target


func _is_illusion_to(slot: int, ev: Dictionary) -> bool:
	var at: Vector2 = ev["apparent"]
	for raw: Variant in _illusions_logged.keys():
		var parts: PackedStringArray = str(raw).split("|")
		if int(parts[0]) != slot or int(parts[1]) != int(Variants.number(ev["type"])) or int(parts[2]) != int(Variants.number(ev["start_tick"])):
			continue
		var logged: Dictionary = _illusions_logged[raw]
		var l_at: Vector2 = logged.get("apparent", Vector2.ZERO)
		if l_at.distance_to(at) <= 1.0 / 16.0 + 1e-6:
			return true
	return false

#endregion

#region Voice

func _check_voice(slot: int, payload: PackedByteArray) -> void:
	_count("voice")
	var p: Dictionary = VoicePackets.read_down(payload)
	if p.is_empty():
		_fail(slot, "VOICE", "voice", "malformed")
		return
	var stream: int = int(Variants.number(p["stream"]))
	var speaker: int = -1
	for raw: Variant in run.voice._speaking.keys():
		var st: Dictionary = Variants.dict(run.voice._speaking[raw])
		if int(Variants.number(Variants.dict(st.get("streams", {})).get(slot, -1))) == stream:
			speaker = int(Variants.number(raw))
	var record: String = "voice stream %d" % stream
	if speaker < 0:
		_fail(slot, record, "voice", "a stream the forwarder never opened to this listener")
		return
	if run.deafen != null and run.deafen.is_deafened(slot) and not Variants.flag(p["end"]):
		_fail(slot, record, "voice", "to a deafened listener")
		return
	if Variants.flag(p["dry"]):
		for raw: Variant in run.voice.channels.values():
			var members: Dictionary = Variants.dict(raw)
			if members.has(slot) and members.has(speaker):
				return
		_fail(slot, record, "voice", "a channel's voice from %d, who shares no channel with this listener" % speaker)
		return
	if Variants.flag(p["telephone"]):
		if not Variants.dict(run.voice.direct.get(speaker, {})).has(slot):
			_fail(slot, record, "voice", "a phone voice from %d with no line open" % speaker)
		return
	if Variants.flag(p["end"]):
		return
	var route: int = int(Variants.number(run.voice.route_of.get(speaker, VoiceRoutes.Route.NORMAL)))
	var band: int = int(Variants.number(p["band"]))
	match route:
		VoiceRoutes.Route.DRAGGED, VoiceRoutes.Route.COMING_ROUND, VoiceRoutes.Route.FALL_MUFFLED:
			band = 1
		VoiceRoutes.Route.FALL_SCREAM:
			band = 3
		VoiceRoutes.Route.CUT, VoiceRoutes.Route.ASIDE:
			_fail(slot, record, "voice", "voice from %d, whose route is cut or whispered to no one" % speaker)
			return
	var keys: Array[StringName] = [&"", &"voice.whisper_range_tiles", &"voice.talk_range_tiles", &"voice.shout_range_tiles", &"voice.scream_range_tiles"]
	if band < 1 or band > 4:
		_fail(slot, record, "voice", "band %d" % band)
		return
	var range_t: float = Tuning.f(keys[band])
	# The route was made when the utterance began or SND-07 last refreshed it (every
	# voice.route_refresh_s once a tile changed): judge it with the miners where they stood then, or now.
	var made: int = int(Variants.number(Variants.dict(run.voice._speaking[speaker]).get("refreshed_tick", run.tick)))
	var places: Array[Array] = [[_tile_of_slot(speaker), _tile_of_slot(slot)]]
	for t: int in [made, made - 1]:
		var then: Dictionary = Variants.dict(_tiles_at.get(t, {}))
		if then.has(speaker) and then.has(slot):
			places.append([then[speaker], then[slot]])
	for pair: Array in places:
		var from_t: Vector2i = pair[0]
		var to_t: Vector2i = pair[1]
		if _voice_reaches(from_t, to_t, range_t):
			return
	_fail(slot, record, "voice", "from %s to %s at band %d: no road within %.0f tiles (doors and gates shut) and no rock line" % [places[0][0],
		places[0][1], band, range_t])


## SND-12: a rock tap reaches a listener through the rock when the straight line from the tapper's
## tile (when it tapped) crosses no brick or door and is within voice.rock_tap_range_tiles, and it
## is heard at a wall face beside the listener.
func _tap_through_rock(event: NoiseSystem.Event, listener: Vector2i, at: Vector2) -> bool:
	var from: Vector2i = Vector2i(-99999, -99999)
	var tiles: Dictionary = Variants.dict(_tiles_at.get(event.tick, {}))
	for raw: Variant in tiles.keys():
		if run.vision.watched_entity(int(Variants.number(raw))) == event.source_entity:
			from = tiles[raw]
	if from.x == -99999:
		return false
	var line: Dictionary = ref.straight_line(from, listener)
	return not Variants.flag(line["brick"]) and not Variants.flag(line["door"]) \
			and float(Variants.number(line["distance"])) <= Tuning.f(&"voice.rock_tap_range_tiles") + 1e-6 \
			and at.distance_to(Vector2(listener) + Vector2(0.5, 0.5)) <= 1.6


func _voice_reaches(from: Vector2i, to: Vector2i, range_t: float) -> bool:
	if Vector2(from).distance_to(Vector2(to)) <= range_t + 1e-6 and ref.reach_cost([from], to, range_t, true, 0.0) >= 0.0:
		return true  # by road
	var line: Dictionary = ref.straight_line(from, to)
	var solid: int = int(Variants.number(line["solid"]))
	return not Variants.flag(line["brick"]) and not Variants.flag(line["door"]) and solid >= 1 \
			and solid <= roundi(Tuning.f(&"voice.rock_line_max_rock_tiles")) \
			and float(Variants.number(line["distance"])) <= range_t * Tuning.f(&"voice.rock_line_range_factor") + 1e-6


func _tile_of_slot(slot: int) -> Vector2i:
	var m: MovementSystem.Miner = run.movement.miner(slot) if run.movement != null else null
	if m == null or not run.registry.has(m.entity_id):
		return Vector2i(-99999, -99999)
	return run.registry.get_entity(m.entity_id).tile()

#endregion

func _count(rule: String) -> void:
	checked[rule] = int(Variants.number(checked.get(rule, 0))) + 1


func _fail(slot: int, record: String, rule: String, detail: String) -> void:
	violation_count += 1
	if violations.size() < KEEP_MAX:
		violations.append({"tick": run.tick if run != null else -1, "client": slot, "record": record, "rule": rule, "detail": detail})
