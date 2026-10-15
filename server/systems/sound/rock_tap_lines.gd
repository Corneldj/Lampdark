class_name RockTapLines
extends SimSystem
## SND-12 (stage ROAD_GRAPH, after the noise dispatch and before SND-09's heard tracker): this
## tick's rock taps through the rock to the teammates the air did not reach (RockTaps).


func stage() -> int:
	return StageTable.Stage.ROAD_GRAPH


func order() -> int:
	return 20


func system_name() -> String:
	return "rock_tap_lines"


func tick(run: RunState) -> void:
	if run.rock_taps != null:
		run.rock_taps.deliver_pending(run)
