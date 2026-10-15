class_name RecordWindow
extends RefCounted
## NET-07: a pinned window of the run record, round one fall, one death or one miner's first
## illusion of the run (GDD §15.3, §15.7). It spans [cause - net.record_event_window_s, cause +
## net.record_tail_s], where the cause is the fall itself or, for a drag, the grab (Gameplay
## §11.10). Once its last block seals it copies, out of the rolling ring, the authoritative track
## and the victim's own stream, so it survives the 10-minute roll; NET-09 saves it with snapshots
## and knock-off saves. The facts RSC-07's extractor gives at the pin are kept with it.
## Server-only: nothing here ever reaches a client.

enum Kind { FALL, DEATH, FIRST_ILLUSION }

var id: int = 0
var kind: Kind = Kind.FALL
## The victim's client slot (-1 for a miner with no client, such as a Hired Hand) and entity.
var slot: int = -1
var entity: int = 0
## The cause tick (the fall, the death, the first illusion; for a drag, the grab), and the span.
var cause_tick: int = 0
var start: int = 0
var end: int = 0
## RSC-01's fall record, or the death's or the illusion's details.
var detail: Dictionary = {}
## RSC-07's card facts, extracted at the pin (the ring will have rolled past them by Lamp Check).
var facts: Dictionary = {}
## True once its blocks are copied out of the ring.
var sealed: bool = false
## True once the budget thinned its keyframes from every 2 s to every 4 s.
var thinned: bool = false
var blocks: Array[RecordBlock] = []


func size() -> int:
	var n: int = 0
	for b: RecordBlock in blocks:
		n += b.size()
	return n


## Keeps the first block's keyframes and every other one after: 2 s to 4 s. Returns bytes freed.
func thin() -> int:
	var freed: int = 0
	for i: int in range(1, blocks.size(), 2):
		freed += blocks[i].thin()
	thinned = true
	return freed


static func kind_name(k: Kind) -> String:
	var names: Array = Kind.keys()
	var name: String = names[k]
	return name.to_lower()


## Plain values only (NET-09).
func to_dict() -> Dictionary:
	var out: Array = []
	for b: RecordBlock in blocks:
		out.append(b.to_dict())
	return {"id": id, "kind": kind, "slot": slot, "entity": entity, "cause_tick": cause_tick, "start": start, "end": end,
		"detail": detail.duplicate(true), "facts": facts.duplicate(true), "sealed": sealed, "thinned": thinned, "blocks": out}


static func from_dict(d: Dictionary) -> RecordWindow:
	var w: RecordWindow = RecordWindow.new()
	w.id = int(Variants.number(d.get("id", 0)))
	var k: int = int(Variants.number(d.get("kind", 0)))
	w.kind = clampi(k, 0, Kind.size() - 1) as Kind
	w.slot = int(Variants.number(d.get("slot", -1)))
	w.entity = int(Variants.number(d.get("entity", 0)))
	w.cause_tick = int(Variants.number(d.get("cause_tick", 0)))
	w.start = int(Variants.number(d.get("start", 0)))
	w.end = int(Variants.number(d.get("end", 0)))
	w.detail = Variants.dict(d.get("detail", {})).duplicate(true)
	w.facts = Variants.dict(d.get("facts", {})).duplicate(true)
	w.sealed = Variants.flag(d.get("sealed", false))
	w.thinned = Variants.flag(d.get("thinned", false))
	for raw: Variant in Variants.array(d.get("blocks", [])):
		w.blocks.append(RecordBlock.from_dict(Variants.dict(raw)))
	return w
