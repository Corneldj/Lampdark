class_name Switchboard
extends SimSystem
## LFT-13 (Gameplay §6.6, §4.10, §3.5, §6.4, §9.2, §13.6, §13.9, §13.11, §14.3, A.3, A.6; GDD §14.2):
## base camp's switchboard, the only voice across the mine. Dead until Power (LFT-05's board_wakes),
## and under Dead Lines there is none (no fixture, no seat). Whoever sits at it (UI-02's seat,
## CloseupState: 2 s, never a Hired Hand) is the operator, and works it from its close-up:
## - **The drops:** a crank on a live line (LFT-12's `calling`) drops its numbered flap, and the
##   buzzer (noise.buzzer_np) sounds at the board, again every phones.buzzer_repeat_s while the flap
##   is down and unanswered (Proposed). Nothing answers but a human; with nobody seated it buzzes on.
##   A caller who leaves puts the flap up; a cut line's flap is dark for the run.
## - **The cord** is in one line at a time. Plugging a calling or held line connects it (LFT-12's
##   answer or resume: voice both ways), holding the call it was in; plugging the cord's own line
##   pulls it (the call ends). Holding leaves the caller on the line in hiss (any number may be held,
##   Proposed). Ringing sounds a live line's bell (LFT-12's ring); a dark or unassigned number
##   rings nothing. A call the operator leaves (unseated by a fall, a grab, a drop, standing) is held,
##   and a line they rang, answered after they left, reaches the board as a call (Proposed).
## - **It never patches:** a line joins one phone to the headset (LFT-12 refuses anything else).
## The operator's client alone hears the board (Protocol.Msg.BOARD: flaps, cord and whether it is
## awake; never a phone's place, the number-to-phone mapping, who calls or why a line went dark);
## anyone seeing the cabinet at 0.30 sees it awake and how many flaps are really down (its FIXTURE's
## bits), never an illusion's drop (CRT-11 shows those to the operator alone). Server-only.

enum Line { IDLE = 0, CALLING = 1, CONNECTED = 2, HELD = 3, DARK = 4 }

## number -> Line (absent: IDLE).
var lines: Dictionary = {}
## The line the cord is in (0: none).
var cord: int = 0
## The cabinet's FIXTURE entity (0: none, as under Dead Lines).
var fixture: int = 0
## {tick, what, number, ...}: drops, plugs, holds, rings, buzzers.
var history: Array[Dictionary] = []
## number -> the tick its buzzer sounds again.
var _buzz: Dictionary = {}
var _operator: int = 0
var _sent: PackedByteArray = PackedByteArray()
var _sent_to: int = -1
var _shown: int = -1
var _board_tile: Vector2i = Vector2i(-1, -1)
var _net: ServerNet = null


func stage() -> int:
	return StageTable.Stage.WORLD


func order() -> int:
	return 66


func system_name() -> String:
	return "switchboard"


## Hashed while any line is in use, so a run with a quiet board hashes as before.
func hashed() -> bool:
	return not lines.is_empty() or cord != 0


func bind(run: RunState, net: ServerNet) -> void:
	_net = net
	if run.phones != null:
		run.phones.calling.connect(func(n: int, _miner: int) -> void: _on_calling(run, n))
		run.phones.answered.connect(func(n: int, _by: int) -> void: _on_answered(run, n))
		run.phones.ended.connect(func(n: int, _why: String) -> void: _on_ended(n))
		run.phones.line_cut.connect(func(n: int) -> void: _on_cut(n))


## The board stands in base camp unless the run is Dead Lines.
static func exists(run: RunState) -> bool:
	return run.power == null or not run.power.dead_lines


static func awake(run: RunState) -> bool:
	return exists(run) and run.power != null and run.power.board_wakes()


## The operator's ear hisses: the cord in a line with no call on it.
func hiss_for(run: RunState, miner: int) -> bool:
	return miner != 0 and run.closeups != null and run.closeups.operator() == miner and cord != 0 \
		and int(Variants.number(lines.get(cord, Line.IDLE))) != Line.CONNECTED


func line_of(number: int) -> Line:
	return int(Variants.number(lines.get(number, Line.IDLE))) as Line


