// NET-08: the audit's reference visibility agrees with production exactly, on random maps: line of
// sight (Ford's symmetric shadowcasting), the light field, and whole perception frames (detail tiles
// with their light and colour, the glow, VIS-04's margin, identity, tokens, margin and turn-band
// tokens). The reference is written apart from VIS-02 to VIS-04; this test is the only place the
// two meet, so a disagreement here is a finding in one of them.
#include "doctest.h"

#include "audit/reference_reach.h"
#include "audit/reference_vis.h"
#include "core/sound/rock_line.h"
#include "core/light/shadowcast.h"
#include "light_fixture.h"
#include "vision_fixture.h"

#include <random>
#include <set>

using namespace vision_fixture;
namespace ref = lb::audit;

namespace {

std::vector<std::string> random_picture(std::mt19937_64 &rng, double walls) {
	std::uniform_real_distribution<double> u(0.0, 1.0);
	std::vector<std::string> rows(20, std::string(20, '.'));
	for (auto &row : rows) {
		for (char &c : row) {
			const double r = u(rng);
			c = r < walls ? '#' : (r < walls * 1.15 ? 'B' : '.');
		}
	}
	return rows;
}

ref::Blocks opaque_of(const MineMap &m) {
	return [&m](ref::Pos p) { return m.is_opaque(Coord{p.x, p.y}); };
}

std::vector<ref::Source> sources_of(const LightGrid &g, const std::vector<uint32_t> &ids) {
	std::vector<ref::Source> out;
	for (uint32_t id : ids) {
		const SourceDesc d = *g.source(id);
		ref::Source s;
		s.id = id;
		s.shape = static_cast<uint8_t>(d.shape);
		s.colour = static_cast<uint8_t>(d.colour);
		s.owner = d.owner;
		s.radius = d.radius;
		s.radius_mult = g.radius_mult(id);
		s.peak = d.peak;
		s.end_value = d.end_value;
		s.x = d.x;
		s.y = d.y;
		for (const Coord &t : d.tiles) {
			s.tiles.push_back({t.x, t.y});
		}
		s.dir = {d.dir.x, d.dir.y};
		s.spot = {d.spot.x, d.spot.y};
		out.push_back(s);
	}
	return out;
}

uint8_t quantise(int64_t v) {
	const int64_t q = (v * 255 + 500) / 1000;
	return static_cast<uint8_t>(q < 0 ? 0 : (q > 255 ? 255 : q));
}

} // namespace

TEST_CASE("NET-08: the reference's line of sight is production's symmetric shadowcasting") {
	std::mt19937_64 rng(808);
	for (int round = 0; round < 60; round++) {
		World w(1, random_picture(rng, 0.08 + 0.004 * round));
		std::uniform_int_distribution<int64_t> at(0, 19);
		const Coord o{at(rng), at(rng)};
		const int64_t depth = 5 + round % 36;
		std::set<std::pair<int64_t, int64_t>> prod;
		lb::core::light::shadowcast(o, depth, [&](Coord t) { return w.mine.is_opaque(t); }, [&](Coord t) { prod.insert({t.x, t.y}); });
		std::set<std::pair<int64_t, int64_t>> mine;
		for (const ref::Pos &p : ref::symmetric_fov({o.x, o.y}, depth, opaque_of(w.mine))) {
			mine.insert({p.x, p.y});
		}
		CHECK(prod == mine);
	}
}

TEST_CASE("NET-08: the reference's light field is production's, value and colour") {
	std::mt19937_64 rng(4040);
	for (int round = 0; round < 25; round++) {
		World w(1, random_picture(rng, 0.12));
		std::uniform_real_distribution<double> pos(0.0, 20.0);
		std::uniform_real_distribution<double> rad(1.0, 9.0);
		std::vector<uint32_t> ids;
		for (int i = 0; i < 6; i++) {
			SourceDesc d = light_fixture::lamp(pos(rng), pos(rng), rad(rng), 0);
			d.colour = static_cast<ColourClass>(1 + i % 5);
			ids.push_back(w.light->add_source(d));
			if (i == 2) {
				w.light->set_radius_modifier(ids.back(), 0.7, "gutter");
			}
		}
		ids.push_back(w.spot({3, 4}, 0.2, ColourClass::EGG_GLOW));
		ids.push_back(w.area({10, 10}, {12, 11}, 0.4, ColourClass::WHITE));
		w.settle();
		const auto mine = ref::light_window(sources_of(*w.light, ids), ref::LightDefs{}, [&](ref::Pos p) { return !w.mine.tile_at({p.x, p.y}).has_value() || w.mine.is_opaque({p.x, p.y}); }, [&](ref::Pos p) { return w.mine.tile_at({p.x, p.y}).has_value(); }, -20, -20, 39, 39);
		int64_t compared = 0;
		for (int64_t y = -20; y <= 39; y++) {
			for (int64_t x = -20; x <= 39; x++) {
				const lb::core::light::TileLight p = w.light->tile_light({x, y});
				auto it = mine.find({x, y});
				const int64_t v = it == mine.end() ? 0 : it->second.value;
				CHECK(p.value == v);
				if (p.value > 0) {
					CHECK(static_cast<uint8_t>(p.colour) == it->second.colour);
					compared++;
				}
			}
		}
		CHECK(compared > 50);
	}
}

