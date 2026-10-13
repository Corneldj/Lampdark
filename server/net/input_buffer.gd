class_name InputBuffer
extends RefCounted
## One client's inputs on the server (NET-03). Each tick consumes exactly one input: the next
## sequence number, kept `target` ticks behind the newest received so a lost packet's redundant
## copy still arrives in time. The first input (and the first after a stop) applies at once and
## is then held for `target` ticks while that depth builds. A missing input repeats the held state (never a one-shot action);
## after net.input_repeat_ms of repeats the miner stops, with `starved_now` set once. The next
## input to arrive resumes the miner from the newest record, older buffered ones discarded.
## One-shot actions apply exactly once, in order of action_seq (the client starts at 0).

## What one tick consumed.
class Consumed:
	extends RefCounted
	var record: InputRecord
	## The tick the client was showing for this input (clamped to plausible), for NET-06.
	var shown_tick: int = 0
	## False for a repeat or a stop.
	var real: bool = false
	var starved: bool = false
	## Set on the tick starvation begins, and on the tick input resumes.
	var starved_now: bool = false
	var resumed_now: bool = false
	## One-shot actions to apply this tick, in order, each exactly once.
	var actions: Array[ActionRecord] = []
	## NET-06: cue reports [cue_id, shown_tick, fraction] first received since the last tick, each once.
	var cue_reports: Array[PackedInt64Array] = []
	## NET-06: the newest frame tick the packet carrying this input acknowledged, -1 if none.
	var acked_frame: int = -1


## How far ahead of the next action an action may be and still be held.
const ACTION_WINDOW: int = 256

var target: int = 1
var max_ahead: int = 8
var repeat_limit: int = 4
var started: bool = false
var starved: bool = false

## Counters for NET-13 and the probes.
var real_count: int = 0
var repeat_count: int = 0
## Packets whose newest input had already been consumed.
var dropped_old: int = 0
var dropped_ahead: int = 0
var invalid: int = 0
var clamped_stamps: int = 0
var dropped_actions: int = 0
## Runs of repeats that ended with a real input again (a gap in the client's inputs), their
## total ticks, and how often the miner was stopped.
var gaps: int = 0
var gap_ticks: int = 0
var starved_count: int = 0
var invalid_actions: int = 0

var _ring: Dictionary = {}
var _stamps: Dictionary = {}
var _next: int = 0
var _held: InputRecord = InputRecord.new()
var _held_stamp: int = 0
var _repeats: int = 0
## After a resume: the newest record to apply now, then ticks to hold it while depth rebuilds.
var _resume_record: InputRecord = null
var _resume_stamp: int = 0
var _rebuild: int = 0
## Set while the session's first input is pending (so it is not reported as a resume).
var _first: bool = true
var _next_action: int = 0
var _waiting_actions: Dictionary = {}
## NET-06: cue ids reported so far, reports waiting for the next tick, and seq -> acked frame.
var _cues_seen: Dictionary = {}
var _new_cues: Array[PackedInt64Array] = []
var _acks: Dictionary = {}
var _held_ack: int = -1


func _init() -> void:
	if Tuning.current.has_key(&"net.input_buffer_target_ticks"):
		target = Tuning.i(&"net.input_buffer_target_ticks")
		max_ahead = Tuning.i(&"net.input_buffer_max_ticks")
		repeat_limit = roundi(Tuning.f(&"net.input_repeat_ms") / (1000.0 / Tuning.f(&"net.tick_hz")))


## Takes a packet. now_tick is the server tick; newest_frame_tick the newest frame sent to this
## client; plausible_ticks how far back a stamp may lie (RTT + interpolation + grace, in ticks).
func receive(packet: InputPacket, now_tick: int, newest_frame_tick: int, plausible_ticks: int) -> void:
	_take_actions(packet)
	for c: PackedInt64Array in packet.cue_reports:
		if not _cues_seen.has(c[0]):
			_cues_seen[c[0]] = true
			_new_cues.append(c)
	if packet.inputs.is_empty():
		return
	if newest_frame_tick >= 0:
		_acks[packet.inputs[0].seq] = now_tick - ((now_tick - packet.ack_frame) & 0xFFFF)
	var shown: int = packet.shown_tick
	var lowest: int = now_tick - plausible_ticks
	if shown > newest_frame_tick or shown < lowest:
		shown = clampi(shown, lowest, maxi(newest_frame_tick, lowest))
		clamped_stamps += 1
	if starved:
		var newest: InputRecord = packet.inputs[0]
		if not newest.is_valid():
			invalid += 1
			return
		starved = false
		_ring.clear()
		_stamps.clear()
		_resume_record = newest
		_resume_stamp = shown - newest.shown_delta
		_rebuild = target
		_next = (packet.newest_seq + 1) & 0xFFFF
		return
	if not started:
		var first: InputRecord = packet.inputs[0]
		if not first.is_valid():
			invalid += 1
			return
		started = true
		_resume_record = first
		_resume_stamp = shown - first.shown_delta
		_rebuild = target
		_next = (packet.newest_seq + 1) & 0xFFFF
		return
	for r: InputRecord in packet.inputs:
		if not r.is_valid():
			invalid += 1
			continue
		var ahead: int = InputPacket.seq_diff(r.seq, _next)
		if ahead < 0:
			# Older redundant copies are expected; only a packet whose newest input was already
			# consumed counts as late.
			if r == packet.inputs[0]:
				dropped_old += 1
			continue
		if ahead > max_ahead:
			dropped_ahead += 1
			continue
		if not _ring.has(r.seq):
			_ring[r.seq] = r
			_stamps[r.seq] = shown - r.shown_delta


