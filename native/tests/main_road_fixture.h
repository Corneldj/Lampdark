#pragma once
// GEN-07's fixtures: east-west main-road templates of every shape (straight, a chicane bend at 5,
// 10 or 15, a crossing, a straight road with an old fall), and a template set with them beside
// grid cells and plain fallbacks for every biome.

#include "core/gen/main_roads.h"
#include "layout_fixture.h"

namespace main_road_fixture {

using namespace layout_fixture;

inline std::vector<std::string> road_rows(const std::string &shape, bool old_fall) {
	std::vector<std::string> rows(20, std::string(20, '#'));
	auto set = [&](int x, int y, char ch) { rows[static_cast<size_t>(y)][static_cast<size_t>(x)] = ch; };
	for (int x = 0; x < 20; x++) {
		set(x, 9, '.');
		set(x, 10, '=');
		set(x, 11, '.');
	}
	if (shape == "crossing") {
		for (int y = 0; y < 20; y++) {
			for (int x = 9; x <= 11; x++) {
				set(x, y, x == 10 ? '=' : (rows[static_cast<size_t>(y)][static_cast<size_t>(x)] == '=' ? '=' : '.'));
			}
		}
		return rows;
	}
	if (old_fall) {
		for (int y = 0; y <= 8; y++) {
			for (int x = 4; x <= 6; x++) set(x, y, '.');
		}
		for (int y = 12; y < 20; y++) {
			for (int x = 14; x <= 16; x++) set(x, y, '.');
		}
		for (int y = 9; y <= 11; y++) {
			for (int x = 9; x <= 11; x++) set(x, y, '#');
		}
		return rows;
	}
	for (int c : {5, 10, 15}) { // side passages on every stub line
		for (int y = 0; y < 20; y++) {
			if (y >= 9 && y <= 11)
				continue;
			for (int x = c - 1; x <= c + 1; x++) set(x, y, '.');
		}
	}
	if (shape.rfind("bend_", 0) == 0) { // a chicane: baffles across rows 9-10 before and 10-11 after
		const int p = std::stoi(shape.substr(5));
		set(p - 1, 9, '#');
		set(p - 1, 10, '#');
		set(p + 1, 10, '#');
		set(p + 1, 11, '#');
	}
	return rows;
}

inline Template main_road(const std::string &id, const std::string &shape, bool old_fall, double weight = 1.0) {
	Spec s;
	s.id = id;
	s.kind = TemplateKind::MAIN_ROAD;
	s.rows = road_rows(shape, old_fall);
	s.collapses = {};
	s.rib = {};
	s.anchors = {anchor(AnchorType::LANDMARK, 2, 10, 1, 1, "milestone"), anchor(AnchorType::RUBBLE_HEAP, 2, 9)};
	for (int y = 0; y < 20; y++) {
		for (int x = 0; x < 20; x++) {
			if (x % 3 == 0 && y % 3 == 0 && s.rows[static_cast<size_t>(y)][static_cast<size_t>(x)] != '#') {
				s.anchors.push_back(anchor(AnchorType::TIMBER_HOOK, x, y));
			}
		}
	}
	s.stubs = {stub(Edge::WEST, 10, 3), stub(Edge::EAST, 10, 3)};
	if (shape == "crossing") {
		s.stubs.push_back(stub(Edge::NORTH, 10, 3));
		s.stubs.push_back(stub(Edge::SOUTH, 10, 3));
	} else if (old_fall) {
		s.stubs.push_back(stub(Edge::NORTH, 5, 3));
		s.stubs.push_back(stub(Edge::SOUTH, 15, 3));
	} else {
		for (int o : {5, 10, 15}) {
			s.stubs.push_back(stub(Edge::NORTH, o, 3));
			s.stubs.push_back(stub(Edge::SOUTH, o, 3));
		}
	}
	Template t = make(s);
	t.biome = "main_road";
	t.shape = shape;
	t.old_fall = old_fall;
	t.weight = weight;
	return t;
}

inline std::vector<Template> main_roads() {
	return {main_road("main_straight", "straight", false), main_road("main_bend_5", "bend_5", false),
			main_road("main_bend_10", "bend_10", false), main_road("main_bend_15", "bend_15", false),
			main_road("main_crossing", "crossing", false), main_road("main_straight_oldfall", "straight", true)};
}

inline std::shared_ptr<TemplateSet> road_set() {
	std::vector<Template> list = main_roads();
	for (const char *biome : {"pit_bottom", "seam", "old_workings", "black_seam", "old_mens"}) {
		Template g = grid(std::string(biome) + "_grid", 1.0);
		g.biome = biome;
		list.push_back(g);
		Spec f = fallback_spec();
		f.id = std::string(biome) + "_plain";
		Template fb = make(f);
		fb.biome = biome;
		list.push_back(fb);
	}
	auto set = std::make_shared<TemplateSet>();
	REQUIRE(set->load(encode_pack("roads", list)));
	return set;
}

inline BiomeTable design_biomes() {
	BiomeTable t;
	t.rings = {{{"pit_bottom", 1.0}}, {{"seam", 0.8}, {"old_workings", 0.2}}, {{"seam", 0.5}, {"old_workings", 0.5}},
			{{"old_workings", 0.6}, {"black_seam", 0.4}}, {{"old_mens", 1.0}}};
	t.widths = {{"pit_bottom", {2, 3}}, {"seam", {2, 3}}, {"old_workings", {1, 2}}, {"black_seam", {2, 3}}, {"old_mens", {1, 1}},
			{"main_road", {3, 3}}};
	return t;
}

// A whole run's derive inputs with biomes and main roads, owning everything they point at.
struct RoadRun {
	RunHeader head;
	std::shared_ptr<TemplateSet> set;
	std::unique_ptr<BiomeCells> biomes;
	std::unique_ptr<MainRoads> roads;
	std::unique_ptr<MainRoadCells> cells;
	std::unique_ptr<MainRoadSockets> sockets;
	DeriveInputs inputs() const {
		DeriveInputs in;
		in.header = &head;
		in.templates = set.get();
		in.cells = cells.get();
		in.providers = {sockets.get()};
		return in;
	}
};

inline std::unique_ptr<RoadRun> road_run(uint64_t seed, std::shared_ptr<TemplateSet> set, MainRoadParams params = {}) {
	auto r = std::make_unique<RoadRun>();
	r->head = header(seed);
	r->set = std::move(set);
	r->biomes = std::make_unique<BiomeCells>(seed, design_biomes(), r->head.sockets);
	std::set<Coord> arches;
	for (int e = 0; e < 4; e++) {
		if (static_cast<Edge>(e) != blind_side(seed)) {
			arches.insert(neighbour({0, 0}, static_cast<Edge>(e)));
		}
	}
	r->roads = std::make_unique<MainRoads>(seed, params, std::vector<int64_t>{80, 200, 400, 700}, arches);
	r->cells = std::make_unique<MainRoadCells>(*r->roads, *r->biomes);
	r->sockets = std::make_unique<MainRoadSockets>(*r->roads, *r->cells, r->head.sockets);
	return r;
}

} // namespace main_road_fixture
