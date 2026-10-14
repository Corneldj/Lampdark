extends RefCounted
## UI-01's test helpers: a received view with identity records and fringe tokens, and an in-play frame.


## A view with the own miner at `own` (tiles).
static func view(own: Vector2) -> ReceivedView:
	var v: ReceivedView = ReceivedView.new()
	v.own["position"] = own
	return v


## An identity record (level 2) of SeenKind `kind`.
static func identity(v: ReceivedView, token_id: int, kind: int, at: Vector2, cues: int = 0) -> void:
	v.entities[token_id] = {"level": 2, "size_or_kind": kind, "position": at, "facing": 0, "cues": cues, "in_hand": 0, "flame": 0}


## A shape token (level 1, fringe) of SeenKind.Size `size`.
static func token(v: ReceivedView, token_id: int, size: int, at: Vector2) -> void:
	v.entities[token_id] = {"level": 1, "size_or_kind": size, "position": at}


static func frame(v: ReceivedView, router: InputRouter, extra: Dictionary = {}) -> Dictionary:
	var f: Dictionary = {"view": v, "view_origin": Vector2.ZERO, "black": false, "inventory": {}, "feel": FeelClient.new(),
		"router": router, "store": router.store, "wheel_anchor": Vector2(960, 540), "short_side": 1080.0, "now_s": 1.0}
	f.merge(extra, true)
	return f
