extends GutTest
## STM-01: the app ID by build flavour (lampblack/steam/app_id with feature-tag overrides). The real
## app is 5110670; Spacewar's 480 never reaches a release build (check_steam_app_id.sh fails CI on it).


func test_app_ids() -> void:
	assert_eq(int(Variants.number(ProjectSettings.get_setting("lampblack/steam/app_id", 0))), 5110670, "dev and QA")
	var release: int = int(Variants.number(ProjectSettings.get_setting("lampblack/steam/app_id.lb_release", 0)))
	assert_eq(release, 5110670, "release: the real app")
	assert_ne(release, 480)
	assert_eq(SteamService.app_id(), 5110670, "this (editor, untagged) run reads the base setting")


func test_the_editor_app_id_file_matches_and_is_never_packed() -> void:
	assert_eq(FileAccess.get_file_as_string("res://steam_appid.txt").strip_edges(), "5110670")
	var cfg: ConfigFile = ConfigFile.new()
	assert_eq(cfg.load("res://export_presets.cfg"), OK)
	for section: String in cfg.get_sections():
		if not section.ends_with(".options") and cfg.has_section_key(section, "include_filter"):
			var include: String = str(cfg.get_value(section, "include_filter"))
			assert_false(include.contains("*.txt") or include.contains("steam_appid"), "%s never packs steam_appid.txt" % section)


func test_servers_exclude_godotsteam() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	assert_eq(cfg.load("res://export_presets.cfg"), OK)
	var servers: int = 0
	for section: String in cfg.get_sections():
		if section.ends_with(".options") or not cfg.has_section_key(section, "custom_features"):
			continue
		if str(cfg.get_value(section, "custom_features")).contains("lb_server"):
			servers += 1
			assert_true(str(cfg.get_value(section, "exclude_filter")).contains("addons/godotsteam/*"), "%s carries no GodotSteam" % section)
	assert_eq(servers, 4)
