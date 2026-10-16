@tool
class_name TemplateExporter
extends RefCounted
## GEN-04's export of the whole template set, shared by the editor dock and the headless
## exporter (tools/build/export_templates.gd). Under `root` (res://data/templates):
##   src/<kind>/<biome>/<id>.tscn   the sources (TemplateSource scenes);
##   export/<id>/...                 the readable source of truth (TemplateBuild.files);
##   packs/<set_version>.lbtp        the packed binary the server loads;
##   set.json                        the current set_version and its templates.
## set_version is the first 16 hex digits of the SHA-256 of the canonical export (every file's
## path and text, in path order), so any change to any template gives a new version. Older packs
## stay: a saved run resumes on its own set (Proposed: servers keep every pack a supported save
## names). Nothing is written unless every template is valid.

const ROOT: String = "res://data/templates"
const SET_FORMAT: int = 1


## {"ok": bool, "messages": Array[String], "set_version": String, "templates": int}. With `check`
## nothing is written: the export, set.json and the pack on disk must equal what the sources give.
static func run(check: bool, root: String = ROOT, extra_rules: Dictionary = {}) -> Dictionary:
	var messages: Array[String] = []
	var tuning: TuningSet = TuningSet.new()
	messages.append_array(tuning.load_directory(TuningSet.DATA_DIR))
	if not messages.is_empty():
		return _result(false, messages, "", 0)
	var params: Dictionary = TemplateBuild.rules(tuning, extra_rules)
	var templates: Array[Dictionary] = []
	var ids: Dictionary = {}
	for path: String in sources(root.path_join("src")):
		var scene: PackedScene = load(path) as PackedScene
		var node: Node = scene.instantiate() if scene != null else null
		var src: TemplateSource = node as TemplateSource
		if src == null:
			messages.append("%s: not a TemplateSource scene" % path)
			if node != null:
				node.free()
			continue
		var built: Dictionary = TemplateBuild.build(src, params)
		var expected: String = root.path_join("src").path_join(src.kind).path_join(src.biome).path_join(src.template_id + ".tscn")
		if path != expected:
			messages.append("%s: template %s belongs at %s" % [path, src.template_id, expected])
		src.free()
		messages.append_array(Variants.array(built["errors"]))
		var template: Dictionary = Variants.dict(built["template"])
		if template.is_empty():
			continue
		if ids.has(template["id"]):
			messages.append("%s: template id %s is used twice" % [path, template["id"]])
		ids[template["id"]] = true
		messages.append_array(TemplateBuild.validate(template, params))
		templates.append(template)
	if not messages.is_empty():
		return _result(false, messages, "", templates.size())
	templates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["id"]) < str(b["id"]))
	var files: Dictionary = {}
	for t: Dictionary in templates:
		files.merge(TemplateBuild.files(t))
	var version: String = set_version(files)
	var pack: PackedByteArray = LbTemplates.encode_pack(version, templates)
	var set_text: String = set_file(version, templates)
	var export_dir: String = root.path_join("export")
	var pack_path: String = root.path_join("packs").path_join(version + ".lbtp")
	if check:
		for rel: String in _sorted_keys(files):
			if FileAccess.get_file_as_string(export_dir.path_join(rel)) != str(files[rel]):
				messages.append("export/%s is out of date: run tools/build/export_templates.gd" % rel)
		for rel: String in list_files(export_dir):
			if not files.has(rel):
				messages.append("export/%s has no source: run tools/build/export_templates.gd" % rel)
		if FileAccess.get_file_as_string(root.path_join("set.json")) != set_text:
			messages.append("set.json does not name set %s: run tools/build/export_templates.gd" % version)
		if not FileAccess.file_exists(pack_path) or FileAccess.get_file_as_bytes(pack_path) != pack:
			messages.append("packs/%s.lbtp is missing or differs: a changed pack needs a new set_version" % version)
		return _result(messages.is_empty(), messages, version, templates.size())
	for rel: String in list_files(export_dir):
		if not files.has(rel):
			DirAccess.remove_absolute(export_dir.path_join(rel))
	for rel: String in _sorted_keys(files):
		messages.append_array(_write(export_dir.path_join(rel), str(files[rel]).to_utf8_buffer()))
	messages.append_array(_write(pack_path, pack))
	messages.append_array(_write(root.path_join("set.json"), set_text.to_utf8_buffer()))
	_remove_empty_dirs(export_dir)
	return _result(messages.is_empty(), messages, version, templates.size())


## Every .tscn under `dir`, sorted.
static func sources(dir: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for rel: String in list_files(dir):
		if rel.get_extension() == "tscn":
			out.append(dir.path_join(rel))
	return out


## Every file under `dir` as a path relative to it, sorted ("" dir: none).
static func list_files(dir: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var d: DirAccess = DirAccess.open(dir)
	if d == null:
		return out
	for name_of: String in d.get_files():
		if not name_of.ends_with(".import") and not name_of.ends_with(".uid") and name_of != ".gitkeep":
			out.append(name_of)
	for sub: String in d.get_directories():
		for rel: String in list_files(dir.path_join(sub)):
			out.append(sub.path_join(rel))
	out.sort()
	return out


static func set_version(files: Dictionary) -> String:
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for rel: String in _sorted_keys(files):
		ctx.update(("%s\n" % rel).to_utf8_buffer())
		ctx.update(str(files[rel]).to_utf8_buffer())
	return ctx.finish().hex_encode().substr(0, 16)


static func set_file(version: String, templates: Array[Dictionary]) -> String:
	var ids: Array = []
	for t: Dictionary in templates:
		ids.append(t["id"])
	var lines: PackedStringArray = PackedStringArray(["{"])
	lines.append("\t\"format\": %d," % SET_FORMAT)
	lines.append("\t\"set_version\": %s," % JSON.stringify(version))
	lines.append("\t\"pack\": %s," % JSON.stringify("packs/%s.lbtp" % version))
	lines.append("\t\"templates\": %s" % JSON.stringify(ids))
	lines.append("}")
	return "\n".join(lines) + "\n"


static func _sorted_keys(d: Dictionary) -> PackedStringArray:
	var keys: PackedStringArray = PackedStringArray()
	for k: Variant in d.keys():
		keys.append(str(k))
	keys.sort()
	return keys


static func _write(path: String, bytes: PackedByteArray) -> Array[String]:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ["cannot write %s: %s" % [path, error_string(FileAccess.get_open_error())]]
	f.store_buffer(bytes)
	f.close()
	return []


static func _remove_empty_dirs(dir: String) -> void:
	var d: DirAccess = DirAccess.open(dir)
	if d == null:
		return
	for sub: String in d.get_directories():
		_remove_empty_dirs(dir.path_join(sub))
		var inner: DirAccess = DirAccess.open(dir.path_join(sub))
		if inner != null and inner.get_files().is_empty() and inner.get_directories().is_empty():
			DirAccess.remove_absolute(dir.path_join(sub))


static func _result(ok: bool, messages: Array[String], version: String, count: int) -> Dictionary:
	return {"ok": ok, "messages": messages, "set_version": version, "templates": count}
