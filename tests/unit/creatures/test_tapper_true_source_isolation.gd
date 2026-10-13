extends GutTest
## CRT-08 and CRT-09: movement and targeting never read SND-01's true_source. A static scan: only
## the hearing (which records it) and the strike check (tapper_strike.gd, which the design allows
## with the Inquiry) read it or the truth behind a heard event.

const DIR: String = "res://server/creatures/tapper"


func test_no_true_source() -> void:
	for f: String in DirAccess.get_files_at(DIR):
		if not f.ends_with(".gd") or f == "tapper_hearing.gd" or f == "tapper_strike.gd":
			continue
		for line: String in FileAccess.get_file_as_string(DIR.path_join(f)).split("\n"):
			if line.strip_edges().begins_with("#"):
				continue
			assert_false(line.contains("true_source") or line.contains("truth_of") or line.contains("true_tile"), "%s: %s" % [f, line.strip_edges()])
	var heard: TapperHearing.HeardEvent = TapperHearing.HeardEvent.new()
	assert_false("true_source" in heard, "a heard event has no true source")
	assert_false("source_entity" in heard, "nor an identity")
