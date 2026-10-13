#include "core/world/materials.h"

namespace lb::core::world {

MaterialTable MaterialTable::defaults() {
	MaterialTable t;
	//                    solid  opaque tapper_moves tapper_face voice  taps   caption
	t.set(TileMaterial::FLOOR, {false, false, false, false, true, false, ""});
	t.set(TileMaterial::ROCK, {true, true, true, true, true, true, "caption.bump.rock"});
	t.set(TileMaterial::COAL, {true, true, true, true, true, true, "caption.bump.rock"});
	t.set(TileMaterial::BRICK, {true, true, false, false, false, false, "caption.bump.brick"});
	t.set(TileMaterial::TIMBER, {true, true, false, false, true, true, "caption.bump.timber"});
	t.set(TileMaterial::STEEL, {true, true, false, false, false, false, "caption.bump.steel"});
	t.set(TileMaterial::WOODEN_DOOR, {true, true, false, false, false, false, "caption.bump.timber"});
	return t;
}

} // namespace lb::core::world
