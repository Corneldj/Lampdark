// NET-04: delta frames round-trip against acknowledged baselines, through loss and full resyncs,
// within the budget.
#include "doctest.h"

#include "net_fixture.h"

#include "core/rng/rng.h"

using namespace net_fixture;

namespace {

Desired room(double x, double y, uint8_t light) {
	Desired d = desired_at(x, y);
	for (int64_t ty = 0; ty < 6; ty++) {
		for (int64_t tx = 0; tx < 8; tx++) {
			add_tile(d, Coord{static_cast<int64_t>(x) + tx, static_cast<int64_t>(y) + ty - 3}, static_cast<uint8_t>(light + tx));
		}
	}
	add_identity(d, 7, 1, x + 3.0, y, 1234);
	add_token(d, 9, vision::SizeClass::MINER, x + 5.5, y + 1.25);
	return d;
}

void expect_view(const ViewState &got, const Desired &want) {
	CHECK(got.tiles.size() == want.frame.tiles.size());
	for (const vision::FrameTile &t : want.frame.tiles) {
		REQUIRE(got.tiles.count(t.tile) == 1);
		CHECK(got.tiles.at(t.tile).light == t.light);
	}
	CHECK(got.entities.size() == want.frame.tokens.size() + want.frame.identified.size());
	CHECK(got.own == want.own);
}

} // namespace

TEST_CASE("frames decode to exactly what the client should hold, frame after frame") {
	ClientView server(0xC0FFEE, 1);
	Client client;
	const ReplicationParams p = roomy();
	for (uint32_t tick = 1; tick <= 30; tick++) {
		const Desired d = room(10.0 + tick * 0.1, 5.0, static_cast<uint8_t>(40 + tick));
		BuildStats st;
		REQUIRE(client.receive(server.build(tick, d, 0xFFFF, 1, p, &st)));
		expect_view(client.latest(), d);
		CHECK(st.full == (tick == 1));
		client.ack(server, tick);
	}
}

TEST_CASE("an unchanged view costs only the header and own block") {
	ClientView server(1, 1);
	Client client;
	const ReplicationParams p = roomy();
	const Desired d = room(10.0, 5.0, 60);
	client.receive(server.build(1, d, 0xFFFF, 0, p));
	client.ack(server, 1);
	BuildStats st;
	const std::vector<uint8_t> second = server.build(2, d, 0xFFFF, 0, p, &st);
	CHECK(st.tiles_sent == 0);
	CHECK(st.entities_sent == 0);
	CHECK(second.size() == 42);
	REQUIRE(client.receive(second));
	expect_view(client.latest(), d);
}

TEST_CASE("lost frames are healed by the next frame against the acknowledged baseline") {
	ClientView server(2, 1);
	Client client;
	const ReplicationParams p = roomy();
	lb::core::Rng rng(77);
	int lost = 0;
	for (uint32_t tick = 1; tick <= 200; tick++) {
		const Desired d = room(10.0 + (tick % 17) * 0.5, 5.0 + (tick % 5), static_cast<uint8_t>(tick));
		const std::vector<uint8_t> bytes = server.build(tick, d, 0xFFFF, 0, p);
		if (rng.chance_ppm(300000) && tick < 200) {
			lost++;
		} else {
			REQUIRE(client.receive(bytes));
			expect_view(client.latest(), d);
		}
		client.ack(server, tick);
	}
	CHECK(lost > 40);
}

TEST_CASE("with no acknowledgement every frame is a full resync that decodes alone") {
	ClientView server(3, 1);
	const ReplicationParams p = roomy();
	for (uint32_t tick = 1; tick <= 5; tick++) {
		Client fresh;
		BuildStats st;
		const Desired d = room(10.0, 5.0, 90);
		REQUIRE(fresh.receive(server.build(tick, d, 0xFFFF, 0, p, &st)));
		CHECK(st.full);
		expect_view(fresh.latest(), d);
	}
}

