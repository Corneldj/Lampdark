class_name LampSignalAnim
extends RefCounted
## SND-12: a lamp signal as a watcher's client draws it, from the kind in the maker's flame byte
## (LampSignalKind, identity only): the held flame swung side to side (STOP), raised and lowered
## (COME) or circled (OK). HELP's blinks are the light's own (the server darkens the lamp) and
## POINT's spot is a real light, so neither needs a motion here. Placeholder motions (art pending).

## One motion cycle a second; the swing's reach as a share of a tile.
const HZ: float = 1.0
const REACH: float = 0.28


## The flame's offset (pixels) from where the hand holds it, at time `t`.
static func offset(kind: LampSignalKind.Kind, t: float, px: float) -> Vector2:
	var phase: float = TAU * HZ * t
	var r: float = REACH * px
	match kind:
		LampSignalKind.Kind.STOP:
			return Vector2(sin(phase) * r, 0.0)
		LampSignalKind.Kind.COME:
			return Vector2(0.0, -absf(sin(phase)) * r)
		LampSignalKind.Kind.OK:
			return Vector2(cos(phase), sin(phase)) * r * 0.7
	return Vector2.ZERO