TEST_CASE("NET-08: the reference's whole frame is production's") {
	std::mt19937_64 rng(9090);
	int64_t tiles = 0, glows = 0, margins = 0, ids = 0, tokens = 0, margin_tokens = 0;
	for (int round = 0; round < 40; round++) {
		World w(2, random_picture(rng, 0.10));
		Vision &v = *w.vision;
		std::uniform_real_distribution<double> pos(-15.0, 35.0);
		std::uniform_real_distribution<double> rad(2.0, 8.0);
		std::uniform_int_distribution<uint32_t> face(0, 65535);
		// The observer (entity 1) carries a lamp; other lights and entities scatter about.
		double ox = 10.5, oy = 10.5;
		for (int tries = 0; tries < 50 && w.mine.is_opaque({static_cast<int64_t>(std::floor(ox)), static_cast<int64_t>(std::floor(oy))}); tries++) {
			ox = std::floor(pos(rng)) + 0.25 + 0.5 * (tries % 2);
			oy = std::floor(pos(rng)) + 0.75;
		}
		std::vector<uint32_t> lights;
		const double own_r = round % 5 == 0 ? 0.0 : rad(rng);
		lights.push_back(w.light->add_source(light_fixture::lamp(ox, oy, own_r > 0.0 ? own_r : 1.0, 1)));
		if (own_r == 0.0) {
			w.light->update_point(lights.back(), ox, oy, 0.0, 1.0); // shuttered: no edge, no margin
		}
		for (int i = 0; i < 5; i++) {
			SourceDesc d = light_fixture::lamp(pos(rng), pos(rng), rad(rng), 0);
			d.colour = static_cast<ColourClass>(1 + (i + round) % 5);
			lights.push_back(w.light->add_source(d));
		}
		w.settle();
		std::vector<MirrorEntity> ents{entity(1, MINER, ox, oy)};
		const uint16_t kinds[] = {MINER, STYTHE, MOTH, COAT_HEAP, ITEM};
		for (uint32_t id = 2; id < 22; id++) {
			const double ex = std::floor(ox + std::uniform_real_distribution<double>(-14.0, 14.0)(rng)) + 0.5;
			const double ey = std::floor(oy + std::uniform_real_distribution<double>(-10.0, 10.0)(rng)) + 0.5;
			ents.push_back(entity(id, kinds[id % 5], ex, ey, id % 7 == 0 ? 1u : 0u));
		}
		const uint32_t facing = face(rng);
		const double band = round % 3 == 0 ? 0.0 : 20.0 + round;
		PerceptionClass moth = v.table.get(MOTH);
		moth.footprint = 2; // a large thing: the brightest of its 2x2 tiles
		v.table.set(MOTH, moth);
		v.set_observer(7, 1, ox, oy, facing);
		v.set_turn_band(7, band);
		const PerceptionFrame f2 = v.compute(7, ents);

		ref::Observer o;
		o.self = 1;
		o.x = ox;
		o.y = oy;
		o.facing = facing;
		o.turn_band = band;
		for (const auto &l : w.light->owned_lights(1)) {
			o.own_lights.push_back({{l.x, l.y}, l.radius});
		}
		const auto field = ref::light_window(sources_of(*w.light, lights), ref::LightDefs{}, [&](ref::Pos p) { return !w.mine.tile_at({p.x, p.y}).has_value() || w.mine.is_opaque({p.x, p.y}); }, [&](ref::Pos p) { return w.mine.tile_at({p.x, p.y}).has_value(); }, -60, -60, 80, 80);
		std::vector<ref::Entity> refs;
		for (const MirrorEntity &e : ents) {
			const PerceptionClass c = v.table.get(e.kind);
			ref::Entity re;
			re.id = e.id;
			re.size = static_cast<uint8_t>(c.size);
			re.token_class = static_cast<uint8_t>(v.table.token_class(e.kind, e.flags));
			re.footprint = c.footprint;
			re.x = e.x;
			re.y = e.y;
			refs.push_back(re);
		}
		const ref::Expected x = ref::evaluate(o, ref::VisionDefs{}, field, opaque_of(w.mine), refs);

		std::map<std::pair<int64_t, int64_t>, std::pair<uint8_t, uint8_t>> prod_tiles, ref_tiles;
		for (const FrameTile &t : f2.tiles) {
			prod_tiles[{t.tile.x, t.tile.y}] = {t.light, t.colour};
		}
		for (const auto &[p, l] : x.detail) {
			ref_tiles[{p.x, p.y}] = {quantise(l.value), l.colour};
		}
		CHECK(prod_tiles == ref_tiles);
		tiles += static_cast<int64_t>(prod_tiles.size());
		REQUIRE(f2.glow.size() == x.glow.size());
		for (size_t b = 0; b < x.glow.size(); b++) {
			CHECK(f2.glow[b].present == x.glow[b].first);
			if (x.glow[b].first) {
				CHECK(f2.glow[b].colour == x.glow[b].second);
				glows++;
			}
		}
		std::set<std::pair<int64_t, int64_t>> prod_margin, ref_margin;
		for (const Coord &t : f2.margin_tiles) {
			prod_margin.insert({t.x, t.y});
		}
		for (const ref::Pos &p : x.margin) {
			ref_margin.insert({p.x, p.y});
		}
		CHECK(prod_margin == ref_margin);
		margins += static_cast<int64_t>(prod_margin.size());
		std::map<uint32_t, std::pair<uint8_t, uint8_t>> prod_ents;
		for (uint32_t id : f2.identified) {
			prod_ents[id] = {ref::LEVEL_IDENTITY, 0};
			ids++;
		}
		for (const FrameToken &t : f2.tokens) {
			prod_ents[t.entity] = {ref::LEVEL_TOKEN, static_cast<uint8_t>(t.size)};
			tokens++;
		}
		for (const FrameToken &t : f2.margin_tokens) {
			prod_ents[t.entity] = {ref::LEVEL_MARGIN, static_cast<uint8_t>(t.size)};
			margin_tokens++;
		}
		CHECK(prod_ents == x.entities);
	}
	MESSAGE("compared " << tiles << " tiles, " << glows << " glow buckets, " << margins << " margin tiles, " << ids
						<< " identities, " << tokens << " tokens, " << margin_tokens << " margin tokens");
	CHECK(tiles > 1000);
	CHECK(glows > 20);
	CHECK(margins > 50);
	CHECK(ids > 10);
	CHECK(tokens > 5);
	CHECK(margin_tokens > 5);
}

