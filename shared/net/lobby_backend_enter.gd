class_name LobbyBackendEnter
extends RefCounted
## STM-02: Steam's ChatRoomEnterResponse values, shared by the client's lobby backends and the dev
## server's rendezvous (which cannot name client classes).

const SUCCESS: int = 1
const DOESNT_EXIST: int = 2
const NOT_ALLOWED: int = 3
const FULL: int = 4
const ERROR: int = 5
