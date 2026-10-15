class_name VoiceChoice
extends RefCounted
## SND-13 and MOD-01: a miner's default character voice, from their name: FNV-1a over its UTF-8 bytes,
## mod 8, stable across platforms. The profile (MOD-01) holds the chosen voice; the server's
## VoiceAssignment makes voices unique per run.

const VOICES: int = 8


static func default_for(miner_name: String) -> int:
	var h: int = 0x811C9DC5
	for b: int in miner_name.to_utf8_buffer():
		h = ((h ^ b) * 0x01000193) & 0xFFFFFFFF
	return h % VOICES
