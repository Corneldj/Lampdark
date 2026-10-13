#include "core/generated/world_ids.h"

#include <doctest.h>

#include <string>

using namespace lb::core::world;

TEST_CASE("material values are stable and ROCK and COAL share a caption") {
	CHECK(static_cast<int>(TileMaterial::FLOOR) == 0);
	CHECK(static_cast<int>(TileMaterial::ROCK) == 1);
	CHECK(static_cast<int>(TileMaterial::WOODEN_DOOR) == 6);
	CHECK(std::string(material_caption_key(TileMaterial::ROCK)) == material_caption_key(TileMaterial::COAL));
	CHECK(std::string(material_caption_key(TileMaterial::ROCK)) == "caption.bump.rock");
	CHECK(std::string(material_caption_key(TileMaterial::BRICK)) == "caption.bump.brick");
	CHECK(std::string(material_caption_key(TileMaterial::FLOOR)).empty());
}

TEST_CASE("world constants") {
	CHECK(CELL_TILES == 20);
	CHECK(BLOCK_CELLS == 2);
	CHECK(REGION_CELLS == 5);
	CHECK(SHAFT_CENTRE_X2 % 2 == 0); // on the half-tile grid at (10.0, 10.0)
	CHECK(TILE_STATE_OPEN == 1);
	CHECK(static_cast<int>(EntityKind::NONE) == 0);
	CHECK(static_cast<int>(EntityKind::MINER) == 1);
}
