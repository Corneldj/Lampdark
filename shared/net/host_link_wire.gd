class_name HostLinkWire
extends RefCounted
## STM-04's control link between a private host's client and its server process: JSON on the
## reliable control lane of a loopback ENet connection. SteamIDs travel as strings (JSON numbers are
## doubles). The server prints one ready line on stdout:
##   LB_READY control=<port> token=<hex> game=<port> identity=<steamid or 0> vport=<base>
## Host to server: auth {token} first, then members {owner, ids, code_users, vouched}, options {...},
## status, shutdown. Server to host: status {clients, identity, logged_on}, bye {reason}.

const READY_PREFIX: String = "LB_READY "


static func encode(message: Dictionary) -> PackedByteArray:
	return JSON.stringify(message).to_utf8_buffer()


static func decode(data: PackedByteArray) -> Dictionary:
	var parsed: Variant = JSON.parse_string(data.get_string_from_utf8())
	return parsed if parsed is Dictionary else {}


static func ready_line(control_port: int, token: String, game_port: int, identity: int, vport: int) -> String:
	return "%scontrol=%d token=%s game=%d identity=%d vport=%d" % [READY_PREFIX, control_port, token, game_port, identity, vport]


## The ready line's fields ({} when `line` is not one).
static func parse_ready(line: String) -> Dictionary:
	var at: int = line.find(READY_PREFIX)
	if at < 0:
		return {}
	var out: Dictionary = {}
	for part: String in line.substr(at + READY_PREFIX.length()).strip_edges().split(" ", false):
		var kv: PackedStringArray = part.split("=", true, 1)
		if kv.size() == 2:
			out[kv[0]] = kv[1]
	for key: String in ["control", "token", "game", "identity", "vport"]:
		if not out.has(key):
			return {}
	return out


static func ids_to_strings(ids: PackedInt64Array) -> Array:
	var out: Array = []
	for id: int in ids:
		out.append(str(id))
	return out


static func strings_to_ids(raw: Variant) -> PackedInt64Array:
	var out: PackedInt64Array = PackedInt64Array()
	for s: Variant in Variants.array(raw):
		out.append(str(s).to_int())
	return out
