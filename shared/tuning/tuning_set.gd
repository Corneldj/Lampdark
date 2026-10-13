class_name TuningSet
extends RefCounted
## A validated set of tuning entries with layering (FND-05).
##
## Layers, lowest first: "base" (the domain files), "profile" (a test profile), "bundle"
## (NET-14's server data bundle) and "dev" (user://tuning_overrides.json and FND-08's
## console). An overlay may change values only: never add a key, nor change its type,
## unit or visibility. Each value records the layer it came from.
##
## A set loaded from the client table (_client.json) holds client keys only, so asking it
## for a server-only key is an error like any unknown key.

const DATA_DIR: String = "res://data/tuning"
const CLIENT_TABLE: String = "res://data/tuning/_client.json"
const PROFILES_DIR: String = "res://data/tuning/profiles"
const LAYERS: Array[String] = ["base", "profile", "bundle", "dev"]
## Fields an overlay entry may carry. Anything but "value" must match the base entry.
const OVERLAY_FIELDS: Array[String] = [
	"value", "type", "unit", "visibility", "source", "starting", "kind", "min", "max", "exclusive_min", "exclusive_max", "options", "note",
]
const LOCKED_FIELDS: Array[String] = ["type", "unit", "visibility"]
const TICK_KEY: String = "net.tick_hz"

## key -> entry Dictionary, values already converted to their declared type.
var entries: Dictionary = {}
## key -> the layer its effective value came from.
var layer_of: Dictionary = {}
var units: Array[String] = []
## True for a set built from the client table.
var client_only: bool = false


#region Loading

## Reads every <domain>.json in dir (files starting with "_" are skipped) and the unit list.
## Returns the errors; an empty list means the set is valid. require_all demands a file for
## every domain; tests turn it off to load small fixtures.
func load_directory(dir: String, require_all: bool = true) -> Array[String]:
	var errors: Array[String] = []
	units = read_units(dir.path_join("_units.json"), errors)
	var files: PackedStringArray = DirAccess.get_files_at(dir)
	var found: Dictionary = {}
	for file: String in files:
		if file.get_extension() != "json" or file.begins_with("_"):
			continue
		var domain: String = file.get_basename()
		if not domain in TuningSchema.DOMAINS:
			errors.append("%s: no such domain" % file)
			continue
		found[domain] = true
		_read_domain(dir.path_join(file), domain, errors)
	if require_all:
		for domain: String in TuningSchema.DOMAINS:
			if not found.has(domain):
				errors.append("missing domain file %s.json" % domain)
	return errors


## Builds a set from the client table written by the export step (_client.json).
func load_client_table(path: String) -> Array[String]:
	var errors: Array[String] = []
	var parsed: Variant = read_json(path, errors)
	if not errors.is_empty():
		return errors
	if not parsed is Dictionary or not Variants.dict(parsed).get("keys") is Dictionary:
		return ["%s: expected an object with 'keys'" % path] as Array[String]
	client_only = true
	var client_file: Dictionary = parsed
	var keys: Dictionary = client_file["keys"]
	for key: Variant in keys.keys():
		var entry: Variant = keys[key]
		if not entry is Dictionary:
			errors.append("%s: entry is not an object" % key)
			continue
		var as_dict: Dictionary = entry
		if str(as_dict.get("visibility", "")) != "client":
			errors.append("%s: server-only key in the client table" % key)
			continue
		entries[str(key)] = convert_entry(as_dict)
		layer_of[str(key)] = "base"
	return errors


