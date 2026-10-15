extends "res://tests/scenario/kit/scenario_test.gd"
## NET-07: true_view() returns nothing before Lamp Check and the full 30x17 frame during it, tick
## by tick, every call logged; when Lamp Check ends the record's memory is freed and every reader
## returns nothing. Statically: only the record's readers name the true view, and no client code
## names the record.

const W = preload("res://tests/scenario/net/record_world.gd")
const PROBE_AT: int = 330


## Ground truth at one tick, taken after the record (stage RECORD): the victim's frame light and
## every entity's position.
class Probe:
	extends SimSystem
	var entity: int = 0
	var light: PackedByteArray = PackedByteArray()
	var origin: Vector2i = Vector2i.ZERO
	var positions: Dictionary = {}

	func stage() -> int:
		return StageTable.Stage.RECORD

	func order() -> int:
		return 90

	func system_name() -> String:
		return "true_view_probe"

	func hashed() -> bool:
		return false

	func tick(run: RunState) -> void:
		if run.tick != PROBE_AT:
			return
		var size: Vector2i = run.record.frame_size
		origin = run.registry.get_entity(entity).tile() - Vector2i(floori(size.x / 2.0), floori(size.y / 2.0))
		light = run.light.grid.light_bytes(Rect2i(origin, size))
		for id: int in run.registry.ids():
			positions[id] = run.registry.get_entity(id).position


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_the_true_view_waits_for_lamp_check() -> void:
	var probe: Probe = Probe.new()
	var s: Scenario = make({"seed": 101, "fixture": "test", "systems": [probe]})
	var miners: Array[MinerHandle] = W.crew(s, 2, 101)
	var ann: MinerHandle = miners[0]
	probe.entity = ann.entity_id
	s.step(400)
	assert_true(s.run.falls.fall_unconscious(s.run, ann.entity_id, FallCause.Cause.MOTH_SMOTHER))
	s.step(200)
	var r: RunRecord = s.run.record
	var w: RecordWindow = W.window_of(s, RecordWindow.Kind.FALL, ann.entity_id)
	assert_not_null(w)
	if w == null:
		return
	assert_eq(RecordReaders.true_view(r, w), [] as Array[Dictionary], "nothing while the run plays")
	s.run.set_phase(RunState.Phase.LAMP_CHECK)
	var frames: Array[Dictionary] = RecordReaders.true_view(r, w)
	assert_eq(frames.size(), w.end - w.start + 1, "a frame for every tick of the window")
	var at_probe: Dictionary = {}
	for f: Dictionary in frames:
		var size: Vector2i = f["size"]
		var light: PackedByteArray = f["light"]
		assert_eq(size, Vector2i(30, 17))
		assert_eq(light.size(), 30 * 17)
		if int(Variants.number(f["tick"])) == PROBE_AT:
			at_probe = f
	assert_false(at_probe.is_empty())
	if not at_probe.is_empty():
		var origin: Vector2i = at_probe["origin"]
		var light: PackedByteArray = at_probe["light"]
		assert_eq(origin, probe.origin, "the victim's frame")
		assert_eq(light, probe.light, "the frame's true light, tile for tile")
		var rect: Rect2 = Rect2(Vector2(probe.origin), Vector2(30, 17))
		var expected: Dictionary = {}
		for raw: Variant in probe.positions.keys():
			var p: Vector2 = probe.positions[raw]
			if rect.has_point(p):
				expected[raw] = p
		var got: Dictionary = {}
		for e: Dictionary in Variants.array(at_probe["entities"]):
			got[e["id"]] = e["position"]
		assert_eq(got, expected, "every real entity in the frame, where it really was")
		assert_true(got.has(ann.entity_id))
		assert_gt(Variants.array(at_probe["sources"]).size(), 0, "the lamps lighting the frame")
	assert_eq(r.true_view_log.size(), 2, "every call is logged")
	assert_string_contains(r.true_view_log[0], "refused")
	assert_string_contains(r.true_view_log[1], "served")
	# Lamp Check ends: everything goes.
	s.run.set_phase(RunState.Phase.ENDED)
	assert_true(r.discarded)
	assert_eq(r.memory_bytes(), 0)
	assert_true(r.ring.is_empty() and r.windows.is_empty())
	assert_eq(RecordReaders.true_view(r, w), [] as Array[Dictionary])
	assert_eq(RecordReaders.victim_view(r, w), [] as Array[Dictionary])
	assert_eq(RecordReaders.delayed_view(r, miners[1].slot, 1.0), {})
	assert_eq(RecordReaders.lies(r, 0, s.run.tick), [] as Array[Dictionary])
	assert_eq(r.export_windows(), [])
	s.step(100)
	assert_eq(r.memory_bytes(), 0, "and records nothing more")


func test_only_the_readers_name_the_true_view_and_no_client_names_the_record() -> void:
	var offenders: Array[String] = []
	for path: String in _scripts("res://server") + _scripts("res://shared"):
		if path.begins_with("res://server/net/record_readers.gd"):
			continue
		if FileAccess.get_file_as_string(path).contains("true_view("):
			offenders.append(path)
	assert_eq(offenders, [] as Array[String], "only RecordReaders serves the true view")
	var named: Array[String] = []
	for path: String in _scripts("res://client") + _scripts("res://shared"):
		var text: String = FileAccess.get_file_as_string(path)
		for cls: String in ["RunRecord", "RecordReaders", "RecordWindow", "RecordBlock"]:
			if text.contains(cls):
				named.append("%s names %s" % [path, cls])
	assert_eq(named, [] as Array[String], "no client or shared code reaches the record")


func _scripts(dir: String) -> Array[String]:
	var out: Array[String] = []
	for f: String in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d: String in DirAccess.get_directories_at(dir):
		out.append_array(_scripts(dir.path_join(d)))
	return out
