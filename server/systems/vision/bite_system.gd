class_name BiteSystem
extends SimSystem
## VIS-10 (stage LIGHT_PASS_2, last): the Stythe's bite, once this tick's light is summed and
## before NET-08's expectations and VIS-03's seen sets (stage 12) read it. VisionSystem holds it.
## Server-only.


func stage() -> int:
	return StageTable.Stage.LIGHT_PASS_2


func order() -> int:
	return 950


func system_name() -> String:
	return "bite"


func tick(run: RunState) -> void:
	if run.vision != null:
		run.vision.compute_bite(run)
