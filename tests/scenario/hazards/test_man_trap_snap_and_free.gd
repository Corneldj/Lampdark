extends "res://tests/scenario/kit/scenario_test.gd"
## HAZ-01 end to end, under NET-08's audit (Gameplay §8.2, §11.3): Bob walks into the jaws on a lit
## road. Ann, a few tiles off, hears the snap and his cry ('[iron jaws snapping]', '[a cry for help]');
## his own client is Caught and told he may struggle. Ann walks up and frees him through her ring's
## "Free", her lamp hooked; he walks off limping, the jaws sprung behind him. Nothing of the trap
## but its record lit to 0.30 reaches either client.

const T = preload("res://tests/unit/hazards/trap_world.gd")
const StreamAudit = preload("res://tools/stream_audit/stream_audit.gd")

## listener (a slot) -> the noise types its client was told of.
var heard: Dictionary = {}


func before_all() -> void:
	assert_true(Tuning.load_server())


func _hear(listener: int, record: Dictionary, _audit: Dictionary = {}) -> void:
	var types: Array = heard.get(listener, [])
	types.append(Variants.whole(record["type"]))
	heard[listener] = types


func _heard(h: MinerHandle, type: NoiseTypes.Type) -> bool:
	return Variants.array(heard.get(h.slot, [])).has(type)


func test_the_snap_the_cry_and_a_teammate_frees() -> void:
	var s: Scenario = make(T.cfg(4901))
	var audit: StreamAudit = StreamAudit.new()
	audit.attach(s.run, s.net)
	T.light(s)
	var trap: int = s.run.man_traps.place(s.run, T.TRAP)
	heard.clear()
	s.run.noise.player_hooks.append(_hear)
	var bob: MinerHandle = T.miner_at(s, "bob", Vector2(T.TRAP) + Vector2(-2.5, 0.5))
	var ann: MinerHandle = T.miner_at(s, "ann", Vector2(T.TRAP) + Vector2(-6.5, 0.5))
	ann.at(0).face(0.0)
	s.step(4)
	bob.at(s.run.tick).move(0.0, InputRecord.Gait.WALK, 30)
	for _i: int in 60:
		s.step()
		if s.run.holds.caught_in(bob.entity_id) != null:
			break
	assert_not_null(s.run.holds.caught_in(bob.entity_id), "Bob walked into the jaws")
	s.step(4)
	assert_true(_heard(ann, NoiseTypes.Type.MANTRAP_SNAP), "Ann hears the snap")
	assert_true(_heard(ann, NoiseTypes.Type.TRAPPED_CRY), "and his cry")
	assert_eq(s.run.miner_state.life(bob.entity_id), MinerTransitions.Life.CAUGHT, "Caught")
	var status: Dictionary = OwnStatus.of(s.run, bob.entity_id)
	assert_ne(Variants.whole(status["flags"]) & StatusWire.TRAP_STRUGGLE, 0, "and his status says he may struggle")
	# Ann walks up beside him, facing him, and frees him.
	s.run.movement.place(s.run, ann.entity_id, Vector2(T.TRAP) + Vector2(-0.5, 0.5))
	ann.at(s.run.tick).face(0.0)
	s.step(3)
	T.L.lit_in_hand(s, ann)
	s.step(2)
	T.RW.tap(s, ann)
	var options: Array = Variants.array(ann.connection.ring.get("options", []))
	assert_true(options.has(ManTraps.FREE_OPTION), "her ring offers Free: %s" % [options])
	ann.at(s.run.tick).press(ActionRecord.Kind.RING_CHOICE, options.find(ManTraps.FREE_OPTION))
	s.step(3)
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 80)
	var started: int = T.started(s, ann.entity_id, ManTraps.FREE_VERB, 20)
	assert_gt(started, 0, "the free begins")
	s.step(70)
	assert_null(s.run.holds.caught_in(bob.entity_id), "freed")
	assert_eq(s.run.miner_state.life(bob.entity_id), MinerTransitions.Life.UPRIGHT)
	assert_ne(Variants.whole(OwnStatus.of(s.run, bob.entity_id)["flags"]) & StatusWire.TRAP_STRUGGLE, StatusWire.TRAP_STRUGGLE, "no more struggling")
	assert_false(s.run.man_traps.is_set(trap), "the jaws sprung behind him")
	for v: Dictionary in audit.violations.slice(0, 8):
		gut.p(str(v))
	assert_eq(audit.violation_count, 0, "NET-08: nothing sent either could not perceive")
