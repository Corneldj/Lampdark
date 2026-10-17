class_name LampmanSequence
extends RefCounted
## RSC-06 (Gameplay §11.9, §13.2, GDD §14.3): the lampman's reading at Lamp Check, as a timeline.
## The band plays alone a moment; then, hook by hook in reading order, he hangs the brass check of
## whoever came up and reads its number digit by digit ('One... one... four'), or waits in silence
## at an empty hook; then one remark on what felled someone, if anyone fell. The band is silent from
## his first word to his last. Every spoken step carries its caption key (data/text/lampman/). Times
## are the clips' own lengths and rescue.lamp_check_* pauses.

## One step: kind (hang | digit | silence | remark), its start and length (s), the hook it belongs
## to (-1 for the remark), and for speech the clip (line id and form, LampmanBank's) and caption key.
class Step:
	extends RefCounted
	var kind: String = ""
	var start_s: float = 0.0
	var length_s: float = 0.0
	var hook: int = -1
	var line_id: String = ""
	var form: String = "one"
	var key: String = ""

	func end_s() -> float:
		return start_s + length_s


var steps: Array[Step] = []
## When he starts and stops reading (the band is silent between), and when it is all done.
var reading_from_s: float = 0.0
var reading_to_s: float = 0.0


## `hooks`: [{lamp, hangs}] in reading order; `remark`: a FallCause name, "" for none; `length_of`:
## (line_id, form) -> seconds, the clip's length (LampmanBank's streams; tests give their own).
static func build(hooks: Array, remark: String, length_of: Callable) -> LampmanSequence:
	var q: LampmanSequence = LampmanSequence.new()
	var t: float = Tuning.f(&"rescue.lamp_check_lead_s")
	q.reading_from_s = t
	for i: int in hooks.size():
		var h: Dictionary = Variants.dict(hooks[i])
		if Variants.flag(h.get("hangs", false)):
			t = q._add("hang", t, Tuning.f(&"rescue.lamp_check_hang_s"), i, "", "", "")
			var digits: String = str(int(Variants.number(h.get("lamp", 0))))
			for d: int in digits.length():
				var form: String = "final" if d == digits.length() - 1 else "continuing"
				var line: String = "digit_" + digits[d]
				t = q._add("digit", t, float(Variants.number(length_of.call(line, form))), i, line, form, "lampman." + line)
				if d < digits.length() - 1:
					t += Tuning.f(&"rescue.lamp_check_digit_gap_s")
		else:
			t = q._add("silence", t, Tuning.f(&"rescue.lamp_check_silence_s"), i, "", "", "")
		t += Tuning.f(&"rescue.lamp_check_hook_gap_s")
	if not remark.is_empty():
		t += Tuning.f(&"rescue.lamp_check_remark_gap_s")
		var line_id: String = "remark_" + remark
		t = q._add("remark", t, float(Variants.number(length_of.call(line_id, "one"))), -1, line_id, "one", "lampman.remark." + remark)
	q.reading_to_s = t
	return q


func _add(kind: String, at: float, length: float, hook: int, line_id: String, form: String, key: String) -> float:
	var s: Step = Step.new()
	s.kind = kind
	s.start_s = at
	s.length_s = maxf(0.0, length)
	s.hook = hook
	s.line_id = line_id
	s.form = form
	s.key = key
	steps.append(s)
	return s.end_s()


## Whether he is reading at `t`: the band is silent then.
func reading(t: float) -> bool:
	return t >= reading_from_s and t < reading_to_s


## The steps that start in [from_s, to_s): what to play, show and caption as time passes.
func starting(from_s: float, to_s: float) -> Array[Step]:
	var out: Array[Step] = []
	for s: Step in steps:
		if s.start_s >= from_s and s.start_s < to_s:
			out.append(s)
	return out


## The digits he reads for hook `i`, in order ("" for an empty hook).
func digits_read(i: int) -> String:
	var out: String = ""
	for s: Step in steps:
		if s.hook == i and s.kind == "digit":
			out += s.line_id.trim_prefix("digit_")
	return out