TEST_CASE("a baseline older than the history window forces a full resync") {
	ClientView server(4, 1);
	Client client;
	ReplicationParams p = roomy();
	p.history = 8;
	client.receive(server.build(1, room(10.0, 5.0, 50), 0xFFFF, 0, p));
	client.ack(server, 1);
	BuildStats st;
	server.build(20, room(10.0, 5.0, 50), 0xFFFF, 0, p, &st);
	CHECK(st.full);
}

TEST_CASE("the budget bounds every frame and the client still converges, events and geometry first") {
	ClientView server(5, 1);
	Client client;
	ReplicationParams p;
	p.budget_bytes_per_tick = 400;
	p.burst_bytes = 800;
	Desired big = desired_at(0.5, 0.5);
	for (int64_t y = -15; y <= 15; y++) {
		for (int64_t x = -15; x <= 15; x++) {
			add_tile(big, Coord{x, y}, 80, 1);
		}
	}
	EventIn shot;
	shot.type = 40;
	shot.start_tick = 1;
	shot.ax = 3.0;
	shot.remaining_np = 30.0;
	server.queue_event(shot);
	BuildStats first;
	std::vector<uint8_t> bytes = server.build(1, big, 0xFFFF, 0, p, &first);
	CHECK(bytes.size() <= 800);
	CHECK(first.events_sent == 1);
	CHECK(first.geometry_sent > 0);
	CHECK(first.tiles_sent == 0); // geometry of newly seen tiles comes before tile light
	REQUIRE(client.receive(bytes));
	client.ack(server, 1);
	uint32_t tick = 2;
	for (; tick < 200; tick++) {
		BuildStats st;
		bytes = server.build(tick, big, 0xFFFF, 0, p, &st);
		CHECK(bytes.size() <= 800);
		REQUIRE(client.receive(bytes));
		client.ack(server, tick);
		if (st.tiles_pending == 0 && st.geometry_pending == 0) {
			break;
		}
	}
	CHECK(tick < 200);
	expect_view(client.latest(), big);
	CHECK(client.latest().geometry.size() == 961);
	CHECK(client.events.size() == 1);
}

TEST_CASE("events are resent until a frame carrying them is acknowledged, and never duplicated") {
	ClientView server(6, 1);
	Client client;
	const ReplicationParams p = roomy();
	EventIn e;
	e.type = 3;
	e.start_tick = 1;
	e.ax = 2.0;
	e.remaining_np = 9.0;
	server.queue_event(e);
	server.build(1, room(1.0, 1.0, 50), 0xFFFF, 0, p); // lost
	server.build(2, room(1.0, 1.0, 50), 0xFFFF, 0, p); // lost
	CHECK(server.pending_events() == 1);
	REQUIRE(client.receive(server.build(3, room(1.0, 1.0, 50), 0xFFFF, 0, p)));
	client.ack(server, 3);
	CHECK(server.pending_events() == 0);
	BuildStats st;
	REQUIRE(client.receive(server.build(4, room(1.0, 1.0, 50), 0xFFFF, 0, p, &st)));
	CHECK(st.events_sent == 0);
	REQUIRE(client.events.size() == 1);
	CHECK(client.events[0].start_tick == 1); // a late event keeps its start tick, so it plays from its offset
}

TEST_CASE("a malformed or truncated frame decodes to nothing") {
	ClientView server(7, 1);
	std::vector<uint8_t> bytes = server.build(1, room(1.0, 1.0, 50), 0xFFFF, 0, roomy());
	std::map<uint32_t, ViewState> history;
	bytes.pop_back();
	CHECK_FALSE(decode_frame(bytes, history, 2).ok);
	bytes[0] = 9;
	CHECK_FALSE(decode_frame(bytes, history, 2).ok);
}

