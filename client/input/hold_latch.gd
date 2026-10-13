class_name HoldLatch
extends RefCounted
## MNR-04 (GDD §14.5): hold-or-toggle for one held input. In hold mode the bit is set while the
## control is down; in toggle mode a press sets it and the next press clears it. Either way the
## server sees only the bit, so a timed action takes exactly as long in both modes: a toggle
## starts or stops an action, never shortens it. MNR-15 binds one per held control.

var toggle: bool = false
var _latched: bool = false
var _was_down: bool = false


## This tick's bit for the control's physical state.
func sample(down: bool) -> bool:
	var pressed: bool = down and not _was_down
	_was_down = down
	if not toggle:
		_latched = down
	elif pressed:
		_latched = not _latched
	return _latched


## Clears a latched toggle (the action ended or was refused, so the next press starts afresh).
func release() -> void:
	_latched = false
