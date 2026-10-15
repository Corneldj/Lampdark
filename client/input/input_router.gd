class_name InputRouter
extends RefCounted
## MNR-15: one client input layer (Gameplay §4.8). Each client tick it takes a frame of device state
## from an InputSource (which actions are down, the sticks or the cursor, the wheel pick) and turns
## it into intents: an InputRecord (a direction, never a speed; a facing; held bits; the wanted lamp
## and slot state) and one-shot actions (wheel picks, the rock tap, a ring choice, a shot). Hold or
## toggle and tap timing are settled here, never on the server, and nothing here is ever a hit, a
## target or a computed result. Contexts: the mine, an open wheel (facing held), a close-up.

## Held actions and the bits they drive, each through a HoldLatch (hold or toggle per action).
const HELD: Dictionary = {
	"interact": InputRecord.HOLD_INTERACT,
	"use": InputRecord.HOLD_USE,
	"set_down": InputRecord.HOLD_SET_DOWN,
	"relight": InputRecord.HOLD_RELIGHT,
	"hold_breath": InputRecord.HOLD_BREATH,
	"check_lamp": InputRecord.HOLD_CHECK_LAMP,
}
## Pad buttons shared by a tap and a hold, when both are bound to one button: [tap, hold, delayed].
## Delayed: the hold only starts once the press passes movement.input_tap_max (LB's callout wheel,
## View's Check Lamp, §4.8 rule 5). Not delayed: the hold starts on the press, so a timed action
## never runs longer than its own time, and a short press also counts as the tap (A: interact, and
## set down with a lamp in hand when nothing is identified).
const TAP_HOLD_PAIRS: Array[Array] = [["tap_rock", "callout", true], ["pocket_book", "check_lamp", true],
	["set_down", "interact", false]]
## Wheels in the mine: [opening action, ActionRecord kind].
const WHEELS: Array[Array] = [["callout", ActionRecord.Kind.CALLOUT], ["signal_wheel", ActionRecord.Kind.LAMP_SIGNAL],
	["chalk_wheel", ActionRecord.Kind.CHALK]]

var store: BindingsStore = BindingsStore.new()
var family: String = "kbm"
var context: InputContexts.Context = InputContexts.Context.MINE
## The wanted state and held bits carried from tick to tick.
var record: InputRecord = InputRecord.new()
## This tick's one-shot actions: [kind, arg, aim]; the caller queues them on its InputSender.
var actions: Array[Array] = []
## This tick's close-up presses (UI-02 reads them): action names.
var close_up_events: Array[String] = []
## Pocket Book presses (UI-02 opens the book; it is a close-up, not an intent).
var pocket_book_presses: int = 0
## What the client knows of its own miner: the revolver drawn (InventoryWire's free hand), a
## two-handed carry or a two-person job (the job page), a lamp or candle in the lamp hand, an
## interactable identified in reach (UI-01's prompt), the ring's options while it is open (MNR-05).
var revolver_drawn: bool = false
var carrying: bool = false
## RSC-04: coming round in the Dark (the callout wheel offers 'Help!' and a moan, no rings).
var coming_round: bool = false
var lamp_in_hand: bool = false
var target_in_reach: bool = false
var ring_options: Array[String] = []
var wheel: WheelInput = WheelInput.new()
var ring_wheel: WheelInput = WheelInput.new()
var facing_deg: float = 0.0
## SND-06: push-to-talk (V; unbound on pad) held this tick. It gates sending only, never the band.
var push_to_talk_held: bool = false
## UI-01 and SND-14: the Aside held this tick (H; the pad's paddles). SND-14 owns what it does.
var aside_held: bool = false
var _prev: Dictionary = {}
var _pressed_at: Dictionary = {}
var _latches: Dictionary = {}
var _set_down_latched: bool = false
var _last_callout_release: float = -INF


func _init(bindings: BindingsStore = null, device_family: String = "kbm") -> void:
	if bindings != null:
		store = bindings
	family = device_family


## One client tick. `frame` as InputSource.frame describes it.
func sample(frame: Dictionary) -> InputRecord:
	actions.clear()
	close_up_events.clear()
	var now: float = Variants.number(frame.get("now_s", 0.0))
	var down: Dictionary = Variants.dict(frame.get("down", {})).duplicate()
	var pick_vec: Vector2 = frame.get("wheel_vec", Vector2.ZERO)
	push_to_talk_held = Variants.flag(down.get("push_to_talk", false))
	aside_held = Variants.flag(down.get("aside", false))
	if context == InputContexts.Context.CLOSE_UP:
		for action: String in InputContexts.CLOSE_UP_ACTIONS:
			if _pressed(action, down):
				close_up_events.append(action)
		record.move_dir = InputRecord.NO_DIRECTION
		record.holds = 0
		_remember(down)
		return record
	_settle_pairs(down, now, pick_vec)
	_move(frame, down)
	_wheels(down, now, pick_vec)
	_ring(down, pick_vec)
	_facing(frame)
	if context == InputContexts.Context.MINE:
		_holds(down)
		_lamp_and_slot(down)
		_fire(down)
	_remember(down)
	return record


