extends GutTest
## CRT-01's retreat: it cancels the wind-up, drops the grab, stands the hunt down and lasts
## 2,400 ticks; hits under the threshold only flinch; a retreat ending in the apex turns home.

const StubCreature = preload("res://tests/scenario/kit/kit_creature.gd")

var run: RunState
var sys: CreatureSystem
var c: StubCreature


func before_all() -> void:
	assert_true(Tuning.load_server())


func before_each() -> void:
	run = RunState.new()
	sys = CreatureSystem.new()
	c = StubCreature.new(WorldIds.EntityKind.STYTHE)
	var flags: Dictionary = Tuning.table(&"creatures.enabled")
	if int(Variants.number(flags.get("stythe", 0))) == 0:
		c.kind = WorldIds.EntityKind.MOTH
	assert_eq(sys.spawn(run, c, Vector2i(3, 3)), OK)


func test_retreat_cancels_drops_and_lasts_2400_ticks() -> void:
	var released: Array[int] = []
	sys.grab_release = func(_c: Creature, miner: int) -> void: released.append(miner)
	assert_true(sys.gate.request_commit(run, c, 77, true))
	var w: CreatureWindUp = sys.begin_wind_up(run, c, 0, 77, 0.6, func(_r: RunState) -> bool: return true)
	c.grabbing = 77
	sys.begin_retreat(run, c, "revolver")
	assert_eq(w.outcome, CreatureWindUp.Outcome.CANCELLED, "the wind-up cancels")
	assert_eq(released, [77] as Array[int], "RSC-03 releases the miner")
	assert_eq(c.grabbing, 0)
	assert_false(sys.gate.is_hunting(c), "the hunt stands down")
	assert_eq(c.retreat_until - run.tick, 2400, "120 s")
	assert_true(c.is_retreating())
	run.tick += 2399
	sys.tick(run)
	assert_true(c.is_retreating())
	run.tick += 1
	sys.tick(run)
	assert_false(c.is_retreating(), "over after 2,400 ticks")
	assert_eq(c.retreats_ended, [false] as Array[bool])


func test_a_retreat_ending_in_the_apex_turns_toward_base() -> void:
	sys.gate.apex_on = func() -> bool: return true
	sys.begin_retreat(run, c, "flare")
	run.tick += 2400
	sys.tick(run)
	assert_eq(c.retreats_ended, [true] as Array[bool])


func test_hits() -> void:
	assert_true(sys.on_hit(run, c.entity_id, false), "a hit under the threshold")
	assert_eq(c.flinches, 1, "flinches")
	assert_false(c.is_retreating(), "and cancels nothing")
	c.enter(run, &"buried")
	assert_false(sys.on_hit(run, c.entity_id, true), "nothing of it can be hit now")
	assert_eq(c.hit_body(), 0.0)
	c.enter(run, &"idle")
	assert_true(sys.on_hit(run, c.entity_id, true))
	assert_true(c.is_retreating(), "over the threshold it retreats")
	var e: SimEntity = run.registry.get_entity(c.entity_id)
	assert_eq(sys.body_radius_of(e), c.body_radius, "NET-06's trace uses its hit body")
