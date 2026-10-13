class_name TuningSchema
## Validation rules for tuning entries (FND-05).
##
## An entry is a Dictionary with the fields below. validate_entry() returns a list of error
## strings, empty when the entry is valid.

const DOMAINS: Array[String] = [
	"camera", "light", "vision", "movement", "noise", "voice", "phones", "items", "lamp",
	"revolver", "basecamp", "lift", "moth", "tapper", "stythe", "creatures", "traps",
	"hazards", "marks", "director", "pull", "depth", "rescue", "modes", "hands", "bess",
	"mine", "net", "ui",
]

const TYPES: Array[String] = [
	"int", "float", "bool", "string", "enum", "int_list", "float_list", "string_list",
	"range", "by_ring", "by_crew", "table",
]
const VISIBILITIES: Array[String] = ["server", "client"]
const KINDS: Array[String] = ["param", "target", "fixed"]
const REQUIRED: Array[String] = ["value", "type", "unit", "source", "starting", "visibility", "kind"]
const OPTIONAL: Array[String] = ["min", "max", "exclusive_min", "exclusive_max", "options", "note"]
## Types whose value is 5 numbers, one per ring (0-4) or per crew count (1-5).
const FIVE: Array[String] = ["by_ring", "by_crew"]

## Bounds every key of a family must meet, whatever its own entry says (CRT-01: a wind-up
## lasts 0.4 s or more; a tell reaches beyond 6 tiles). pattern -> bound fields.
const FAMILY_BOUNDS: Dictionary = {
	"^[a-z]+\\.([a-z0-9_]+_)?windup_s$": {"min": 0.4},
	"^[a-z]+\\.([a-z0-9_]+_)?tell_reach_tiles$": {"exclusive_min": 6},
}

## DIR-04: creatures grow keener with depth, never faster, longer-armed or quicker to strike, so
## no key naming one of these may vary by ring.
const DEPTH_FIXED_WORDS: Array[String] = ["speed", "reach", "tell", "windup"]

const KEY_PATTERN: String = "^[a-z]+\\.[a-z0-9_]+$"
const SOURCE_PATTERN: String = "^(Gameplay §|GDD §|Proposed)"


static func validate_entry(key: String, entry: Dictionary, units: Array[String]) -> Array[String]:
	var errors: Array[String] = []
	if RegEx.create_from_string(KEY_PATTERN).search(key) == null:
		errors.append("%s: key must be <domain>.<snake_case>" % key)
	if not key.get_slice(".", 0) in DOMAINS:
		errors.append("%s: unknown domain '%s'" % [key, key.get_slice(".", 0)])
	for field: String in REQUIRED:
		if not entry.has(field):
			errors.append("%s: missing field '%s'" % [key, field])
	for field: Variant in entry.keys():
		if not (str(field) in REQUIRED or str(field) in OPTIONAL):
			errors.append("%s: unknown field '%s'" % [key, field])
	if not errors.is_empty():
		return errors

	var type_name: String = str(entry["type"])
	if not type_name in TYPES:
		errors.append("%s: unknown type '%s'" % [key, type_name])
		return errors
	if not entry["unit"] is String or not str(entry["unit"]) in units:
		errors.append("%s: unknown unit '%s'" % [key, entry["unit"]])
	if not entry["source"] is String or RegEx.create_from_string(SOURCE_PATTERN).search(str(entry["source"])) == null:
		errors.append("%s: source must start with 'Gameplay §', 'GDD §' or 'Proposed'" % key)
	if not entry["starting"] is bool:
		errors.append("%s: 'starting' must be true or false" % key)
	if not str(entry["visibility"]) in VISIBILITIES:
		errors.append("%s: visibility must be server or client" % key)
	if not str(entry["kind"]) in KINDS:
		errors.append("%s: kind must be param, target or fixed" % key)
	if key.ends_with("_by_ring"):
		if type_name != "by_ring":
			errors.append("%s: a _by_ring key must be of type by_ring (5 values, rings 0-4)" % key)
		for word: String in key.get_slice(".", 1).split("_"):
			if word in DEPTH_FIXED_WORDS:
				errors.append("%s: a %s never varies with depth (DIR-04)" % [key, word])
	errors.append_array(validate_value(key, type_name, entry["value"], with_family_bounds(key, entry)))
	return errors


