extends GutTest
## Transport rules: the unreliable size cap, lane checks, release binds loopback only (NET-02).


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_unreliable_payload_over_the_cap_is_refused() -> void:
	var hub: InProcessTransport.Hub = InProcessTransport.Hub.new()
	var server: InProcessTransport = InProcessTransport.new(hub)
	server.listen("s", 1)
	var client: InProcessTransport = InProcessTransport.new(hub)
	var peer: int = client.connect_to("s", 1)
	client.poll()
	assert_eq(client.unreliable_max_bytes, 1200)
	var big: PackedByteArray = PackedByteArray()
	big.resize(1201)
	assert_eq(client.send(peer, Lane.Id.FRAMES, big), ERR_INVALID_PARAMETER)
	assert_push_error("exceed the 1200-byte unreliable limit")
	assert_eq(client.send(peer, Lane.Id.VOICE, big.slice(0, 1200)), OK, "1200 bytes fits")
	assert_eq(client.send(peer, Lane.Id.BULK, big), OK, "reliable lanes may be larger")
	assert_eq(client.send(peer, 7, big), ERR_INVALID_PARAMETER)
	assert_push_error("no lane 7")


func test_release_binds_loopback_only() -> void:
	var release: BuildInfo = BuildInfo.detect(FeatureProvider.Fixed.new(PackedStringArray(["lb_server", "lb_release"])))
	var refused: EnetTransport = EnetTransport.new()
	refused.build = release
	assert_eq(refused.listen("0.0.0.0", 0), ERR_UNAUTHORIZED)
	assert_push_error("release builds bind only to 127.0.0.1")
	assert_eq(refused.listen("*", 0), ERR_UNAUTHORIZED)
	assert_push_error("release builds bind only to 127.0.0.1")
	var allowed: EnetTransport = EnetTransport.new()
	allowed.build = release
	assert_eq(allowed.listen("127.0.0.1", 0), OK)
	allowed.close()
	var dev: EnetTransport = EnetTransport.new()
	dev.build = BuildInfo.detect(FeatureProvider.Fixed.new(PackedStringArray(["editor"])))
	assert_eq(dev.listen("0.0.0.0", 0), OK, "dev builds may bind any interface")
	dev.close()


func test_filter_passes_through() -> void:
	var hub: InProcessTransport.Hub = InProcessTransport.Hub.new()
	var server: TransportFilter = TransportFilter.new(InProcessTransport.new(hub))
	assert_eq(server.listen("s", 1), OK)
	var client: InProcessTransport = InProcessTransport.new(hub)
	var peer: int = client.connect_to("s", 1)
	client.poll()
	client.send(peer, Lane.Id.INPUTS, PackedByteArray([1, 2, 3]))
	var events: Array[TransportEvent] = server.poll()
	assert_eq(events.size(), 2)
	assert_eq(events[1].data, PackedByteArray([1, 2, 3]))
	assert_eq(server.stats(events[1].peer).bytes_in, 3, "stats come from the inner transport")
