@tool
extends EditorPlugin
## GEN-04's authoring plugin (dev only; no export carries addons/lampblack_templates). Adds the
## Templates dock and the template node types.

var _dock: EditorDock = null


func _enter_tree() -> void:
	var panel: TemplatesPanel = TemplatesPanel.new()
	panel.edited_root = func() -> Node: return EditorInterface.get_edited_scene_root()
	panel.open_scene = func(path: String) -> void: EditorInterface.open_scene_from_path(path)
	panel.rescan = func() -> void: EditorInterface.get_resource_filesystem().scan()
	_dock = EditorDock.new()
	_dock.title = "Templates"
	_dock.default_slot = EditorDock.DOCK_SLOT_RIGHT_UL
	_dock.add_child(panel)
	add_dock(_dock)


func _exit_tree() -> void:
	if _dock != null:
		remove_dock(_dock)
		_dock.queue_free()
		_dock = null
