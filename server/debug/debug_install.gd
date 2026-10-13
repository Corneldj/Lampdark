extends RefCounted
## FND-08: installs the debug channel's server end (DebugServer, QaOverlayTagger, TruthPublisher)
## into a run. ServerSystems loads this file by path, and only outside release builds, so no
## release script names a debug class.


static func install(run: RunState, net: ServerNet) -> void:
	var server: DebugServer = DebugServer.new(net)
	run.add_system(server)
	run.add_system(QaOverlayTagger.new(net, server))
	run.add_system(TruthPublisher.new(net, server))
	run.debug = server
