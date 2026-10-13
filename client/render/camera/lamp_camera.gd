class_name LampCamera
extends Camera2D
## VIS-01 (Gameplay §5.1): the one camera. Orthographic, straight down and north-up: rotation is
## always 0 and the zoom never changes (nothing zooms, rotates or frees it). It follows the predicted
## own miner with a lead toward the facing that eases through a critically damped spring
## (camera.lead_settle_s): camera.lead_tiles normally, camera.squint_lead_tiles while squinting or
## aiming the drawn revolver. Facing itself is instant, so the cone (drawn from the miner) never
## lags. Squinting moves only the view: never the cone, the listener (on the miner, SND-04) or
## anything sent (VIS-03 sends to the full-squint view always). States: coming round, centred on the
## body with no lead; a close-up, held still. Shake obeys the screen-shake option. Canvas units are
## pixels at 1080p (camera.tile_px_at_1080p a tile); the project's stretch fits them to the window.

enum State { MINE = 0, COMING_ROUND = 1, CLOSE_UP = 2 }

## The screen-shake option (UI-06 sets it); off, shake moves the camera by exactly zero.
var shake_enabled: bool = true
var state: State = State.MINE
## The eased lead (tiles) and its velocity.
var lead: Vector2 = Vector2.ZERO
var lead_velocity: Vector2 = Vector2.ZERO
var _shake_amp: float = 0.0
var _shake_left: float = 0.0
var _shake_total: float = 0.0
var _shake_t: float = 0.0


func _init() -> void:
	ignore_rotation = true
	rotation = 0.0
	zoom = Vector2.ONE


## The lead the camera eases toward now (tiles).
static func lead_target(facing: int, squint_or_aim: bool, camera_state: State) -> Vector2:
	if camera_state == State.COMING_ROUND:
		return Vector2.ZERO
	var tiles: float = Tuning.f(&"camera.squint_lead_tiles") if squint_or_aim else Tuning.f(&"camera.lead_tiles")
	return ViewGeometry.facing_vector(facing) * tiles


## One frame: the predicted own miner (tiles), its facing, whether the squint (or the aim, with the
## revolver drawn) is on (MNR-15's held bits, hold or toggle already applied), and `dt`.
func follow(miner_pos: Vector2, facing: int, squint_or_aim: bool, dt: float) -> void:
	rotation = 0.0
	zoom = Vector2.ONE
	if state == State.CLOSE_UP:
		return
	var target: Vector2 = lead_target(facing, squint_or_aim, state)
	# A critically damped spring: about 98% settled after camera.lead_settle_s.
	var omega: float = 4.0 / maxf(Tuning.f(&"camera.lead_settle_s"), 1e-3)
	var x: Vector2 = lead - target
	var e: float = exp(-omega * dt)
	var temp: Vector2 = (lead_velocity + x * omega) * dt
	lead_velocity = (lead_velocity - temp * omega) * e
	lead = target + (x + temp) * e
	if state == State.COMING_ROUND:
		lead = Vector2.ZERO
		lead_velocity = Vector2.ZERO
	var tile_px: float = Tuning.f(&"camera.tile_px_at_1080p")
	position = (miner_pos + lead) * tile_px
	offset = _shake_offset(dt) * tile_px


## The view now (tiles), from the same shared geometry as the server's detail region.
func view_rect(miner_pos: Vector2) -> Rect2:
	var size: Vector2 = ViewGeometry.view_size()
	return Rect2(miner_pos + lead - size / 2.0, size)


## Snaps the drawn position to whole screen pixels at `screen_scale` (screen px per canvas px).
func snapped_position(screen_scale: float) -> Vector2:
	return (position * screen_scale).round() / screen_scale


## A shake request (a blast, a roof fall, the own shot: their owners call it). Capped at
## camera.shake_max_tiles; nothing at all while the option is off.
func add_shake(amplitude_tiles: float, duration_s: float) -> void:
	if not shake_enabled or duration_s <= 0.0:
		return
	_shake_amp = maxf(_shake_amp, minf(amplitude_tiles, Tuning.f(&"camera.shake_max_tiles")))
	_shake_left = maxf(_shake_left, duration_s)
	_shake_total = maxf(_shake_total, duration_s)


func _shake_offset(dt: float) -> Vector2:
	if not shake_enabled or _shake_left <= 0.0:
		_shake_left = 0.0
		_shake_amp = 0.0
		return Vector2.ZERO
	_shake_left = maxf(0.0, _shake_left - dt)
	_shake_t += dt
	var fade: float = _shake_left / maxf(_shake_total, 1e-6)
	return Vector2(sin(_shake_t * 47.0), cos(_shake_t * 53.0)) * _shake_amp * fade