## Facing is held while a wheel or the ring is open (the source anchors the mouse pick meanwhile).
func picking() -> bool:
	return context == InputContexts.Context.WHEEL or not ring_options.is_empty()


func open_close_up() -> void:
	context = InputContexts.Context.CLOSE_UP


func close_close_up() -> void:
	context = InputContexts.Context.MINE


## What the own miner holds, from ClientConnection.inventory (InventoryWire.decode).
func know_inventory(inventory: Dictionary) -> void:
	if inventory.is_empty():
		return
	lamp_in_hand = int(Variants.number(Variants.array(inventory["lamp"])[0])) != ItemKinds.Kind.NONE \
		and not Variants.flag(inventory.get("hooked", false))
	carrying = Variants.flag(inventory.get("two_handed", false))
	revolver_drawn = int(Variants.number(Variants.array(inventory["free"])[0])) == ItemKinds.Kind.REVOLVER


## The interact ring, from ClientConnection.ring (RingMessages.decode): its options while open.
func know_ring(ring: Dictionary) -> void:
	ring_options.clear()
	if Variants.flag(ring.get("open", false)):
		for raw: Variant in Variants.array(ring.get("options", [])):
			ring_options.append(str(raw))


## STM-01: the Steam overlay opened. Every gameplay input lets go: toggled holds release, and the
## next samples (fed neutral_frame while the overlay is up) hold nothing, move nowhere and pick
## nothing, so the miner stands and a timed action is cancelled as on a drop. Nothing pauses.
func release_all() -> void:
	for raw: Variant in _latches.values():
		var l: HoldLatch = raw
		l.release()
	record.move_dir = InputRecord.NO_DIRECTION
	record.holds = 0


## A frame with nothing held, no movement and a centred pick (a wheel then cancels); the cursor
## stays where it was, so facing holds.
static func neutral_frame(frame: Dictionary) -> Dictionary:
	var out: Dictionary = frame.duplicate()
	out["down"] = {}
	out["move"] = Vector2.ZERO
	out["face_stick"] = Vector2.ZERO
	out["wheel_vec"] = Vector2.ZERO
	return out


## The action a toggled hold drove has ended (or was refused): the next press starts afresh.
func release_toggle(action: String) -> void:
	if _latches.has(action):
		var l: HoldLatch = _latches[action]
		l.release()


## The server's lamp state (after a douse or a snuff) taken into the held wanted state, so the next
## shutter press opens it (MNR-06).
func sync_lamp(shut: bool, wick: int) -> void:
	var slot: int = record.selected_slot()
	record.desired = (1 if shut else 0) | (clampi(wick, 0, 2) << 1)
	record.set_selected_slot(slot)


## A shared pad button: the tap fires on a release inside movement.input_tap_max, the hold as above.
## With the callout timing option the callout wheel opens on the press itself: its release times the
## band (SND-11), and a quick centred release is still the rock tap (_wheels).
func _settle_pairs(down: Dictionary, now: float, pick_vec: Vector2) -> void:
	var tap_max: float = Tuning.f(&"movement.input_tap_max")
	for pair: Array in TAP_HOLD_PAIRS:
		var tap: String = pair[0]
		var hold: String = pair[1]
		if not _shared_button(tap, hold):
			continue
		var key: String = "__pair_" + hold
		var is_down: bool = Variants.flag(down.get(hold, false)) or Variants.flag(down.get(tap, false))
		var was_down: bool = Variants.flag(_prev.get(key, false))
		if is_down and not was_down:
			_pressed_at[key] = now
		var held_for: float = now - Variants.number(_pressed_at.get(key, now))
		var short: bool = held_for < tap_max - 1e-6
		var timing: bool = hold == "callout" and store.callout_timing
		var delayed: bool = Variants.flag(pair[2]) and not timing
		down[hold] = is_down and (not delayed or not short)
		down[tap] = false
		if not is_down and was_down and short and not timing:
			if tap != "tap_rock" or pick_vec.length() < WheelInput.cancel_radius():
				down["__tap_" + tap] = true
		_prev[key] = is_down


