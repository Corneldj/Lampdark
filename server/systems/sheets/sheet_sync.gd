class_name SheetSync
extends SimSystem
## LFT-14 (stage SEND, after NET-04's frames): the map table's sheet to every conscious client
## (GDD §15.3: synced to all, shown only in the close-up). Each client is sent, reliably on the bulk
## lane, every stroke and label it does not hold and the removal of each it holds that is gone, its
## own commits accepted or dropped, and whether the sheet is full.
##
## - Pacing (Proposed): from what NET-04's per-client bucket holds after this tick's frame, less
##   net.sheet_reserve_bytes kept for the frames (sheets go last); away from the table no more than
##   net.sheet_background_kbps, at the table all that is left ("at once"). Live changes go before
##   a resync's backlog.
## - Unconscious or dead miners' clients get no sheet traffic at all; coming round, or a new
##   connection, resyncs them against what they hold.
## - A blocker is never sent the blocked player's strokes or labels, nor their strokes as made
##   (STM-08's safety lists through `blocks_of`).
## - Strokes as they are made (SKETCH) are relayed on arrival, between ticks, unreliably on the
##   frames lane and only to the other miners with the table open, under a pen number that names
##   nobody; a commit, or the drawer leaving the table, lifts the pen (PEN_UP).
## - Once the sheet freezes (the cage's departure or a wipe) every client is sent all of it, then
##   its digest (FREEZE) for the map card. Server-only.

## One client's sync.
class Client:
	extends RefCounted
	var peer: int = -1
	## id -> true: strokes and labels sent and not since removed.
	var held: Dictionary = {}
	## Ops waiting, in order: [Op, a, b] (ADD id, REMOVE id, ACCEPT seq id, DROPPED seq, PEN_UP pen, RESET).
	var queue: Array[Array] = []
	## Ids to add after the queue (a resync), ascending.
	var backlog: Array[int] = []
	var eligible: bool = false
	## The background rate's tokens (bytes).
	var background: float = 0.0
	## The FULL flag as last told (-1 unknown).
	var full_told: int = -1
	var freeze_told: bool = false
	## Identities this client's player blocks.
	var blocked: Dictionary = {}
	## Commits whose answer was waiting when the client went out of reach: dropped on its return.
	var unanswered: Array[int] = []
	## NET-04's budget over the last second: the non-voice bytes sent to the peer in each of the
	## last tick_hz - 1 ticks, and its counter at the last tick.
	var ring: Array[int] = []
	var counted: int = -1

const LIVE_LIVES: Array[int] = [MinerTransitions.Life.UPRIGHT, MinerTransitions.Life.CAUGHT, MinerTransitions.Life.GRABBED]

## STM-08's safety lists: (slot) -> the identities its player blocks. Unset: nobody is blocked.
var blocks_of: Callable = Callable()
## slot -> Client.
var clients: Dictionary = {}
## Bytes sent, for tests and the soak: slot -> bulk-lane sheet bytes, and frames-lane pen bytes.
var sent_bytes: Dictionary = {}
var pen_bytes: Dictionary = {}
## Sketch packets dropped at the relay (not at the table, over the rate, frozen, malformed).
var sketches_refused: int = 0
var _run: RunState = null
var _net: ServerNet = null
var _table: MapTable = null
## slot -> [the client's stroke number, pen]: the stroke each drawer is making.
var _pens: Dictionary = {}
var _next_pen: int = 0
## slot -> the ticks of its recent sketch packets.
var _sketch_ticks: Dictionary = {}
## slot -> the client's number of the stroke whose pen last lifted (a late packet of it is ignored).
var _lifted_seq: Dictionary = {}


func stage() -> int:
	return StageTable.Stage.SEND


func order() -> int:
	return 10


func system_name() -> String:
	return "sheet_sync"


func bind(run: RunState, net: ServerNet, table: MapTable) -> void:
	_run = run
	_net = net
	_table = table
	if run != null and net != null:
		run.add_system(self)


