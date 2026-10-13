class_name VisualEvents
extends RefCounted
## VIS-09: event types the client draws rather than plays, riding NET-04's event channel with the
## audio records (an AudioRecord's fields; the type byte from 250 up, clear of NoiseTypes below 200
## and LocalSounds' 200s). A puff of dust off a lit wall face where the Tapper tapped; a burst of
## dust (CRT-06's laying, MNR-16's flinch) with its radius in `level_np` and its length in
## `duration_s`. Each goes only to a viewer who sees the place lit. Append only.

enum Type { PUFF = 250, DUST_BURST = 251 }


static func is_visual(type: int) -> bool:
	return type >= 250