TEST_CASE("the full-frame debug switch sends every frame against an empty view") {
	ClientView server(8, 1);
	Client client;
	ReplicationParams p = roomy();
	p.full_frames = true;
	for (uint32_t tick = 1; tick <= 5; tick++) {
		BuildStats st;
		REQUIRE(client.receive(server.build(tick, room(10.0, 5.0, 50), 0xFFFF, 0, p, &st)));
		client.ack(server, tick);
		CHECK(st.full);
		CHECK(st.tiles_sent == 48);
	}
}

TEST_CASE("VIS-08: flame states ride identity records and the own block, and their changes are sent") {
	ClientView server(5, 1);
	Client client;
	const ReplicationParams p = roomy();
	Desired d = desired_at(3.5, 3.5);
	add_identity(d, 40, 2, 5.0, 3.5, 0);
	d.flame[40] = 1 | 2; // trembling and guttering
	d.own.flame = 2;     // the owner's shuttered lamp: the sputter only
	REQUIRE(client.receive(server.build(1, d, 0xFFFF, 0, p)));
	client.ack(server, 1);
	const ViewState &first = client.latest();
	REQUIRE(first.entities.size() == 1);
	CHECK(first.entities.begin()->second.flame == 3);
	CHECK(first.own.flame == 2);
	// The flame calms: only that change is sent, and it lands.
	d.flame.erase(40);
	d.own.flame = 0;
	BuildStats st;
	REQUIRE(client.receive(server.build(2, d, 0xFFFF, 0, p, &st)));
	CHECK(st.entities_sent == 1);
	CHECK(client.latest().entities.begin()->second.flame == 0);
	CHECK(client.latest().own.flame == 0);
	// A fringe token never carries a flame byte.
	Desired t = desired_at(3.5, 3.5);
	add_token(t, 41, vision::SizeClass::MINER, 6.0, 3.5);
	t.flame[41] = 1;
	Client c2;
	ClientView s2(6, 1);
	REQUIRE(c2.receive(s2.build(1, t, 0xFFFF, 0, p)));
	CHECK(c2.latest().entities.begin()->second.flame == 0);
}

TEST_CASE("a frame crowded with identity records never exceeds max_frame_bytes") {
	// The budget counts every byte the encoder writes: an identity carries facing, cues, in hand
	// and flame (VIS-08); a full frame of them must stay within the 1200-byte unreliable limit.
	for (int64_t limit : {1200, 600, 300}) {
		ClientView server(9, 1);
		ReplicationParams p;
		p.budget_bytes_per_tick = 100000;
		p.burst_bytes = 100000;
		p.max_frame_bytes = limit;
		Desired d = desired_at(3.5, 3.5);
		for (uint32_t e = 1; e <= 200; e++) {
			add_identity(d, e, 2, 3.5 + (e % 20), 3.5 + (e / 20), static_cast<uint16_t>(e));
			d.cues[e] = 0xFFFF;
			d.in_hand[e] = 0xFFFF;
			d.flame[e] = 0x1F;
		}
		d.own.flame = 0x1F;
		Client client;
		for (uint32_t tick = 1; tick <= 6; tick++) {
			const std::vector<uint8_t> bytes = server.build(tick, d, 0xFFFF, 0, p);
			CHECK(static_cast<int64_t>(bytes.size()) <= limit);
			REQUIRE(client.receive(bytes));
			client.ack(server, tick);
		}
	}
}