## A stroke or label `id` is on the sheet: its drawer (`slot`, -1 for a rub's pieces) is told it
## was accepted as `seq`, everyone else in reach that does not block its author is sent it.
func added(id: int, slot: int, seq: int) -> void:
	for raw: Variant in clients.keys():
		var c: Client = clients[raw]
		if not c.eligible:
			continue
		if int(Variants.number(raw)) == slot:
			c.queue.append([SheetCodec.Op.ACCEPT, seq, id])
		else:
			c.queue.append([SheetCodec.Op.ADD_STROKE, id, 0])
	if slot >= 0:
		_lift(slot)


## `id` is gone: everyone holding it is told.
func removed(id: int) -> void:
	for raw: Variant in clients.keys():
		var c: Client = clients[raw]
		if c.eligible and c.held.has(id):
			c.queue.append([SheetCodec.Op.REMOVE, id, 0])


## The drawer's commit `seq` marked nothing.
func dropped(slot: int, seq: int) -> void:
	var c: Client = clients.get(slot, null)
	if c != null and c.eligible:
		c.queue.append([SheetCodec.Op.DROPPED, seq, 0])
	_lift(slot)


## The client asked for the whole sheet again (its copy failed the freeze's digest).
func resync(slot: int) -> void:
	var c: Client = clients.get(slot, null)
	if c == null:
		return
	c.queue.clear()
	c.backlog.clear()
	c.held.clear()
	c.queue.append([SheetCodec.Op.RESET, 0, 0])
	c.freeze_told = false
	c.full_told = -1
	if c.eligible:
		_diff(c)


## A drawer left the table: their stroke as made ends for the others.
func left_table(slot: int) -> void:
	_lift(slot)


## NET-09's resume: every client starts afresh (they all rejoin as new connections).
func restart() -> void:
	clients.clear()
	_pens.clear()
	_lifted_seq.clear()
	_sketch_ticks.clear()


func tick(run: RunState) -> void:
	_run = run
	if _net == null:
		return
	var seen: Dictionary = {}
	for session: Sessions.Session in _net.sessions.welcomed():
		seen[session.slot] = true
		var c: Client = _client(session)
		var entity: int = _miner_of(run, session.slot)
		var now_eligible: bool = _table.frozen or (entity != 0 and run.miner_state != null
			and LIVE_LIVES.has(run.miner_state.life(entity)))
		if now_eligible and not c.eligible:
			c.eligible = true
			for seq: int in c.unanswered:
				c.queue.append([SheetCodec.Op.DROPPED, seq, 0])
			c.unanswered.clear()
			_diff(c)
		elif not now_eligible and c.eligible:
			# Out of reach: nothing more is sent; their own commits are answered on return.
			c.eligible = false
			for op: Array in c.queue:
				if int(Variants.number(op[0])) == SheetCodec.Op.ACCEPT or int(Variants.number(op[0])) == SheetCodec.Op.DROPPED:
					c.unanswered.append(int(Variants.number(op[1])))
			c.queue.clear()
			c.backlog.clear()
		if not c.eligible:
			_close_tick(c)
			continue
		_refresh_blocks(session, c)
		var full: int = 1 if _table.at_cap() else 0
		if c.full_told != full:
			c.queue.append([SheetCodec.Op.FULL, full, 0])
			c.full_told = full
		_send(run, session, c, entity)
		if _table.frozen and not c.freeze_told and c.queue.is_empty() and c.backlog.is_empty():
			c.freeze_told = true
			var msg: PackedByteArray = SheetCodec.freeze(digest_for(c), _held_count(c), run.header.run_uuid)
			_net.transport.send(session.peer, Lane.Id.BULK, Protocol.frame(Protocol.Msg.SHEET, msg))
		_close_tick(c)
	for raw: Variant in clients.keys():
		if not seen.has(raw):
			clients.erase(raw)
			_pens.erase(raw)


## The digest of the sheet as `c` should hold it (its blocks left out): the map card's check.
func digest_for(c: Client) -> int:
	if c.blocked.is_empty():
		return _table.sheet.digest()
	var view: Sheet = Sheet.new()
	for raw: Variant in _table.sheet.strokes.keys():
		var s: SheetStroke = _table.sheet.strokes[raw]
		if not _blocks(c, s.author):
			view.add_stroke(s)
	for raw: Variant in _table.sheet.labels.keys():
		var l: SheetLabel = _table.sheet.labels[raw]
		if not _blocks(c, l.author):
			view.add_label(l)
	return view.digest()


