class_name NoiseTypes
extends RefCounted
## SND-02's noise event types: the id a client record carries (SND-03) for each catalogue entry
## in data/sound/noise_catalogue.json. Values are wire ids, so never renumber: append new types.
## A unit test checks this list against the catalogue.

enum Type {
	NONE = 0,
	RELOAD_CLICK = 1,
	LAMP_HANG_CLINK = 2,
	STEP_WALK = 3,
	PANTING = 4,
	FLINT_CLICK = 5,
	SPANNER = 6,
	STEP_STRETCHER = 7,
	STEP_DRUM_GEAR = 8,
	DRAG_SCRAPE = 9,
	ROCK_TAP = 10,
	CANARY = 11,
	GASP = 12,
	COUGH = 13,
	CARRY_KNOCK = 14,
	STEP_HEAVY = 15,
	STRUGGLE = 16,
	MOTH_LAYING = 17,
	BUZZER = 18,
	TRAPPED_CRY = 19,
	RAIL_BANG = 20,
	TUB_RUMBLE = 21,
	STONE_LANDING = 22,
	GATE = 23,
	HAMMER = 24,
	PHONE_CRANK = 25,
	MANTRAP_SNAP = 26,
	FLARE_STRIKE = 27,
	STEP_RUN = 28,
	PHONE_BELL = 29,
	HOLD_BELL = 30,
	ENGINE_CRANK = 31,
	MAIN_SWITCH = 32,
	CAGE_FREED = 33,
	STAPLE_PIT_CRASH = 34,
	BROOD_BURST = 35,
	ENGINE_RUNNING = 36,
	BESS_WHINNY = 37,
	BACKFIRE = 38,
	ROOF_FALL = 39,
	SHOT = 40,
	FIREDAMP_BLAST = 41,
	VOICE = 42,
	CALLOUT = 43,
	FALL_SCREAM = 44,
}


## The catalogue id ("step_walk") of a type.
static func id_of(type: Type) -> String:
	return str(Type.find_key(type)).to_lower() if type != Type.NONE else ""


## The type for a catalogue id, or NONE.
static func from_id(id: String) -> Type:
	var key: String = id.to_upper()
	return Type[key] if Type.has(key) else Type.NONE