## Once per tick (NET-01 stage 2). Returns null until the first input arrives.
func consume() -> Consumed:
	if not started:
		return null
	var out: Consumed = _consume()
	out.cue_reports = _new_cues
	_new_cues = []
	if out.real:
		_held_ack = int(Variants.number(_acks.get(out.record.seq, _held_ack)))
		for key: Variant in _acks.keys():
			if InputPacket.seq_diff(int(Variants.number(key)), out.record.seq) <= 0:
				_acks.erase(key)
	out.acked_frame = _held_ack
	return out


func _consume() -> Consumed:
	var out: Consumed = Consumed.new()
	if starved:
		_repeats += 1
		out.record = _held.stopped()
		out.starved = true
		out.shown_tick = _held_stamp
		return out
	if _resume_record != null:
		_held = _resume_record
		_held_stamp = _resume_stamp
		_resume_record = null
		if not _first:
			gaps += 1
			gap_ticks += _repeats
		_repeats = 0
		out.record = _held
		out.real = true
		out.resumed_now = not _first
		_first = false
		real_count += 1
	elif _rebuild > 0:
		# Hold the first or resumed input while the buffer fills to its target depth.
		_rebuild -= 1
		out.record = _held.duplicate_record()
	elif _ring.has(_next):
		_held = _ring[_next]
		_held_stamp = int(Variants.number(_stamps[_next]))
		_ring.erase(_next)
		_stamps.erase(_next)
		if _repeats > 0:
			gaps += 1
			gap_ticks += _repeats
		_repeats = 0
		out.record = _held
		out.real = true
		real_count += 1
		_next = (_next + 1) & 0xFFFF
	else:
		_repeats += 1
		repeat_count += 1
		_next = (_next + 1) & 0xFFFF
		if _repeats > repeat_limit:
			starved = true
			starved_count += 1
			_ring.clear()
			_stamps.clear()
			out.record = _held.stopped()
			out.starved = true
			out.starved_now = true
			out.shown_tick = _held_stamp
			return out
		out.record = _held.duplicate_record()
	out.shown_tick = _held_stamp
	while _waiting_actions.has(_next_action):
		var action: ActionRecord = _waiting_actions[_next_action]
		# An invalid action still uses up its sequence number, so later ones are not stalled.
		if action.is_valid():
			out.actions.append(action)
		else:
			invalid_actions += 1
		_waiting_actions.erase(_next_action)
		_next_action = (_next_action + 1) & 0xFFFF
	return out


## The seq of the input applied last (a repeat or a stop reports the input it repeats), or
## 0xFFFF before the first; the frame header carries it for NET-05's reconciliation.
func applied_seq() -> int:
	return _held.seq if started and _resume_record == null and real_count > 0 else 0xFFFF


## Inputs buffered at or after the next one to consume (reported in the frame header).
func depth() -> int:
	var n: int = 0
	for key: Variant in _ring.keys():
		if InputPacket.seq_diff(int(Variants.number(key)), _next) >= 0:
			n += 1
	return n


## The newest one-shot action applied, 0xFFFF before the first (for the frame header).
func action_ack() -> int:
	return (_next_action - 1) & 0xFFFF


func _take_actions(packet: InputPacket) -> void:
	for a: ActionRecord in packet.actions:
		var ahead: int = InputPacket.seq_diff(a.action_seq, _next_action)
		if ahead < 0 or _waiting_actions.has(a.action_seq):
			continue
		if ahead >= ACTION_WINDOW:
			dropped_actions += 1
			continue
		_waiting_actions[a.action_seq] = a
