class_name SpeedModifiers
extends RefCounted
## One miner's slowdowns (MNR-01): factors that multiply, each set by an owner (HAZ-02's sump
## mud, MNR-13's carries), and one wound slot (Hurt or a trap wound, x0.8, never both). A
## modifier may override the step level (mud and carrying a body or a can: 12 np). Server-only.

var wound: bool = false
var wound_multiplier: float = 0.8
## owner -> [factor, step_np_override (0 for none)]
var _mods: Dictionary = {}


func _init() -> void:
	if Tuning.current.has_key(&"movement.wound_gait_multiplier"):
		wound_multiplier = Tuning.f(&"movement.wound_gait_multiplier")


func set_modifier(owner: StringName, multiplier: float, step_level_np: float = 0.0) -> void:
	_mods[owner] = [multiplier, step_level_np]


func clear(owner: StringName) -> void:
	_mods.erase(owner)


func set_wound(active: bool) -> void:
	wound = active


## Speed = gait speed x this.
func factor() -> float:
	var f: float = wound_multiplier if wound else 1.0
	var owners: Array = _mods.keys()
	owners.sort()
	for owner: Variant in owners:
		f *= float(Variants.number(Variants.array(_mods[owner])[0]))
	return f


## The loudest step-level override in force, or 0.
func step_np_override() -> float:
	var best: float = 0.0
	for raw: Variant in _mods.values():
		best = maxf(best, float(Variants.number(Variants.array(raw)[1])))
	return best


func write_state(writer: SimStateWriter) -> void:
	writer.put_bool(wound)
	var owners: Array = _mods.keys()
	owners.sort()
	writer.put_i64(owners.size())
	for owner: Variant in owners:
		var m: Array = Variants.array(_mods[owner])
		writer.put_string(str(owner))
		writer.put_f64(float(Variants.number(m[0])))
		writer.put_f64(float(Variants.number(m[1])))
