class_name WheelInput
extends RefCounted
## MNR-15: the generic wheel (Gameplay §4.8, §6.7): it opens on its button, the mouse or the right
## stick picks, and releasing picks or, centred, cancels. The pick is reported as an angle and a
## distance (the mouse's distance over the wheel's radius, or the stick's deflection, 1.0 at the
## edge); SND-11's voice.wheel_ring_bounds turn the distance into a band, and its first bound is the
## centre that cancels. Facing is held while a wheel is open (InputRouter's WHEEL context).

## The action whose button opened it, and the ActionRecord kind its pick sends.
var button: String = ""
var kind: int = 0
var opened_at: float = 0.0
## The job page (Now!, Left!, Right!, Stop!) in place of the callout wheel (carrying two-handed or
## at a two-person job); the slices are SND-11's, the switch is this flag.
var job_page: bool = false
## One button opens both lamp signals and chalk (the pad's Y): which slices are chalk is MNR-10's.
var combined: bool = false
## With the callout timing option the wheel opens on the press itself (InputRouter).
var timing: bool = false
var vec: Vector2 = Vector2.ZERO


func open(by: String, record_kind: int, now: float, is_job_page: bool = false) -> void:
	button = by
	kind = record_kind
	opened_at = now
	job_page = is_job_page
	combined = false
	timing = false
	vec = Vector2.ZERO


## The current pick: a mouse offset over the wheel's radius, or a stick (both 1.0 at the edge).
func update(pick_vec: Vector2) -> void:
	vec = pick_vec.limit_length(1.0)


func centred() -> bool:
	return vec.length() < cancel_radius()


## {angle_deg (clockwise from east, screen space), distance (0-1)}, or {} when centred.
func pick() -> Dictionary:
	if centred():
		return {}
	return {"angle_deg": fposmod(rad_to_deg(vec.angle()), 360.0), "distance": vec.length()}


static func cancel_radius() -> float:
	return Tuning.current.list_f(&"voice.wheel_ring_bounds")[0]


## Which of `count` equal slices an angle falls in, slice 0 centred straight up, going clockwise.
static func slice(angle_deg: float, count: int) -> int:
	if count <= 0:
		return -1
	var width: float = 360.0 / count
	return floori(fposmod(angle_deg + 90.0 + width / 2.0, 360.0) / width) % count
