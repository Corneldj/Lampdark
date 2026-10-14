class_name Variants
## Typed views of Variant values, for code that reads parsed JSON under the strict warnings.
## Each returns an empty value of its type when the input is something else.


static func dict(value: Variant) -> Dictionary:
	if value is Dictionary:
		return value
	return {}


static func array(value: Variant) -> Array:
	if value is Array:
		return value
	return []


static func text(value: Variant) -> String:
	return str(value) if value != null else ""


static func number(value: Variant) -> float:
	if value is float or value is int:
		return float(str(value))
	return 0.0


## An exact integer: an int as it is (64-bit IDs survive, which number()'s double does not), a float
## truncated, a numeric string parsed; anything else 0. STM-01 and STM-02 read SteamIDs and lobby IDs
## through it.
static func whole(value: Variant) -> int:
	if value is int:
		var i: int = value
		return i
	if value is float:
		var f: float = value
		return int(f)
	if value is String or value is StringName:
		return str(value).to_int()
	return 0


## True only for a real `true` (JSON booleans); anything else is false.
static func flag(value: Variant) -> bool:
	if value is bool:
		var as_bool: bool = value
		return as_bool
	return false


## A plain Array from an Array or a packed array of strings or ints; [] otherwise.
static func list(value: Variant) -> Array:
	if value is Array:
		return value
	if value is PackedStringArray:
		var strings: PackedStringArray = value
		return Array(strings)
	if value is PackedInt32Array:
		var ints: PackedInt32Array = value
		return Array(ints)
	if value is PackedInt64Array:
		var longs: PackedInt64Array = value
		return Array(longs)
	return []
