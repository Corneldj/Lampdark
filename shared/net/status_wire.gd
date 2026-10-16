class_name StatusWire
extends RefCounted
## The own miner's status, to its owner only (Protocol.Msg.STATUS, control lane, sent whenever it
## changes and on every welcome): what holds the body (its MinerCues, the cap badge left out), the
## struggle when one is offered (RSC-03's skill check: its needle's start tick and turn, its zone,
## the hits made and needed, a miss's lockout), and the self-revive's count (RSC-09). The client
## shows it as standard status, key hints and the struggle's ring (the first playtests). Layout: u16
## cues, u8 flags, u32 the self-revive's due tick, u16 its length in ticks, then the struggle: u32
## epoch tick, u16 sweep ticks, u16 zone start and u16 zone size in hundredths of a degree, u8 hits,
## u8 hits needed, u32 the lockout's end tick.

## A struggle is offered now (its fields are valid).
const STRUGGLE: int = 1
## LFT-04: the miner stands at a job for two (SND-11's job page replaces the callout wheel).
const AT_JOB: int = 2
## RSC-09: the self-revive's count is running (due at `revive_due_tick`).
const REVIVE_COUNTING: int = 4
## RSC-09: a self-revive is pending but waits (a drag holds the body).
const REVIVE_WAITING: int = 8
const SIZE: int = 25
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
	b.put_u32(maxi(0, int(Variants.number(d.get("epoch", 0)))))
	b.put_u16(clampi(int(Variants.number(d.get("sweep_ticks", 0))), 0, 0xFFFF))
	b.put_u16(clampi(roundi(float(Variants.number(d.get("zone_start", 0.0))) * 100.0), 0, 36000))
	b.put_u16(clampi(roundi(float(Variants.number(d.get("zone_size", 0.0))) * 100.0), 0, 36000))
	b.put_u8(clampi(int(Variants.number(d.get("hits", 0))), 0, 255))
	b.put_u8(clampi(int(Variants.number(d.get("needed", 0))), 0, 255))
	b.put_u32(maxi(0, int(Variants.number(d.get("lockout_until", 0)))))
	return b.data_array


## {cues, flags, revive_due_tick, revive_ticks, epoch, sweep_ticks, zone_start, zone_size, hits,
## needed, lockout_until}, or {} if malformed.
static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() != SIZE:
		return {}
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	b.data_array = bytes
	return {"cues": b.get_u16(), "flags": b.get_u8(), "revive_due_tick": b.get_u32(), "revive_ticks": b.get_u16(),
		"epoch": b.get_u32(), "sweep_ticks": b.get_u16(), "zone_start": b.get_u16() / 100.0, "zone_size": b.get_u16() / 100.0,
		"hits": b.get_u8(), "needed": b.get_u8(), "lockout_until": b.get_u32()}


## The struggle's needle at shown tick `t` (degrees), from a decoded status.
static func needle_deg(status: Dictionary, t: float) -> float:
	var sweep: float = maxf(1.0, float(Variants.number(status.get("sweep_ticks", 1))))
	return fposmod((t - float(Variants.number(status.get("epoch", 0)))) * 360.0 / sweep, 360.0)
