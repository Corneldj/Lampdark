class_name QaOverlayTagger
extends SimSystem
## FND-08 (GDD §15.7): the QA overlay's tags. On a dev or QA server, each illusion a frame carried
## to a miner is followed, the same tick, by one debug-lane tag naming its lie-log id, by the frame
## tick and record number, to that client alone and only while its overlay is on. A tag never rides
## inside a normal-stream record. Stage SEND, after Replication. Never in the state hash.

var net: ServerNet = null
var debug: DebugServer = null
## {slot, tick, number, illusion_id} tagged (tests).
var tagged: Array[Dictionary] = []


func _init(server_net: ServerNet, debug_server: DebugServer) -> void:
	net = server_net
	debug = debug_server


func stage() -> int:
	return StageTable.Stage.SEND


func order() -> int:
	return 40


func system_name() -> String:
	return "qa_overlay_tagger"


func hashed() -> bool:
	return false


func tick(run: RunState) -> void:
	if run.replication == null or net.flavour == BuildInfo.Flavour.RELEASE:
		return
	for sent: Dictionary in run.replication.illusions_sent:
		var slot: int = int(Variants.number(sent["slot"]))
		if not Variants.flag(debug.subscription(slot).get("overlay", false)):
			continue
		for s: Sessions.Session in net.sessions.welcomed():
			if s.slot == slot and s.debug:
				net.transport.send(s.peer, Lane.Id.DEBUG, Protocol.frame(Protocol.Msg.DEBUG_TAG, DebugMessages.encode(sent)))
				tagged.append(sent)
	net.transport.flush()
