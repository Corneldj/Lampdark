class_name HandInteractionFilter
extends RefCounted
## MOD-08 (Gameplay §13.9): the never list, enforced twice. The controller emits only movement,
## facing, gait and the lamp's state, the interact held for a POINTed job and the flint held for
## 'Light up!'; this filter strips anything else from every input a Hand drives (counted, so a
## soak can show every injected attempt was turned away), and the world's own systems refuse a
## Hand-driven miner too (gates, air doors, the lift's levers, crank and throttle, the revolver,
## the switchboard, kits, tools). Hands send no one-shot actions at all. Server-only.

## The holds a Hand may ever drive, and when.
const JOB_HOLDS: int = InputRecord.HOLD_INTERACT
const RELIGHT_HOLDS: int = InputRecord.HOLD_RELIGHT


## `record` as the Hand may drive it: holds outside `allowed` cleared. Returns the stripped bits.
static func strip(record: InputRecord, allowed: int) -> int:
	var refused: int = record.holds & ~allowed
	record.holds &= allowed
	return refused


## The holds a Hand in this state may drive: the interact only while its POINTed job acts, the
## flint only while it relights its own lamp.
static func allowed_for(acting: bool, relighting: bool) -> int:
	return (JOB_HOLDS if acting else 0) | (RELIGHT_HOLDS if relighting else 0)