#region The operator's hands

## The operator's ask (BoardWire): PLUG a line, PULL the cord, HOLD the call, RING a line.
func ask(run: RunState, arg: int) -> void:
	if not awake(run):
		return
	var slot: int = _operator_slot(run)
	if slot < 0:
		return
	var n: int = BoardWire.number_of(arg)
	match BoardWire.verb_of(arg):
		BoardWire.Verb.PLUG:
			if n == cord:
				pull(run)
			elif n >= 1:
				plug(run, n, slot)
		BoardWire.Verb.PULL:
			pull(run)
		BoardWire.Verb.HOLD:
			hold(run)
		BoardWire.Verb.RING:
			if n >= 1:
				var rang: bool = run.phones != null and run.phones.ring(run, n, slot)
				history.append({"tick": run.tick, "what": "ring", "number": n, "rang": rang})


## Into line `n`: a calling or held call connects; the call the cord was in is held first.
func plug(run: RunState, n: int, slot: int) -> void:
	hold(run)
	match line_of(n):
		Line.CALLING:
			if run.phones.answer(run, n, slot):
				lines[n] = Line.CONNECTED
				_buzz.erase(n)
		Line.HELD:
			if run.phones.resume(run, n, slot):
				lines[n] = Line.CONNECTED
	cord = n
	history.append({"tick": run.tick, "what": "plug", "number": n, "line": line_of(n)})


## The cord out: the call it was in ends.
func pull(run: RunState) -> void:
	if cord == 0:
		return
	var n: int = cord
	cord = 0
	if line_of(n) == Line.CONNECTED and run.phones != null:
		run.phones.hang_up(run, n)
	history.append({"tick": run.tick, "what": "pull", "number": n})


## The call the cord is in, held: the caller waits on the line in hiss; the cord comes free.
func hold(run: RunState) -> void:
	if cord == 0 or line_of(cord) != Line.CONNECTED:
		return
	if run.phones != null and run.phones.hold(run, cord):
		lines[cord] = Line.HELD
		history.append({"tick": run.tick, "what": "hold", "number": cord})
	cord = 0

#endregion

#region LFT-12's lines

func _on_calling(run: RunState, n: int) -> void:
	if not awake(run):
		return
	lines[n] = Line.CALLING
	_buzz[n] = run.tick
	history.append({"tick": run.tick, "what": "drop", "number": n})


## A line the operator rang, answered at the wall: the cord goes to it, holding the call it was in.
func _on_answered(run: RunState, n: int) -> void:
	if cord != n:
		hold(run)
	lines[n] = Line.CONNECTED
	cord = n
	_buzz.erase(n)
	history.append({"tick": run.tick, "what": "answered", "number": n})


func _on_ended(n: int) -> void:
	_buzz.erase(n)
	if line_of(n) == Line.DARK:
		return
	lines.erase(n)


func _on_cut(n: int) -> void:
	_buzz.erase(n)
	lines[n] = Line.DARK

#endregion

func tick(run: RunState) -> void:
	_ensure_fixture(run)
	var op: int = run.closeups.operator() if run.closeups != null else 0
	if op != _operator:
		# The seat changed hands (or emptied): a call the operator left is held, and a line they rang
		# answers to the board as a call.
		hold(run)
		cord = 0
		if run.phones != null:
			run.phones.forget_rings()
		_operator = op
	if op != 0:
		var slot: int = _operator_slot(run)
		var c: InputBuffer.Consumed = run.input_for(slot) if slot >= 0 else null
		if c != null and not _hand(run, op):
			for a: ActionRecord in c.actions:
				if a.kind == ActionRecord.Kind.BOARD:
					ask(run, a.arg)
	_buzzers(run)
	_send(run)
	_show(run)


func _buzzers(run: RunState) -> void:
	if run.noise == null or fixture == 0:
		return
	var repeat: int = maxi(1, roundi(Tuning.f(&"phones.buzzer_repeat_s") * Tuning.f(&"net.tick_hz")))
	var ids: Array = _buzz.keys()
	ids.sort()
	for raw: Variant in ids:
		var n: int = int(Variants.number(raw))
		if line_of(n) != Line.CALLING:
			_buzz.erase(n)
			continue
		if run.tick >= int(Variants.number(_buzz[n])):
			run.noise.emit(NoiseTypes.Type.BUZZER, _board_tile)
			_buzz[n] = run.tick + repeat
			history.append({"tick": run.tick, "what": "buzz", "number": n})


