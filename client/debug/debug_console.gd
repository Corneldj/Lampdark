class_name DebugConsole
extends CanvasLayer
## FND-08: the client console (backtick), dev and QA builds only (this folder is not in a release
## pack, and the client loads it by path outside release). A line is parsed with the shared
## DebugCommands registry: client commands run here (help, listener_mode, and the truth and overlay
## switches), server commands go over the debug lane and their answers come back to this log.
## Without the debug channel (no QA token, or a release server), server commands are refused here.

signal line_entered(line: String)

const MAX_LINES: int = 200

var log_lines: PackedStringArray = PackedStringArray()
var _panel: PanelContainer = null
var _log: RichTextLabel = null
var _input: LineEdit = null


func _ready() -> void:
	layer = 100
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_panel.custom_minimum_size = Vector2(0, 360)
	_panel.visible = false
	var box: VBoxContainer = VBoxContainer.new()
	_log = RichTextLabel.new()
	_log.scroll_following = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_input = LineEdit.new()
	_input.placeholder_text = "help"
	_input.text_submitted.connect(_on_submit)
	box.add_child(_log)
	box.add_child(_input)
	_panel.add_child(box)
	add_child(_panel)


func is_open() -> bool:
	return _panel != null and _panel.visible


func toggle() -> void:
	_panel.visible = not _panel.visible
	if _panel.visible:
		_input.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_QUOTELEFT:
		toggle()
		get_viewport().set_input_as_handled()


func _on_submit(line: String) -> void:
	_input.clear()
	if not line.strip_edges().is_empty():
		print_line("> " + line)
		line_entered.emit(line)


func print_line(text: String) -> void:
	log_lines.append(text)
	if log_lines.size() > MAX_LINES:
		log_lines = log_lines.slice(log_lines.size() - MAX_LINES)
	if _log != null:
		_log.append_text(text.replace("[", "[lb]") + "\n")
