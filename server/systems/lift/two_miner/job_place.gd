class_name JobPlace
extends RefCounted
## LFT-04: one place at a job for two (Gameplay §3.3): a spot in the world a miner works from,
## who holds it now and since when, and when and how its last holder let go. A place is held with
## interact (hold or toggle, MNR-15) in touch range; a CuePress's presser place is pressed, not held.
## Server-only: nothing here reaches a client.

## Unique among the run's places (TwoMinerJobs numbers them).
var id: int = 0
## Where it is worked from (tiles, a point).
var anchor: Vector2 = Vector2.ZERO
## The miner holding it, 0 for none.
var holder: int = 0
## The server tick it was taken.
var since: int = -1
## Its last holder, and when they let go: on their own screen (their input's shown tick) when they
## released interact, else the server tick (a fall, a grab, a drop, out of reach).
var released_by: int = 0
var released_at: float = -1.0


static func at(where: Vector2) -> JobPlace:
	var p: JobPlace = JobPlace.new()
	p.anchor = where
	return p
