extends GutTest
## FND-08: the shared command registry's parser: syntax, defaults, clamping, refusals, help.


func _p(line: String) -> Dictionary:
	return DebugCommands.parse(line)


func _args(line: String) -> Dictionary:
	return Variants.dict(_p(line)["args"])


func _arg(line: String, key: String) -> Variant:
	return _args(line).get(key)


func test_spawn_forms() -> void:
	var a: Dictionary = _p("spawn moth")
	assert_true(Variants.flag(a["ok"]))
	assert_eq(Variants.dict(a["args"]), {"what": "moth", "at": "here", "state": ""}, "here by default")
	assert_eq(_args("spawn tapper 12 -3 listen"), {"what": "tapper", "at": Vector2i(12, -3), "state": "listen"})
	assert_eq(_args("spawn stythe here hunt"), {"what": "stythe", "at": "here", "state": "hunt"})
	assert_eq(_args("spawn item flare 4 5"), {"what": "item", "item": "flare", "at": Vector2i(4, 5), "state": ""})
	assert_false(Variants.flag(_p("spawn dragon")["ok"]))
	assert_false(Variants.flag(_p("spawn moth 3")["ok"]), "x without y")
	assert_false(Variants.flag(_p("spawn item")["ok"]))
	assert_false(Variants.flag(_p("spawn item flare 1 2 extra")["ok"]))


func test_teleport_and_targets() -> void:
	assert_eq(_args("teleport me 3 4"), {"who": "me", "tile": Vector2i(3, 4)})
	assert_eq(_args("teleport 2 -1 9"), {"who": 2, "tile": Vector2i(-1, 9)})
	assert_false(Variants.flag(_p("teleport all 1 1")["ok"]), "teleport takes one miner")
	assert_false(Variants.flag(_p("teleport me 1")["ok"]))


func test_clamping() -> void:
	var pull: Dictionary = _p("set_pull all 150")
	assert_true(Variants.flag(pull["ok"]))
	assert_eq(float(Variants.number(Variants.dict(pull["args"]).get("value"))), 100.0)
	assert_true(Variants.flag(pull["clamped"]))
	assert_eq(float(Variants.number(_arg("set_intensity 1 -20", "value"))), 0.0)
	assert_false(Variants.flag(_p("set_intensity 1 50")["clamped"]))
	var ring: Dictionary = _p("ring_override 9")
	assert_eq(int(Variants.number(Variants.dict(ring["args"]).get("ring"))), 4)
	assert_true(Variants.flag(ring["clamped"]))
	assert_eq(int(Variants.number(_arg("ring_override off", "ring"))), -1)
	var deaf: Dictionary = _p("deafen me 500")
	assert_eq(float(Variants.number(Variants.dict(deaf["args"]).get("seconds"))), 60.0)
	assert_true(Variants.flag(deaf["clamped"]))
	assert_eq(float(Variants.number(_arg("deafen 1", "seconds"))), -1.0, "the default duration")


func test_switches() -> void:
	assert_eq(_args("freeze_ai on"), {"on": true})
	assert_eq(_args("apex off"), {"on": false})
	assert_eq(_args("creatures off tapper"), {"on": false, "kind": "tapper"})
	assert_eq(_args("creatures on"), {"on": true, "kind": ""})
	var some: PackedStringArray = _arg("truth on light vision", "layers")
	assert_eq(some, PackedStringArray(["light", "vision"]))
	var every: PackedStringArray = _arg("truth on", "layers")
	assert_eq(every, PackedStringArray(DebugCommands.LAYERS), "every layer by default")
	assert_false(Variants.flag(_p("truth on xray")["ok"]))
	assert_false(Variants.flag(_p("freeze_ai maybe")["ok"]))
	assert_eq(_args("listener_mode screen_up"), {"mode": "screen_up"})
	assert_eq(_args("tuning set moth.speed 2.5"), {"action": "set", "key": "moth.speed", "value": "2.5"})
	assert_eq(_args("tuning reload"), {"action": "reload"})


func test_refusals_and_help() -> void:
	assert_false(Variants.flag(_p("")["ok"]))
	assert_string_contains(str(_p("explode")["error"]), "unknown command")
	assert_string_contains(str(_p("teleport")["error"]), "usage: teleport")
	assert_string_contains(DebugCommands.help(), "spawn")
	assert_string_contains(DebugCommands.help("freeze_ai"), "freeze_ai <on|off>")
	assert_true(DebugCommands.taints("teleport"))
	assert_false(DebugCommands.taints("truth"))
	assert_false(DebugCommands.taints("seed"))
	assert_eq(DebugCommands.where("listener_mode"), DebugCommands.Where.CLIENT)
	assert_eq(DebugCommands.where("spawn"), DebugCommands.Where.SERVER)