## SND-07's pattern for SKETCH, between ticks (ServerNet.service) or in its pump: the drawer's
## newest points to the others at the table at once. False only for a malformed message.
func on_sketch(slot: int, payload: PackedByteArray) -> bool:
	var ops: Array[Dictionary] = SheetCodec.decode(payload)
	if ops.size() != 1 or int(Variants.number(ops[0]["op"])) != SheetCodec.Op.SKETCH:
		return false
	if _run == null or _table.frozen or _run.closeups == null:
		sketches_refused += 1
		return true
	var entity: int = _miner_of(_run, slot)
	var points: PackedVector2Array = ops[0]["points"]
	if entity == 0 or _run.closeups.kind_of(entity) != CloseupKind.Kind.MAP_TABLE or not _sketch_window(slot) \
			or points.size() > Tuning.i(&"mine.sheet_stroke_max_points"):
		sketches_refused += 1
		return true
	var seq: int = int(Variants.number(ops[0]["seq"]))
	if int(Variants.number(_lifted_seq.get(slot, -1))) == seq:
		return true
	var pen: Array = Variants.array(_pens.get(slot, []))
	if pen.is_empty() or int(Variants.number(pen[0])) != seq:
		_lift(slot)
		_next_pen = (_next_pen % 0xFFFF) + 1
		pen = [seq, _next_pen]
		_pens[slot] = pen
	var msg: PackedByteArray = Protocol.frame(Protocol.Msg.SHEET, SheetCodec.pen(int(Variants.number(pen[1])), points))
	var author: String = _identity_of(slot)
	for session: Sessions.Session in _net.sessions.welcomed():
		if session.slot == slot:
			continue
		var reader: int = _miner_of(_run, session.slot)
		if reader == 0 or _run.closeups.kind_of(reader) != CloseupKind.Kind.MAP_TABLE:
			continue
		var c: Client = clients.get(session.slot, null)
		if c != null and c.blocked.has(author):
			continue
		if c != null and not _pen_fits(c, msg.size()):
			continue  # strokes as made are the first to give way to NET-04's budget
		_net.transport.send(session.peer, Lane.Id.FRAMES, msg)
		if _run.replication != null:
			_run.replication.native.spend(session.slot, msg.size())
		pen_bytes[session.slot] = int(Variants.number(pen_bytes.get(session.slot, 0))) + msg.size()
	_net.transport.flush()
	return true


## A stroke as made fits the reader's last second with room kept for the frames.
func _pen_fits(c: Client, size: int) -> bool:
	var hz: float = Tuning.f(&"net.tick_hz")
	var per_tick: int = roundi(Tuning.f(&"net.down_budget_kbps") * 1000.0 / 8.0 / hz)
	return window_bytes(c) + size <= roundi(per_tick * hz) - Tuning.i(&"net.sheet_reserve_bytes") - per_tick


## At most two sketch packets a tick on average over a second (mine.sheet_sketch_hz, doubled for
## jitter).
func _sketch_window(slot: int) -> bool:
	var hz: int = roundi(Tuning.f(&"net.tick_hz"))
	var recent: Array[int] = []
	for raw: Variant in Variants.array(_sketch_ticks.get(slot, [])):
		var t: int = int(Variants.number(raw))
		if _run.tick - t < hz:
			recent.append(t)
	if recent.size() >= 2 * Tuning.i(&"mine.sheet_sketch_hz"):
		_sketch_ticks[slot] = recent
		return false
	recent.append(_run.tick)
	_sketch_ticks[slot] = recent
	return true


## The drawer's pen lifts: the others at the table are told after whatever is queued (a commit's
## stroke arrives before its sketch goes). Nobody away from the table hears of it.
func _lift(slot: int) -> void:
	var pen: Array = Variants.array(_pens.get(slot, []))
	if pen.is_empty():
		return
	_pens.erase(slot)
	_lifted_seq[slot] = int(Variants.number(pen[0]))
	for raw: Variant in clients.keys():
		var c: Client = clients[raw]
		var reader: int = _miner_of(_run, int(Variants.number(raw))) if _run != null else 0
		if c.eligible and int(Variants.number(raw)) != slot and _at_table(_run, reader):
			c.queue.append([SheetCodec.Op.PEN_UP, int(Variants.number(pen[1])), 0])