func _read_domain(path: String, domain: String, errors: Array[String]) -> void:
	var parsed: Variant = read_json(path, errors)
	if parsed == null:
		return
	if not parsed is Dictionary or not Variants.dict(parsed).get("keys") is Dictionary:
		errors.append("%s: expected an object with 'keys'" % path)
		return
	var file_dict: Dictionary = parsed
	var keys: Dictionary = file_dict["keys"]
	for raw_key: Variant in keys.keys():
		var key: String = str(raw_key)
		if entries.has(key):
			errors.append("%s: duplicate key (again in %s.json)" % [key, domain])
			continue
		if key.get_slice(".", 0) != domain:
			errors.append("%s: key prefix does not match file %s.json" % [key, domain])
			continue
		var raw_entry: Variant = keys[raw_key]
		if not raw_entry is Dictionary:
			errors.append("%s: entry is not an object" % key)
			continue
		var entry: Dictionary = raw_entry
		var entry_errors: Array[String] = TuningSchema.validate_entry(key, entry, units)
		if not entry_errors.is_empty():
			errors.append_array(entry_errors)
			continue
		entries[key] = convert_entry(entry)
		layer_of[key] = "base"


static func read_units(path: String, errors: Array[String]) -> Array[String]:
	var parsed: Variant = read_json(path, errors)
	var out: Array[String] = []
	if parsed is Dictionary and Variants.dict(parsed).get("units") is Array:
		for unit: Variant in Variants.array(Variants.dict(parsed)["units"]):
			out.append(str(unit))
	elif parsed != null:
		errors.append("%s: expected an object with a 'units' list" % path)
	return out


