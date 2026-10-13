extends "res://tools/bots/soak.gd"
## MNR-06's lamp soak (accelerated only): 1 server, 4 bots, 30 minutes of the lamp brain in a lit
## hall of their own lamps, each bot handed a burning gauze lamp. A monitor snuffs a random lamp every 30 s and relights it
## through LampSystem.relight 10 s later, and checks every tick that no lamp goes from Out to
## Burning without a relight call and none opens without its holder's own shutter press.

const Scenario = preload("res://tests/scenario/kit/scenario.gd")
const MinerHandle = preload("res://tests/scenario/kit/miner_handle.gd")
const FixtureMap = preload("res://tests/scenario/kit/fixture_map.gd")


class Monitor:
	extends SimSystem
	var violations: Array[String] = []
	var relights: int = 0
	var snuffs: int = 0
	var openings: int = 0
	var presses: int = 0
	var _burning: Dictionary = {}
	var _relit_now: Dictionary = {}
	var _to_relight: Dictionary = {}
	var _rng: LbRng = LbRng.from_seed(4242)
	var _run: RunState = null

	func stage() -> int:
		return StageTable.Stage.MINERS

	func order() -> int:
		return 95

	func system_name() -> String:
		return "LampSoakMonitor"

	func watch(run: RunState) -> void:
		_run = run
		run.lamps.lamp_changed.connect(_on_changed)

	func _on_changed(l: GauzeLamp, what: StringName, _cause: String) -> void:
		if what == &"step_pressed":
			presses += 1
		if what == &"relight":
			_relit_now[l.uid] = true
		elif what == &"step_pressed" and not l.want_closed and l.shutter_closed:
			openings += 1
			var slot: int = -1
			for s: int in _run.movement.miner_slots():
				if _run.movement.miner(s).entity_id == l.holder:
					slot = s
			var c: InputBuffer.Consumed = _run.input_for(slot) if slot >= 0 else null
			if c == null or (c.record.desired & 1) != 0:
				violations.append("tick %d: lamp %d opened without its holder's press" % [_run.tick, l.uid])

	func tick(run: RunState) -> void:
		var uids: Array = run.lamps.lamps.keys()
		uids.sort()
		for raw: Variant in uids:
			var l: GauzeLamp = run.lamps.lamps[raw]
			var was: bool = Variants.flag(_burning.get(l.uid, l.burning()))
			if not was and l.burning() and not _relit_now.has(l.uid):
				violations.append("tick %d: lamp %d burns again without a relight call" % [run.tick, l.uid])
			_burning[l.uid] = l.burning()
		_relit_now.clear()
		if run.tick % 600 == 300 and not uids.is_empty():
			var l: GauzeLamp = run.lamps.lamps[uids[_rng.range(0, uids.size() - 1)]]
			if l.burning() and run.lamps.snuff(run, l, "soak"):
				snuffs += 1
				_to_relight[l.uid] = run.tick + 200
		for raw: Variant in _to_relight.keys():
			if run.tick >= int(Variants.number(_to_relight[raw])):
				_to_relight.erase(raw)
				var l: GauzeLamp = run.lamps.lamps.get(raw, null)
				if l != null and run.lamps.relight(run, l, "flint"):
					relights += 1


func setup(_ctx: Dictionary) -> void:
	profile = {"servers": 1, "bots": 4, "minutes": 30.0, "seed": 6060, "brains": ["lamp"], "link": ""}


## A 40 x 16 hall, so the lamps light something and the bots see what they set down.
func scenario_config(_server: int) -> Dictionary:
	var rows: PackedStringArray = PackedStringArray()
	rows.append("#".repeat(40))
	for y: int in 14:
		rows.append("#" + ".".repeat(38) + "#")
	rows.append("#".repeat(40))
	rows[8] = "#" + ".".repeat(18) + "a" + ".".repeat(19) + "#"
	return {"fixture": FixtureMap.from_ascii(rows)}


func spawn_tile(scenario: Scenario, bot: int) -> Vector2i:
	return scenario.fixture.spot("a") + Vector2i(bot * 2 - 3, 0)


## Accelerated runs: each bot gets a burning lamp in hand, and the monitor joins the run.
func prepare(scenario: Scenario) -> void:
	for h: MinerHandle in scenario.miners:
		var at: Vector2 = scenario.run.registry.get_entity(h.entity_id).position
		var l: GauzeLamp = scenario.run.lamps.create(scenario.run, 1.0, 3, true, LampRules.WICK_NORMAL, at)
		scenario.run.lamps.pick_up(scenario.run, l, h.entity_id)
	var m: Monitor = Monitor.new()
	scenario.run.add_system(m)
	m.watch(scenario.run)


func inspect(scenario: Scenario) -> Dictionary:
	var m: Monitor = null
	for s: SimSystem in scenario.run.stages.systems_in(StageTable.Stage.MINERS):
		if s is Monitor:
			m = s
	var where: Array[String] = []
	for raw: Variant in scenario.run.lamps.lamps.keys():
		var l: GauzeLamp = scenario.run.lamps.lamps[raw]
		where.append("%s/%s" % [LampRules.Place.find_key(l.place), GauzeLamp.State.find_key(l.state())])
	where.sort()
	return {"violations": m.violations, "relights": m.relights, "snuffs": m.snuffs, "openings": m.openings, "presses": m.presses,
		"lamps": scenario.run.lamps.lamps.size(), "where": where, "refused": scenario.run.lamps.refused.size()}


func verify(report: Dictionary) -> Array[String]:
	var errors: Array[String] = standard_checks(report, roundi(float(Variants.number(profile["minutes"])) * 1200.0))
	for raw: Variant in Variants.array(report.get("servers", [])):
		var s: Dictionary = Variants.dict(raw)
		var seen: Dictionary = Variants.dict(s.get("inspect", {}))
		if seen.is_empty():
			errors.append("server %s: no lamp inspection (run with --accelerated)" % s.get("index"))
			continue
		for v: Variant in Variants.array(seen["violations"]):
			errors.append("server %s: %s" % [s.get("index"), v])
		if int(Variants.number(seen["openings"])) == 0 or int(Variants.number(seen["relights"])) == 0:
			errors.append("server %s: the soak never opened or relit a lamp: %s" % [s.get("index"), seen])
	return errors
