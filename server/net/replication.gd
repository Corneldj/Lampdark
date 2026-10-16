class_name Replication
extends SimSystem
## NET-04 on the server (stage 15, SEND): each welcomed client's frame, built natively
## (LbReplication) from VIS-03's frame for its miner, GEN-01's geometry and its own miner,
## against the newest frame it acknowledged, within its byte budget, and sent on the frames
## lane. Audio events come from SND-02's player deliveries; CRT-10 appends illusions with
## append_illusion_event() before this stage, and numbering happens only here, in a canonical
## order. Every frame goes to the stream tap. Server-only.

## NET-03's acknowledgement as it arrived, with the client's receive delay (2 ms units), for
## NET-07's run record.
signal acked(slot: int, now: int, ack16: int, bits: int, recv_delay: int)

var net: ServerNet
var native: LbReplication = LbReplication.new()
var tap: StreamTap = StreamTap.new()
var _secret: int = 0
var _built_tick: int = -1
var _margin_delay_ticks: int = 0
## CRT-10's illusions queued this tick: [slot, event, illusion id].
var _illusions: Array[Array] = []
## FND-08: the illusions this tick's frames carried, {slot, tick, number, illusion_id}, for the QA
## overlay's tags on the debug lane. Server-side only; never in a frame.
var illusions_sent: Array[Dictionary] = []
## slot -> the transport peer its frames go to; a new peer on a slot (a rejoin) resyncs it.
var _peers: Dictionary = {}
## slot -> the own-inventory bytes last sent on that peer (MNR-04); a new peer gets them afresh.
var _inventory_sent: Dictionary = {}
## slot -> the own status bytes last sent on that peer (StatusWire); a new peer gets them afresh.
var _status_sent: Dictionary = {}
## VIS-08: the flame bits last set per entity (so a cleared state is cleared on the wire too).
var _flame_set: Dictionary = {}
## VIS-06: the lying things' held bits last set, by entity (so a lifted one is cleared).
var _lying_set: Dictionary = {}
var _run: RunState = null


func _init(server_net: ServerNet, vision: VisionSystem, mine: Mine, secret: int) -> void:
	net = server_net
	_secret = secret
	native.attach(vision.native if vision != null else null, mine.native if mine != null else null)
	native.set_params(_params(false))
	for name: String in SeenKind.Kind.keys():
		if WorldIds.EntityKind.has(name):
			native.set_seen_kind(int(Variants.number(WorldIds.EntityKind[name])), int(Variants.number(SeenKind.Kind[name])))
	# CRT-09: the Tapper's arm is all of it ever seen: identified as the Tapper (the first playtest
	# found it arriving as an unknown square).
	native.set_seen_kind(WorldIds.EntityKind.TAPPER_ARM, SeenKind.Kind.TAPPER)


func _params(full_frames: bool) -> Dictionary:
	return {
		"budget_kbps": Tuning.f(&"net.down_budget_kbps"),
		"burst_bytes": Tuning.i(&"net.down_burst_bytes"),
		"max_frame_bytes": Tuning.i(&"net.unreliable_max_bytes") - 8,
		"history": Tuning.i(&"net.ack_history_frames"),
		"token_cooldown": Tuning.i(&"net.token_reuse_cooldown_frames"),
		"age_gain": Tuning.f(&"net.priority_age_gain"),
		"held_cells": Tuning.i(&"vision.held_geometry_cells"),
		"full_frames": full_frames,
		"margin_delay_ticks": _margin_delay_ticks,
	}


## NET-12's planted fault (tests only): margin tokens reach clients only after `ticks` ticks in the
## margin, so the margin's head start is lost and criterion 4's probe must fail. 0 restores it.
func plant_margin_delay(ticks: int) -> void:
	_margin_delay_ticks = ticks
	native.set_params(_params(false))


func stage() -> int:
	return StageTable.Stage.SEND


func order() -> int:
	return 0


func system_name() -> String:
	return "replication"


## NET-03's acknowledgement from an input packet (InputService calls it at stage 2).
func on_ack(slot: int, now: int, ack16: int, bits: int, recv_delay: int = 0) -> void:
	_ensure(slot)
	native.on_ack(slot, now, ack16, bits)
	acked.emit(slot, now, ack16, bits, recv_delay)