## Everything the client should hold against what it holds: removals queued, additions backlogged.
func _diff(c: Client) -> void:
	for raw: Variant in c.held.keys():
		var id: int = raw
		if not _table.sheet.has(id) or _blocks(c, _author_of(id)):
			c.queue.append([SheetCodec.Op.REMOVE, id, 0])
	var ids: Array = _table.sheet.strokes.keys()
	ids.append_array(_table.sheet.labels.keys())
	ids.sort()
	c.backlog.clear()
	for raw: Variant in ids:
		var id: int = raw
		if not c.held.has(id) and not _blocks(c, _author_of(id)):
			c.backlog.append(id)
	c.full_told = -1


## Sends what this tick's allowance holds, live ops first, as one bulk-lane message.
func _send(run: RunState, session: Sessions.Session, c: Client, entity: int) -> void:
	var allowance: int = _allowance(run, session.slot, c, entity)
	var out: PackedByteArray = PackedByteArray()
	var public: bool = run.header.mode == ServerConfig.Mode.PUBLIC
	while not c.queue.is_empty() or not c.backlog.is_empty():
		var from_queue: bool = not c.queue.is_empty()
		var op: Array = c.queue[0] if from_queue else [SheetCodec.Op.ADD_STROKE, c.backlog[0], 0]
		var bytes: PackedByteArray = _bytes_for(c, op, public)
		if out.size() + bytes.size() > allowance:
			break
		if from_queue:
			c.queue.pop_front()
		else:
			c.backlog.pop_front()
		if not bytes.is_empty():
			_apply(c, op)
			out.append_array(bytes)
	if out.is_empty():
		return
	var msg: PackedByteArray = Protocol.frame(Protocol.Msg.SHEET, out)
	_net.transport.send(session.peer, Lane.Id.BULK, msg)
	if run.replication != null and not _table.frozen:
		run.replication.native.spend(session.slot, msg.size())
	if not _table.frozen and not _at_table(run, entity):
		c.background -= msg.size()
	sent_bytes[session.slot] = int(Variants.number(sent_bytes.get(session.slot, 0))) + msg.size()


## This tick's bytes for a client: what NET-04's 1 s budget has left once its frames and the rest
## of this tick are counted, keeping room for the next frames (net.sheet_reserve_bytes and a tick's
## refill: sheets go last), and never below what the frames' own bucket keeps; away from the table
## also no more than net.sheet_background_kbps; once frozen, net.sheet_flush_bytes_per_tick.
func _allowance(run: RunState, slot: int, c: Client, entity: int) -> int:
	if _table.frozen:
		return Tuning.i(&"net.sheet_flush_bytes_per_tick")
	var hz: float = Tuning.f(&"net.tick_hz")
	var per_tick: int = roundi(Tuning.f(&"net.down_budget_kbps") * 1000.0 / 8.0 / hz)
	var reserve: int = Tuning.i(&"net.sheet_reserve_bytes")
	var left: int = roundi(per_tick * hz) - window_bytes(c) - reserve - per_tick
	if run.replication != null:
		left = mini(left, run.replication.native.bucket_bytes(slot) - reserve)
	left -= 5  # the message's own frame
	if _at_table(run, entity):
		return maxi(0, left)
	var background: float = Tuning.f(&"net.sheet_background_kbps") * 1000.0 / 8.0 / hz
	c.background = minf(c.background + background, background * hz)
	return maxi(0, mini(left, floori(c.background) - 5))


## The non-voice bytes sent to the slot's peer over the last second, this tick so far included.
func window_bytes(c: Client) -> int:
	var now: int = _down_bytes(c)
	if c.counted < 0:
		c.counted = now
	var total: int = now - c.counted
	for b: int in c.ring:
		total += b
	return total


## Closes this tick's count: its bytes join the ring, the oldest leaves it.
func _close_tick(c: Client) -> void:
	var now: int = _down_bytes(c)
	if c.counted < 0:
		c.counted = now
	c.ring.append(now - c.counted)
	c.counted = now
	while c.ring.size() > roundi(Tuning.f(&"net.tick_hz")) - 1:
		c.ring.pop_front()


