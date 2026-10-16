class_name BodyState
extends RefCounted
## RSC-01: a fallen miner's body. The body is the miner's own entity (same id), lying; NET-04
## sends it like any miner (a shape in the fringe, identity at 0.30, with MNR-03's lying cues).
## This record says where it is and what holds it. Server-only; NET-09 snapshots it.

enum Posture { STANDING = 0, LYING = 1 }

var entity: int = 0
var posture: Posture = Posture.LYING
var on_floor: bool = true
## The miner carrying it (MNR-13), 0 if none.
var carried_by: int = 0
## MNR-14: the item uid of the stretcher it lies on or the tub it rides in, 0 if none (not on the
## floor meanwhile; LoadCarry and TubRails move it with the load).
var on_load: int = 0
var on_table: bool = false
## RSC-03's trap still holding it (a miner who falls in a trap stays in it until freed).
var held_by_trap: bool = false
## CRT-15: kept in the Stythe's lair.
var kept_in_lair: bool = false
## CRT-14: the Stythe dragging it, 0 if none.
var dragged_by: int = 0
var dead: bool = false
var fall_id: int = 0


func feel_caption() -> String:
	return "[a body, cold]" if dead else "[a body, breathing]"
