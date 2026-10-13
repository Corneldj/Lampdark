extends GutTest
## NET-05: flame states (trembling, guttering, the blue cap, silent shrinking) and any light but
## the own lamp come only from server records, never from client prediction; another entity
## never moves without a frame.


func test_no_client_code_predicts_a_flame_state() -> void:
	var pattern: RegEx = RegEx.create_from_string("(?i)gutter|tremble|blue_cap|flame_state|blackdamp|shrink")
	for dir: String in ["res://client/net", "res://shared/sim"]:
		for file: String in DirAccess.get_files_at(dir):
			if not file.ends_with(".gd"):
				continue
			var text: String = FileAccess.get_file_as_string(dir.path_join(file))
			for line: String in text.split("\n"):
				if line.strip_edges().begins_with("#"):
					continue
				assert_null(pattern.search(line), "%s/%s: %s" % [dir, file, line.strip_edges()])
	var lamp: Dictionary = Prediction.new().lamp()
	assert_eq(lamp.keys(), ["position", "shutter_closed", "wick", "radius"], "the predicted lamp: a position, the wanted state and its pool")


func test_other_entities_move_only_with_frames() -> void:
	var b: InterpolationBuffer = InterpolationBuffer.new()
	var v: ReceivedView = ReceivedView.new()
	v.entities[3] = {"level": 2, "size_or_kind": 1, "position": Vector2(4, 4)}
	b.push(10, v)
	var first: Vector2 = Variants.dict(b.sample(10.0)[3])["position"]
	var later: Vector2 = Variants.dict(b.sample(30.0)[3])["position"]
	assert_eq(later, first, "a lone frame: held where the server put it")