func _down_bytes(c: Client) -> int:
	var st: PeerStats = _net.transport.stats(c.peer)
	var total: int = 0
	for lane: int in Lane.COUNT:
		if lane != Lane.Id.VOICE:
			total += st.lane_out[lane]
	return total


## One op's bytes for this client, or none when it no longer applies (an id gone or blocked, a
## removal of something never sent). Pure: _apply() records it once it is sent.
func _bytes_for(c: Client, op: Array, public: bool) -> PackedByteArray:
	var kind: int = op[0]
	match kind:
		SheetCodec.Op.ADD_STROKE:
			var id: int = op[1]
			if c.held.has(id) or not _table.sheet.has(id) or _blocks(c, _author_of(id)):
				return PackedByteArray()
			if _table.sheet.strokes.has(id):
				var s: SheetStroke = _table.sheet.strokes[id]
				return SheetCodec.add_stroke_blob(id, s.encoded())
			var l: SheetLabel = _table.sheet.labels[id]
			# Public lobbies only: the author's SteamID rides along for STM-08's FilterText.
			return SheetCodec.add_label(id, l.anchor, l.text, _table.identity_of(l.author) if public else "")
		SheetCodec.Op.ACCEPT:
			var id: int = op[2]
			return SheetCodec.accept(int(Variants.number(op[1])), id) if _table.sheet.has(id) else SheetCodec.dropped(int(Variants.number(op[1])))
		SheetCodec.Op.REMOVE:
			return SheetCodec.remove(int(Variants.number(op[1]))) if c.held.has(int(Variants.number(op[1]))) else PackedByteArray()
		SheetCodec.Op.DROPPED:
			return SheetCodec.dropped(int(Variants.number(op[1])))
		SheetCodec.Op.FULL:
			return SheetCodec.full(int(Variants.number(op[1])) == 1)
		SheetCodec.Op.PEN_UP:
			return SheetCodec.pen_up(int(Variants.number(op[1])))
		SheetCodec.Op.RESET:
			return SheetCodec.reset()
	return PackedByteArray()


## What the client holds once `op` is sent.
func _apply(c: Client, op: Array) -> void:
	match int(Variants.number(op[0])):
		SheetCodec.Op.ADD_STROKE:
			c.held[int(Variants.number(op[1]))] = true
		SheetCodec.Op.ACCEPT:
			if _table.sheet.has(int(Variants.number(op[2]))):
				c.held[int(Variants.number(op[2]))] = true
		SheetCodec.Op.REMOVE:
			c.held.erase(int(Variants.number(op[1])))


func _client(session: Sessions.Session) -> Client:
	var c: Client = clients.get(session.slot, null)
	if c != null and c.peer == session.peer:
		return c
	# A new connection on the slot (a join or a rejoin): it holds nothing.
	c = Client.new()
	c.peer = session.peer
	c.queue.append([SheetCodec.Op.RESET, 0, 0])
	clients[session.slot] = c
	return c


func _refresh_blocks(session: Sessions.Session, c: Client) -> void:
	if not blocks_of.is_valid():
		return
	var now: Dictionary = {}
	for identity: Variant in Variants.array(blocks_of.call(session.slot)):
		now[str(identity)] = true
	if now == c.blocked:
		return
	c.blocked = now
	_diff(c)


func _blocks(c: Client, author: int) -> bool:
	return not c.blocked.is_empty() and c.blocked.has(_table.identity_of(author))


func _author_of(id: int) -> int:
	if _table.sheet.strokes.has(id):
		var s: SheetStroke = _table.sheet.strokes[id]
		return s.author
	if _table.sheet.labels.has(id):
		var l: SheetLabel = _table.sheet.labels[id]
		return l.author
	return -1


func _held_count(c: Client) -> int:
	return c.held.size()


func _at_table(run: RunState, entity: int) -> bool:
	return entity != 0 and run.closeups != null and run.closeups.kind_of(entity) == CloseupKind.Kind.MAP_TABLE


func _identity_of(slot: int) -> String:
	for session: Sessions.Session in _net.sessions.welcomed():
		if session.slot == slot:
			return session.identity
	return ""


func _miner_of(run: RunState, slot: int) -> int:
	if run.movement == null or run.movement.miner(slot) == null:
		return 0
	return run.movement.miner(slot).entity_id
