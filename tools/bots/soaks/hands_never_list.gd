extends "res://tools/bots/soak.gd"
## MOD-08's never list under fuzz: 30 minutes (accelerated) of base camp ready to leave, two idle
## humans, and four Hired Hands standing at a gate's levers, the medbay's cupboard, the engine's
## prime and throttle, and a revolver and a kit lying at their feet. Every tick each Hand's input is
## fuzzed with every held control and a one-shot action (the filter must strip them all), and every
## two seconds a seeded order (any callout or signal, POINTs at the gates, the cupboard, the engine
## and the floor) goes to a random Hand. Judged: no gate, air door, kit, revolver, cord, engine or
## lever is ever worked (the humans stand idle, so any change is a Hand's), no Hand holds a tool, a
## kit or the revolver, every injected attempt was turned away, and no Hand moves further in a tick
## than its gait allows. run_soak.sh hands_never_list [--minutes T] (nightly).

const Scenario = preload("res://tests/scenario/kit/scenario.gd")
const MinerHandle = preload("res://tests/scenario/kit/miner_handle.gd")
const FixtureMap = preload("res://tests/scenario/kit/fixture_map.gd")
const C = preload("res://tests/scenario/basecamp/camp_world.gd")
const E = preload("res://tests/unit/lift/engine_world.gd")

const ALL_HOLDS: int = 0x01FF
const ORDER_EVERY_TICKS: int = 40

var _rng: LbRng = null
var _hands: Array[int] = []
var _spots: Array[Vector2i] = []
var _gates_at_start: int = 0
var _injected: int = 0
var _orders: int = 0
var _max_step: float = 0.0
var _last: Dictionary = {}
var _ticks: int = 0


func setup(_ctx: Dictionary) -> void:
	profile = {"servers": 1, "bots": 2, "minutes": 30.0, "seed": 4941, "brains": ["idle"], "link": "", "accelerated": true,
		"capture_keep_s": 5.0}


func scenario_config(_server: int) -> Dictionary:
	return {"fixture": C.scenario_fixture(), "slots": 6}


## Base camp ready to leave: every job but Start done, the tank full, the engine waiting.
func created(s: Scenario) -> void:
	E.ready(s)


func spawn_tile(s: Scenario, bot: int) -> Vector2i:
	return s.run.base_camp.medbay_tables()[0] + Vector2i(1 + bot, 1)


func prepare(s: Scenario) -> void:
	_rng = LbRng.from_seed(int(Variants.number(profile["seed"])))
	var gate: String = s.run.base_camp.gate_system.gates[0].side
	_spots = [C.lever(s, gate, "inside"), s.run.base_camp.medbay_tables()[0], E.spot(s, "engine_prime"), E.spot(s, "engine_throttle")]
	for i: int in _spots.size():
		var at: Vector2i = _spots[i]
		var e: int = s.run.hands.fill_place(s.run, 2 + i, Vector2(at) + Vector2(0.5, 0.5))
		if e != 0:
			_hands.append(e)
			_last[e] = s.run.registry.get_entity(e).position
	var w: ItemWorld = s.run.inventory.world
	for e: int in _hands:
		var at: Vector2 = s.run.registry.get_entity(e).position
		w.put(s.run, w.make(ItemKinds.Kind.REVOLVER), at)
		w.put(s.run, w.make(ItemKinds.Kind.HEALING_KIT), at)
	_gates_at_start = s.run.base_camp.gate_system.diff_log.size()
	s.run.hands.inject = func(_r: RunState, _e: int, rec: InputRecord) -> Array[ActionRecord]:
		_injected += 1
		rec.holds |= ALL_HOLDS & _rng.range(1, ALL_HOLDS)
		var a: ActionRecord = ActionRecord.new()
		a.kind = _rng.range(1, 8) as ActionRecord.Kind
		return [a] as Array[ActionRecord]
	s.on_tick = func(sc: Scenario) -> void: _fuzz(sc)


