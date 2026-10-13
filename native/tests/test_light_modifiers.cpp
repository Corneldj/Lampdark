#include "light_fixture.h"

#include <doctest.h>

using namespace light_fixture;

TEST_CASE("guttering shrinks the grid's light; the core stays at 0.6 of the modified radius") {
	MineMap mine;
	LightGrid grid(mine);
	load_open(mine, &grid);
	const uint32_t id = grid.add_source(lamp(5.5, 5.5, 4.0));
	grid.update();
	CHECK(grid.value({7, 5}) == falloff_milli(2.0, 4.0, 1.0, grid.params));
	grid.set_radius_modifier(id, 0.7, "guttering");
	grid.update();
	CHECK(grid.value({7, 5}) == falloff_milli(2.0, 2.8, 1.0, grid.params));
	CHECK(grid.value({9, 5}) == 0); // beyond 2.8
	grid.set_radius_modifier(id, 0.7 * 0.5, "blackdamp"); // modifiers multiply
	grid.update();
	CHECK(grid.value({7, 5}) == 0);
}

TEST_CASE("events: added once, changed on radius, peak and modifier, removed") {
	MineMap mine;
	LightGrid grid(mine);
	load_open(mine, &grid);
	const uint32_t id = grid.add_source(lamp(5.5, 5.5, 4.0));
	std::vector<LightEvent> e = grid.take_events();
	REQUIRE(e.size() == 1);
	CHECK(e[0].type == LightEvent::Type::ADDED);
	grid.update_point(id, 6.5, 5.5, 4.0, 1.0); // a move is no light change
	CHECK(grid.take_events().empty());
	grid.update_point(id, 6.5, 5.5, 0.0, 1.0); // shuttered: radius 0
	grid.update_point(id, 6.5, 5.5, 0.0, 0.5);
	grid.set_radius_modifier(id, 0.7, "guttering");
	e = grid.take_events();
	REQUIRE(e.size() == 3);
	CHECK(e[0].cause == "radius");
	CHECK(e[1].cause == "peak");
	CHECK(e[2].cause == "guttering");
	grid.remove_source(id);
	CHECK(grid.take_events()[0].type == LightEvent::Type::REMOVED);
}

TEST_CASE("flame_sources includes shuttered lamps at radius 0") {
	MineMap mine;
	LightGrid grid(mine);
	load_open(mine, &grid);
	const uint32_t shut = grid.add_source(lamp(3.5, 3.5, 0.0));
	SourceDesc electric = lamp(4.5, 4.5, 6.0);
	electric.kind = "electric_lamp";
	electric.flags = flag::CARRIED | flag::BEYOND_SNUFF | flag::CANNOT_TAKE;
	grid.add_source(electric);
	grid.update();
	const std::vector<uint32_t> flames = grid.flame_sources(0, 0, 10, 10);
	REQUIRE(flames.size() == 1);
	CHECK(flames[0] == shut);
	CHECK(grid.value({3, 3}) > 0); // lit by the electric lamp only; the shuttered flame adds nothing
}

TEST_CASE("a muzzle flash exists for exactly 2 ticks") {
	MineMap mine;
	LightGrid grid(mine);
	load_open(mine, &grid);
	SourceDesc flash = lamp(5.5, 5.5, 6.0);
	flash.kind = "muzzle_flash";
	flash.colour = ColourClass::PALE_AMBER;
	flash.flags = 0;
	flash.lifetime_ticks = 2;
	const uint32_t id = grid.add_source(flash); // fired during tick t
	grid.update();
	CHECK(grid.value({5, 5}) == 1000);
	grid.begin_tick(20.0); // tick t + 1
	grid.update();
	CHECK(grid.has_source(id));
	CHECK(grid.value({5, 5}) == 1000);
	grid.begin_tick(20.0); // tick t + 2
	grid.update();
	CHECK_FALSE(grid.has_source(id));
	CHECK(grid.value({5, 5}) == 0);
}

TEST_CASE("velocity in tiles a second, for the Widow") {
	MineMap mine;
	LightGrid grid(mine);
	load_open(mine, &grid);
	const uint32_t id = grid.add_source(lamp(5.5, 5.5, 4.0));
	grid.begin_tick(20.0);
	grid.update_point(id, 5.65, 5.5, 4.0, 1.0); // 0.15 tiles in a tick: 3 tiles a second
	grid.begin_tick(20.0);
	CHECK(grid.velocity(id).first == doctest::Approx(3.0));
	CHECK(grid.velocity(id).second == doctest::Approx(0.0));
}
