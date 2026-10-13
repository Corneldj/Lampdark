#include "godot/sim/lb_entity_mirror.h"

#include "core/sim/entity_mirror.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;
using lb::core::sim::EntityMirror;
using lb::core::sim::MirrorEntity;

namespace lb::godot {

void LbEntityMirror::_bind_methods() {
	ClassDB::bind_static_method("LbEntityMirror", D_METHOD("set_packed", "tick", "ids", "kinds", "xy", "flags"), &LbEntityMirror::set_packed);
	ClassDB::bind_static_method("LbEntityMirror", D_METHOD("count"), &LbEntityMirror::count);
	ClassDB::bind_static_method("LbEntityMirror", D_METHOD("mirrored_tick"), &LbEntityMirror::mirrored_tick);
	ClassDB::bind_static_method("LbEntityMirror", D_METHOD("find", "id"), &LbEntityMirror::find);
}

bool LbEntityMirror::set_packed(int64_t tick, const PackedInt64Array &ids, const PackedInt32Array &kinds,
		const PackedFloat64Array &xy, const PackedInt32Array &flags) {
	const int64_t n = ids.size();
	if (kinds.size() != n || flags.size() != n || xy.size() != 2 * n) {
		UtilityFunctions::push_error("LbEntityMirror.set_packed: array sizes disagree");
		return false;
	}
	std::vector<MirrorEntity> entities(static_cast<size_t>(n));
	for (int64_t i = 0; i < n; i++) {
		MirrorEntity &e = entities[static_cast<size_t>(i)];
		e.id = static_cast<uint32_t>(ids[i]);
		e.kind = static_cast<uint16_t>(kinds[i]);
		e.x = xy[2 * i];
		e.y = xy[2 * i + 1];
		e.flags = static_cast<uint32_t>(flags[i]);
	}
	if (!EntityMirror::current().set(tick, std::move(entities))) {
		UtilityFunctions::push_error("LbEntityMirror.set_packed: IDs must be ascending, unique and non-zero");
		return false;
	}
	return true;
}

int64_t LbEntityMirror::count() {
	return static_cast<int64_t>(EntityMirror::current().size());
}

int64_t LbEntityMirror::mirrored_tick() {
	return EntityMirror::current().tick();
}

Dictionary LbEntityMirror::find(int64_t id) {
	Dictionary out;
	if (id <= 0 || id > UINT32_MAX) {
		return out;
	}
	std::optional<MirrorEntity> e = EntityMirror::current().find(static_cast<uint32_t>(id));
	if (e) {
		out["id"] = static_cast<int64_t>(e->id);
		out["kind"] = static_cast<int64_t>(e->kind);
		out["x"] = e->x;
		out["y"] = e->y;
		out["flags"] = static_cast<int64_t>(e->flags);
	}
	return out;
}

} // namespace lb::godot