## The M1 debug switch: every frame against an empty view (a full resync), ignoring acks.
func set_full_frames(on: bool) -> void:
	native.set_params(_params(on))


## CRT-10's illusion stage: an event for one client, encoded exactly as a real one. Must come
## before this tick's frames are built.
## `event` is a whole AudioRecord's event dictionary (AudioRecord.to_event): an illusion carries
## every field a real record has, and no other.
## `illusion_id` is the lie log's id (FND-08's QA overlay names it); it never rides in the frame.
func append_illusion_event(slot: int, event: Dictionary, illusion_id: int = -1) -> void:
	if _run != null and _built_tick == _run.tick:
		push_error("Replication.append_illusion_event: this tick's frames are already built")
		return
	_ensure(slot)
	native.queue_event(slot, event)
	_illusions.append([slot, event, illusion_id])


## A rejoin (NET-11): forget what the client held; the next frame is a full resync.
func reset_client(slot: int) -> void:
	native.reset_client(slot)


func tick(run: RunState) -> void:
	_run = run
	if run.tells != null:
		run.tells.prepare(run)
	for slot: int in net.dropped_slots:
		native.remove_client(slot)
		_peers.erase(slot)
		_inventory_sent.erase(slot)
		_status_sent.erase(slot)
	if run.movement != null:
		for raw: Variant in _watched_slots(run):
			var m: MovementSystem.Miner = run.movement.miner(int(Variants.number(raw)))
			if m != null:
				native.set_entity_facing(m.entity_id, m.state.facing)
				if run.miner_state != null:
					# VIS-06: the cap badge rides with the cues (identity only). Proposed: by seat until
					# the lobby assigns badges (STM-02).
					native.set_entity_cues(m.entity_id, MinerCues.with_badge(run.miner_state.cues(m.entity_id), m.slot % 6))
				if run.inventory != null:
					native.set_entity_held(m.entity_id, run.inventory.held_bits(m.entity_id))
	_push_flames(run)
	_push_lying_lamps(run)
	_push_arms(run)
	_push_fixtures(run)
	illusions_sent.clear()
	for session: Sessions.Session in net.sessions.welcomed():
		_ensure(session.slot)
		if int(Variants.number(_peers.get(session.slot, session.peer))) != session.peer:
			native.reset_client(session.slot)
			_inventory_sent.erase(session.slot)
			_status_sent.erase(session.slot)
		_peers[session.slot] = session.peer
		_send_inventory(run, session)
		_send_feel(run, session)
		_send_ambient(run, session)
		_send_deafened(run, session)
		_send_knocks(run, session)
		_send_ring(run, session)
		_send_status(run, session)
		var observer: int = session.slot if run.vision != null and run.vision.watched_entity(session.slot) != 0 else -1
		var bytes: PackedByteArray = native.build(session.slot, observer, run.tick, _own_block(run, session.slot),
			run.inputs.action_ack(session.slot) if run.inputs != null else 0xFFFF,
			run.inputs.depth(session.slot) if run.inputs != null else 0,
			run.inputs.input_ack(session.slot) if run.inputs != null else 0xFFFF)
		net.transport.send(session.peer, Lane.Id.FRAMES, Protocol.frame(Protocol.Msg.FRAME, bytes))
		tap.publish(session.slot, run.tick, bytes)
		_number_illusions(run, session.slot)
	if run.fall_audio != null:
		run.fall_audio.outbox.clear()  # a miner with no client misses them
	_illusions.clear()
	_built_tick = run.tick
	# Frames leave this tick, not at the next tick's poll.
	net.transport.flush()