TEST_CASE("SND-03: an audio record's level, flags, mask gain and points cross the wire whole") {
	ClientView server(13, 1);
	Client client;
	const ReplicationParams p = roomy();
	EventIn tell;
	tell.type = 210;
	tell.start_tick = 1;
	tell.ax = 9.0;
	tell.ay = 3.5;
	tell.remaining_np = 7.5;
	tell.level_np = 13.25;
	tell.duration_s = 1.5;
	tell.flags = audio_flag::DIFFUSE | audio_flag::MUFFLED;
	tell.gain_db = -9;
	tell.points = {{8.0, 1.5}, {10.25, 4.0}, {7.5, 5.5}};
	server.queue_event(tell);
	EventIn voiced;
	voiced.type = 42;
	voiced.start_tick = 1;
	voiced.ax = 4.0;
	voiced.remaining_np = 12.0;
	voiced.level_np = 12.0;
	voiced.voice = 5;
	server.queue_event(voiced);
	REQUIRE(client.receive(server.build(1, room(5.0, 3.0, 60), 0xFFFF, 0, p)));
	REQUIRE(client.events.size() == 2);
	const EventRec *t = nullptr;
	const EventRec *v = nullptr;
	for (const EventRec &e : client.events) {
		(e.type == 210 ? t : v) = &e;
	}
	REQUIRE(t != nullptr);
	REQUIRE(v != nullptr);
	CHECK(t->level_q4 == 53);
	CHECK(t->remaining_q4 == 30);
	CHECK(t->flags == (audio_flag::DIFFUSE | audio_flag::MUFFLED));
	CHECK(t->gain_db == -9);
	CHECK(t->voice == -1);
	REQUIRE(t->points.size() == 3);
	CHECK(t->points[0] == std::make_pair<int64_t, int64_t>(128, 24));
	CHECK(t->points[1] == std::make_pair<int64_t, int64_t>(164, 64));
	CHECK(v->voice == 5);
	CHECK(v->points.empty());
}

TEST_CASE("MNR-10: chalk glyphs ride a tile with its chalk bit, and a changed glyph is sent again") {
	ClientView server(0xC0FFEE, 1);
	Client client;
	const ReplicationParams p = roomy();
	Desired d = room(10.0, 5.0, 90);
	REQUIRE(!d.frame.tiles.empty());
	d.frame.tiles[0].decals = vision::DECAL_CHALK;
	d.frame.tiles[0].chalk = 0x8C000000ULL | 0x83ULL; // the floor and the south face
	d.frame.tiles[1].decals = vision::DECAL_CHALK;
	d.frame.tiles[1].chalk = 0x8100000000ULL; // the west face alone
	REQUIRE(client.receive(server.build(1, d, 0xFFFF, 1, p)));
	CHECK(client.latest().tiles.at(d.frame.tiles[0].tile).chalk == (0x8C000000ULL | 0x83ULL));
	CHECK(client.latest().tiles.at(d.frame.tiles[1].tile).chalk == 0x8100000000ULL);
	CHECK(client.latest().tiles.at(d.frame.tiles[2].tile).chalk == 0);
	client.ack(server, 1);
	d.frame.tiles[0].chalk = 0x8C000000ULL | 0xA0ULL; // the floor mark replaced
	BuildStats st;
	REQUIRE(client.receive(server.build(2, d, 0xFFFF, 1, p, &st)));
	CHECK(st.tiles_sent == 1);
	CHECK(client.latest().tiles.at(d.frame.tiles[0].tile).chalk == (0x8C000000ULL | 0xA0ULL));
}

TEST_CASE("LFT-14: other lanes spend from the frames' bucket, which may run below zero without refilling") {
	ClientView server(11, 1);
	Client client;
	ReplicationParams p;
	p.budget_bytes_per_tick = 400;
	p.burst_bytes = 2400;
	const Desired d = room(10.0, 5.0, 60);
	CHECK(server.bucket() == 0.0); // nothing before the first build
	server.spend(500.0);
	CHECK(server.bucket() == 0.0);
	const std::vector<uint8_t> first = server.build(1, d, 0xFFFF, 0, p);
	const double left = server.bucket();
	CHECK(left == doctest::Approx(2400.0 - static_cast<double>(first.size())));
	// The sheets take what is left and more: the bucket goes below zero ...
	server.spend(left + 300.0);
	CHECK(server.bucket() == doctest::Approx(-300.0));
	client.receive(first);
	client.ack(server, 1);
	// ... and the next frame refills from there, never from a fresh burst.
	const std::vector<uint8_t> second = server.build(2, d, 0xFFFF, 0, p);
	CHECK(server.bucket() == doctest::Approx(-300.0 + 400.0 - static_cast<double>(second.size())));
	CHECK(second.size() <= 400);
}
