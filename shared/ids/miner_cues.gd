class_name MinerCues
extends RefCounted
## MNR-03's body cues: how a miner's state shows on the body, never as a number. Bits, since a
## held miner can also limp. Sent only on an identity record (light 0.30, VIS-03); a fringe token
## carries none. Rock-touched has no cue, and egg-glow is a real light (CRT-06), not a bit.
## Wire values: append only.

const LIMP: int = 1 << 0          ## Hurt or a trap wound: silent
const COUGH: int = 1 << 1         ## soot-lung (HAZ-06 makes the sound)
const HELD_JAWS: int = 1 << 2     ## Caught in a man-trap
const HELD_PROP: int = 1 << 3     ## Caught under a timber pin
const HELD_PIT: int = 1 << 4      ## Caught in a staple pit
const HALF_IN_WALL: int = 1 << 5  ## Grabbed by a Tapper pin
const DRAGGED: int = 1 << 6       ## Grabbed by a Stythe drag (or a body being dragged)
const LYING_BREATHING: int = 1 << 7  ## Unconscious
const LYING_STILL: int = 1 << 8      ## Dead
## VIS-06: the cap badge (0-5: clear, green, violet, grey, rose, brown; 7 none) in bits 13-15, on the
## same identity-only record: a fringe token never shows it.
const BADGE_SHIFT: int = 13
const BADGE_MASK: int = 7 << BADGE_SHIFT
const BADGE_NONE: int = 7


static func with_badge(cues: int, badge: int) -> int:
	return (cues & ~BADGE_MASK) | ((badge & 7) << BADGE_SHIFT)


static func badge_of(cues: int) -> int:
	return (cues & BADGE_MASK) >> BADGE_SHIFT
