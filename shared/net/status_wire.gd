class_name StatusWire
extends RefCounted
## The own miner's status, to its owner only (Protocol.Msg.STATUS, control lane, sent whenever it
## changes and on every welcome): what holds the body (its MinerCues, the cap badge left out), whether
## the one self-rescue is offered or was spent and failed (RSC-03), and the self-revive's count
## (RSC-09). The client shows it as standard status and key hints (the first playtest: being pinned
## or knocked out explained nothing). Layout: u16 cues, u8 flags, u32 the self-revive's due tick,
## u16 its length in ticks.

const SELF_RESCUE_OFFERED: int = 1
const SELF_RESCUE_FAILED: int = 2
## RSC-09: the self-revive's count is running (due at `revive_due_tick`).
const REVIVE_COUNTING: int = 4
## RSC-09: a self-revive is pending but waits (a drag holds the body).
const REVIVE_WAITING: int = 8
const SIZE: int = 9
## The own block's life bits (flags bits 4-6) as the client names them: MNR-03's states, wire values
## (test_standard_hud checks them against the server's own states, which client code never names).
const LIFE_UPRIGHT: int = 0
const LIFE_CAUGHT: int = 1
const LIFE_GRABBED: int = 2
const LIFE_UNCONSCIOUS: int = 3
const LIFE_DEAD: int = 4


static func encode(d: Dictionary) -> PackedByteArray:
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	b.put_u16(int(Variants.number(d.get("cues", 0))) & ~MinerCues.BADGE_MASK & 0xFFFF)
	b.put_u8(int(Variants.number(d.get("flags", 0))) & 0xFF)
	b.put_u32(maxi(0, int(Variants.number(d.get("revive_due_tick", 0)))))
	b.put_u16(clampi(int(Variants.number(d.get("revive_ticks", 0))), 0, 0xFFFF))
	return b.data_array


## {cues, flags, revive_due_tick, revive_ticks}, or {} if malformed.
static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() != SIZE:
		return {}
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	b.data_array = bytes
	return {"cues": b.get_u16(), "flags": b.get_u8(), "revive_due_tick": b.get_u32(), "revive_ticks": b.get_u16()}
