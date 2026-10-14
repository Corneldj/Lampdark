extends "res://tools/bots/soaks/stream_audit_push.gd"
## NET-08's nightly audit (FND-04's stream_audit slot): the push audit's mine and checks, 30 minutes
## of four bots.


func setup(ctx: Dictionary) -> void:
	super(ctx)
	profile["minutes"] = 30.0
	profile["seed"] = 8081
