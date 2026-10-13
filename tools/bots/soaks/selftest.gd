extends "res://tools/bots/soak.gd"
## The per-push self-test (FND-09): 60 s, 1 server, 2 bots, loopback.


func setup(_ctx: Dictionary) -> void:
	profile = {"servers": 1, "bots": 2, "minutes": 1.0, "seed": 9001, "brains": ["wander", "chatter"], "link": ""}


func verify(report: Dictionary) -> Array[String]:
	return standard_checks(report, roundi(float(Variants.number(profile["minutes"])) * 1200.0))
