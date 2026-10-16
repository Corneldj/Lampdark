extends RefCounted
## LFT-14's scenarios: base camp (LFT-01) with miners at its map table (UI-02's close-up open) and
## what their clients draw through their ClientSheet.

const Scenario = preload("res://tests/scenario/kit/scenario.gd")
const MinerHandle = preload("res://tests/scenario/kit/miner_handle.gd")
const W = preload("res://tests/scenario/ui/closeup_world.gd")
const C = preload("res://tests/scenario/basecamp/camp_world.gd")


static func camp(seed_value: int, scenario_test: Object, mode: ServerConfig.Mode = ServerConfig.Mode.FRIENDS) -> Scenario:
	var s: Scenario = scenario_test.call(&"make", {"seed": seed_value, "fixture": C.scenario_fixture(), "mode": mode, "slots": 8})
	C.load_camp(s)
	return s


## A miner beside the table, opening it with an interact as a player does.
static func walk_up(s: Scenario, name: String, nth: int = 0) -> MinerHandle:
	var h: MinerHandle = W.beside(s, name, CloseupKind.Kind.MAP_TABLE, nth)
	W.interact(s, h)
	s.step(4)
	return h


## A miner beside the table with its close-up opened directly: a crowd round the table faces each
## other, and an interact picks whatever lies most along the miner's facing, often a teammate.
static func at_table(s: Scenario, name: String, nth: int = 0) -> MinerHandle:
	var h: MinerHandle = W.beside(s, name, CloseupKind.Kind.MAP_TABLE, nth)
	s.step(1)
	open_table(s, h)
	return h


## Opens the table's close-up for a miner wherever they stand (the scenario's shortcut).
static func open_table(s: Scenario, h: MinerHandle) -> void:
	s.run.closeups.open_for(s.run, h.entity_id, CloseupKind.Kind.MAP_TABLE, "test")


static func close_table(s: Scenario, h: MinerHandle) -> void:
	s.run.closeups.close(h.entity_id, "test")


## A stroke from `from` to `to` in `steps` even steps (keep each 16 to 127 units).
static func line(from: Vector2, to: Vector2, steps: int) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	for i: int in steps + 1:
		out.append(from.lerp(to, float(i) / steps).round())
	return out


## The client commits a finished stroke (its seq, or -1).
static func draw(h: MinerHandle, points: PackedVector2Array) -> int:
	return h.connection.sheet.commit_stroke(points, Transport.now_usec())


## The client sends a raw SHEET message on the bulk lane (what a modified client could send).
static func send_raw(h: MinerHandle, payload: PackedByteArray) -> void:
	h.connection.send(Lane.Id.BULK, payload, Protocol.Msg.SHEET)


## Every SHEET message the server sent this client, decoded: [{tick, lane, ops}].
static func sheet_messages(h: MinerHandle) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m: Dictionary in h.capture.messages:
		if int(Variants.number(m["type"])) != Protocol.Msg.SHEET:
			continue
		var bytes: PackedByteArray = m["bytes"]
		var unframed: Dictionary = Protocol.unframe(bytes)
		var payload: PackedByteArray = unframed.get("payload", PackedByteArray())
		out.append({"tick": m["tick"], "lane": m["lane"], "ops": SheetCodec.decode(payload)})
	return out


## The ops for one sheet (the map table's unless asked) of every SHEET message, in order, of the
## kinds asked (all when empty).
static func ops_of(h: MinerHandle, kinds: Array = [], sheet: int = SheetKind.Kind.MAP_TABLE) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m: Dictionary in sheet_messages(h):
		var ops: Array[Dictionary] = []
		ops.assign(Variants.array(m["ops"]))
		var parts: Dictionary = SheetCodec.by_sheet(ops)
		for d: Dictionary in Variants.array(parts.get(sheet, [])):
			if kinds.is_empty() or kinds.has(int(Variants.number(d["op"]))):
				out.append(d)
	return out


static func refused_whys(s: Scenario) -> Array[String]:
	var out: Array[String] = []
	for r: Dictionary in s.run.sheets.refused:
		out.append(str(r["why"]))
	return out
