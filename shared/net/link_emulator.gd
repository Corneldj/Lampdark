class_name LinkEmulator
extends LinkFilter
## NET-12's network emulator: a NET-02 TransportFilter on one connection that reproduces a link.
## Per direction (up: what this end sends; down: what it receives): half the RTT each way, +- a
## uniform jitter, and loss, either independent (`loss`) or bursty (a Gilbert-Elliott chain: good
## and bad states with their own loss, and the chances of switching each packet). Duplication is
## off by default. Reliable lanes are delayed in order and never dropped or duplicated (the
## transport under it already made them reliable); unreliable lanes may reorder through the
## jitter. A timeline scripts changes over time (an outage: loss 1 for 10 s), for NET-10 and NET-11.
## Uses Transport.now_usec, so it runs on the wall clock or the kit's virtual clock alike.

class Direction:
	extends RefCounted
	var delay_ms: float = 0.0
	var jitter_ms: float = 0.0
	var loss: float = 0.0
	var duplicate: float = 0.0
	## Gilbert-Elliott: when burst is set, loss is loss_good in the good state, loss_bad in the bad.
	var burst: bool = false
	var p_good_to_bad: float = 0.0
	var p_bad_to_good: float = 1.0
	var loss_good: float = 0.0
	var loss_bad: float = 1.0
	var in_bad: bool = false
	var sent: int = 0
	var dropped: int = 0
	var duplicated: int = 0

	func lose(rng: LbRng) -> bool:
		if not burst:
			return rng.unit_double() < loss
		if in_bad:
			if rng.unit_double() < p_bad_to_good:
				in_bad = false
		elif rng.unit_double() < p_good_to_bad:
			in_bad = true
		return rng.unit_double() < (loss_bad if in_bad else loss_good)

	func delay_usec(rng: LbRng) -> int:
		return roundi((delay_ms + (rng.unit_double() * 2.0 - 1.0) * jitter_ms) * 1000.0)


var up: Direction = Direction.new()
var down: Direction = Direction.new()
## [{at_s, up?: {field: value}, down?: {...}, both?: {...}}] applied in order as time passes.
var timeline: Array[Dictionary] = []
## FND-06's seeded stream: a link replays the same losses for the same seed.
var _rng: LbRng = LbRng.from_seed(1)
var _started_usec: int = -1
var _next_event: int = 0
## [due_usec, order, peer, lane, bytes] going out; [due_usec, order, event] coming in.
var _out: Array[Array] = []
var _in: Array[Array] = []
var _order: int = 0
## lane -> the latest due time given on it (reliable lanes keep their order).
var _last_due_out: Dictionary = {}
var _last_due_in: Dictionary = {}


func _init(wrapped: Transport, link_rtt_ms: int = 0, link_loss_pct: float = 0.0, seed_value: int = 1) -> void:
	super(wrapped, link_rtt_ms, link_loss_pct)
	_rng = LbRng.from_seed(seed_value)
	pass_through = false
	configure(link_rtt_ms, link_loss_pct)


## The plain link: `rtt_ms` round trip, `loss_pct` percent independent loss each way, and
## net.emu_jitter_ms of jitter each way when a delay is set.
func configure(link_rtt_ms: int, link_loss_pct: float) -> void:
	super(link_rtt_ms, link_loss_pct)
	if up == null:
		return
	var jitter: float = Tuning.f(&"net.emu_jitter_ms") if link_rtt_ms > 0 and Tuning.current.has_key(&"net.emu_jitter_ms") else 0.0
	for d: Direction in [up, down]:
		d.delay_ms = link_rtt_ms / 2.0
		d.jitter_ms = minf(jitter, link_rtt_ms / 2.0)
		d.loss = link_loss_pct / 100.0
		d.burst = false


## Bursty loss each way: the long-run loss is p_gb / (p_gb + p_bg) x loss_bad (+ the good share).
func set_burst(p_good_to_bad: float, p_bad_to_good: float, loss_bad: float = 1.0, loss_good: float = 0.0) -> void:
	for d: Direction in [up, down]:
		d.burst = true
		d.p_good_to_bad = p_good_to_bad
		d.p_bad_to_good = p_bad_to_good
		d.loss_bad = loss_bad
		d.loss_good = loss_good


func filter_send(peer: int, lane: int, data: PackedByteArray) -> Error:
	_advance_timeline()
	up.sent += 1
	if not Lane.is_reliable(lane) and up.lose(_rng):
		up.dropped += 1
		return OK
	var copies: int = 2 if not Lane.is_reliable(lane) and _rng.unit_double() < up.duplicate else 1
	if copies == 2:
		up.duplicated += 1
	for _c: int in copies:
		var due: int = _due(up, lane, _last_due_out)
		_out.append([due, _order, peer, lane, data])
		_order += 1
	_release_out()
	return OK


func filter_receive(events: Array[TransportEvent]) -> Array[TransportEvent]:
	_advance_timeline()
	_release_out()
	var out: Array[TransportEvent] = []
	for event: TransportEvent in events:
		if event.kind != TransportEvent.Kind.MESSAGE:
			out.append(event)
			continue
		down.sent += 1
		if not Lane.is_reliable(event.lane) and down.lose(_rng):
			down.dropped += 1
			continue
		var copies: int = 2 if not Lane.is_reliable(event.lane) and _rng.unit_double() < down.duplicate else 1
		if copies == 2:
			down.duplicated += 1
		for _c: int in copies:
			_in.append([_due(down, event.lane, _last_due_in), _order, event])
			_order += 1
	var now: int = Transport.now_usec()
	_in.sort_custom(_earlier)
	var waiting: Array[Array] = []
	for item: Array in _in:
		if int(Variants.number(item[0])) <= now:
			var e: TransportEvent = item[2]
			out.append(e)
		else:
			waiting.append(item)
	_in = waiting
	return out


func flush() -> void:
	_release_out()
	super()


func _due(d: Direction, lane: int, last: Dictionary) -> int:
	var due: int = Transport.now_usec() + maxi(0, d.delay_usec(_rng))
	if Lane.is_reliable(lane):
		due = maxi(due, int(Variants.number(last.get(lane, 0))))
		last[lane] = due
	return due


func _release_out() -> void:
	var now: int = Transport.now_usec()
	_out.sort_custom(_earlier)
	var waiting: Array[Array] = []
	for item: Array in _out:
		if int(Variants.number(item[0])) <= now:
			var bytes: PackedByteArray = item[4]
			inner.send(int(Variants.number(item[2])), int(Variants.number(item[3])), bytes)
		else:
			waiting.append(item)
	_out = waiting


static func _earlier(a: Array, b: Array) -> bool:
	var at_a: int = int(Variants.number(a[0]))
	var at_b: int = int(Variants.number(b[0]))
	return at_a < at_b or (at_a == at_b and int(Variants.number(a[1])) < int(Variants.number(b[1])))


func _advance_timeline() -> void:
	var now: int = Transport.now_usec()
	if _started_usec < 0:
		_started_usec = now
	while _next_event < timeline.size():
		var ev: Dictionary = timeline[_next_event]
		if now - _started_usec < roundi(float(Variants.number(ev.get("at_s", 0.0))) * 1000000.0):
			break
		for which: String in ["up", "down", "both"]:
			if not ev.has(which):
				continue
			for d: Direction in ([up, down] if which == "both" else ([up] if which == "up" else [down])):
				var change: Dictionary = Variants.dict(ev[which])
				for key: Variant in change.keys():
					d.set(str(key), change[key])
		_next_event += 1
