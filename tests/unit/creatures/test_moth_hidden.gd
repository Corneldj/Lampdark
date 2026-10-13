extends GutTest
## CRT-03: the stir clock, the hunger timer, the roost and the fact that a heap is the Moth stay
## on the server: no client code names them (the runtime audit is NET-08's).


func test_client_code_never_names_the_sleep() -> void:
	var pattern: RegEx = RegEx.create_from_string("MothSleep|\\bMoth\\b|hunger_at|stir_clock|roost")
	for dir: String in ["res://client", "res://shared/net"]:
		for path: String in _files(dir):
			for line: String in FileAccess.get_file_as_string(path).split("\n"):
				if line.strip_edges().begins_with("#"):
					continue
				assert_null(pattern.search(line), "%s: %s" % [path, line.strip_edges()])


func _files(dir: String) -> Array[String]:
	var out: Array[String] = []
	for f: String in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d: String in DirAccess.get_directories_at(dir):
		out.append_array(_files(dir.path_join(d)))
	return out
