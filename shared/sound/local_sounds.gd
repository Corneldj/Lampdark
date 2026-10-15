class_name LocalSounds
extends RefCounted
## SND-03: wire ids for sounds outside the Road Graph, sharing the audio record's type byte with
## NoiseTypes (whose ids stay below 200). Local emitters (the firedamp hiss, the hatch's ticking)
## reach only clients within their radius; diffuse creature tells (CRT-03, CRT-04) play from wall
## points near the listener, never where. Append only.

enum Type {
	NONE = 0, FIREDAMP_HISS = 200, HATCH_TICKING = 201, MOTH_STIR = 210, MOTH_SETTLE = 211, MOTH_AWAKE = 212, MOTH_THRUM = 213,
	STYTHE_BREATH = 214, STYTHE_INTAKE = 215,
}

## CRT-01's tell kinds -> their wire ids.
const TELLS: Dictionary = {&"moth_stir": Type.MOTH_STIR, &"moth_settle": Type.MOTH_SETTLE, &"moth_awake": Type.MOTH_AWAKE,
	&"moth_thrum": Type.MOTH_THRUM, &"stythe_breath": Type.STYTHE_BREATH}


static func id_of(type: int) -> String:
	return str(Type.find_key(type)).to_lower() if Type.values().has(type) and type != Type.NONE else ""


static func is_local(type: int) -> bool:
	return type >= 200
