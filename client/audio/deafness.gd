class_name Deafness
extends Node
## SND-04 (Gameplay §4.7, A.3): the client's side of being deafened. One Deafened record from the
## server starts a ringing on the Ringing bus for its duration and dips this client's own ambient beds
## by its dip (the events it plays meanwhile arrive already dipped, and its tells, taps and voices do
## not arrive at all). A second record restarts both. The ringing volume option sets only the Ringing
## bus (AudioBuses.set_ringing_volume_db), never the dip. `ringing` raises UI-03's '[ringing]' caption.

signal ringing(start: bool)

var beds: AmbientBeds = null
var player: AudioStreamPlayer = null
var remaining_s: float = 0.0
var dip_db: float = 0.0


func _init(ambient: AmbientBeds = null) -> void:
	beds = ambient


func deafened() -> bool:
	return remaining_s > 0.0


## One Deafened record: {duration_s, dip_db}.
func start(record: Dictionary) -> void:
	var was: bool = deafened()
	remaining_s = float(Variants.number(record.get("duration_s", 0.0)))
	dip_db = float(Variants.number(record.get("dip_db", 0.0)))
	if player != null:
		player.queue_free()
	player = AudioStreamPlayer.new()
	player.stream = SampleBank.ringing(remaining_s)
	player.bus = "Ringing"
	add_child(player)
	if is_inside_tree():
		player.play()
	if beds != null:
		beds.set_dip_db(-dip_db)
	if not was:
		ringing.emit(true)


func _process(delta: float) -> void:
	advance(delta)


func advance(seconds: float) -> void:
	if not deafened():
		return
	remaining_s = maxf(0.0, remaining_s - seconds)
	if remaining_s > 0.0:
		return
	if player != null:
		player.queue_free()
		player = null
	if beds != null:
		beds.set_dip_db(0.0)
	ringing.emit(false)