## The board as the operator sees it, to the operator's client alone, when it changes.
func view(run: RunState) -> PackedByteArray:
	var flaps: PackedByteArray = PackedByteArray()
	flaps.resize(BoardWire.DROPS)
	var on: bool = awake(run)
	for i: int in BoardWire.DROPS:
		var f: int = BoardWire.Flap.UP
		if on:
			match line_of(i + 1):
				Line.CALLING:
					f = BoardWire.Flap.DOWN
				Line.HELD:
					f = BoardWire.Flap.HELD
				Line.DARK:
					f = BoardWire.Flap.DARK
		flaps[i] = f
	return BoardWire.encode(on, cord if on else 0, flaps)


func _send(run: RunState) -> void:
	if _net == null:
		return
	var slot: int = _operator_slot(run)
	if slot < 0:
		_sent_to = -1
		return
	var now: PackedByteArray = view(run)
	if slot == _sent_to and now == _sent:
		return
	for session: Sessions.Session in _net.sessions.welcomed():
		if session.slot == slot:
			_net.transport.send(session.peer, Lane.Id.CONTROL, Protocol.frame(Protocol.Msg.BOARD, now))
	_sent = now
	_sent_to = slot


## The cabinet in base camp, where the seat faces (none under Dead Lines).
func _ensure_fixture(run: RunState) -> void:
	if fixture != 0 or run.base_camp == null or not exists(run):
		return
	var seats: Array[Dictionary] = Basecamp.fixture(run.base_camp.seed_value, "switchboard_seat", run.base_camp.side)
	if seats.is_empty():
		return
	var seat: Vector2i = seats[0]["position"]
	var facing: Dictionary = {"N": Vector2i(0, -1), "E": Vector2i(1, 0), "S": Vector2i(0, 1), "W": Vector2i(-1, 0)}
	var ahead: Vector2i = facing.get(str(seats[0]["facing"]), Vector2i.ZERO)
	_board_tile = seat + ahead
	fixture = run.registry.create(WorldIds.EntityKind.FIXTURE, Vector2(_board_tile) + Vector2(0.5, 0.5)).id


## Its FIXTURE bits: awake, and how many flaps are really down.
func _show(run: RunState) -> void:
	if fixture == 0 or run.replication == null:
		return
	var down: int = 0
	for raw: Variant in lines.keys():
		if int(Variants.number(lines[raw])) == Line.CALLING:
			down += 1
	var bits: int = FixtureKinds.switchboard(awake(run), down)
	if bits != _shown:
		run.replication.native.set_entity_held(fixture, bits)
		_shown = bits


func _operator_slot(run: RunState) -> int:
	if _operator == 0 or run.movement == null:
		return -1
	for slot: int in run.movement.miner_slots():
		if run.movement.miner(slot).entity_id == _operator:
			return slot
	return -1


static func _hand(run: RunState, miner: int) -> bool:
	return run.crew != null and Variants.flag(run.crew.is_hand_driven.call(miner))


func write_state(writer: SimStateWriter) -> void:
	writer.put_i64(cord)
	var ids: Array = lines.keys()
	ids.sort()
	writer.put_i64(ids.size())
	for raw: Variant in ids:
		writer.put_i64(int(Variants.number(raw)))
		writer.put_i32(int(Variants.number(lines[raw])))


## The dark lines are kept (a cut is for the run); calls are not (a resumed board is quiet).
func save_state() -> Dictionary:
	var dark: Array = []
	for raw: Variant in lines.keys():
		if int(Variants.number(lines[raw])) == Line.DARK:
			dark.append(int(Variants.number(raw)))
	dark.sort()
	return {"dark": dark}


func load_state(_run: RunState, state: Dictionary) -> void:
	lines.clear()
	for raw: Variant in Variants.array(state.get("dark", [])):
		lines[int(Variants.number(raw))] = Line.DARK
