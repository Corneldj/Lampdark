#include "mine_fixture.h"

#include <doctest.h>

using namespace mine_fixture;

// Recorded on Linux from content_digest's canonical bytes; Windows must match exactly.
constexpr uint64_t GOLDEN_SAMPLE = 12094887385061122671ULL;
constexpr uint64_t GOLDEN_ALL_ROCK = 11704115202601724803ULL;

namespace {

std::unique_ptr<Cell> sample_cell() {
	auto cell = cell_from({-3, 7}, {"####B", "#..D.", "#.c..", "#T..#"});
	Anchor hook;
	hook.type = AnchorType::TIMBER_HOOK;
	hook.x = 2;
	hook.y = 1;
	hook.tags = {"road"};
	cell->anchors.push_back(hook);
	Anchor slot;
	slot.type = AnchorType::POI_SLOT;
	slot.x = 1;
	slot.y = 2;
	slot.w = 2;
	slot.kind = "lamp_cabin";
	cell->anchors.push_back(slot);
	Barrier door;
	door.id = 1;
	door.portal = 4;
	door.tiles = {static_cast<uint16_t>(Cell::index_of(3, 1))};
	cell->barriers.push_back(door);
	cell->road_graph = {1, 2, 3, 250};
	return cell;
}

} // namespace

TEST_CASE("content digests are stable golden values on every platform") {
	CHECK(content_digest(*sample_cell()) == GOLDEN_SAMPLE);
	CHECK(content_digest(*cell_from({0, 0}, {})) == GOLDEN_ALL_ROCK);
}

TEST_CASE("any change of content or state changes the digest") {
	const uint64_t base = content_digest(*sample_cell());
	auto moved = sample_cell();
	moved->anchors[0].x = 3;
	CHECK(content_digest(*moved) != base);
	auto opened = sample_cell();
	opened->barriers[0].open = true;
	CHECK(content_digest(*opened) != base);
	auto zoned = sample_cell();
	zoned->tiles[5].zone = 9;
	CHECK(content_digest(*zoned) != base);
	auto elsewhere = sample_cell();
	elsewhere->coord = {-3, 8};
	CHECK(content_digest(*elsewhere) != base);
}
