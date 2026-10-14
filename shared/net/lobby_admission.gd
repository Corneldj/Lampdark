class_name LobbyAdmission
extends RefCounted
## STM-02's admission rule (GDD §13.8), applied by the game server from M2 (the host's client hands it
## the lobby's members over STM-04's control link; STM-03 calls judge() for every connection, since
## any signed-in owner who learns the server identity can try one). A SteamID is seated only if it is
## a lobby member; it entered the code, owns the lobby, or a seated member's client vouches that it is
## their Steam friend (invites and friends-list joins come only from friends); and the crew is not full.

enum Verdict { SEAT, NOT_MEMBER, NOT_INVITED, FULL }


## `members`: the lobby's SteamIDs; `code_users`: SteamIDs that joined by the code; `vouched`:
## SteamIDs a seated member's client vouched for; `seated`: SteamIDs already seated; `limit`:
## modes.friends_lobby_max.
static func judge(steam_id: int, owner: int, members: PackedInt64Array, code_users: Dictionary, vouched: Dictionary,
		seated: PackedInt64Array, limit: int) -> Verdict:
	if not members.has(steam_id):
		return Verdict.NOT_MEMBER
	if steam_id != owner and not code_users.has(steam_id) and not vouched.has(steam_id):
		return Verdict.NOT_INVITED
	if not seated.has(steam_id) and seated.size() >= limit:
		return Verdict.FULL
	return Verdict.SEAT