## The entry's own bounds plus any family bound its key falls under; the stricter wins.
static func with_family_bounds(key: String, entry: Dictionary) -> Dictionary:
	var out: Dictionary = entry
	for pattern: String in FAMILY_BOUNDS.keys():
		if RegEx.create_from_string(pattern).search(key) == null:
			continue
		out = entry.duplicate()
		var bounds: Dictionary = FAMILY_BOUNDS[pattern]
		for field: String in bounds.keys():
			var floor_value: float = Variants.number(bounds[field])
			if not out.has(field) or Variants.number(out[field]) < floor_value:
				out[field] = floor_value
	return out


## Checks a value against its type and the entry's bounds and options.
static func validate_value(key: String, type_name: String, value: Variant, entry: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	match type_name:
		"int":
			if not _is_integral(value):
				errors.append("%s: int value must be a whole number, got %s" % [key, value])
		"float":
			if not _is_number(value):
				errors.append("%s: float value must be a number, got %s" % [key, value])
		"bool":
			if not value is bool:
				errors.append("%s: bool value must be true or false" % key)
		"string":
			if not value is String:
				errors.append("%s: string value must be text" % key)
		"enum":
			var options: Variant = entry.get("options")
			if not options is Array or Variants.array(options).is_empty():
				errors.append("%s: enum needs a non-empty 'options' list" % key)
			elif not value in Variants.array(options):
				errors.append("%s: enum value '%s' is not one of %s" % [key, value, options])
		"int_list", "float_list", "by_ring", "by_crew":
			if not value is Array:
				errors.append("%s: %s value must be a list" % [key, type_name])
			else:
				var items: Array = value
				for item: Variant in items:
					if (type_name == "int_list" and not _is_integral(item)) or not _is_number(item):
						errors.append("%s: %s holds a non-%s item %s" % [key, type_name,
							"integer" if type_name == "int_list" else "number", item])
						break
				if type_name in FIVE and items.size() != 5:
					errors.append("%s: %s needs exactly 5 values, got %d" % [key, type_name, items.size()])
		"string_list":
			if not value is Array:
				errors.append("%s: string_list value must be a list" % key)
			else:
				for item: Variant in Variants.array(value):
					if not item is String:
						errors.append("%s: string_list holds a non-text item" % key)
						break
		"range":
			if not value is Array or Variants.array(value).size() != 2 \
					or not _is_number(Variants.array(value)[0]) or not _is_number(Variants.array(value)[1]):
				errors.append("%s: range value must be [min, max]" % key)
			else:
				var low: float = Variants.array(value)[0]
				var high: float = Variants.array(value)[1]
				if low > high:
					errors.append("%s: range min %s is above max %s" % [key, low, high])
		"table":
			if not value is Dictionary or Variants.dict(value).is_empty():
				errors.append("%s: table value must be a non-empty object of name -> number" % key)
			else:
				for name: Variant in Variants.dict(value).keys():
					if not _is_number(Variants.dict(value)[name]):
						errors.append("%s: table entry '%s' is not a number" % [key, name])
						break
	if errors.is_empty():
		errors.append_array(_check_bounds(key, type_name, value, entry))
	return errors


static func _check_bounds(key: String, type_name: String, value: Variant, entry: Dictionary) -> Array[String]:
	var numbers: Array[float] = []
	match type_name:
		"int", "float":
			numbers.append(float(str(value)))
		"int_list", "float_list", "by_ring", "by_crew", "range":
			for item: Variant in Variants.array(value):
				numbers.append(float(str(item)))
		"table":
			for item: Variant in Variants.dict(value).values():
				numbers.append(float(str(item)))
		_:
			return []
	var errors: Array[String] = []
	for number: float in numbers:
		if entry.has("min") and number < float(str(entry["min"])):
			errors.append("%s: %s is below min %s" % [key, number, entry["min"]])
		if entry.has("max") and number > float(str(entry["max"])):
			errors.append("%s: %s is above max %s" % [key, number, entry["max"]])
		if entry.has("exclusive_min") and number <= float(str(entry["exclusive_min"])):
			errors.append("%s: %s must be greater than %s" % [key, number, entry["exclusive_min"]])
		if entry.has("exclusive_max") and number >= float(str(entry["exclusive_max"])):
			errors.append("%s: %s must be less than %s" % [key, number, entry["exclusive_max"]])
	return errors


static func _is_number(value: Variant) -> bool:
	return (value is float or value is int) and not value is bool


static func _is_integral(value: Variant) -> bool:
	if value is int:
		return true
	if value is float:
		var number: float = value
		return is_finite(number) and number == floorf(number)
	return false
