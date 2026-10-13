extends "res://tools/bots/brain.gd"
## Plays a timeline file (args "arg" = path). JSON: {"steps": [{"tick": 0, "move": 90, "gait":
## "walk", "ticks": 20}, {"tick": 5, "face": 180}, {"tick": 30, "press": "callout", "arg": 2},
## {"tick": 40, "hold": "interact", "ticks": 10}, {"tick": 50, "lamp": [false, 2]}]}

const InputScript = preload("res://tests/scenario/kit/input_script.gd")
const GAITS: Dictionary = {"crouch": InputRecord.Gait.CROUCH, "walk": InputRecord.Gait.WALK, "run": InputRecord.Gait.RUN}
const HOLDS: Dictionary = {"interact": InputRecord.HOLD_INTERACT, "check_lamp": InputRecord.HOLD_CHECK_LAMP,
	"aim": InputRecord.HOLD_AIM, "breath": InputRecord.HOLD_BREATH, "squint": InputRecord.HOLD_SQUINT, "feel": InputRecord.HOLD_FEEL}
const KINDS: Dictionary = {"callout": ActionRecord.Kind.CALLOUT, "lamp_signal": ActionRecord.Kind.LAMP_SIGNAL,
	"chalk": ActionRecord.Kind.CHALK, "ring_choice": ActionRecord.Kind.RING_CHOICE, "trigger": ActionRecord.Kind.TRIGGER,
	"tap_rock": ActionRecord.Kind.TAP_ROCK}

var timeline: InputScript = InputScript.new()


func setup(seed_value: int, brain_args: Dictionary) -> void:
	super(seed_value, brain_args)
	var path: String = str(args.get("arg", ""))
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if not path.is_empty() else null
	if not parsed is Dictionary:
		push_error("scripted brain: cannot read timeline '%s'" % path)
		return
	load_steps(Variants.array(Variants.dict(parsed).get("steps", [])))


func load_steps(steps: Array) -> void:
	for raw: Variant in steps:
		var step: Dictionary = Variants.dict(raw)
		timeline.at(int(Variants.number(step.get("tick", 0))))
		var ticks: int = int(Variants.number(step.get("ticks", 1)))
		if step.has("move"):
			var gait: InputRecord.Gait = int(Variants.number(GAITS.get(str(step.get("gait", "walk")), 1))) as InputRecord.Gait
			timeline.move(float(Variants.number(step["move"])), gait, ticks)
		if step.has("face"):
			timeline.face(float(Variants.number(step["face"])))
		if step.has("press"):
			var kind: ActionRecord.Kind = int(Variants.number(KINDS.get(str(step["press"]), 0))) as ActionRecord.Kind
			timeline.press(kind, int(Variants.number(step.get("arg", 0))))
		if step.has("hold"):
			timeline.hold(int(Variants.number(HOLDS.get(str(step["hold"]), 0))), ticks)
		if step.has("lamp"):
			var lamp: Array = Variants.array(step["lamp"])
			timeline.lamp(Variants.flag(lamp[0]), int(Variants.number(lamp[1])))


func think(ctx: BotContext) -> InputRecord:
	for action: Variant in timeline.actions_at(ctx.tick):
		ctx.actions.append(Variants.array(action))
	return timeline.record_at(ctx.tick)
