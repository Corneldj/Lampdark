extends SceneTree
## GEN-04's headless template exporter: validates every template under data/templates/src/ and
## writes data/templates/export/, the pack data/templates/packs/<set_version>.lbtp and
## data/templates/set.json (TemplateExporter, the editor dock's code). Nothing is written unless
## every template is valid. With --check (CI) nothing is written either: it fails if any template
## is invalid or the committed export, set.json or pack differ from what the sources give.
## Usage: godot --headless --path . -s tools/build/export_templates.gd [-- --check] [-- --root <dir>]


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var root: String = TemplateExporter.ROOT
	var at: int = args.find("--root")
	if at >= 0 and at + 1 < args.size():
		root = args[at + 1]
	var check: bool = args.has("--check")
	var result: Dictionary = TemplateExporter.run(check, root)
	for line: Variant in Variants.array(result["messages"]):
		printerr("export_templates: %s" % line)
	if Variants.flag(result["ok"]):
		print("export_templates: %s %d templates, set %s" % ["checked" if check else "exported",
			int(Variants.number(result["templates"])), str(result["set_version"])])
	quit(0 if Variants.flag(result["ok"]) else 1)
