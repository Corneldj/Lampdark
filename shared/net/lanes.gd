class_name Lane
## The six transport lanes (NET-02; FND-08's debug lane). Each is an independent channel, so voice never waits
## behind state or reliable traffic.

enum Id {
	CONTROL = 0,  ## reliable ordered: handshake, session, clock sync, phases, journal entries
	FRAMES = 1,   ## unreliable sequenced: per-tick frames, server to client (NET-04)
	INPUTS = 2,   ## unreliable sequenced: inputs and frame acks, client to server (NET-03)
	VOICE = 3,    ## unreliable sequenced: Opus frames, both ways (SND-07)
	BULK = 4,     ## reliable ordered: sheets, save deltas, the backup feed
	DEBUG = 5,    ## reliable ordered: FND-08's debug channel, dev and QA only, never a release build
}

const COUNT: int = 6


static func is_reliable(lane: int) -> bool:
	return lane == Id.CONTROL or lane == Id.BULK or lane == Id.DEBUG


static func lane_name(lane: int) -> String:
	return str(Id.find_key(lane)).to_lower()
