extends RefCounted
## Fixtures for CRT-02's tests, as ASCII ('.' floor, '#' rock, 'C' coal, 'B' brick, 'T' timber,
## 'G' shut gate, 'D' shut air door; lowercase letters are named floor spots).


## A long straight road along row 2 from x 1, rock above and below: `length` floor tiles.
static func road(length: int) -> PackedStringArray:
	var w: int = length + 2
	return PackedStringArray(["#".repeat(w), "#".repeat(w), "#" + ".".repeat(length) + "#", "#".repeat(w), "#".repeat(w)])


## Corridors and chambers: two 9 x 9 chambers joined by a 2-wide corridor, a road north.
static func chambers() -> PackedStringArray:
	return PackedStringArray([
		"########################################",
		"#a.....................................#",
		"########.###############.###############",
		"#.........##############.........#######",
		"#.........##############.........#######",
		"#.........##############.........#######",
		"#..........................b.....#######",
		"#..........................c.....#######",
		"#.........##############.........#######",
		"#.........##############.........#######",
		"#.........##############.........#######",
		"#.........##############.........#######",
		"########################################",
		"########################################",
	])
