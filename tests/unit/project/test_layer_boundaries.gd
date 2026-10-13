extends GutTest
## server/ and client/ never reference each other (FND-03). Both may use shared/.
## Checks res:// paths (preload, load, extends) and class_name types declared on the other side.

const EXTENSIONS: Array[String] = ["gd", "tscn", "tres"]


func _collect(dir: String, out: Array[String]) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for file: String in DirAccess.get_files_at(dir):
		if file.get_extension() in EXTENSIONS:
			out.append(dir.path_join(file))
	for sub: String in DirAccess.get_directories_at(dir):
		_collect(dir.path_join(sub), out)


func _files(dir: String) -> Array[String]:
	var out: Array[String] = []
	_collect(dir, out)
	return out


static func declared_class_names(sources: Array[String]) -> Array[String]:
	var names: Array[String] = []
	var pattern: RegEx = RegEx.create_from_string("(?m)^class_name\\s+(\\w+)")
	for source: String in sources:
		for found: RegExMatch in pattern.search_all(source):
			names.append(found.get_string(1))
	return names


## The other side's paths or class names that source mentions.
static func violations(source: String, forbidden_root: String, forbidden_classes: Array[String]) -> Array[String]:
	var found: Array[String] = []
	if source.contains(forbidden_root):
		found.append(forbidden_root)
	for name: String in forbidden_classes:
		if RegEx.create_from_string("\\b%s\\b" % name).search(source) != null:
			found.append(name)
	return found


func _check(side: String, other: String) -> void:
	var other_sources: Array[String] = []
	for path: String in _files("res://" + other):
		other_sources.append(FileAccess.get_file_as_string(path))
	var other_classes: Array[String] = declared_class_names(other_sources)
	var files: Array[String] = _files("res://" + side)
	for path: String in files:
		var found: Array[String] = violations(FileAccess.get_file_as_string(path), "res://%s/" % other, other_classes)
		assert_eq(found, [] as Array[String], "%s references nothing in %s/" % [path, other])
	pass_test("%d files in %s/ checked" % [files.size(), side])


func test_scanner_detects_violations() -> void:
	assert_eq(violations('const M := preload("res://client/ui/x.gd")', "res://client/", []), ["res://client/"] as Array[String])
	assert_eq(violations("var v: ClientView", "res://client/", ["ClientView"] as Array[String]), ["ClientView"] as Array[String])
	assert_eq(violations("var v: ClientViewer", "res://client/", ["ClientView"] as Array[String]), [] as Array[String])
	assert_eq(declared_class_names(["class_name Foo\nextends Node"] as Array[String]), ["Foo"] as Array[String])


func test_server_never_references_client() -> void:
	_check("server", "client")


func test_client_never_references_server() -> void:
	_check("client", "server")
