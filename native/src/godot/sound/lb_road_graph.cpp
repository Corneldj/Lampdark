#include "godot/sound/lb_road_graph.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;
namespace sound = lb::core::sound;
using lb::core::world::Coord;

namespace lb::godot {

namespace {

Vector2i vec(Coord c) {
	return Vector2i(static_cast<int32_t>(c.x), static_cast<int32_t>(c.y));
}

Dictionary to_dict(const sound::Delivery &d) {
	Dictionary out;
	out["listener"] = static_cast<int64_t>(d.listener);
	out["remaining_np"] = d.remaining_np;
	out["path_tiles"] = d.path_tiles;
	out["closed_portals"] = d.closed_portals;
	out["apparent_tile"] = vec(d.apparent_tile);
	out["apparent"] = Vector2(static_cast<real_t>(d.apparent_x), static_cast<real_t>(d.apparent_y));
	out["via"] = d.via;
	out["true_source"] = vec(d.true_source);
	return out;
}

} // namespace

#define REQUIRE_GRAPH(ret) ERR_FAIL_NULL_V_MSG(graph_, ret, "LbRoadGraph: attach() a mine first")

void LbRoadGraph::_bind_methods() {
	ClassDB::bind_method(D_METHOD("attach", "mine"), &LbRoadGraph::attach);
	ClassDB::bind_method(D_METHOD("set_params", "closed_cost", "jitter_per_tile", "search_cap_air", "run_seed"), &LbRoadGraph::set_params);
	ClassDB::bind_method(D_METHOD("stitch", "cell"), &LbRoadGraph::stitch);
	ClassDB::bind_method(D_METHOD("unload", "cell"), &LbRoadGraph::unload);
	ClassDB::bind_method(D_METHOD("on_tiles_changed", "cell", "rect", "reason"), &LbRoadGraph::on_tiles_changed);
	ClassDB::bind_method(D_METHOD("is_stitched", "cell"), &LbRoadGraph::is_stitched);
	ClassDB::bind_method(D_METHOD("epoch"), &LbRoadGraph::epoch);
	ClassDB::bind_method(D_METHOD("set_listener", "id", "tile", "threshold", "multiplier"), &LbRoadGraph::set_listener);
	ClassDB::bind_method(D_METHOD("remove_listener", "id"), &LbRoadGraph::remove_listener);
	ClassDB::bind_method(D_METHOD("propagate", "event_id", "origins", "level", "mode"), &LbRoadGraph::propagate);
	ClassDB::bind_method(D_METHOD("deliver", "source", "level", "listener_tile", "mode", "threshold", "multiplier", "key"), &LbRoadGraph::deliver);
	ClassDB::bind_method(D_METHOD("path_cost", "a", "b", "mode", "max"), &LbRoadGraph::path_cost);
	ClassDB::bind_method(D_METHOD("nearest_open_tile", "rock_tile", "max_radius"), &LbRoadGraph::nearest_open_tile);
	ClassDB::bind_method(D_METHOD("rock_line", "from", "to"), &LbRoadGraph::rock_line);
	ClassDB::bind_method(D_METHOD("tables_digest"), &LbRoadGraph::tables_digest);
	ClassDB::bind_method(D_METHOD("validate", "cell"), &LbRoadGraph::validate);
	ClassDB::bind_integer_constant("LbRoadGraph", "", "MODE_AIR", static_cast<int64_t>(sound::Mode::AIR));
	ClassDB::bind_integer_constant("LbRoadGraph", "", "MODE_VOICE", static_cast<int64_t>(sound::Mode::VOICE));
}

void LbRoadGraph::attach(const Ref<LbMine> &mine) {
	ERR_FAIL_COND(mine.is_null());
	mine_ = mine;
	graph_ = std::make_unique<sound::RoadGraph>(mine_->map());
}

void LbRoadGraph::set_params(double closed_cost, double jitter_per_tile, double search_cap_air, int64_t run_seed) {
	REQUIRE_GRAPH();
	graph_->params.closed_cost = closed_cost;
	graph_->params.jitter_per_tile = jitter_per_tile;
	graph_->params.search_cap_air = search_cap_air;
	graph_->params.run_seed = static_cast<uint64_t>(run_seed);
}

bool LbRoadGraph::stitch(Vector2i cell) {
	REQUIRE_GRAPH(false);
	const lb::core::world::Cell *c = mine_->map().cell({cell.x, cell.y});
	ERR_FAIL_NULL_V_MSG(c, false, "LbRoadGraph.stitch: the cell is not committed");
	std::optional<sound::CellBlock> block = sound::decode_block(c->road_graph);
	if (!block) {
		UtilityFunctions::push_error("LbRoadGraph.stitch: cell ", cell, " has a malformed Road Graph block");
		return false;
	}
	if (!graph_->stitch({cell.x, cell.y}, *block)) {
		UtilityFunctions::push_error("LbRoadGraph.stitch: cell ", cell, " failed validation: ", validate(cell));
		return false;
	}
	return true;
}

bool LbRoadGraph::unload(Vector2i cell) {
	REQUIRE_GRAPH(false);
	return graph_->unload({cell.x, cell.y});
}

void LbRoadGraph::on_tiles_changed(Vector2i cell, Rect2i, const String &) {
	REQUIRE_GRAPH();
	graph_->on_tiles_changed({cell.x, cell.y});
}

bool LbRoadGraph::is_stitched(Vector2i cell) const {
	return graph_ && graph_->is_stitched({cell.x, cell.y});
}

int64_t LbRoadGraph::epoch() const {
	return graph_ ? static_cast<int64_t>(graph_->epoch()) : 0;
}

void LbRoadGraph::set_listener(int64_t id, Vector2i tile, double threshold, double multiplier) {
	REQUIRE_GRAPH();
	graph_->set_listener({static_cast<uint32_t>(id), {tile.x, tile.y}, threshold, multiplier});
}

void LbRoadGraph::remove_listener(int64_t id) {
	REQUIRE_GRAPH();
	graph_->remove_listener(static_cast<uint32_t>(id));
}

Array LbRoadGraph::propagate(int64_t event_id, const Array &origins, double level, int64_t mode) {
	Array out;
	REQUIRE_GRAPH(out);
	std::vector<Coord> list;
	for (int64_t i = 0; i < origins.size(); i++) {
		const Vector2i t = origins[i];
		list.push_back({t.x, t.y});
	}
	for (const sound::Delivery &d : graph_->propagate(static_cast<uint64_t>(event_id), list, level, static_cast<sound::Mode>(mode))) {
		out.push_back(to_dict(d));
	}
	return out;
}

Dictionary LbRoadGraph::deliver(Vector2i source, double level, Vector2i listener_tile, int64_t mode, double threshold,
		double multiplier, int64_t key) const {
	REQUIRE_GRAPH(Dictionary());
	std::optional<sound::Delivery> d = graph_->deliver({source.x, source.y}, level, {listener_tile.x, listener_tile.y},
			static_cast<sound::Mode>(mode), threshold, multiplier, static_cast<uint64_t>(key));
	return d ? to_dict(*d) : Dictionary();
}

double LbRoadGraph::path_cost(Vector2i a, Vector2i b, int64_t mode, double max) const {
	REQUIRE_GRAPH(-1.0);
	std::optional<double> cost = graph_->path_cost({a.x, a.y}, {b.x, b.y}, static_cast<sound::Mode>(mode), max);
	return cost ? *cost : -1.0;
}

Dictionary LbRoadGraph::nearest_open_tile(Vector2i rock_tile, int64_t max_radius) const {
	Dictionary out;
	REQUIRE_GRAPH(out);
	std::optional<Coord> t = graph_->nearest_open_tile({rock_tile.x, rock_tile.y}, max_radius);
	out["found"] = t.has_value();
	out["tile"] = t ? vec(*t) : Vector2i();
	return out;
}

Dictionary LbRoadGraph::rock_line(Vector2i from, Vector2i to) const {
	Dictionary out;
	ERR_FAIL_COND_V(mine_.is_null(), out);
	const sound::RockLine line = sound::rock_line(mine_->map(), {from.x, from.y}, {to.x, to.y});
	out["solid_tiles"] = line.solid_tiles;
	out["brick"] = line.brick;
	out["door"] = line.door;
	out["distance"] = line.distance;
	out["has_face"] = line.has_face;
	out["listener_face"] = vec(line.listener_face);
	return out;
}

int64_t LbRoadGraph::tables_digest() const {
	return graph_ ? static_cast<int64_t>(graph_->tables_digest()) : 0;
}

PackedStringArray LbRoadGraph::validate(Vector2i cell) const {
	PackedStringArray out;
	ERR_FAIL_COND_V(mine_.is_null(), out);
	const lb::core::world::Cell *c = mine_->map().cell({cell.x, cell.y});
	if (c == nullptr) {
		out.push_back("cell is not committed");
		return out;
	}
	std::optional<sound::CellBlock> block = sound::decode_block(c->road_graph);
	if (!block) {
		out.push_back("malformed Road Graph block");
		return out;
	}
	for (const std::string &p : sound::validate_block(*c, *block)) {
		out.push_back(String::utf8(p.c_str()));
	}
	return out;
}

} // namespace lb::godot
