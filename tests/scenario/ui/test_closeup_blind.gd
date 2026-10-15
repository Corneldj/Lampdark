extends "res://tests/scenario/kit/scenario_test.gd"
## UI-02 (Proposed): while a close-up is open its reader's seen set is empty: their client holds no
## lit tile and no entity, so nothing of the mine reaches anyone watching them (NET-07's delayed
## view, RSC-04's stream). It returns within one round trip of closing.

const W = preload("res://tests/scenario/ui/closeup_world.gd")
const RTT_MS: int = 120


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_the_reader_sees_nothing_and_sees_again_within_a_round_trip() -> void:
	var s: Scenario = W.camp(241, self)
	var deck: Vector2i = Basecamp.fixture(W.C.SEED, "cage_deck", s.run.base_camp.side)[0]["position"]
	var ann: MinerHandle = s.add_miner("ann", deck)
	s.add_miner("bob", deck + Vector2i(1, 0))
	ann.link(RTT_MS, 0.0)
	s.run.light.grid.add_point("gauze_lamp", 1, ann.entity_id, 0, 5.5, 1.0, Vector2(deck) + Vector2(0.5, 0.5), 0)
	var by_tick: Dictionary = {}
	s.client(ann).on_decoded = func(d: FrameDecoder.Decoded) -> void: by_tick[s.run.tick] = d.view
	s.step(20)
	var before: ReceivedView = s.client(ann).records_at(s.run.tick)
	assert_gt(before.tiles.size(), 0, "the reader sees base camp before")
	assert_gt(before.entities.size(), 0, "and Bob beside them")
	W.ask(s, ann, CloseupKind.Ask.OPEN_POCKET_BOOK)
	s.step(15)
	assert_eq(W.kind_of(s, ann), CloseupKind.Kind.POCKET_BOOK)
	s.step(40)
	var during: ReceivedView = s.client(ann).records_at(s.run.tick)
	assert_eq(during.tiles.size(), 0, "no lit tile while reading")
	assert_eq(during.entities.size(), 0, "no entity while reading")
	s.step(300)
	# What a watcher would be given of the reader's screen 8 s ago, mid close-up: nothing of the mine.
	var watched: Dictionary = RecordReaders.delayed_view(s.run.record, ann.slot, 8.0)
	assert_false(watched.is_empty())
	if not watched.is_empty():
		var v: ReceivedView = watched["view"]
		assert_eq(v.tiles.size() + v.entities.size(), 0, "the watch stream holds nothing while they read")
	W.ask(s, ann, CloseupKind.Ask.CLOSE)
	s.step(15)
	var shut: Array = s.run.closeups.history.filter(func(e: Dictionary) -> bool: return not Variants.flag(e["open"]))
	assert_eq(shut.size(), 1)
	var closed_at: int = int(Variants.number(Variants.dict(shut[0])["tick"]))
	var back: int = -1
	var ticks: Array = by_tick.keys()
	ticks.sort()
	for raw: Variant in ticks:
		var t: int = raw
		var view: ReceivedView = by_tick[t]
		if t > closed_at and not view.tiles.is_empty():
			back = t
			break
	assert_gt(back, closed_at, "the seen set came back")
	var round_trip_ticks: int = ceili(RTT_MS / (1000.0 / Tuning.f(&"net.tick_hz")))
	gut.p("closed at tick %d; tiles back on the client at tick %d (a round trip is %d ticks)" % [closed_at, back, round_trip_ticks])
	assert_lte(back - closed_at, round_trip_ticks, "within one round trip of closing")
