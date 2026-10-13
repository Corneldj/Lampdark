class_name MineCommitSystem
extends SimSystem
## Stage 5 (NET-01): commits finished cells and applies unloads, atomically on the tick thread.

var mine: Mine


func _init(server_mine: Mine) -> void:
	mine = server_mine


func stage() -> int:
	return StageTable.Stage.GENERATION


func order() -> int:
	return 0


func tick(_run: RunState) -> void:
	mine.apply_pending()