func _shared_button(a: String, b: String) -> bool:
	for sa: Variant in store.specs(a, family):
		for sb: Variant in store.specs(b, family):
			var da: Dictionary = Variants.dict(sa)
			var db: Dictionary = Variants.dict(sb)
			if str(da.get("type", "")) == "joy_button" and str(db.get("type", "")) == "joy_button" \
					and int(Variants.number(da["button"])) == int(Variants.number(db["button"])):
				return true
	return false


## A direction only: any deflection past the stick's dead zone is the same intent, so no binding
## can make speed depend on it. Run and crouch go through their latches.
func _move(frame: Dictionary, down: Dictionary) -> void:
	var dead: float = Tuning.f(&"movement.stick_dead_zone")
	var v: Vector2 = frame.get("move", Vector2.ZERO)
	if family == "kbm" or v.length() < dead:
		v = Vector2(_axis(down, "move_right") - _axis(down, "move_left"), _axis(down, "move_down") - _axis(down, "move_up"))
	if v.length() >= dead:
		record.move_dir = Intents.direction_byte(rad_to_deg(v.angle()))
		_set_down_latched = false
	else:
		record.move_dir = InputRecord.NO_DIRECTION
	var run: bool = _latch("run", Variants.flag(down.get("run", false)))
	var crouch: bool = _latch("crouch", Variants.flag(down.get("crouch", false)))
	record.gait = InputRecord.Gait.CROUCH if crouch else (InputRecord.Gait.RUN if run else InputRecord.Gait.WALK)


func _axis(down: Dictionary, action: String) -> float:
	return 1.0 if Variants.flag(down.get(action, false)) else 0.0


## Facing turns at once: toward the cursor from the own miner's screen position with the camera's
## lead taken out (InputSource's own_screen), so the lead never feeds back; or along the right stick
## past its dead zone, a centred stick keeping it. Held while a wheel or the ring is open.
func _facing(frame: Dictionary) -> void:
	if picking():
		return
	if family == "kbm":
		var cursor: Vector2 = frame.get("cursor", Vector2(INF, INF))
		var own: Vector2 = frame.get("own_screen", Vector2.ZERO)
		if cursor.is_finite() and cursor.distance_to(own) > 0.5:
			facing_deg = fposmod(rad_to_deg((cursor - own).angle()), 360.0)
	else:
		var stick: Vector2 = frame.get("face_stick", Vector2.ZERO)
		if stick.length() > Tuning.f(&"movement.facing_dead_zone"):
			facing_deg = fposmod(rad_to_deg(stick.angle()), 360.0)
	record.facing = Intents.facing_u16(facing_deg)


## The rock tap, the Pocket Book, and the wheels: the callout wheel (the job page while carrying),
## lamp signals and chalk (one wheel when both share a button). A wheel's button opens it; releasing
## picks, or, centred, cancels.
func _wheels(down: Dictionary, now: float, pick_vec: Vector2) -> void:
	if Variants.flag(down.get("__tap_tap_rock", false)) or (_pressed("tap_rock", down) and not _shared_button("tap_rock", "callout")):
		actions.append([ActionRecord.Kind.TAP_ROCK, 0, record.facing])
	if Variants.flag(down.get("__tap_pocket_book", false)) or (_pressed("pocket_book", down) and not _shared_button("pocket_book", "check_lamp")):
		pocket_book_presses += 1
	if context == InputContexts.Context.MINE and ring_options.is_empty():
		for pair: Array in WHEELS:
			var action: String = pair[0]
			if _pressed(action, down):
				var kind: int = pair[1]
				wheel.open(action, kind, now, carrying and action == "callout")
				wheel.timing = action == "callout" and store.callout_timing
				wheel.combined = action == "signal_wheel" and _same_specs("signal_wheel", "chalk_wheel")
				context = InputContexts.Context.WHEEL
				break
	if context != InputContexts.Context.WHEEL:
		return
	wheel.update(pick_vec)
	if Variants.flag(down.get(wheel.button, false)):
		return
	# Released: pick, or cancel when centred (a quick centred release of a shared LB is the rock).
	context = InputContexts.Context.MINE
	var pick: Dictionary = wheel.pick()
	if wheel.button == "callout":
		var gap: float = wheel.opened_at - _last_callout_release
		_last_callout_release = now
		if pick.is_empty():
			if wheel.timing and now - wheel.opened_at < Tuning.f(&"movement.input_tap_max") - 1e-6 \
					and _shared_button("tap_rock", "callout"):
				actions.append([ActionRecord.Kind.TAP_ROCK, 0, record.facing])
			return
		if wheel.timing:
			var hold_ms: int = roundi((now - wheel.opened_at) * 1000.0)
			var gap_ms: int = roundi(gap * 1000.0) if gap <= store.shout_window_s + 1e-6 else -1
			actions.append([wheel.kind, Intents.wheel_arg_timing(hold_ms, gap_ms), _aim(pick)])
			return
	if pick.is_empty():
		return
	var arg: int = Intents.wheel_arg_distance(Variants.number(pick["distance"]))
	if wheel.combined:
		arg |= Intents.COMBINED_FLAG
	actions.append([wheel.kind, arg, _aim(pick)])


