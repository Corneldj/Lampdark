class_name LobbyRendezvousWire
extends RefCounted
## STM-02's dev-mode lobby rendezvous (FakeLobbyBackend to the dev server's LobbyRendezvous): JSON
## messages on the reliable control lane, dev, QA and kill-test builds only. Client to server: hello
## {id, name}, create {limit}, join {lobby}, leave, set_data {key, value}, set_member_data {key, value},
## set_joinable {on}, set_limit {limit}, search {filters}. Server to client: created {lobby, ok},
## entered {lobby, response}, state {lobby, owner, limit, joinable, data, members: [{id, name, data}]},
## left {lobby}, results {lobbies}.


static func encode(message: Dictionary) -> PackedByteArray:
	return JSON.stringify(message).to_utf8_buffer()


static func decode(data: PackedByteArray) -> Dictionary:
	var parsed: Variant = JSON.parse_string(data.get_string_from_utf8())
	return parsed if parsed is Dictionary else {}


## The rendezvous port for a game server's port (net.dev_lobby_port_offset above it).
static func port_for(game_port: int) -> int:
	return game_port + Tuning.i(&"net.dev_lobby_port_offset")
