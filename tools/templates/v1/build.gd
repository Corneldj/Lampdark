extends SceneTree
## GEN-16: writes the v1 template set as GEN-04 sources (data/templates/src/<kind>/<biome>/<id>.tscn)
## from TemplateDesignsV1, every design checked against GEN-04's validator first, then exports the
## whole set (TemplateExporter: the readable export, the pack and set.json). A source whose template
## is unchanged is left as it is (Godot gives saved nodes new ids); sources this tool wrote before
## and no longer draws are removed (data/templates/src/v1_generated.json lists them); hand-made
## sources are never touched.
## Usage: godot --headless --path . -s tools/templates/v1/build.gd [-- --check]
## --check writes nothing: it fails if a design breaks a rule or a source on disk differs from what
## its design draws, then runs the exporter's own check.

const MANIFEST: String = "res://data/templates/src/v1_generated.json"
## Loaded when run, so a design script that fails to compile fails the build (a static reference
## would leave this script running on without it).
const DESIGNS: String = "res://tools/templates/v1/template_designs_v1.gd"


func _init() -> void:
	var check: bool = OS.get_cmdline_user_args().has("--check")
	quit(_main(check))


func _main(check: bool) -> int:
	var tuning: TuningSet = TuningSet.new()
	var problems: Array[String] = tuning.load_directory(TuningSet.DATA_DIR)
	if not problems.is_empty():
		for p: String in problems:
			printerr("v1 templates: tuning: %s" % p)
		return 1
	var rules: Dictionary = TemplateBuild.rules(tuning)
	var designs: GDScript = load(DESIGNS) as GDScript
	if designs == null or not designs.can_instantiate():
		printerr("v1 templates: %s does not compile" % DESIGNS)
		return 1
	var specs: Array[Dictionary] = []
	specs.assign(Variants.array(designs.call("all", rules)))
	if specs.is_empty():
		printerr("v1 templates: the designs drew nothing (does tools/templates/v1/template_designs_v1.gd compile?)")
		return 1
	var built: Dictionary = {}
	var errors: Array[String] = []
	var ids: Dictionary = {}
	for spec: Dictionary in specs:
		var id: String = str(spec["id"])
		if ids.has(id):
			errors.append("%s: drawn twice" % id)
		ids[id] = true
		var order: String = _slot_order(spec)
		if not order.is_empty():
			errors.append(order)
		var src: TemplateSource = TemplateScaffold.from_spec(spec)
		var result: Dictionary = TemplateBuild.build(src, rules)
		src.free()
		var template: Dictionary = Variants.dict(result["template"])
		for e: Variant in Variants.array(result["errors"]):
			errors.append(str(e))
		if not template.is_empty():
			for e: String in TemplateBuild.validate(template, rules):
				errors.append(e)
			built[id] = template
	if not errors.is_empty():
		for e: String in errors:
			printerr("v1 templates: %s" % e)
		printerr("v1 templates: %d problems in %d designs; nothing written" % [errors.size(), specs.size()])
		return 1
	var paths: Array[String] = []
	var changed: int = 0
	var stale: Array[String] = []
	for spec: Dictionary in specs:
		var id: String = str(spec["id"])
		var path: String = TemplateScaffold.path_for(id, str(spec["kind"]), str(spec["biome"]))
		paths.append(path)
		if _same_on_disk(path, Variants.dict(built[id]), rules):
			continue
		if check:
			stale.append(path)
			continue
		var src: TemplateSource = TemplateScaffold.from_spec(spec)
		var err: Error = TemplateScaffold.save(src, path)
		src.free()
		if err != OK:
			printerr("v1 templates: cannot write %s (%s)" % [path, error_string(err)])
			return 1
		changed += 1
	var before: Array = Variants.array(JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))) if FileAccess.file_exists(MANIFEST) else []
	paths.sort()
	var removed: int = 0
	for raw: Variant in before:
		var old: String = str(raw)
		if not paths.has(old) and FileAccess.file_exists(old):
			if check:
				stale.append(old)
				continue
			DirAccess.remove_absolute(ProjectSettings.globalize_path(old))
			removed += 1
	if check:
		for path: String in stale:
			printerr("v1 templates: %s differs from its design (run tools/templates/v1/build.gd)" % path)
		var checked: Dictionary = TemplateExporter.run(true)
		for line: Variant in Variants.array(checked["messages"]):
			printerr("v1 templates: export: %s" % line)
		var ok: bool = stale.is_empty() and Variants.flag(checked["ok"])
		print("v1 templates: %d designs %s" % [specs.size(), "match their sources" if ok else "do NOT match"])
		return 0 if ok else 1
	var manifest: FileAccess = FileAccess.open(MANIFEST, FileAccess.WRITE)
	manifest.store_string(JSON.stringify(paths, "\t") + "\n")
	manifest.close()
	var result: Dictionary = TemplateExporter.run(false)
	for line: Variant in Variants.array(result["messages"]):
		printerr("v1 templates: export: %s" % line)
	if not Variants.flag(result["ok"]):
		return 1
	print("v1 templates: %d designs (%d written, %d removed); exported %d templates, set %s" % [specs.size(), changed, removed,
		int(Variants.number(result["templates"])), str(result["set_version"])])
	return 0


## GEN-09 gives a point of interest's contents lines its poi_slots in the order the export keeps them:
## cell by cell, then row by row. A design must draw them in that order, or a line lands in another
## line's slot (the tub off its rails). The problem, or "".
static func _slot_order(spec: Dictionary) -> String:
	var drawn: Array = []
	for raw: Variant in Variants.array(spec["anchors"]):
		var a: Array = raw
		if str(a[0]) != "poi_slot":
			continue
		var x: int = Variants.whole(a[1])
		var y: int = Variants.whole(a[2])
		drawn.append([y / WorldIds.CELL_TILES, x / WorldIds.CELL_TILES, y % WorldIds.CELL_TILES, x % WorldIds.CELL_TILES, Variants.whole(a[3]),
			Variants.whole(a[4]), str(a[6])])
	var sorted: Array = drawn.duplicate(true)
	sorted.sort_custom(func(p: Array, q: Array) -> bool: return p < q)
	for i: int in drawn.size():
		if drawn[i] != sorted[i]:
			var at: Array = drawn[i]
			return "%s: its slot for contents line %d (cell %d, %d, tile %d, %d) is not the cell-by-cell, row-by-row slot %d: draw the slots in that order" % [
				spec["id"], i, at[1], at[0], at[3], at[2], sorted.find(at)]
	return ""


## Whether the source at `path` builds to the same template as `template` (its export text).
static func _same_on_disk(path: String, template: Dictionary, rules: Dictionary) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var scene: PackedScene = load(path) as PackedScene
	var node: Node = scene.instantiate() if scene != null else null
	var src: TemplateSource = node as TemplateSource
	if src == null:
		if node != null:
			node.free()
		return false
	var result: Dictionary = TemplateBuild.build(src, rules)
	src.free()
	var old: Dictionary = Variants.dict(result["template"])
	return not old.is_empty() and TemplateBuild.files(old) == TemplateBuild.files(template)
