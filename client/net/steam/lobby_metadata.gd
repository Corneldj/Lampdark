class_name LobbyMetadata
extends RefCounted
## STM-02's lobby and member data (Proposed keys). Lobby data never carries the seed, the draw, the
## staging level, the plan or any miner's state (MOD-03), and a release build never writes an address
## or port: lb_dev_addr is for dev, QA and kill-test builds only.

const GAME: String = "lampblack"
## lb_state values.
const PITHEAD: String = "pithead"
const RUNNING: String = "running"
const LAMP_CHECK: String = "lamp_check"

const LOBBY_KEYS: Array[String] = ["lb_game", "lb_build", "lb_proto", "lb_mode", "lb_list", "lb_hard", "lb_hands", "lb_state",
	"lb_resume", "lb_server", "lb_code", "lb_dev_addr"]
const MEMBER_KEYS: Array[String] = ["lb_ready", "lb_name", "lb_lamp", "lb_badge", "lb_muted"]
## STM-04: how a member came in ("code" or "invite"), for the host's admission lists.
const MEMBER_VIA: String = "lb_via"
## MOD-03's RunOptions as a dictionary, when the lobby has set none: the Escape (a friends lobby), the
## Standard list, no hard variant, no Hands.
const DEFAULT_OPTIONS: Dictionary = {"mode": "friends", "list": "standard", "hard": "", "hands": false}


## Every lobby key. `options`: RunOptions as a dictionary; `server`: STM-04's identity (M2+).
static func lobby_data(options: Dictionary, state: String, code: String, dev_addr: String, release: bool, resume: String = "",
		server: String = "") -> Dictionary:
	var o: Dictionary = DEFAULT_OPTIONS.duplicate()
	o.merge(options, true)
	var d: Dictionary = {
		"lb_game": GAME,
		"lb_build": Protocol.build_id(),
		"lb_proto": str(Protocol.PROTOCOL_VERSION),
		"lb_mode": str(o["mode"]),
		"lb_list": str(o["list"]),
		"lb_hard": str(o["hard"]),
		"lb_hands": "1" if Variants.flag(o["hands"]) else "0",
		"lb_state": state,
		"lb_resume": resume,
		"lb_server": server,
		"lb_code": code,
		"lb_dev_addr": "" if release else dev_addr,
	}
	return d


## A member's own data, for UI-04's crew list before a run.
static func member_data(ready: bool, miner_name: String, lamp: int, badge: int, muted: bool) -> Dictionary:
	return {"lb_ready": "1" if ready else "0", "lb_name": miner_name, "lb_lamp": str(lamp), "lb_badge": str(badge),
		"lb_muted": "1" if muted else "0"}


## Whether a lobby is this game's and this build's (searches filter on these too; a stale result
## or an invite into another build is refused with "Different version").
static func compatible(data: Dictionary) -> bool:
	return str(data.get("lb_game", "")) == GAME and str(data.get("lb_build", "")) == Protocol.build_id() \
		and str(data.get("lb_proto", "")) == str(Protocol.PROTOCOL_VERSION)


## The search for a code: this game, this build, the code (worldwide).
static func code_filters(code: String) -> Dictionary:
	return {"lb_game": GAME, "lb_build": Protocol.build_id(), "lb_code": code}
