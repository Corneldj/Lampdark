extends GutTest
## Hot reload: a valid edit swaps in at a tick boundary with one signal; an invalid edit
## changes nothing; release builds never poll (FND-05).

const Fixture = preload("res://tests/unit/shared/tuning/tuning_fixture.gd")
const TuningNode = preload("res://shared/tuning/tuning.gd")

var tuning: TuningNode
var dir: String
var signals: Array[PackedStringArray] = []


func before_each() -> void:
	dir = Fixture.write("valid_set")
	tuning = TuningNode.new()
	tuning.data_dir = dir
	tuning.overrides_path = ""
	tuning.require_all_domains = false
	add_child_autofree(tuning)
	signals.clear()
	tuning.tuning_changed.connect(func(keys: PackedStringArray) -> void: signals.append(keys))


func _load() -> void:
	# Fixtures hold only two domains, so load the set directly rather than via load_server().
	var built: TuningSet = TuningSet.new()
	assert_eq(built.load_directory(dir, false), [] as Array[String])
	tuning.current = built
	tuning.poll_files()
	tuning.on_tick_boundary()


func _edit_moth(key: String, value: Variant) -> void:
	var fixture: Dictionary = Fixture.read("valid_set")
	var moth: Dictionary = Variants.dict(Variants.dict(fixture["files"])["moth.json"])
	Variants.dict(Variants.dict(moth["keys"])[key])["value"] = value
	Fixture.store(dir.path_join("moth.json"), moth)


func _current() -> TuningSet:
	return tuning.current


func test_valid_edit_applies_at_tick_boundary_with_one_signal() -> void:
	_load()
	_edit_moth("moth.lamps", 9)
	tuning.poll_files()
	assert_true(tuning.has_pending(), "the edit is staged")
	assert_eq(_current().i(&"moth.lamps"), 3, "not applied before the tick boundary")
	tuning.on_tick_boundary()
	assert_eq(_current().i(&"moth.lamps"), 9)
	assert_eq(signals.size(), 1, "one tuning_changed")
	assert_eq(signals[0], PackedStringArray(["moth.lamps"]))


func test_invalid_edit_changes_nothing() -> void:
	_load()
	var before: String = _current().content_hash()
	_edit_moth("moth.windup_s", 0.1)
	tuning.poll_files()
	assert_false(tuning.has_pending(), "nothing staged")
	tuning.on_tick_boundary()
	assert_eq(_current().content_hash(), before)
	assert_eq(signals.size(), 0)
	assert_push_error("below min 0.4")


func test_poller_sees_an_edit_within_two_seconds() -> void:
	_load()
	tuning.enable_hot_reload(true)
	assert_true(tuning.is_polling())
	_edit_moth("moth.lamps", 4)
	await wait_until(func() -> bool: return tuning.has_pending(), 2.0)
	assert_true(tuning.has_pending(), "staged within 2 s")
	tuning.on_tick_boundary()
	assert_eq(_current().i(&"moth.lamps"), 4)


func test_release_never_polls() -> void:
	var release: BuildInfo = BuildInfo.detect(FeatureProvider.Fixed.new(PackedStringArray(["lb_server", "lb_release"])))
	assert_false(release.allows_tuning_hot_reload(true), "release refuses even when asked")
	tuning.enable_hot_reload(release.allows_tuning_hot_reload(true))
	assert_false(tuning.is_polling())


func test_dev_and_qa_rules() -> void:
	var dev: BuildInfo = BuildInfo.detect(FeatureProvider.Fixed.new(PackedStringArray(["editor"])))
	var qa: BuildInfo = BuildInfo.detect(FeatureProvider.Fixed.new(PackedStringArray(["lb_server", "lb_qa"])))
	assert_true(dev.allows_tuning_hot_reload(false))
	assert_false(qa.allows_tuning_hot_reload(false))
	assert_true(qa.allows_tuning_hot_reload(true))
