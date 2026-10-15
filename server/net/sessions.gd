class_name Sessions
extends RefCounted
## The server's session table (NET-02): slot, identity, transport peer and session token.
## The token lets NET-11 recognise a rejoining player. Server-only.

class Session:
	extends RefCounted
	var slot: int = -1
	var peer: int = -1
	var identity: String = ""
	var seat: int = Protocol.Seat.PLAYER
	var token: String = ""
	var welcomed: bool = false
	var connected_usec: int = 0
	## FND-08: granted the debug channel at the handshake (never on a release server).
	var debug: bool = false
	## SND-10: the crew-list label ('Mute (callouts and taps only)'), as the client last sent it.
	## Shown until the client says otherwise; UI-04's crew list relays it, and nothing else about voice.
	var mute_label: bool = true
	## STM-04's Path B: the SteamID the host's relay vouched for (with the host token), "" otherwise.
	var relayed_identity: String = ""


var max_slots: int = 5
## peer -> Session, for peers that have connected (welcomed or not)
var _by_peer: Dictionary = {}
## token -> Session, kept after a drop so a rejoin can be recognised
var _by_token: Dictionary = {}
## FND-09's scenario kit sets a seeded stream so tokens, and every byte sent, replay exactly.
## Live servers leave it null and draw tokens from the OS's cryptographic source.
var token_rng: LbRng = null


func _init(slots: int = 5) -> void:
	max_slots = slots


func on_connected(peer: int, now_usec: int) -> Session:
	var session: Session = Session.new()
	session.peer = peer
	session.connected_usec = now_usec
	_by_peer[peer] = session
	return session


func for_peer(peer: int) -> Session:
	if not _by_peer.has(peer):
		return null
	var session: Session = _by_peer[peer]
	return session


func find_by_token(token: String) -> Session:
	if token.is_empty() or not _by_token.has(token):
		return null
	var session: Session = _by_token[token]
	return session


## Seats a session in the lowest free slot, never one in `held` (NET-11: a dropped player's), or in
## `forced` when it is free (a rejoining player's own). Returns false when no slot is to be had.
func seat(session: Session, identity: String, seat_kind: int, held: Dictionary = {}, forced: int = -1) -> bool:
	var taken: Dictionary = {}
	for other: Variant in _by_peer.values():
		var s: Session = other
		if s.welcomed:
			taken[s.slot] = true
	for slot: int in max_slots:
		var fits: bool = slot == forced if forced >= 0 else not held.has(slot)
		if fits and not taken.has(slot):
			session.slot = slot
			session.identity = identity
			session.seat = seat_kind
			session.token = _new_token()
			session.welcomed = true
			_by_token[session.token] = session
			return true
	return false


func on_dropped(peer: int) -> Session:
	var session: Session = for_peer(peer)
	_by_peer.erase(peer)
	return session


func welcomed() -> Array[Session]:
	var out: Array[Session] = []
	for value: Variant in _by_peer.values():
		var session: Session = value
		if session.welcomed:
			out.append(session)
	out.sort_custom(func(a: Session, b: Session) -> bool: return a.slot < b.slot)
	return out


func pending() -> Array[Session]:
	var out: Array[Session] = []
	for value: Variant in _by_peer.values():
		var session: Session = value
		if not session.welcomed:
			out.append(session)
	return out


func _new_token() -> String:
	if token_rng == null:
		return Crypto.new().generate_random_bytes(16).hex_encode()
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(16)
	bytes.encode_s64(0, token_rng.next_u64())
	bytes.encode_s64(8, token_rng.next_u64())
	return bytes.hex_encode()
