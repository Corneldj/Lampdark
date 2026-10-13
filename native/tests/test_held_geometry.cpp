// NET-04: held geometry: kept for cells within 2 of the own miner; an about-turn skips walls the
// client already holds and resends one that changed while unseen.
#include "doctest.h"

#include "net_fixture.h"

using namespace net_fixture;

TEST_CASE("the held rule keeps cells within 2 of the own miner's cell") {
	ViewState v;
	v.own = own_at(25.0, 5.0); // cell (1, 0)
	v.geometry[Coord{-21, 0}] = GeoView{1, 0};  // cell -2: 3 away
	v.geometry[Coord{-19, 0}] = GeoView{1, 0};  // cell -1: 2 away
	v.geometry[Coord{70, 45}] = GeoView{1, 0};  // cell (3, 2): 2 away
	v.geometry[Coord{80, 0}] = GeoView{1, 0};   // cell 4: 3 away
	apply_held_rule(v, 2);
	CHECK(v.geometry.size() == 2);
	CHECK(v.geometry.count(Coord{-19, 0}) == 1);
	CHECK(v.geometry.count(Coord{70, 45}) == 1);
}

namespace {

Desired facing_east(uint8_t wall_material) {
	Desired d = desired_at(10.5, 10.5);
	for (int64_t x = 11; x <= 16; x++) {
		add_tile(d, Coord{x, 10}, 120, x == 16 ? wall_material : 0);
	}
	return d;
}

Desired facing_west() {
	Desired d = desired_at(10.5, 10.5);
	for (int64_t x = 5; x <= 9; x++) {
		add_tile(d, Coord{x, 10}, 120, 0);
	}
	return d;
}

} // namespace

TEST_CASE("an about-turn skips held geometry and resends what changed while unseen") {
	ClientView server(21, 1);
	Client client;
	const ReplicationParams p = roomy();
	uint32_t tick = 1;
	BuildStats st;
	REQUIRE(client.receive(server.build(tick, facing_east(2), 0xFFFF, 0, p, &st)));
	CHECK(st.geometry_sent == 6);
	client.ack(server, tick++);
	REQUIRE(client.receive(server.build(tick, facing_west(), 0xFFFF, 0, p, &st)));
	CHECK(st.geometry_sent == 5);
	client.ack(server, tick++);
	// Turn back: the east road is still held, so none of its geometry is sent again.
	REQUIRE(client.receive(server.build(tick, facing_east(2), 0xFFFF, 0, p, &st)));
	CHECK(st.geometry_sent == 0);
	CHECK(st.tiles_sent == 6); // its light, which was dropped, comes back
	client.ack(server, tick++);
	// Turn away, the wall at x = 16 changes unseen (a door shut), turn back: only it is resent.
	REQUIRE(client.receive(server.build(tick, facing_west(), 0xFFFF, 0, p, &st)));
	client.ack(server, tick++);
	REQUIRE(client.receive(server.build(tick, facing_east(7), 0xFFFF, 0, p, &st)));
	CHECK(st.geometry_sent == 1);
	CHECK(client.latest().geometry.at(Coord{16, 10}).material == 7);
	// Nothing about a held tile is sent while it is unseen: the west frame carried no east tile.
	const ViewState &east_held = client.latest();
	CHECK(east_held.geometry.count(Coord{5, 10}) == 1); // the west road is held too
}

TEST_CASE("walking more than 2 cells away drops held geometry on both sides alike") {
	ClientView server(22, 1);
	Client client;
	const ReplicationParams p = roomy();
	REQUIRE(client.receive(server.build(1, facing_east(2), 0xFFFF, 0, p)));
	client.ack(server, 1);
	Desired far = desired_at(75.5, 10.5); // cell 3: the east road's cell 0 is 3 away
	REQUIRE(client.receive(server.build(2, far, 0xFFFF, 0, p)));
	CHECK(client.latest().geometry.empty());
	client.ack(server, 2);
	BuildStats st;
	REQUIRE(client.receive(server.build(3, facing_east(2), 0xFFFF, 0, p, &st)));
	CHECK(st.geometry_sent == 6); // back again: sent anew
}
