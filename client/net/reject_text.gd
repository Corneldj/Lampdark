class_name RejectText
## Placeholder English for handshake reject reasons (NET-02), from data/text/.

const PATH: String = "res://data/text/net_reject_reasons.json"


static func text(reason: int) -> String:
	var reasons: Dictionary = Variants.dict(Variants.dict(JSON.parse_string(FileAccess.get_file_as_string(PATH))).get("reasons", {}))
	var name: String = Protocol.reject_name(reason)
	return str(reasons.get(name, name))
