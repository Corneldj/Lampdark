@tool
class_name TemplatesPanel
extends VBoxContainer
## The dock's contents: make a new template scene, validate the open one, and validate and export
## the whole set (TemplateExporter, as the CI exporter does). The plugin wires the editor in through
## the callables, so this panel never names the editor's own classes.

## () -> Node: the scene open in the editor.
var edited_root: Callable = func() -> Node: return null
## (path: String) -> void: open a scene in the editor.
var open_scene: Callable = func(_path: String) -> void: pass
## () -> void: rescan the project's files after an export.
var rescan: Callable = func() -> void: pass

var _id: LineEdit = LineEdit.new()
var _kind: OptionButton = OptionButton.new()
var _biome: LineEdit = LineEdit.new()
var _footprint: OptionButton = OptionButton.new()
var _out: TextEdit = TextEdit.new()

const KINDS: Array[String] = ["biome_cell", "main_road", "poi", "fallback", "base_camp"]
const FOOTPRINTS: Array[Vector2i] = [Vector2i(1, 1), Vector2i(1, 2), Vector2i(2, 1), Vector2i(2, 2)]


func _init() -> void:
	name = "Templates"
	custom_minimum_size = Vector2(260.0, 0.0)
	_id.placeholder_text = "template id, e.g. seam_crossing_02"
	for k: String in KINDS:
		_kind.add_item(k)
	_biome.text = "seam"
	for f: Vector2i in FOOTPRINTS:
		_footprint.add_item("%dx%d cells" % [f.x, f.y])
	var make: Button = Button.new()
	make.text = "New template"
	make.pressed.connect(func() -> void: new_template())
	var check: Button = Button.new()
	check.text = "Validate this template"
	check.pressed.connect(func() -> void: validate_open())
	var export_button: Button = Button.new()
	export_button.text = "Validate and export all"
	export_button.pressed.connect(func() -> void: export_all())
	_out.editable = false
	_out.custom_minimum_size = Vector2(0.0, 240.0)
	_out.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_out.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	for c: Control in [_id, _kind, _biome, _footprint, make, check, export_button, _out]:
		add_child(c)


## Makes data/templates/src/<kind>/<biome>/<id>.tscn, all rock, and opens it.
func new_template() -> String:
	var id: String = _id.text.strip_edges()
	var kind: String = KINDS[maxi(_kind.selected, 0)]
	var biome: String = _biome.text.strip_edges()
	if not id.is_valid_ascii_identifier() or biome.is_empty():
		return _say("A template needs an id (letters, digits and _) and a biome.")
	var path: String = TemplateScaffold.path_for(id, kind, biome)
	if FileAccess.file_exists(path):
		return _say("%s already exists." % path)
	var src: TemplateSource = TemplateScaffold.empty(id, kind, biome, FOOTPRINTS[maxi(_footprint.selected, 0)])
	var err: Error = TemplateScaffold.save(src, path)
	src.free()
	if err != OK:
		return _say("Could not save %s: %s" % [path, error_string(err)])
	rescan.call()
	open_scene.call(path)
	return _say("Made %s. Paint floor on Geometry; add TemplateAnchor, TemplateStub and TemplateCollapse children." % path)


## Validates the open scene's template: its problems, or that it is valid.
func validate_open() -> String:
	var src: TemplateSource = edited_root.call() as TemplateSource
	if src == null:
		return _say("Open a template scene (its root is a TemplateSource) first.")
	var tuning: TuningSet = TuningSet.new()
	var problems: Array[String] = tuning.load_directory(TuningSet.DATA_DIR)
	if not problems.is_empty():
		return _say("\n".join(PackedStringArray(problems)))
	var rules: Dictionary = TemplateBuild.rules(tuning)
	var built: Dictionary = TemplateBuild.build(src, rules)
	problems.append_array(Variants.array(built["errors"]))
	var template: Dictionary = Variants.dict(built["template"])
	if not template.is_empty():
		problems.append_array(TemplateBuild.validate(template, rules))
	if problems.is_empty():
		return _say("Template %s is valid." % src.template_id)
	return _say("\n".join(PackedStringArray(problems)))


## Validates every template and, if all are valid, writes the export, the pack and set.json.
func export_all() -> String:
	var result: Dictionary = TemplateExporter.run(false)
	rescan.call()
	if Variants.flag(result["ok"]):
		return _say("Exported %d templates as set %s." % [int(Variants.number(result["templates"])), str(result["set_version"])])
	return _say("Nothing written:\n" + "\n".join(PackedStringArray(Variants.array(result["messages"]))))


func _say(text: String) -> String:
	_out.text = text
	return text
