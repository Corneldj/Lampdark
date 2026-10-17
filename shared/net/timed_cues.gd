class_name TimedCues
extends RefCounted
## NET-06: the audio events a 'Now!' is judged against. The client reports when it presented
## each one (NET-03's cue_reports); a cue is named by its event's type and start tick, which both
## ends know, so no server number is needed. LFT-04 adds its cues here: the engine's crank at its
## top (LFT-08) and the trip lever caught as it is taken (LFT-05).

const TYPES: Array[NoiseTypes.Type] = [NoiseTypes.Type.ENGINE_CRANK, NoiseTypes.Type.TRIP_LEVER]


static func is_timed(type: int) -> bool:
	return TYPES.has(type as NoiseTypes.Type)


## The id both ends use for the cue of `type` starting at server tick `start_tick`.
static func cue_id(type: int, start_tick: int) -> int:
	return ((type & 0xFF) << 24) | (start_tick & 0xFFFFFF)