static func read_json(path: String, errors: Array[String]) -> Variant:
	if not FileAccess.file_exists(path):
		errors.append("%s: file not found" % path)
		return null
	var json: JSON = JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		errors.append("%s:%d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data


## Returns a copy of entry with its value converted to the declared type.
static func convert_entry(entry: Dictionary) -> Dictionary:
	var out: Dictionary = entry.duplicate(true)
	out["value"] = convert_value(str(entry.get("type", "")), entry.get("value"))
	return out


static func convert_value(type_name: String, value: Variant) -> Variant:
	match type_name:
		"int":
			return int(str(value).to_float()) if value is float else value
		"int_list":
			var ints: Array[int] = []
			for item: Variant in Variants.array(value):
				ints.append(int(str(item).to_float()))
			return ints
		"float_list", "by_ring", "by_crew", "range":
			var floats: Array[float] = []
			for item: Variant in Variants.array(value):
				floats.append(str(item).to_float())
			return floats
		"float":
			return str(value).to_float()
		"string_list":
			var strings: Array[String] = []
			for item: Variant in Variants.array(value):
				strings.append(str(item))
			return strings
	return value

#endregion

#region Layers

## Applies an overlay ({key: {"value": ...}} or full entries) at the given layer.
## The overlay applies in full or not at all. Returns the errors.
func apply_overlay(overlay: Dictionary, layer: String) -> Array[String]:
	var errors: Array[String] = []
	if not layer in LAYERS or layer == "base":
		return ["overlay layer must be one of profile, bundle, dev; got '%s'" % layer] as Array[String]
	var staged: Dictionary = {}
	for raw_key: Variant in overlay.keys():
		var key: String = str(raw_key)
		if not entries.has(key):
			errors.append("%s: overlay may not add a key" % key)
			continue
		var raw: Variant = overlay[raw_key]
		if not raw is Dictionary or not Variants.dict(raw).has("value"):
			errors.append("%s: overlay entry needs a 'value'" % key)
			continue
		var change: Dictionary = raw
		var base: Dictionary = entries[key]
		var bad_field: bool = false
		for field: Variant in change.keys():
			if not str(field) in OVERLAY_FIELDS:
				errors.append("%s: unknown overlay field '%s'" % [key, field])
				bad_field = true
			elif str(field) in LOCKED_FIELDS and str(change[field]) != str(base.get(field)):
				errors.append("%s: overlay may not change %s" % [key, field])
				bad_field = true
		if bad_field:
			continue
		var value_errors: Array[String] = TuningSchema.validate_value(key, str(base["type"]), change["value"],
			TuningSchema.with_family_bounds(key, base))
		if not value_errors.is_empty():
			errors.append_array(value_errors)
			continue
		staged[key] = convert_value(str(base["type"]), change["value"])
	if not errors.is_empty():
		return errors
	for key: Variant in staged.keys():
		Variants.dict(entries[key])["value"] = staged[key]
		layer_of[key] = layer
	return errors


## Reads every domain-named file in a profile folder as an overlay.
func apply_profile_directory(dir: String) -> Array[String]:
	var errors: Array[String] = []
	var overlay: Dictionary = {}
	for file: String in DirAccess.get_files_at(dir):
		if file.get_extension() != "json":
			continue
		var parsed: Variant = read_json(dir.path_join(file), errors)
		if parsed is Dictionary and Variants.dict(parsed).get("keys") is Dictionary:
			overlay.merge(Variants.dict(Variants.dict(parsed)["keys"]))
		elif parsed != null:
			errors.append("%s: expected an object with 'keys'" % file)
	if not errors.is_empty():
		return errors
	return apply_overlay(overlay, "profile")


func duplicate_set() -> TuningSet:
	var copy: TuningSet = TuningSet.new()
	copy.entries = entries.duplicate(true)
	copy.layer_of = layer_of.duplicate()
	copy.units = units.duplicate()
	copy.client_only = client_only
	return copy


## Keys whose effective values differ between this set and other.
func changed_keys(other: TuningSet) -> PackedStringArray:
	var changed: PackedStringArray = PackedStringArray()
	for key: Variant in entries.keys():
		if not other.entries.has(key) or \
				var_to_str(Variants.dict(entries[key])["value"]) != var_to_str(Variants.dict(other.entries[key])["value"]):
			changed.append(str(key))
	return changed

#endregion

#region Hash and export

## SHA-256 over the canonical effective table: sorted keys, each "key|type|value".
## visibility "" hashes every key; "client" hashes the client table only.
func content_hash(visibility: String = "") -> String:
	var keys: Array = entries.keys()
	keys.sort()
	var context: HashingContext = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	for key: Variant in keys:
		var entry: Dictionary = entries[key]
		if not visibility.is_empty() and str(entry["visibility"]) != visibility:
			continue
		var line: String = "%s|%s|%s\n" % [key, entry["type"], canonical_value(entry["value"])]
		context.update(line.to_utf8_buffer())
	return context.finish().hex_encode()


## A platform-independent text form of a value: numbers in shortest round-trip form,
## lists and tables with sorted names.
static func canonical_value(value: Variant) -> String:
	if value is float:
		var number: float = value
		if number == floorf(number) and absf(number) < 1e15:
			return str(int(number))
		return String.num(number, 15)
	if value is Array:
		var parts: PackedStringArray = PackedStringArray()
		for item: Variant in Variants.array(value):
			parts.append(canonical_value(item))
		return "[" + ",".join(parts) + "]"
	if value is Dictionary:
		var names: Array = Variants.dict(value).keys()
		names.sort()
		var parts: PackedStringArray = PackedStringArray()
		for name: Variant in names:
			parts.append("%s:%s" % [name, canonical_value(Variants.dict(value)[name])])
		return "{" + ",".join(parts) + "}"
	return str(value)


## The client table: client keys only, with the fields a client needs.
func client_table() -> Dictionary:
	var keys: Dictionary = {}
	var names: Array = entries.keys()
	names.sort()
	for key: Variant in names:
		var entry: Dictionary = entries[key]
		if str(entry["visibility"]) != "client":
			continue
		var out: Dictionary = {}
		for field: String in ["value", "type", "unit", "min", "max", "visibility", "kind", "options"]:
			if entry.has(field):
				out[field] = entry[field]
		keys[key] = out
	return {"hash": content_hash("client"), "keys": keys}

#endregion

#region Typed access

## Returns the entry for key, or an empty Dictionary after reporting an error.
func entry_for(key: StringName, type_names: Array[String]) -> Dictionary:
	if not entries.has(String(key)):
		if client_only:
			push_error("Tuning: '%s' is unknown or server-only; a client cannot read it" % key)
		else:
			push_error("Tuning: unknown key '%s'" % key)
		return {}
	var entry: Dictionary = entries[String(key)]
	if not str(entry["type"]) in type_names:
		push_error("Tuning: '%s' is %s, not %s" % [key, entry["type"], "/".join(PackedStringArray(type_names))])
		return {}
	return entry


func f(key: StringName) -> float:
	var entry: Dictionary = entry_for(key, ["float", "int"] as Array[String])
	return float(str(entry["value"])) if not entry.is_empty() else 0.0


func i(key: StringName) -> int:
	var entry: Dictionary = entry_for(key, ["int"] as Array[String])
	if entry.is_empty():
		return 0
	var value: int = entry["value"]
	return value


func b(key: StringName) -> bool:
	var entry: Dictionary = entry_for(key, ["bool"] as Array[String])
	if entry.is_empty():
		return false
	var value: bool = entry["value"]
	return value


func s(key: StringName) -> String:
	var entry: Dictionary = entry_for(key, ["string", "enum"] as Array[String])
	return str(entry["value"]) if not entry.is_empty() else ""


func list_f(key: StringName) -> Array[float]:
	var entry: Dictionary = entry_for(key, ["float_list", "by_ring", "by_crew", "range"] as Array[String])
	var out: Array[float] = []
	if not entry.is_empty():
		out.assign(Variants.array(entry["value"]))
	return out


func list_i(key: StringName) -> Array[int]:
	var entry: Dictionary = entry_for(key, ["int_list"] as Array[String])
	var out: Array[int] = []
	if not entry.is_empty():
		out.assign(Variants.array(entry["value"]))
	return out


func list_s(key: StringName) -> Array[String]:
	var entry: Dictionary = entry_for(key, ["string_list"] as Array[String])
	var out: Array[String] = []
	if not entry.is_empty():
		out.assign(Variants.array(entry["value"]))
	return out


func range_f(key: StringName) -> Vector2:
	var entry: Dictionary = entry_for(key, ["range"] as Array[String])
	if entry.is_empty():
		return Vector2.ZERO
	var pair: Array = entry["value"]
	return Vector2(float(str(pair[0])), float(str(pair[1])))


## The value for ring 0-4.
func by_ring(key: StringName, ring: int) -> float:
	var entry: Dictionary = entry_for(key, ["by_ring"] as Array[String])
	if entry.is_empty():
		return 0.0
	if ring < 0 or ring > 4:
		push_error("Tuning: ring %d out of 0-4 for '%s'" % [ring, key])
		return 0.0
	return float(str(Variants.array(entry["value"])[ring]))


## The value for crew count 1-5.
func by_crew(key: StringName, crew_count: int) -> float:
	var entry: Dictionary = entry_for(key, ["by_crew"] as Array[String])
	if entry.is_empty():
		return 0.0
	if crew_count < 1 or crew_count > 5:
		push_error("Tuning: crew count %d out of 1-5 for '%s'" % [crew_count, key])
		return 0.0
	return float(str(Variants.array(entry["value"])[crew_count - 1]))


func table(key: StringName) -> Dictionary:
	var entry: Dictionary = entry_for(key, ["table"] as Array[String])
	return Variants.dict(entry["value"]).duplicate() if not entry.is_empty() else {}


## A probability as an integer per million: round(p × 10^6). FND-06 generation uses only this.
func ppm(key: StringName) -> int:
	var entry: Dictionary = entry_for(key, ["float", "int"] as Array[String])
	if entry.is_empty():
		return 0
	return roundi(float(str(entry["value"])) * 1000000.0)


## Seconds converted to whole simulation ticks at net.tick_hz, rounded to nearest.
func ticks(key: StringName) -> int:
	var seconds: float = f(key)
	return roundi(seconds * f(StringName(TICK_KEY)))


func has_key(key: StringName) -> bool:
	return entries.has(String(key))

#endregion
