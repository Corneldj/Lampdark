class_name Deafen
extends SimSystem
## SND-04 (Gameplay §4.7, §6.10, §7.6, A.3): the deafened state. MNR-16 calls `deafen` for the shooter
## and every miner within revolver.deafen_radius of a shot; until then a FND-08 console command does.
## For noise.deafen_duration_s (a new shot restarts it) SND-03's `deafen` mask drops every tell (the
## diffuse ones), rock tap, voice and callout, and sets the rest noise.deafen_dip_db down. The client
## gets one Deafened record (DeafenedMessages) and starts the ringing and its own beds' dip; the
## records it plays arrive already dipped. SND-08 reads `is_deafened` (no voice frames). Stage
## ROAD_GRAPH, before SND-01's noise: a timer that ends this tick ends before this tick's deliveries.

## Never reach a deafened listener (§4.7, §7.6): the rock taps, voices and callouts; and every tell,
## which travels as a DIFFUSE record.
const DROPPED_TYPES: Array[int] = [NoiseTypes.Type.ROCK_TAP, NoiseTypes.Type.VOICE, NoiseTypes.Type.CALLOUT, NoiseTypes.Type.FALL_SCREAM]

## slot -> the tick the deafness ends (exclusive).
var until: Dictionary = {}
## [slot, bytes] Deafened records for Replication to send on the control lane.
var outbox: Array[Array] = []
var _run: RunState = null


func stage() -> int:
	return StageTable.Stage.ROAD_GRAPH


func order() -> int:
	return 5


func system_name() -> String:
	return "deafen"


func bind(run: RunState) -> void:
	_run = run
	if run.audio != null:
		run.audio.register_mask("deafen", mask)


## Deafens one miner's listener for `seconds` (noise.deafen_duration_s by default) from now. A new
## shot restarts the timer rather than adding to it.
func deafen(run: RunState, slot: int, seconds: float = -1.0) -> void:
	var s: float = seconds if seconds >= 0.0 else Tuning.f(&"noise.deafen_duration_s")
	until[slot] = run.tick + maxi(1, roundi(s * Tuning.f(&"net.tick_hz")))
	outbox.append([slot, DeafenedMessages.encode(s, Tuning.f(&"noise.deafen_dip_db"))])


func is_deafened(slot: int) -> bool:
	return _run != null and int(Variants.number(until.get(slot, -1))) > _run.tick


func tick(run: RunState) -> void:
	for raw: Variant in until.keys():
		if int(Variants.number(until[raw])) <= run.tick:
			until.erase(raw)


## SND-03's mask: (run, slot, record) -> null to drop, or the change.
func mask(_r: RunState, slot: int, record: AudioRecord) -> Variant:
	if not is_deafened(slot):
		return {}
	if (record.flags & AudioRecord.DIFFUSE) != 0 or DROPPED_TYPES.has(record.type):
		return null
	return {"gain_db": -roundi(Tuning.f(&"noise.deafen_dip_db"))}


func write_state(writer: SimStateWriter) -> void:
	var slots: Array = until.keys()
	slots.sort()
	writer.put_i64(slots.size())
	for raw: Variant in slots:
		writer.put_i64(int(Variants.number(raw)))
		writer.put_i64(int(Variants.number(until[raw])))


func read_state(reader: SimStateReader) -> void:
	until.clear()
	for _i: int in reader.get_i64():
		var slot: int = reader.get_i64()
		until[slot] = reader.get_i64()