func _fuzz(s: Scenario) -> void:
	_ticks += 1
	for e: int in _hands:
		var p: Vector2 = s.run.registry.get_entity(e).position
		var was: Vector2 = _last[e]
		_max_step = maxf(_max_step, p.distance_to(was))
		_last[e] = p
	if _ticks % ORDER_EVERY_TICKS != 0 or _hands.is_empty():
		return
	var hand: int = _hands[_rng.range(0, _hands.size() - 1)]
	var what: HandOrders.Order = _rng.range(1, HandOrders.Order.POINT) as HandOrders.Order
	var at: Vector2i = _spots[_rng.range(0, _spots.size() - 1)] + Vector2i(_rng.range(-1, 1), _rng.range(-1, 1))
	var from: int = s.miners[_rng.range(0, s.miners.size() - 1)].entity_id
	s.run.hands.give_order(s.run, hand, what, from, at)
	_orders += 1


func inspect(s: Scenario) -> Dictionary:
	var held: Dictionary = {}
	for e: int in _hands:
		var h: HandsAndBelt = s.run.inventory.hands_of(e)
		for kind: int in [ItemKinds.Kind.REVOLVER, ItemKinds.Kind.HEALING_KIT, ItemKinds.Kind.SPANNER, ItemKinds.Kind.HAMMER,
				ItemKinds.Kind.CROWBAR]:
			if h.count_of(kind) > 0:
				held[str(e)] = str(ItemKinds.Kind.find_key(kind))
	var kit_uses: int = 0
	for u: Dictionary in s.run.revival.uses:
		if _hands.has(int(Variants.number(u.get("user", 0)))):
			kit_uses += 1
	var shots: int = 0
	for r: Dictionary in s.run.revolver.shots:
		if _hands.has(int(Variants.number(r.get("shooter", r.get("miner", 0))))):
			shots += 1
	return {"hands": _hands.size(), "gate_changes": s.run.base_camp.gate_system.diff_log.size() - _gates_at_start,
		"air_door_changes": s.run.air_doors.diff_log.size() if s.run.air_doors != null else 0, "kit_uses": kit_uses,
		"shots": shots, "cord_pulls": s.run.cage.cord.pullers().size() if s.run.cage != null else 0,
		"engine_log": s.run.engine.log.size() if s.run.engine != null else 0, "held": held, "injected": _injected,
		"rejected": s.run.hands.rejected_count, "orders": _orders, "max_step": _max_step,
		"gait_step": MinerMotion.Params.from_tuning().run_speed / Tuning.f(&"net.tick_hz")}


func verify(report: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for raw: Variant in Variants.array(report.get("servers", [])):
		var g: Dictionary = Variants.dict(Variants.dict(raw).get("inspect", {}))
		if int(Variants.number(g.get("hands", 0))) < 4:
			errors.append("only %s Hands stood at their posts" % g.get("hands"))
		for key: String in ["gate_changes", "air_door_changes", "kit_uses", "shots", "cord_pulls", "engine_log"]:
			if int(Variants.number(g.get(key, 0))) > 0:
				errors.append("%s: %s (a Hand worked what it never may)" % [key, g.get(key)])
		if not Variants.dict(g.get("held", {})).is_empty():
			errors.append("Hands hold what they never may: %s" % g.get("held"))
		if int(Variants.number(g.get("rejected", 0))) < int(Variants.number(g.get("injected", 1))):
			errors.append("%s injected attempts, only %s turned away" % [g.get("injected"), g.get("rejected")])
		if int(Variants.number(g.get("orders", 0))) == 0:
			errors.append("no orders were fuzzed")
		if float(Variants.number(g.get("max_step", 0.0))) > float(Variants.number(g.get("gait_step", 0.0))) + 1e-6:
			errors.append("a Hand moved %s tiles in a tick, more than its gait allows" % g.get("max_step"))
	return errors
