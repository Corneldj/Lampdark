class_name Palette
extends RefCounted
## VIS-06 (GDD §14.1): the palette, each colour for one thing only. Pure black is "no data" and
## never painted (VIS-05). Light colours follow VIS-02's colour classes on the wire. Badges, UI and
## close-ups never use amber, umber, egg-glow or firedamp blue; magenta is FND-08's QA overlay only.
## Placeholder values until final art; test_palette_lint.gd keeps the rules.

const COAL: Color = Color(0.105, 0.085, 0.07)        ## everything lit (grained brown-black)
const LAMP_AMBER: Color = Color(1.0, 0.72, 0.36)     ## flame light
const PALE_AMBER: Color = Color(1.0, 0.88, 0.72)     ## flares and the muzzle flash, palest
const CAMP_WHITE: Color = Color(0.93, 0.96, 1.0)     ## electric light, whiter than any flame, steady
const CHALK_WHITE: Color = Color(0.86, 0.86, 0.82)   ## chalk marks
const PENCIL_GREY: Color = Color(0.42, 0.42, 0.45)   ## the map table and Pocket Book
const BLOOD_UMBER: Color = Color(0.38, 0.19, 0.11)   ## blood trails
const EGG_GLOW: Color = Color(0.72, 0.96, 0.78)      ## egg-glow: green-white, apart from chalk
const FIREDAMP_BLUE: Color = Color(0.45, 0.62, 1.0)  ## a flame's cap only
const GOB_ORANGE: Color = Color(1.0, 0.44, 0.1)      ## gob fires only
const EMBER_RED: Color = Color(0.5, 0.09, 0.05)      ## the Black Seam's lit coal only
const QA_MAGENTA: Color = Color(1.0, 0.0, 1.0)       ## FND-08's illusion overlay only
const SHADOW_TONE: Color = Color(0.03, 0.025, 0.02)   ## VIS-09's shadow tell, laid over lit floor (never opaque)
const DUST_GREY: Color = Color(0.78, 0.74, 0.66)     ## VIS-09's dust haze, puffs and bursts

## VIS-02's light::ColourClass on the wire: NONE, AMBER, PALE_AMBER, WHITE, EGG_GLOW, GOB_ORANGE.
const CLASS_COLOURS: Array[Color] = [COAL, LAMP_AMBER, PALE_AMBER, CAMP_WHITE, EGG_GLOW, GOB_ORANGE]
const CLASS_PALE_AMBER: int = 2

## Cap badges: a glass disc in one of six colours, each engraved with a pattern, so identity never
## rests on colour (clear plain, green cross, violet bar, grey dot, rose chevron, brown ring).
const BADGE_COLOURS: Array[Color] = [Color(0.82, 0.86, 0.9), Color(0.24, 0.56, 0.3), Color(0.47, 0.3, 0.66),
	Color(0.55, 0.55, 0.55), Color(0.88, 0.46, 0.58), Color(0.55, 0.43, 0.33)]
const BADGE_PATTERNS: Array[String] = ["plain", "cross", "bar", "dot", "chevron", "ring"]

## Colours no badge, UI or close-up may come near.
const RESERVED_FOR_WORLD: Array[Color] = [LAMP_AMBER, BLOOD_UMBER, EGG_GLOW, FIREDAMP_BLUE]


static func class_colour(colour_class: int) -> Color:
	return CLASS_COLOURS[colour_class] if colour_class >= 0 and colour_class < CLASS_COLOURS.size() else COAL


static func distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()
