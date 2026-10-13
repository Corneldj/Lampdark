class_name Bench
extends RefCounted
## LFT-01: the bench holds what is laid on it (an absent miner's lamp and belt, MOD-05). Items on
## it are ordinary items on its tile; this only names the place.

var tile: Vector2i = Vector2i.ZERO


func install(seed_value: int, side: int) -> void:
	tile = Basecamp.fixture(seed_value, "bench", side)[0]["position"]