## MNR-04: the own miner's hands and belt, to its owner only, whenever they change.
func _send_inventory(run: RunState, session: Sessions.Session) -> void:
	if run.inventory == null or run.movement == null or run.movement.miner(session.slot) == null:
		return
	var miner: int = run.movement.miner(session.slot).entity_id
	# MNR-07: Check Lamp's oil and notches, only to the holder and only while it is held.
	var c: InputBuffer.Consumed = run.input_for(session.slot)
	var check: Dictionary = {}
	if c != null and (c.record.holds & InputRecord.HOLD_CHECK_LAMP) != 0 and run.lamps != null:
		check = run.lamps.check_record(miner)
		if check.is_empty() and run.electric != null:
			check = run.electric.check_record(miner)
	var bytes: PackedByteArray = run.inventory.own_bytes(miner, check)
	if _inventory_sent.get(session.slot, PackedByteArray()) == bytes:
		return
	_inventory_sent[session.slot] = bytes
	net.transport.send(session.peer, Lane.Id.CONTROL, Protocol.frame(Protocol.Msg.INVENTORY, bytes))


## The own miner's status (OwnStatus, StatusWire), to its owner only, whenever it changes.
func _send_status(run: RunState, session: Sessions.Session) -> void:
	if run.movement == null or run.movement.miner(session.slot) == null:
		return
	var bytes: PackedByteArray = StatusWire.encode(OwnStatus.of(run, run.movement.miner(session.slot).entity_id))
	if _status_sent.get(session.slot, PackedByteArray()) == bytes:
		return
	_status_sent[session.slot] = bytes
	net.transport.send(session.peer, Lane.Id.CONTROL, Protocol.frame(Protocol.Msg.STATUS, bytes))


## MNR-05: the interact ring's options (and a body's belt), to the actor's client only.
func _send_ring(run: RunState, session: Sessions.Session) -> void:
	if run.ring == null:
		return
	var keep: Array[Array] = []
	for item: Array in run.ring.outbox:
		if int(Variants.number(item[0])) == session.slot:
			var bytes: PackedByteArray = item[1]
			net.transport.send(session.peer, Lane.Id.CONTROL, Protocol.frame(Protocol.Msg.RING, bytes))
		else:
			keep.append(item)
	run.ring.outbox = keep


## VIS-07: feel answers and wall bumps, each to its own miner's client only.
func _send_feel(run: RunState, session: Sessions.Session) -> void:
	if run.feel == null:
		return
	var keep: Array[Array] = []
	for item: Array in run.feel.outbox:
		if int(Variants.number(item[0])) == session.slot:
			var bytes: PackedByteArray = item[1]
			net.transport.send(session.peer, Lane.Id.CONTROL, Protocol.frame(Protocol.Msg.FEEL, bytes))
		else:
			keep.append(item)
	run.feel.outbox = keep


func _ensure(slot: int) -> void:
	if not native.has_client(slot):
		var keys: PackedInt64Array = PackedInt64Array([slot])
		native.add_client(slot, LbHash.hash(_secret, HashDomain.NET_TOKEN, keys))


func _watched_slots(run: RunState) -> Array:
	var out: Array = []
	for session: Sessions.Session in net.sessions.welcomed():
		if run.movement.miner(session.slot) != null:
			out.append(session.slot)
	return out


## The own block: position, facing, gait, the speed factor, and flags: bits 0-3 the gait
## constraints (movement off, run disallowed, walk only, facing lock, MNR-01); bits 4-6 the life
## state and bits 7-14 the capabilities (move, turn, voice, lamp, belt, signals, and interact as
## 0 no, 1 yes, 2 within reach, 3 self-rescue), MNR-03; bit 15 movement authority: set while the
## server drives the own miner (Caught, Grabbed, unconscious outside the crawl, dead), NET-05.
## Overlays, marks and causes never ride here.
const INTERACT: Dictionary = {"no": 0, "yes": 1, "reach": 2, "self_rescue": 3}


