extends GutTest
## CRT-03's stir clock: 20 ticks at 0.30 or more in all within 200 start a stir; 19 do not; two
## separated half-second looks within 10 s do; 0.60 at any moment does.


func before_all() -> void:
	assert_true(Tuning.load_server())


func _feed(c: MothSleep, pattern: Array) -> MothSleep.Cause:
	var last: MothSleep.Cause = MothSleep.Cause.NONE
	var run: RunState = RunState.new()
	for step: Array in pattern:
		var value: int = step[0]
		var ticks: int = step[1]
		for i: int in ticks:
			var flag: int = 1 if value >= c.stir_level else 0
			c.lit += flag - c.ring[c.at]
			c.ring[c.at] = flag
			c.at = (c.at + 1) % c.window
			last = c.trigger(run, Vector2.ZERO, value)
			if last != MothSleep.Cause.NONE:
				return last
	return last


func test_window_and_clock() -> void:
	var c: MothSleep = MothSleep.new()
	assert_eq(c.window, 200)
	assert_eq(c.clock_ticks, 20)
	assert_eq(c.stir_ticks, 30)
	assert_eq(c.settle_ticks, 60)
	assert_eq(c.preen_ticks, 100)


func test_twenty_ticks_in_all_start_it() -> void:
	assert_eq(_feed(MothSleep.new(), [[300, 19], [0, 100]]), MothSleep.Cause.NONE, "19 ticks: no stir")
	assert_eq(_feed(MothSleep.new(), [[300, 20]]), MothSleep.Cause.CLOCK, "20 ticks: a stir")
	assert_eq(_feed(MothSleep.new(), [[310, 10], [0, 150], [310, 10]]), MothSleep.Cause.CLOCK, "two half-second looks within 10 s")
	assert_eq(_feed(MothSleep.new(), [[310, 10], [0, 190], [310, 10]]), MothSleep.Cause.NONE, "the first look has left the window")
	assert_eq(_feed(MothSleep.new(), [[290, 300]]), MothSleep.Cause.NONE, "0.29 never counts")


func test_060_at_any_moment() -> void:
	assert_eq(_feed(MothSleep.new(), [[600, 1]]), MothSleep.Cause.BRIGHT)
	var c: MothSleep = MothSleep.new()
	c.cause = MothSleep.Cause.CLOCK
	assert_false(c.wakes_at_end(299), "the clock's stir ends in a settle without 0.30")
	assert_true(c.wakes_at_end(300))
	c.cause = MothSleep.Cause.BRIGHT
	assert_true(c.wakes_at_end(0), "0.60 always wakes")


func test_hunger_draws() -> void:
	var c: MothSleep = MothSleep.new()
	var run: RunState = RunState.new()
	var lo: int = 1 << 40
	var hi: int = 0
	for i: int in 300:
		var rng: LbRng = LbRng.from_seed(1000 + i)
		c.draw_hunger(run, rng, false)
		lo = mini(lo, c.hunger_at)
		hi = maxi(hi, c.hunger_at)
	assert_gte(lo, 900 * 20)
	assert_lte(hi, 1500 * 20)
	assert_lt(lo, 950 * 20, "the draw covers the range")
	assert_gt(hi, 1450 * 20)
	for i: int in 100:
		c.draw_hunger(run, LbRng.from_seed(i), true)
		assert_between(c.hunger_at, 60 * 20, 120 * 20, "Restless Moth: within 2 minutes")
