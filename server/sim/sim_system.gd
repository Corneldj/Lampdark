class_name SimSystem
extends RefCounted
## The interface every gameplay system registers into the tick (NET-01). Subclasses override
## stage() and order() explicitly, tick() for their work, and write_state()/read_state() for
## snapshots (NET-09). Systems never read the wall clock; time is run.tick. Randomness comes
## only from LbRng streams seeded from the run seed (FND-06).


## One of StageTable.Stage. The default, -1, fails registration.
func stage() -> int:
	return -1


## The order within the stage; unique per stage. The default, -1, fails registration.
func order() -> int:
	return -1


func system_name() -> String:
	var script: Script = get_script()
	return script.resource_path.get_file().get_basename() if script != null else "system"


## False for FND-08's debug systems: they never enter the state hash, so a dev or QA run and a
## release run of the same inputs hash alike. Gameplay systems leave it true.
func hashed() -> bool:
	return true


func tick(_run: RunState) -> void:
	pass


func write_state(_writer: SimStateWriter) -> void:
	pass


func read_state(_reader: SimStateReader) -> void:
	pass


## NET-09: the system's lasting state for a snapshot or a knock-off save, as plain values
## (var_to_bytes-able: no objects, no callables). {} when it keeps nothing a resume needs:
## transient state (actions, wind-ups, the noise log) starts afresh on a resume.
func save_state() -> Dictionary:
	return {}


## NET-09: a resume puts back what save_state() wrote, after every system is installed and the
## registry restored (the systems load in stage order).
func load_state(_run: RunState, _state: Dictionary) -> void:
	pass