func _own_block(run: RunState, slot: int) -> Dictionary:
	var m: MovementSystem.Miner = run.movement.miner(slot) if run.movement != null else null
	if m == null:
		return {"x": 0.0, "y": 0.0, "facing": 0, "gait": 255, "speed_q": 100, "flags": 0, "stamina_q": 0, "lamp_radius": 0.0}
	var c: MinerMotion.Constraints = MinerMotion.Constraints.most_restrictive(m.requests.values())
	var flags: int = (1 if c.movement_off else 0) | (0 if c.run_allowed else 2) | (4 if c.walk_only else 0) | (8 if c.facing_lock else 0)
	if run.miner_state != null and run.miner_state.miner(m.entity_id) != null:
		var caps: Dictionary = run.miner_state.capabilities(m.entity_id)
		flags |= (run.miner_state.life(m.entity_id) & 7) << 4
		var bit: int = 7
		for key: String in ["move", "turn", "voice", "lamp", "belt", "signals"]:
			flags |= (1 if Variants.flag(caps[key]) else 0) << bit
			bit += 1
		flags |= int(Variants.number(INTERACT.get(caps["interact"], 0))) << 13
		if not Variants.flag(caps["move"]):
			flags |= 1 << 15
	return {"x": m.state.x, "y": m.state.y, "facing": m.state.facing, "gait": m.state.gait if m.state.gait >= 0 else 255,
		"speed_q": clampi(roundi(m.modifiers.factor() * 100.0), 0, 255), "flags": flags,
		"stamina_q": clampi(m.stamina.pool_ms / 50, 0, 255),
		"lamp_radius": run.light.grid.owned_radius(m.entity_id) if run.light != null else 0.0,
		"flame": (run.flame_states.own_flags(m.entity_id) if run.flame_states != null else 0)
			| (LampSignalKind.to_flame(run.lamp_signals.kind_of(m.entity_id)) if run.lamp_signals != null else 0),
		"dust": run.tells.dust_for(slot) if run.tells != null else false}


## VIS-08: each entity's flame states on its identity record (a miner's lamp-hand flame, a lamp
## lying or hanging); a shuttered or slotted lamp shows nothing to others.
func _push_flames(run: RunState) -> void:
	if run.flame_states == null:
		return
	var now: Dictionary = run.flame_states.entity_bits.duplicate()
	# SND-12: a lamp signal under way rides in its maker's flame byte (bits 5-7, identity only).
	if run.lamp_signals != null:
		for raw: Variant in run.lamp_signals.active.keys():
			var m: int = int(Variants.number(raw))
			now[m] = int(Variants.number(now.get(m, 0))) | LampSignalKind.to_flame(run.lamp_signals.kind_of(m))
	for raw: Variant in _flame_set.keys():
		if not now.has(raw):
			native.set_entity_flame(int(Variants.number(raw)), 0)
	for raw: Variant in now.keys():
		native.set_entity_flame(int(Variants.number(raw)), int(Variants.number(now[raw])))
	_flame_set = now.duplicate()


## VIS-06: a thing lying or hanging shows its kind on its own identity record (the same low byte a
## miner's hand uses), so the player can tell a spanner from a fuse once it is lit to identity
## (0.30) and the glyph can name it; a lamp also shows whether its flame shows. Records of items no
## longer lying are cleared. (Lamps only until the first playtest found "Pick up" told nothing.)
## MNR-14: a load also shows its heading (its record's facing), and a tub the cans in it.
func _push_lying_lamps(run: RunState) -> void:
	if run.inventory == null:
		return
	var now: Dictionary = {}
	for raw: Variant in run.inventory.world.items.keys():
		var it: Item = run.inventory.world.items[raw]
		var bits: int = it.kind
		if ItemKinds.is_load(it.kind):
			native.set_entity_facing(int(Variants.number(raw)), int(Variants.number(it.state.get("heading", 0))) & 0xFFFF)
			if it.kind == ItemKinds.Kind.TUB:
				bits |= Variants.array(it.state.get("cans", [])).size() << ItemKinds.TUB_CANS_SHIFT
		if run.lamps != null and run.lamps.lamps.has(it.uid):
			var l: GauzeLamp = run.lamps.lamps[it.uid]
			if l.held():
				continue
			bits |= ItemKinds.LAMP_LIT_BIT if l.burning() and not l.shutter_closed else 0
		now[int(Variants.number(raw))] = bits
	for raw: Variant in _lying_set.keys():
		if not now.has(raw):
			native.set_entity_held(int(Variants.number(raw)), 0)
	for raw: Variant in now.keys():
		native.set_entity_held(int(Variants.number(raw)), int(Variants.number(now[raw])))
	_lying_set = now


