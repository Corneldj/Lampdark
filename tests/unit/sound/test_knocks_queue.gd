extends GutTest
## SND-15's client: each KNOCKS message plays voice.knock_count knocks voice.knock_interval_s apart;
## a second set queues after the first; one caption per set, with no direction.


func before_all() -> void:
	Tuning.load_client()


func test_three_knocks_a_set_and_sets_queue() -> void:
	var k: KnocksPlayer = KnocksPlayer.new()
	var times: Array[float] = []
	var clock: Array[float] = [0.0]
	k.knocked.connect(func() -> void: times.append(clock[0]))
	var captions: Array[int] = [0]
	k.caption.connect(func() -> void: captions[0] += 1)
	k.enqueue()
	k.enqueue()  # a second fall while the first set plays
	for i: int in 200:
		clock[0] = (i + 1) * 0.05
		k.advance(0.05)
	var gap: float = Tuning.f(&"voice.knock_interval_s")
	assert_eq(roundi(Tuning.f(&"voice.knock_count")), 3)
	assert_eq(times.size(), 6, "two falls, two sets of three")
	assert_eq(captions[0], 2, "one caption per set")
	for i: int in range(1, times.size()):
		assert_almost_eq(times[i] - times[i - 1], gap, 0.051, "about 1.5 s apart, the sets back to back")
	assert_false(k.playing())
	k.free()


func test_the_knocks_dip_while_deafened() -> void:
	var deaf: Deafness = Deafness.new()
	deaf.start({"duration_s": 5.0, "dip_db": 20.0})
	var k: KnocksPlayer = KnocksPlayer.new(deaf)
	assert_true(deaf.deafened())
	assert_eq(-deaf.dip_db, -20.0, "the same dip as other game sound")
	k.free()
	deaf.free()
