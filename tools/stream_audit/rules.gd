extends RefCounted
## NET-08's record-type registry: every message the protocol defines and every record a frame can
## carry names the audit rule that judges it (GDD §15.3, §9.2). A type with no entry fails
## test_every_record_has_rule.gd, so each ticket that adds a record type adds its rule here and in
## stream_audit.gd. "client_only" messages travel to the server: one sent to a client is a leak.

## Protocol.Msg name -> the rule that judges it.
const MESSAGES: Dictionary = {
	"HELLO": "client_only",
	"WELCOME": "handshake",
	"REJECT": "handshake",
	"PING": "client_only",
	"PONG": "handshake",
	"FRAME": "frame",
	"INPUT": "client_only",
	"VOICE": "voice",
	"INVENTORY": "inventory",
	"FEEL": "feel",
	"RING": "ring",
	"AMBIENT": "ambient",
	"DEAFENED": "deafened",
	"DEBUG_COMMAND": "client_only",
	"DEBUG_REPLY": "debug",
	"DEBUG_SUBSCRIBE": "client_only",
	"DEBUG_TRUTH": "debug",
	"DEBUG_TAG": "debug",
	"MIC_LABEL": "client_only",
	"KNOCKS": "knocks",
	"RELAY_TAG": "client_only",  # STM-04: the host's relay to its own server, never downstream
	"CLOSE_UP": "closeup",  # UI-02: the own close-up and the board's seat, to that client only
	"CALLOUT": "callout",  # SND-11: a callout as this client hears it (illusions and echoes alike)
	"WATCH": "watch",  # RSC-04: a teammate's frames 45 s late, to the fallen only
	"REPLAY": "replay",  # RSC-04: the victim's own frames before the fall, to the victim only
	"SAVE_DATA": "save",  # NET-09: sealed sections and a plain header of versions, never in public
	"JOURNAL": "save",  # NET-09: one sealed journal entry, never in public
	"SAVE_ACK": "client_only",  # NET-09: a member's acknowledgement
	"STATUS": "status",  # the own miner's status, to its owner only: exactly its own cues and offers
	"SHEET": "sheet",  # LFT-14: a sheet's sync; strokes as made only to its readers; never to the fallen
	"MANUAL": "manual",  # LFT-03: the repair list's kind, cans and jobs, only to a reader of the Manual
	"LAMP_CHECK": "lamp_check",  # RSC-06: after the run's end only: its opening (own outcome only) and its end
}

## Each record a frame carries -> its rule (client_view's layout, FrameDecoder's fields).
const FRAME_RECORDS: Dictionary = {
	"header": "frame",            # tick, age, acks, depth, flags: the client's own bookkeeping
	"own_block": "frame",         # the client's own miner
	"blinded_flag": "frame",      # the own miner's state
	"dust_flag": "dust",          # VIS-09: a Moth's tell within reach
	"tile": "tile",               # light, colour, decals: seen
	"tile_removal": "frame",      # forgetting is always allowed
	"geometry": "geometry",       # seen or margin
	"entity_identity": "entity",  # seen and lit to identity
	"entity_token": "entity",     # seen in the fringe, by size class
	"entity_margin": "entity",    # VIS-04's margin or NET-12's turn band
	"entity_removal": "frame",
	"glow": "glow",               # the reference's buckets exactly
	"event_audio": "audio",       # a real delivery the reference reaches, or a logged illusion
	"event_visual": "visual",     # VIS-09's puffs and bursts: lit tiles the viewer sees
}

## Records no build sends yet (M2): any one arriving fails.
const NOT_YET: Array[String] = ["sheet", "watch_frame", "true_view"]


static func rule_of_message(type: int) -> String:
	var name: Variant = Protocol.Msg.find_key(type)
	return str(MESSAGES.get(str(name), "")) if name != null else ""
