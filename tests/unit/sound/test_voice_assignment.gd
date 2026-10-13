extends GutTest
## SND-13 (Proposed): voices are unique within a run of up to five miners plus Hired Hands, a clash
## giving the later joiner the first free voice, and the same roster in the same join order always
## gets the same voices.


func _roster(voices: Array[int]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in voices.size():
		out.append({"miner": 100 + i, "voice": voices[i], "name": "miner %d" % i})
	return out


func test_unique_for_five_and_hands() -> void:
	var got: Dictionary = VoiceAssignment.assign(_roster([3, 3, 5, 3, 0]), 3)
	var miners: Dictionary = got["miners"]
	assert_eq(int(Variants.number(miners[100])), 3, "the first joiner keeps theirs")
	assert_eq(int(Variants.number(miners[101])), 0, "a clash: the first free voice")
	assert_eq(int(Variants.number(miners[102])), 5, "no clash: kept")
	assert_eq(int(Variants.number(miners[103])), 1, "another clash: the next free")
	assert_eq(int(Variants.number(miners[104])), 2, "wanted 0, taken by an earlier joiner")
	var all: Array[int] = []
	for v: Variant in miners.values():
		all.append(int(Variants.number(v)))
	for v: int in Variants.array(got["hands"]):
		all.append(v)
	assert_eq(all.size(), 8)
	var unique: Dictionary = {}
	for v: int in all:
		unique[v] = true
	assert_eq(unique.size(), 8, "five miners and three Hands, eight voices")


func test_deterministic_and_order_matters() -> void:
	var a: Dictionary = VoiceAssignment.assign(_roster([-1, -1, 2, 2]), 1)
	assert_eq(VoiceAssignment.assign(_roster([-1, -1, 2, 2]), 1), a, "same roster, same order: same voices")
	var swapped: Array[Dictionary] = _roster([2, 2])
	var first: Dictionary = VoiceAssignment.assign(swapped, 0)
	assert_eq(int(Variants.number(Variants.dict(first["miners"])[100])), 2, "the earlier joiner keeps the voice")
	assert_ne(int(Variants.number(Variants.dict(first["miners"])[101])), 2)


func test_default_from_the_name() -> void:
	assert_eq(VoiceAssignment.default_for("Ada Rowe"), VoiceAssignment.default_for("Ada Rowe"))
	assert_between(VoiceAssignment.default_for("Ada Rowe"), 0, 7)
	var spread: Dictionary = {}
	for i: int in 64:
		spread[VoiceAssignment.default_for("name %d" % i)] = true
	assert_eq(spread.size(), 8, "names spread over every voice")
	var got: Dictionary = VoiceAssignment.assign([{"miner": 1, "voice": -1, "name": "Ada Rowe"}] as Array[Dictionary], 0)
	assert_eq(int(Variants.number(Variants.dict(got["miners"])[1])), VoiceAssignment.default_for("Ada Rowe"), "no choice: the name's voice")