## CRT-09: each Tapper arm's facing, out of the wall toward its target.
func _push_arms(run: RunState) -> void:
	if run.creatures == null:
		return
	for c: Creature in run.creatures.creatures:
		var t: Tapper = c as Tapper
		if t != null and t.hunt.arm != 0:
			native.set_entity_facing(t.hunt.arm, t.hunt.arm_facing)


## LFT-06: the paraffin tank's sight glass, as its identity record shows it (FixtureKinds).
func _push_fixtures(run: RunState) -> void:
	if run.fuel != null and run.fuel.glass != 0 and run.registry.has(run.fuel.glass):
		native.set_entity_held(run.fuel.glass, run.fuel.glass_bits(run))


## MNR-13: a body over a carrier's shoulder is never sent as its own token.
func set_attached(entity: int, attached: bool) -> void:
	native.set_entity_attached(entity, attached)


## VIS-09: a puff or a dust burst (VisualEvents) for one viewer, on the event channel; before this
## tick's frames are built.
func queue_visual(slot: int, record: AudioRecord) -> void:
	if net.sessions.welcomed().filter(func(s: Sessions.Session) -> bool: return s.slot == slot).is_empty():
		return
	_ensure(slot)
	native.queue_event(slot, record.to_event())


## SND-03: one audio record that survived the masks, into that client's frame events.
func queue_audio(listener: int, record: AudioRecord) -> void:
	if net.sessions.welcomed().filter(func(s: Sessions.Session) -> bool: return s.slot == listener).is_empty():
		return
	_ensure(listener)
	native.queue_event(listener, record.to_event())


## SND-03: ambient cues, each to its own client only.
func _send_ambient(run: RunState, session: Sessions.Session) -> void:
	if run.audio == null:
		return
	var keep: Array[Array] = []
	for item: Array in run.audio.outbox:
		if int(Variants.number(item[0])) == session.slot:
			var bytes: PackedByteArray = item[1]
			net.transport.send(session.peer, Lane.Id.CONTROL, Protocol.frame(Protocol.Msg.AMBIENT, bytes))
		else:
			keep.append(item)
	run.audio.outbox = keep


## SND-04: a Deafened record, to the deafened miner's client only.
func _send_deafened(run: RunState, session: Sessions.Session) -> void:
	if run.deafen == null:
		return
	var keep: Array[Array] = []
	for item: Array in run.deafen.outbox:
		if int(Variants.number(item[0])) == session.slot:
			var bytes: PackedByteArray = item[1]
			net.transport.send(session.peer, Lane.Id.CONTROL, Protocol.frame(Protocol.Msg.DEAFENED, bytes))
		else:
			keep.append(item)
	run.deafen.outbox = keep


## SND-15: a fall's knocks: an empty KNOCKS message per fall, to each conscious miner's client.
func _send_knocks(run: RunState, session: Sessions.Session) -> void:
	if run.fall_audio == null:
		return
	for slot: int in run.fall_audio.outbox:
		if slot == session.slot:
			net.transport.send(session.peer, Lane.Id.CONTROL, Protocol.frame(Protocol.Msg.KNOCKS, PackedByteArray()))


## FND-08: each illusion this client's frame carried, by the record number the build gave it
## (matched on the fields the number was keyed by).
func _number_illusions(run: RunState, slot: int) -> void:
	var numbered: Array = []
	for item: Array in _illusions:
		if int(Variants.number(item[0])) != slot:
			continue
		if numbered.is_empty():
			numbered = native.last_numbered(slot)
		var ev: Dictionary = item[1]
		var at: Vector2 = Variants.dict(ev).get("apparent", Vector2.ZERO)
		for raw: Variant in numbered:
			var n: Dictionary = raw
			if int(Variants.number(n["type"])) == int(Variants.number(ev.get("type", -1))) \
					and int(Variants.number(n["start_tick"])) == int(Variants.number(ev.get("start_tick", -1))) \
					and int(Variants.number(n["ax16"])) == roundi(at.x * 16.0) and int(Variants.number(n["ay16"])) == roundi(at.y * 16.0):
				illusions_sent.append({"slot": slot, "tick": run.tick, "number": int(Variants.number(n["number"])), "illusion_id": item[2]})
				break
