#include "mine_fixture.h"

#include <doctest.h>

using namespace mine_fixture;

TEST_CASE("material table: the design's facts hold") {
	const MaterialTable t = MaterialTable::defaults();
	CHECK_FALSE(t.get(TileMaterial::FLOOR).solid);
	for (TileMaterial m : {TileMaterial::ROCK, TileMaterial::COAL, TileMaterial::BRICK, TileMaterial::TIMBER, TileMaterial::STEEL, TileMaterial::WOODEN_DOOR}) {
		CHECK(t.get(m).solid);
		CHECK(t.get(m).opaque);
	}
	CHECK(t.get(TileMaterial::ROCK).tapper_moves);
	CHECK(t.get(TileMaterial::COAL).tapper_face);
	const TileMaterial never[] = {TileMaterial::BRICK, TileMaterial::TIMBER, TileMaterial::STEEL, TileMaterial::WOODEN_DOOR};
	for (TileMaterial m : never) {
		CHECK_FALSE(t.get(m).tapper_face);
		CHECK_FALSE(t.get(m).tapper_moves);
	}
	CHECK_FALSE(t.get(TileMaterial::BRICK).voice_crosses);
	CHECK(t.get(TileMaterial::ROCK).caption_key == t.get(TileMaterial::COAL).caption_key);
}

TEST_CASE("an open gate or air door is floor; shut, it blocks bodies, light and sight") {
	MineMap mine;
	mine.commit(cell_from({0, 0}, {"#####", "#.S.#", "#.s.#", "#.D.#", "#.d.#"}));
	CHECK_FALSE(mine.is_walkable({2, 1}));
	CHECK(mine.is_opaque({2, 1}));
	CHECK(mine.is_walkable({2, 2}));
	CHECK_FALSE(mine.is_opaque({2, 2}));
	CHECK_FALSE(mine.is_walkable({2, 3}));
	CHECK(mine.is_walkable({2, 4}));
	CHECK(mine.is_walkable({2, 3}, true)); // doors-open path queries
	CHECK(mine.effective_material({2, 4}) == TileMaterial::FLOOR);
}

TEST_CASE("only rock and coal faces touching floor are usable by the Tapper") {
	MineMap mine;
	mine.commit(cell_from({0, 0}, {"#cBT#", "#...#", "#####"}));
	CHECK(mine.tapper_face_usable({1, 0}));      // coal over floor
	CHECK_FALSE(mine.tapper_face_usable({2, 0})); // brick
	CHECK_FALSE(mine.tapper_face_usable({3, 0})); // timber
	CHECK(mine.tapper_face_usable({1, 2}));       // rock under floor
	CHECK_FALSE(mine.tapper_face_usable({0, 2})); // rock touching no floor (diagonal only)
	CHECK_FALSE(mine.tapper_face_usable({2, 1})); // floor
}

TEST_CASE("unloaded tiles are solid rock and never walkable") {
	MineMap mine;
	CHECK_FALSE(mine.tile_at({3, 3}).has_value());
	CHECK(mine.is_solid({3, 3}));
	CHECK_FALSE(mine.is_walkable({3, 3}));
}