TEST_CASE("NET-08: blinded, the reference expects nothing") {
	ref::Observer o;
	o.blinded = true;
	const ref::Expected x = ref::evaluate(o, ref::VisionDefs{}, {}, [](ref::Pos) { return false; }, {});
	CHECK(x.blinded);
	CHECK(x.detail.empty());
	CHECK(x.entities.empty());
}

TEST_CASE("NET-08: the reference's straight line is SND-01's rock line") {
	std::mt19937_64 rng(5150);
	std::uniform_int_distribution<int64_t> at(0, 19);
	for (int round = 0; round < 20; round++) {
		World w(1, random_picture(rng, 0.3));
		for (int k = 0; k < 40; k++) {
			const Coord a{at(rng), at(rng)}, b{at(rng), at(rng)};
			const lb::core::sound::RockLine prod = lb::core::sound::rock_line(w.mine, a, b);
			auto mat = [&](ref::Pos p) {
				const auto t = w.mine.tile_at({p.x, p.y});
				return t ? static_cast<lb::core::world::TileMaterial>(t->material) : lb::core::world::TileMaterial::ROCK;
			};
			const ref::Line mine = ref::straight_line({a.x, a.y}, {b.x, b.y}, [&](ref::Pos p) { return w.mine.is_solid({p.x, p.y}); }, [&](ref::Pos p) { return mat(p) == lb::core::world::TileMaterial::BRICK; }, [&](ref::Pos p) {
						const auto m = mat(p);
						return m == lb::core::world::TileMaterial::STEEL || m == lb::core::world::TileMaterial::WOODEN_DOOR; });
			CHECK(mine.solid == prod.solid_tiles);
			CHECK(mine.brick == prod.brick);
			CHECK(mine.door == prod.door);
			CHECK(mine.distance == doctest::Approx(prod.distance));
		}
	}
}

TEST_CASE("NET-08: the reference's reach is a lower bound: eight neighbours at 1, closed portals at 12 or impassable") {
	auto kind = [](ref::Pos p) -> uint8_t {
		if (p.x < 0 || p.x > 9 || p.y < 0 || p.y > 4) {
			return ref::SOLID;
		}
		if (p.x == 5) {
			return p.y == 2 ? ref::PORTAL_CLOSED : ref::SOLID; // a wall with a shut door in it
		}
		return ref::OPEN;
	};
	CHECK(ref::reach_cost({{0, 0}}, {4, 4}, 40.0, false, 12.0, kind) == doctest::Approx(4.0)); // diagonal steps cost 1
	CHECK(ref::reach_cost({{0, 2}}, {9, 2}, 40.0, false, 12.0, kind) == doctest::Approx(9.0 + 12.0));
	CHECK(ref::reach_cost({{0, 2}}, {9, 2}, 40.0, true, 12.0, kind) < 0.0); // voice: the door stops it
	CHECK(ref::reach_cost({{0, 2}}, {9, 2}, 20.0, false, 12.0, kind) < 0.0); // beyond the budget
}
