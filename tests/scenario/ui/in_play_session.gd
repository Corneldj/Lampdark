extends RefCounted
## UI-01's scripted M1 session on the grey box: two miners from base camp, Ann's lamp lit in hand, a
## spanner by her, Bob beside her; she checks her lamp, walks to a chamber, where her lamp goes out
## and she feels about in the black, and walks back.
## Every tick her client's in-play layer is updated from her own connection, as ClientMain does.

const Scenario = preload("res://tests/scenario/kit/scenario.gd")
const MinerHandle = preload("res://tests/scenario/kit/miner_handle.gd")
const B = preload("res://tests/unit/mnr/belt_world.gd")
const L = preload("res://tests/unit/mnr/lamp_world.gd")
const F = preload("res://tests/unit/vis/feel_world.gd")

const MAP: String = "m1_greybox"


class Session:
	extends RefCounted
	var s: Scenario
	var ann: MinerHandle
	var bob: MinerHandle
	var layer: InPlayLayer
	var router: InputRouter = InputRouter.new()
	var overlay: CanvasLayer
	var check_until: int = -1
	## Per frame: [violations, glyph target, the view's records within touch range].
	var frames: Array[Dictionary] = []
	var shown: Dictionary = {}

	func tick(_sc: Scenario) -> void:
		var v: ReceivedView = ann.connection.view
		if v == null or v.own.is_empty():
			return
		router.record.holds = InputRecord.HOLD_CHECK_LAMP if s.run.tick < check_until else 0
		var own: Vector2 = v.own.get("position", Vector2.ZERO)
		layer.update({"view": v, "view_origin": own - Vector2(15, 8.4375), "black": false, "inventory": ann.connection.inventory,
			"feel": ann.connection.feel, "router": router, "store": router.store, "wheel_anchor": Vector2(960, 540),
			"short_side": 1080.0, "now_s": s.run.tick / Tuning.f(&"net.tick_hz")})
		var near: Array[Dictionary] = []
		for raw: Variant in v.entities.keys():
			var e: Dictionary = v.entities[raw]
			var at: Vector2 = e.get("position", Vector2.ZERO)
			if at.distance_to(own) <= Tuning.f(&"vision.touch_range_tiles") + 1e-6:
				near.append({"token": raw, "level": e.get("level", 0)})
		frames.append({"violations": layer.check_frame([overlay]), "target": layer.target.duplicate(), "near": near,
			"view": v})
		for n: Node in layer.get_children():
			var item: CanvasItem = n as CanvasItem
			if item.visible:
				shown[ScreenElementRegistry.type_of(n)] = true


static func run(test: GutTest, seed_value: int) -> Session:
	var x: Session = Session.new()
	var make: Callable = Callable(test, "make")
	x.s = make.call({"seed": seed_value, "fixture": MAP})
	var inside: Array = Basecamp.inside_tiles(FixedMapLoader.run_seed(FixedMapLoader.manifest(MAP)),
		FixedMapLoader.blind_side(FixedMapLoader.manifest(MAP))).keys()
	inside.sort()
	var start: Vector2i = Vector2i.ZERO
	for raw: Variant in inside:
		var t: Vector2i = raw
		if x.s.mine.native.is_walkable(t) and x.s.mine.native.is_walkable(t + Vector2i(1, 0)) and x.s.mine.native.is_walkable(t + Vector2i(0, 1)):
			start = t
			break
	x.ann = x.s.add_miner("ann", start)
	x.bob = x.s.add_miner("bob", start + Vector2i(1, 0))
	x.layer = InPlayLayer.new()
	test.add_child_autofree(x.layer)
	var wv: WorldView = WorldView.new()
	test.add_child_autofree(wv)
	x.overlay = wv.overlay_layer()
	x.s.step(3)
	var lamp: GauzeLamp = L.lit_in_hand(x.s, x.ann)
	B.put(x.s, ItemKinds.Kind.SPANNER, start + Vector2i(0, 1))
	x.s.on_tick = x.tick
	x.s.step(20)
	x.check_until = x.s.run.tick + 30
	x.ann.at(x.s.run.tick).hold(InputRecord.HOLD_CHECK_LAMP, 30)
	x.s.step(40)
	var targets: Array[Vector2i] = M1GreyboxCheck.walk_targets(x.s.mine, MAP)
	for goal: Vector2i in [targets[0], start]:
		if goal == start:
			# In the far chamber her lamp goes out: she feels about in the black, then walks home dark.
			x.s.run.lamps.snuff(x.s.run, lamp, "test")
			x.s.step(5)
			F.feel(x.s, x.ann)
		x.ann.at(x.s.run.tick).walk_to(goal)
		x.s.run_until(func(sc: Scenario) -> bool:
			var at: Vector2 = sc.state.miner(x.ann)["position"]
			return Vector2i(at.floor()) == goal, 1500)
	x.s.step(10)
	return x
