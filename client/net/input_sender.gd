class_name ClientInputSender
extends RefCounted
## The client half of NET-03: one input per client tick, sent with the previous
## net.input_redundancy inputs, the frame acknowledgements NET-04 needs, and every one-shot
## action until a frame header acknowledges it. A record holds actions, never devices, so every
## input method (Steam Input, the Deck, keyboard and mouse) produces the same packets.

## How many inputs to keep for redundancy and NET-05's reconciliation.
const HISTORY: int = 64

var redundancy: int = 3
var next_seq: int = 0
var next_action_seq: int = 0
## [cue_id, shown_tick, fraction] reports NET-06 fills (report_cue). The frame header has no
## acknowledgement for them, so each rides in REPORT_SENDS packets, like an input's redundant
## copies; if all are lost the server estimates the time instead.
const REPORT_SENDS: int = 8
var cue_reports: Array[PackedInt64Array] = []
var _report_sends: PackedInt32Array = PackedInt32Array()
## The frame header's view of this client's server buffer (NET-05 nudges its clock by it).
var server_depth: int = 0
var packets_sent: int = 0

var _history: Array[InputRecord] = []
var _history_shown: PackedInt64Array = PackedInt64Array()
var _actions: Array[ActionRecord] = []
var _newest_frame: int = -1
var _newest_frame_usec: int = 0
var _frames_seen: Dictionary = {}


func _init() -> void:
	if Tuning.current.has_key(&"net.input_redundancy"):
		redundancy = Tuning.i(&"net.input_redundancy")


## Records this tick's input, stamped with the tick the client was showing. Returns its seq.
func sample(record: InputRecord, shown_tick: int) -> int:
	var r: InputRecord = record.duplicate_record()
	r.seq = next_seq
	next_seq = (next_seq + 1) & 0xFFFF
	_history.push_front(r)
	_history_shown.insert(0, shown_tick)
	if _history.size() > HISTORY:
		_history.resize(HISTORY)
		_history_shown.resize(HISTORY)
	return r.seq


## Queues a one-shot action (callout, signal, chalk, ring choice, trigger with its tick and aim).
func queue_action(kind: ActionRecord.Kind, arg: int = 0, tick: int = 0, aim: int = 0) -> int:
	var a: ActionRecord = ActionRecord.new()
	a.action_seq = next_action_seq
	a.kind = kind
	a.arg = arg
	a.tick = tick
	a.aim = aim
	next_action_seq = (next_action_seq + 1) & 0xFFFF
	_actions.append(a)
	return a.action_seq


## NET-06: the cue `cue_id` was presented at this shown tick and fraction.
func report_cue(cue_id: int, shown_tick: int, shown_fraction: int) -> void:
	cue_reports.append(PackedInt64Array([cue_id, shown_tick, shown_fraction]))
	_report_sends.append(REPORT_SENDS)


## One-shot actions not yet acknowledged.
func pending_actions() -> Array[ActionRecord]:
	return _actions


## A frame arrived: note it for the acknowledgements and drop the actions it acknowledges.
func on_frame(tick: int, action_ack: int, input_depth: int, now_usec: int) -> void:
	_frames_seen[tick] = true
	if tick > _newest_frame:
		_newest_frame = tick
		_newest_frame_usec = now_usec
		server_depth = input_depth
		for key: Variant in _frames_seen.keys():
			if int(Variants.number(key)) < _newest_frame - 32:
				_frames_seen.erase(key)
	while not _actions.is_empty() and InputPacket.seq_diff(action_ack, _actions[0].action_seq) >= 0:
		_actions.remove_at(0)


## The packet for the newest input: it and up to `redundancy` before it.
func build_packet(shown_tick: int, shown_fraction: int, now_usec: int) -> InputPacket:
	var p: InputPacket = InputPacket.new()
	if _newest_frame >= 0:
		p.ack_frame = _newest_frame & 0xFFFF
		var bits: int = 0
		for i: int in 32:
			if _frames_seen.has(_newest_frame - 1 - i):
				bits |= 1 << i
		p.ack_bits = bits
		p.recv_delay = clampi((now_usec - _newest_frame_usec) / 2000, 0, 255)
	p.shown_tick = shown_tick
	p.shown_fraction = shown_fraction
	if not _history.is_empty():
		p.newest_seq = _history[0].seq
		for i: int in mini(redundancy + 1, _history.size()):
			var r: InputRecord = _history[i].duplicate_record()
			r.shown_delta = clampi(shown_tick - _history_shown[i], 0, 255)
			p.inputs.append(r)
	p.actions = _actions.duplicate()
	p.cue_reports = cue_reports.duplicate()
	for i: int in range(cue_reports.size() - 1, -1, -1):
		_report_sends[i] -= 1
		if _report_sends[i] <= 0:
			cue_reports.remove_at(i)
			_report_sends.remove_at(i)
	return p


## Samples, builds and sends in one step: what the client does once per tick.
func send_tick(connection: ClientConnection, record: InputRecord, shown_tick: int, shown_fraction: int = 0) -> Error:
	sample(record, shown_tick)
	var packet: InputPacket = build_packet(shown_tick, shown_fraction, Transport.now_usec())
	var error: Error = connection.send_raw(Lane.Id.INPUTS, packet.encode())
	if error == OK:
		packets_sent += 1
	return error