## The interact ring while the server has it open (MNR-05): the mouse or stick points at an option,
## and an interact press there sends the RING_CHOICE (the index in the options sent); holding on
## performs it, as the server reads the held bit.
func _ring(down: Dictionary, pick_vec: Vector2) -> void:
	if ring_options.is_empty():
		return
	ring_wheel.update(pick_vec)
	if not _pressed("interact", down):
		return
	var pick: Dictionary = ring_wheel.pick()
	if pick.is_empty():
		return
	var index: int = WheelInput.slice(Variants.number(pick["angle_deg"]), ring_options.size())
	actions.append([ActionRecord.Kind.RING_CHOICE, index, _aim(pick)])


func _aim(pick: Dictionary) -> int:
	return Intents.facing_u16(Variants.number(pick["angle_deg"]))


func _same_specs(a: String, b: String) -> bool:
	return store.specs(a, family) == store.specs(b, family)


## Held bits, each through its hold-or-toggle latch. Squint becomes aim with the revolver drawn.
func _holds(down: Dictionary) -> void:
	var bits: int = 0
	var aiming: bool = _latch("squint", Variants.flag(down.get("squint", false)))
	# The pad's RT both uses the slot and fires: with the revolver drawn and aimed it only fires.
	if revolver_drawn and aiming and _same_specs("use", "fire"):
		down["use"] = false
	for raw: Variant in HELD.keys():
		var action: String = str(raw)
		if _latch(action, Variants.flag(down.get(action, false))):
			bits |= int(Variants.number(HELD[raw]))
	# The pad's A tapped with a lamp or candle in hand and nothing identified starts set down or
	# hang; moving or a second tap cancels it (§4.8, Proposed).
	if Variants.flag(down.get("__tap_set_down", false)) and not target_in_reach:
		_set_down_latched = lamp_in_hand and not _set_down_latched
	if _set_down_latched:
		bits |= InputRecord.HOLD_SET_DOWN
	if aiming:
		bits |= InputRecord.HOLD_AIM if revolver_drawn else InputRecord.HOLD_SQUINT
	record.holds = bits


## The shutter flips, the wick steps, the slot is chosen: all sent as state (InputRecord.desired),
## so a lost packet never loses a press.
func _lamp_and_slot(down: Dictionary) -> void:
	var closed: int = record.desired & 1
	var wick: int = (record.desired >> 1) & 3
	if _pressed("shutter", down):
		closed ^= 1
	if _pressed("wick_up", down):
		wick = mini(wick + 1, 2)
	if _pressed("wick_down", down):
		wick = maxi(wick - 1, 0)
	var slot: int = record.selected_slot()
	for i: int in 4:
		if _pressed("slot_%d" % (i + 1), down):
			slot = i
	if _pressed("slot_next", down):
		slot = (slot + 1) % 4
	if _pressed("slot_prev", down):
		slot = (slot + 3) % 4
	record.desired = closed | (wick << 1)
	record.set_selected_slot(slot)


## Left mouse (or RT) does nothing in the mine unless the revolver is drawn and aimed (§4.8 rule 6).
func _fire(down: Dictionary) -> void:
	if _pressed("fire", down) and revolver_drawn and (record.holds & InputRecord.HOLD_AIM) != 0:
		actions.append([ActionRecord.Kind.TRIGGER, 0, record.facing])


func _latch(action: String, is_down: bool) -> bool:
	if not _latches.has(action):
		_latches[action] = HoldLatch.new()
	var l: HoldLatch = _latches[action]
	l.toggle = store.is_toggle(action)
	return l.sample(is_down)


func _pressed(action: String, down: Dictionary) -> bool:
	return Variants.flag(down.get(action, false)) and not Variants.flag(_prev.get(action, false))


## This frame's state for the next frame's edges; an action the frame leaves out is up.
func _remember(down: Dictionary) -> void:
	for raw: Variant in _prev.keys():
		if not str(raw).begins_with("__pair_") and not down.has(raw):
			_prev[raw] = false
	for raw: Variant in down.keys():
		var action: String = str(raw)
		if not action.begins_with("__"):
			_prev[action] = Variants.flag(down[raw])
