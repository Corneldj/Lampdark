class_name PitPhone
extends RefCounted
## LFT-12: one pit phone and its line. The painted number and the road home are fixed when the phone
## first generates (kept through eviction, saves and resumes); the cut is for the run; the call is
## who is on it now. Server-only: no route, cut or crossing ever leaves the server.

## CALLING: on the line, the flap down; ON_CALL: the operator plugged in; HELD: the operator holds it
## (LFT-13), the caller on the line in hiss.
enum State { IDLE = 0, CALLING = 1, ON_CALL = 2, HELD = 3 }

## GEN-10's placement id ("p" + 16 hex digits), or a test's own.
var id: String = ""
var cell: Vector2i = Vector2i.ZERO
var tile: Vector2i = Vector2i.ZERO
## 1 to phones.line_number_max; 0 once the pool ran out (a dead, unnumbered phone).
var number: int = 0
## A road home was found, and the tick it was looked for (-1: not yet; the line is dead till then).
var routed: bool = false
var route_found_at: int = -1
## Its length in tiles, and the cells it passes through.
var route_tiles: int = 0
var route_cells: Array[Vector2i] = []
## [cell, collapse id]: the collapse alternates whose fall would cut it.
var crossings: Array = []
var cut: bool = false
## The PHONE entity while its cell is loaded (0 otherwise).
var entity: int = 0
var state: State = State.IDLE
## The miner on the phone (0: on the hook), and the operator's slot on the line (-1: none).
var caller: int = 0
var operator: int = -1
## Ringing (LFT-13's ring) until this tick, by this operator's slot.
var ringing_until: int = -1
var ringing_by: int = -1


func crosses(at_cell: Vector2i, collapse: int) -> bool:
	for raw: Variant in crossings:
		var pair: Array = raw
		var c: Vector2i = pair[0]
		if c == at_cell and int(Variants.number(pair[1])) == collapse:
			return true
	return false


## What a save keeps (the call is not kept: a resumed line is on the hook).
func to_dict() -> Dictionary:
	return {"id": id, "cell": cell, "tile": tile, "number": number, "routed": routed, "route_found_at": route_found_at, "route_tiles": route_tiles,
		"route_cells": route_cells.duplicate(), "crossings": crossings.duplicate(true), "cut": cut}


static func from_dict(d: Dictionary) -> PitPhone:
	var p: PitPhone = PitPhone.new()
	p.id = str(d.get("id", ""))
	p.cell = d.get("cell", Vector2i.ZERO)
	p.tile = d.get("tile", Vector2i.ZERO)
	p.number = int(Variants.number(d.get("number", 0)))
	p.routed = Variants.flag(d.get("routed", false))
	p.route_found_at = int(Variants.number(d.get("route_found_at", -1)))
	p.route_tiles = int(Variants.number(d.get("route_tiles", 0)))
	for raw: Variant in Variants.array(d.get("route_cells", [])):
		var c: Vector2i = raw
		p.route_cells.append(c)
	p.crossings = Variants.array(d.get("crossings", [])).duplicate(true)
	p.cut = Variants.flag(d.get("cut", false))
	return p
