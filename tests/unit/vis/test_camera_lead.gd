extends GutTest
## VIS-01: the lead settles at 3.0 tiles toward facing, at 8.0 while the squint is held or toggled on
## and while aiming the drawn revolver, each within 0.5 s; facing turns at once, only the lead eases;
## coming round centres on the body; a close-up holds still; shake obeys the option and its cap.

const F = preload("res://tests/unit/mnr/input_frames.gd")
const DT: float = 1.0 / 60.0


func before_all() -> void:
	assert_true(Tuning.load_server())


func _run(cam: LampCamera, facing: int, squint: bool, seconds: float, at: Vector2 = Vector2(10, 10)) -> void:
	var t: float = 0.0
	while t < seconds - 1e-9:
		cam.follow(at, facing, squint, DT)
		t += DT


func test_settles_at_three_then_eight() -> void:
	var cam: LampCamera = LampCamera.new()
	var east: int = Intents.facing_u16(0.0)
	_run(cam, east, false, 0.5)
	assert_almost_eq(cam.lead.length(), 3.0, 0.02, "3 tiles within 0.5 s")
	assert_almost_eq(cam.lead.x, 3.0, 0.02, "toward the facing")
	_run(cam, east, true, 0.5)
	assert_almost_eq(cam.lead.length(), 8.0, 0.02, "8 tiles within 0.5 s of squinting")
	_run(cam, east, false, 0.5)
	assert_almost_eq(cam.lead.length(), 3.0, 0.02, "and back")
	var south: int = Intents.facing_u16(90.0)
	_run(cam, south, false, 0.5)
	assert_almost_eq(cam.lead.y, 3.0, 0.02, "follows the facing")
	cam.free()


func test_squint_hold_toggle_and_aim_through_the_router() -> void:
	# The camera reads MNR-15's held bits: the squint held, the squint toggled on, the drawn revolver aimed.
	var cases: Array = [["hold", false, false], ["toggle", true, false], ["aim", false, true]]
	for raw: Variant in cases:
		var c: Array = raw
		var store: BindingsStore = BindingsStore.new()
		store.set_toggle("squint", Variants.flag(c[1]))
		var r: InputRouter = F.router("kbm", store)
		r.revolver_drawn = Variants.flag(c[2])
		var cam: LampCamera = LampCamera.new()
		var t: float = 0.0
		var lead_at_half: float = 0.0
		while t < 1.0:
			var down: Dictionary = {"squint": true} if (not Variants.flag(c[1]) or t < DT) else {}
			r.sample(F.frame(t, down, {"cursor": Vector2(100, 0), "own_screen": Vector2.ZERO}))
			var on: bool = (r.record.holds & (InputRecord.HOLD_SQUINT | InputRecord.HOLD_AIM)) != 0
			cam.follow(Vector2(5, 5), r.record.facing, on, DT)
			t += DT
			if absf(t - 0.5) < DT / 2.0:
				lead_at_half = cam.lead.length()
		assert_almost_eq(lead_at_half, 8.0, 0.03, "%s: 8 tiles within 0.5 s" % c[0])
		if Variants.flag(c[2]):
			assert_ne(r.record.holds & InputRecord.HOLD_AIM, 0, "aiming, not squinting")
		cam.free()


func test_facing_is_instant_only_the_lead_eases() -> void:
	var cam: LampCamera = LampCamera.new()
	_run(cam, Intents.facing_u16(0.0), false, 1.0)
	var r: InputRouter = F.router()
	r.sample(F.frame(0.0, {}, {"cursor": Vector2(-100, 0), "own_screen": Vector2.ZERO}))
	assert_almost_eq(r.record.facing / 65536.0 * 360.0, 180.0, 0.01, "facing turned in one frame")
	cam.follow(Vector2(10, 10), r.record.facing, false, DT)
	assert_gt(cam.lead.x, 2.0, "the lead is still swinging round")
	cam.free()


func test_states() -> void:
	var cam: LampCamera = LampCamera.new()
	_run(cam, 0, true, 1.0)
	cam.state = LampCamera.State.COMING_ROUND
	cam.follow(Vector2(4, 4), 0, true, DT)
	assert_eq(cam.lead, Vector2.ZERO, "coming round: centred on the body")
	assert_eq(cam.position, Vector2(4, 4) * 64.0)
	cam.state = LampCamera.State.CLOSE_UP
	var held: Vector2 = cam.position
	_run(cam, 16384, true, 0.5, Vector2(30, 30))
	assert_eq(cam.position, held, "a close-up holds still")
	cam.free()


func test_shake_obeys_the_option_and_the_cap() -> void:
	var off: LampCamera = LampCamera.new()
	off.shake_enabled = false
	off.add_shake(1.0, 1.0)
	for _i: int in 30:
		off.follow(Vector2(1, 1), 0, false, DT)
		assert_eq(off.offset, Vector2.ZERO, "option off: exactly zero")
	off.free()
	var on: LampCamera = LampCamera.new()
	on.add_shake(5.0, 0.5)
	var biggest: float = 0.0
	for _i: int in 60:
		on.follow(Vector2(1, 1), 0, false, DT)
		biggest = maxf(biggest, on.offset.length() / 64.0)
	assert_gt(biggest, 0.0, "it shakes")
	assert_lte(biggest, Tuning.f(&"camera.shake_max_tiles") * sqrt(2.0) + 1e-6, "capped")
	assert_eq(on.offset, Vector2.ZERO, "and it ends")
	on.free()


func test_pixel_snap() -> void:
	var cam: LampCamera = LampCamera.new()
	cam.position = Vector2(100.37, 55.81)
	var scale: float = 42.6667 / 64.0
	var p: Vector2 = cam.snapped_position(scale)
	assert_almost_eq(p.x * scale, roundf(p.x * scale), 1e-4, "whole screen pixels (float32)")
	assert_almost_eq(p.y * scale, roundf(p.y * scale), 1e-4)
	cam.free()
