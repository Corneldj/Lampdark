class_name DarkView
extends RefCounted
## RSC-04's client side of the Dark (Gameplay §11.8). From the own block's life state: black while
## unconscious or dead (VIS-05's BLACK), the coming-round view while a window is open (the own miner
## may move again: COMING_ROUND). Over that it plays two streams of frames the server relays, each
## through its own FrameDecoder, one frame a tick:
##   the replay (REPLAY): this miner's own view of the moments before the fall, once, skippable;
##   watching (WATCH): a teammate's own stream 45 s late, illusions and all, with its game sound.
## While either plays, the world view draws that stream's view and the ears sit on its miner.
## Watching is chosen with the interact press (the next teammate) and stopped with Use.

const LIFE_UNCONSCIOUS: int = 3
const LIFE_DEAD: int = 4
const FLAG_MOVE: int = 1 << 7

## The replay: frames and the decoder they play through.
var replay_frames: Array = []
var replay_parts: int = 0
var replay_of: int = -1
var replay_at: int = 0
var replay_decoder: FrameDecoder = FrameDecoder.new()
var replay_view: ReceivedView = null
var replay_done: bool = false
## Watching.
var watch_frames: Array = []
var watch_decoder: FrameDecoder = FrameDecoder.new()
var watch_view: ReceivedView = null
var watching: bool = false
## Game sound decoded from the watched frames, not yet played: event dictionaries.
var watch_events: Array[Dictionary] = []
var _seen_numbers: Dictionary = {}
var _frame_s: float = 0.05
var _clock: float = 0.0
var _interact_was: bool = false
var _use_was: bool = false


static func life_of(view: ReceivedView) -> int:
	if view == null:
		return 0
	return (int(Variants.number(view.own.get("flags", 0))) >> 4) & 7


static func fallen(view: ReceivedView) -> bool:
	var life: int = life_of(view)
	return life == LIFE_UNCONSCIOUS or life == LIFE_DEAD


static func in_window(view: ReceivedView) -> bool:
	return life_of(view) == LIFE_UNCONSCIOUS and (int(Variants.number(view.own.get("flags", 0))) & FLAG_MOVE) != 0


## What the world view shows for the own view: NORMAL (also while another stream is drawn),
## COMING_ROUND in a window, BLACK otherwise in the Dark.
func mode(own: ReceivedView) -> WorldView.Mode:
	if override_view(own) != null or not fallen(own):
		return WorldView.Mode.NORMAL
	return WorldView.Mode.COMING_ROUND if in_window(own) else WorldView.Mode.BLACK


## The stream drawn instead of the own view `own`, or null: the replay first, then watching (never
## in a coming-round window, when the own cone is what matters).
func override_view(own: ReceivedView = null) -> ReceivedView:
	if in_window(own):
		return null
	if replay_view != null and not replay_done:
		return replay_view
	if watching and watch_view != null:
		return watch_view
	return null


## Takes the connection's messages, then plays one frame a tick of each stream.
func tick(connection: ClientConnection, delta: float) -> void:
	if connection != null:
		while not connection.replay_in.is_empty():
			var r: Dictionary = connection.replay_in.pop_front()
			_take_replay(r)
		while not connection.watch_in.is_empty():
			var w: Dictionary = connection.watch_in.pop_front()
			_take_watch(w)
	_clock += delta
	if Tuning.current.has_key(&"net.tick_hz"):
		_frame_s = 1.0 / Tuning.f(&"net.tick_hz")
	while _clock >= _frame_s:
		_clock -= _frame_s
		_step()


## The interact press watches the next teammate, Use stops: [arg] for ActionRecord.Kind.WATCH. A
## replay playing is skipped by either.
func asks(router: InputRouter, own: ReceivedView) -> Array[int]:
	var out: Array[int] = []
	var interact: bool = (router.record.holds & InputRecord.HOLD_INTERACT) != 0
	var use: bool = (router.record.holds & InputRecord.HOLD_USE) != 0
	if fallen(own) and not in_window(own):
		if interact and not _interact_was:
			if replay_view != null and not replay_done:
				skip_replay()
			else:
				out.append(1)
		if use and not _use_was:
			if replay_view != null and not replay_done:
				skip_replay()
			elif watching:
				out.append(0)
	_interact_was = interact
	_use_was = use
	return out


func skip_replay() -> void:
	replay_done = true


func _take_replay(d: Dictionary) -> void:
	if replay_of < 0:
		replay_of = int(Variants.number(d.get("of", 1)))
	var views: Dictionary = d["views"]
	if not views.is_empty():
		_seed(replay_decoder, views)
	replay_frames.append_array(Variants.array(d["frames"]))
	replay_parts += 1
	if replay_parts >= replay_of and replay_view == null:
		replay_frames.sort_custom(func(a: Variant, b: Variant) -> bool:
			return int(Variants.number(Variants.array(a)[0])) < int(Variants.number(Variants.array(b)[0])))
		replay_at = 0
		replay_done = replay_frames.is_empty()
		replay_view = ReceivedView.new()


func _take_watch(d: Dictionary) -> void:
	if Variants.flag(d.get("ended", false)):
		watching = false
		watch_view = null
		watch_frames.clear()
		return
	if Variants.flag(d.get("reset", false)):
		watch_decoder = FrameDecoder.new()
		var views: Dictionary = d["views"]
		_seed(watch_decoder, views)
		watch_frames.clear()
		watch_view = null
		watching = true
	watch_frames.append_array(Variants.array(d["frames"]))


func _step() -> void:
	if replay_view != null and not replay_done:
		if replay_at < replay_frames.size():
			var f: Array = replay_frames[replay_at]
			replay_at += 1
			var bytes: PackedByteArray = f[1]
			var dec: FrameDecoder.Decoded = replay_decoder.decode(bytes)
			if dec.ok:
				replay_view = dec.view
		else:
			replay_done = true  # its end: black
	if watching and not watch_frames.is_empty():
		var f: Array = watch_frames.pop_front()
		var bytes: PackedByteArray = f[1]
		var dec: FrameDecoder.Decoded = watch_decoder.decode(bytes)
		if dec.ok:
			watch_view = dec.view
			for e: Dictionary in dec.events:
				var n: int = int(Variants.number(e["number"]))
				if not _seen_numbers.has(n):
					_seen_numbers[n] = true
					watch_events.append(e)


static func _seed(decoder: FrameDecoder, views: Dictionary) -> void:
	for raw: Variant in views.keys():
		var t: int = raw
		decoder.history[t] = ReceivedView.from_dict(Variants.dict(views[raw]))
