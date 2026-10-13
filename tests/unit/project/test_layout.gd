extends GutTest
## Every folder of the README's code layout exists, and nothing else sits at the top level (FND-01).

const LAYOUT: Array[String] = [
	"addons",
	"native",
	"shared",
	"server", "server/sim", "server/systems", "server/creatures", "server/director",
	"server/world", "server/net", "server/modes",
	"client", "client/render", "client/audio", "client/ui", "client/input", "client/net",
	"data", "data/tuning", "data/templates", "data/text",
	"tests", "tests/unit", "tests/scenario", "tests/fixtures", "tests/support",
	"tools", "tools/bots", "tools/seed_harness", "tools/stream_audit", "tools/build",
]

## Top-level folders that are not part of the layout but may exist locally (ignored by Git).
const IGNORED_TOP_LEVEL: Array[String] = [".godot", "build"]


func test_every_layout_folder_exists() -> void:
	for folder: String in LAYOUT:
		assert_true(DirAccess.dir_exists_absolute("res://" + folder), "res://%s exists" % folder)


func test_no_unlisted_top_level_folders() -> void:
	for folder: String in DirAccess.get_directories_at("res://"):
		if folder in IGNORED_TOP_LEVEL or folder.begins_with("."):
			continue
		assert_has(LAYOUT, folder, "top-level folder %s is in the README layout" % folder)
