extends RefCounted
## UI-03's scenarios: one miner's captions, fed as its client feeds them. Every audio event the
## client received (and so would play) goes to CaptionSystem.on_played with its direction from the
## own miner; DEAFENED records reach a real Deafness (its ringing), ambient cues a real AmbientBeds
## (its silence captions). Nothing else is read.

const Scenario = preload("res://tests/scenario/kit/scenario.gd")
const MinerHandle = preload("res://tests/scenario/kit/miner_handle.gd")
const Capture = preload("res://tests/scenario/kit/capture.gd")

var system: CaptionSystem = CaptionSystem.new()
var deafness: Deafness = null
var beds: AmbientBeds = null
var _h: MinerHandle = null
var _events_seen: int = 0
var _deafened_seen: int = 0
var _cues_seen: int = 0


## `parent` holds the audio nodes (a test's tree).
func _init(h: MinerHandle, parent: Node) -> void:
	_h = h
	beds = AmbientBeds.new()
	parent.add_child(beds)
	deafness = Deafness.new(beds)
	parent.add_child(deafness)
	deafness.ringing.connect(func(start: bool) -> void: system.on_ringing(start, _now()))
	beds.silence_caption.connect(func(layer: StringName, start: bool) -> void: system.on_silence(layer, start, _now()))


func free_nodes() -> void:
	deafness.queue_free()
	beds.queue_free()


## Call once a tick (Scenario.on_tick).
func pump(s: Scenario) -> void:
	var c: Capture = s.client(_h)
	var view: ReceivedView = c.records_at(s.run.tick)
	var own: Vector2 = view.own["position"] if view != null else Vector2.ZERO
	while _events_seen < c.received_events.size():
		var e: Dictionary = c.received_events[_events_seen]
		_events_seen += 1
		var r: AudioRecord = AudioRecord.from_event(e)
		if VisualEvents.is_visual(r.type):
			continue
		system.on_played(r, null if (r.flags & AudioRecord.DIFFUSE) != 0 else r.apparent - own, _now_of(s))
	var conn: ClientConnection = _h.connection
	while _deafened_seen < conn.deafened.size():
		deafness.start(conn.deafened[_deafened_seen])
		_deafened_seen += 1
	while _cues_seen < conn.ambient_cues.size():
		beds.apply(conn.ambient_cues[_cues_seen])
		_cues_seen += 1


## Every caption line shown so far, by text.
func texts() -> Array[String]:
	var out: Array[String] = []
	for h: Dictionary in system.history:
		out.append(str(h["text"]))
	return out


static func _now_of(s: Scenario) -> float:
	return s.run.tick * 0.05


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
