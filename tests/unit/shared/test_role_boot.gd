extends GutTest
## Role and flavour chosen from injected feature tags (FND-03).


func _build(tags: Array[String]) -> BuildInfo:
	return BuildInfo.detect(FeatureProvider.Fixed.new(PackedStringArray(tags)))


func test_flavour_from_tags() -> void:
	assert_eq(_build(["editor"]).flavour, BuildInfo.Flavour.DEV)
	assert_eq(_build(["lb_client", "lb_qa"]).flavour, BuildInfo.Flavour.QA)
	assert_eq(_build(["lb_server", "lb_release"]).flavour, BuildInfo.Flavour.RELEASE)


func test_untagged_export_fails_closed_to_release() -> void:
	assert_eq(_build(["lb_client"]).flavour, BuildInfo.Flavour.RELEASE)
	assert_true(_build([]).is_release())


func test_server_export_is_always_server() -> void:
	assert_eq(_build(["lb_server", "lb_release"]).role_for(false), BuildInfo.Role.SERVER)
	assert_eq(_build(["lb_server", "lb_qa"]).role_for(false), BuildInfo.Role.SERVER)


func test_client_export_is_always_client() -> void:
	assert_eq(_build(["lb_client", "lb_qa"]).role_for(true), BuildInfo.Role.CLIENT, "--server cannot turn a client export into a server")
	assert_eq(_build(["lb_client", "lb_release"]).role_for(true), BuildInfo.Role.CLIENT)


func test_editor_runs_choose_by_flag() -> void:
	assert_eq(_build(["editor"]).role_for(false), BuildInfo.Role.CLIENT)
	assert_eq(_build(["editor"]).role_for(true), BuildInfo.Role.SERVER)


func test_kill_test_tag() -> void:
	var info: BuildInfo = _build(["lb_client", "lb_qa", "lb_killtest"])
	assert_true(info.kill_test)
	assert_eq(info.flavour, BuildInfo.Flavour.QA)


func test_server_config_constructible_without_boot() -> void:
	var config: ServerConfig = ServerConfig.new()
	assert_eq(config.mode, ServerConfig.Mode.FRIENDS)
	assert_eq(config.exit_after_ticks, 0)
	assert_not_null(config.build)
