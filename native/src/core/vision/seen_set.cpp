#include "core/vision/seen_set.h"

#include <algorithm>

#include <cmath>

#include <chrono>

namespace lb::core::vision {

using world::Coord;
using world::floor_div;

namespace {

// The tile a point lies in: floor, so -2.0 is tile -2 (NET-08's audit found -3).
Coord tile_of(double x, double y) {
	return Coord{static_cast<int64_t>(std::floor(x)), static_cast<int64_t>(std::floor(y))};
}

} // namespace

Vision::Observer *Vision::observer(uint32_t id) {
	auto it = observers_.find(id);
	return it == observers_.end() ? nullptr : &it->second;
}

void Vision::set_observer(uint32_t id, uint32_t self, double x, double y, uint32_t facing_u16) {
	Observer &o = observers_[id];
	o.self = self;
	o.x = x;
	o.y = y;
	o.facing = facing_u16 & 0xFFFFu;
}

void Vision::remove_observer(uint32_t id) {
	observers_.erase(id);
	last_.erase(id);
}

void Vision::set_blinded(uint32_t id, bool on) {
	if (Observer *o = observer(id)) {
		o->blinded = on;
	}
}

void Vision::set_radius_clamp(uint32_t id, double tiles) {
	if (Observer *o = observer(id)) {
		o->clamp = tiles > 0.0 ? tiles : 0.0;
	}
}

void Vision::set_bite_tiles(uint32_t id, std::set<Coord> tiles) {
	if (Observer *o = observer(id)) {
		o->bite = std::move(tiles);
	}
}

void Vision::set_identity_threshold(uint32_t entity, int64_t thousandths) {
	if (thousandths < 0) {
		identity_override_.erase(entity);
	} else {
		identity_override_[entity] = thousandths;
	}
}

void Vision::set_turn_band(uint32_t id, double degrees) {
	Observer *o = observer(id);
	if (o != nullptr) {
		o->turn_band = degrees < 0.0 ? 0.0 : (degrees > 180.0 ? 180.0 : degrees);
	}
}

void Vision::update_shadows(const std::vector<sim::MirrorEntity> &entities) {
	shadows_ = compute_shadows(map_, light_, table, entities, shadow);
}

void Vision::set_decals(Coord tile, uint8_t bits) {
	if (bits == 0) {
		decals_.erase(tile);
	} else {
		decals_[tile] = bits;
	}
}

void Vision::set_chalk(Coord tile, uint64_t glyphs) {
	if (glyphs == 0) {
		chalk_.erase(tile);
	} else {
		chalk_[tile] = glyphs;
	}
}

void Vision::on_tiles_changed(int64_t x0, int64_t y0, int64_t x1, int64_t y1) {
	for (auto &[id, o] : observers_) {
		if (o.los.valid() && o.los.touches(x0, y0, x1, y1)) {
			o.los.invalidate();
		}
	}
}

void Vision::ensure_los(Observer &o) {
	const Coord here = tile_of(o.x, o.y);
	if (o.los.valid() && o.los.origin() == here && o.los.range() == params.range) {
		return;
	}
	o.los.cast(here, params.range, [this](Coord t) { return map_.is_opaque(t); });
	recasts_++;
}

Cone Vision::cone_of(const Observer &o) const {
	return Cone::make(o.x, o.y, o.facing, params.cone_deg);
}

Unseen Vision::tile_state(Observer &o, const Cone &cone, Coord tile, int64_t &light) const {
	light = 0;
	if (o.blinded) {
		return Unseen::BLINDED;
	}
	const double cx = static_cast<double>(tile.x) + 0.5;
	const double cy = static_cast<double>(tile.y) + 0.5;
	const Coord here = o.los.origin();
	const int64_t dx = tile.x - here.x;
	const int64_t dy = tile.y - here.y;
	if (dx * dx + dy * dy > params.range * params.range) {
		return Unseen::BEYOND_RANGE;
	}
	if (o.clamp > 0.0) {
		const double ex = cx - o.x;
		const double ey = cy - o.y;
		if (ex * ex + ey * ey > o.clamp * o.clamp) {
			return Unseen::BEYOND_RANGE;
		}
	}
	if (!o.los.visible(tile)) {
		return Unseen::NO_LOS;
	}
	if (!cone.contains(cx, cy)) {
		return Unseen::OUTSIDE_CONE;
	}
	if (o.bite.count(tile) != 0) {
		return Unseen::BITE;
	}
	light = light_.tile_light(tile).value;
	if (light < params.seen_min) {
		return Unseen::DARK;
	}
	return Unseen::SEEN;
}

int64_t Vision::entity_light(Observer &o, const Cone &cone, const sim::MirrorEntity &e, Unseen &why) const {
	const PerceptionClass c = table.get(e.kind);
	const int64_t f = c.footprint < 1 ? 1 : c.footprint;
	const double half = static_cast<double>(f) * 0.5;
	const Coord lo = tile_of(e.x - half + 0.5, e.y - half + 0.5);
	int64_t best = -1;
	Unseen best_reason = Unseen::UNKNOWN;
	// Footprint tiles in row-major order; the brightest seen-eligible tile counts. The reason for a
	// miss is the most permissive state any footprint tile reached.
	for (int64_t yy = 0; yy < f; yy++) {
		for (int64_t xx = 0; xx < f; xx++) {
			const Coord t{lo.x + xx, lo.y + yy};
			int64_t light = 0;
			const Unseen s = tile_state(o, cone, t, light);
			if (s == Unseen::SEEN || s == Unseen::DARK) {
				if (light > best) {
					best = light;
				}
			}
			if (best_reason == Unseen::UNKNOWN || static_cast<uint8_t>(s) < static_cast<uint8_t>(best_reason)) {
				best_reason = s;
			}
		}
	}
	if (best >= params.seen_min) {
		why = Unseen::SEEN;
	} else if (best >= 0) {
		why = Unseen::DARK;
	} else {
		why = best_reason;
	}
	return best;
}

int64_t Vision::bucket_count() const {
	const int64_t n = static_cast<int64_t>(params.cone_deg / params.bucket_deg + 0.5);
	return n < 1 ? 1 : n;
}

std::array<double, 4> Vision::detail_rect(uint32_t id) const {
	auto it = observers_.find(id);
	if (it == observers_.end()) {
		return {0.0, 0.0, 0.0, 0.0};
	}
	const Observer &o = it->second;
	const Vec2 f = unit_at_facing(o.facing);
	const double cx = o.x + f.x * params.squint_lead;
	const double cy = o.y + f.y * params.squint_lead;
	const double hw = params.view_w * 0.5 + params.detail_widen;
	const double hh = params.view_h * 0.5 + params.detail_widen;
	return {cx - hw, cy - hh, cx + hw, cy + hh};
}

int64_t Vision::glow_bucket(uint32_t id, double x, double y) const {
	auto it = observers_.find(id);
	if (it == observers_.end()) {
		return -1;
	}
	const Observer &o = it->second;
	const Cone cone = cone_of(o);
	if (!cone.contains(x, y)) {
		return -1;
	}
	const double vx = x - o.x;
	const double vy = y - o.y;
	const double facing_turns = static_cast<double>(o.facing) / 65536.0;
	const int64_t n = bucket_count();
	// Bucket k spans [left + k * step, left + (k + 1) * step); count the boundaries passed.
	int64_t k = 0;
	for (int64_t b = 1; b < n; b++) {
		const double deg = -params.cone_deg * 0.5 + static_cast<double>(b) * params.bucket_deg;
		const Vec2 ray = unit_at_turns(facing_turns + deg / 360.0);
		// Past the ray when the point lies clockwise of it in screen space (+y down): cross >= 0.
		if (ray.x * vy - ray.y * vx >= 0.0) {
			k = b;
		}
	}
	return k;
}

PerceptionFrame Vision::compute(uint32_t id, const std::vector<sim::MirrorEntity> &entities) {
	PerceptionFrame frame = compute_frame(id, entities);
	if (observers_.count(id) != 0) {
		last_[id] = frame;
	}
	return frame;
}

PerceptionFrame Vision::compute_frame(uint32_t id, const std::vector<sim::MirrorEntity> &entities) {
	PerceptionFrame frame;
	Observer *o = observer(id);
	if (o == nullptr) {
		return frame;
	}
	frame.glow.assign(static_cast<size_t>(bucket_count()), GlowBucket{});
	o->bite_seen = false;
	o->bite_seen_at = -1.0;
	if (o->blinded) {
		frame.blinded = true;
		return frame;
	}
	ensure_los(*o);
	const Cone cone = cone_of(*o);
	const std::array<double, 4> rect = detail_rect(id);
	std::vector<std::array<int64_t, 8>> colour_counts(frame.glow.size(), std::array<int64_t, 8>{});
	o->los.for_each([&](Coord t) {
		int64_t light = 0;
		const Unseen state = tile_state(*o, cone, t, light);
		if (state == Unseen::BITE && light_.tile_light(t).value >= params.seen_min) {
			o->bite_seen = true; // a tile it would have seen, taken by the bite
			const double dx = static_cast<double>(t.x) + 0.5 - o->x;
			const double dy = static_cast<double>(t.y) + 0.5 - o->y;
			const double d = std::sqrt(dx * dx + dy * dy);
			if (o->bite_seen_at < 0.0 || d < o->bite_seen_at) {
				o->bite_seen_at = d;
			}
		}
		if (state != Unseen::SEEN) {
			return;
		}
		const double cx = static_cast<double>(t.x) + 0.5;
		const double cy = static_cast<double>(t.y) + 0.5;
		const light::TileLight tl = light_.tile_light(t);
		if (cx >= rect[0] && cx <= rect[2] && cy >= rect[1] && cy <= rect[3]) {
			FrameTile ft;
			ft.tile = t;
			ft.light = lb::core::light::quantise_u8(light);
			ft.colour = static_cast<uint8_t>(tl.colour);
			if (tl.colour == light::ColourClass::EGG_GLOW) {
				const auto src = light_.source(tl.brightest);
				if (src && (src->flags & light::flag::HATCH_TELL) != 0) {
					ft.colour = static_cast<uint8_t>(ft.colour | COLOUR_HATCH_BIT);
				}
			}
			auto d = decals_.find(t);
			if (d != decals_.end()) {
				uint8_t bits = 0;
				if ((d->second & DECAL_BLOOD) && light >= params.trail_min) {
					bits |= static_cast<uint8_t>(DECAL_BLOOD | (d->second & DECAL_DIR_MASK));
				}
				if (light >= params.small_min) {
					bits |= d->second & (DECAL_CHALK | DECAL_LINE_NUMBER);
				}
				// MNR-10: the glyphs ride with the chalk bit, never without it.
				if ((bits & DECAL_CHALK) != 0) {
					auto c = chalk_.find(t);
					if (c != chalk_.end()) {
						ft.chalk = c->second;
					} else {
						bits = static_cast<uint8_t>(bits & ~DECAL_CHALK);
					}
				}
				ft.decals = bits;
			}
			auto sh = shadows_.find(t);
			if (sh != shadows_.end()) {
				ft.decals = static_cast<uint8_t>(ft.decals | ((sh->second & 3) << SHADE_SHIFT));
			}
			frame.tiles.push_back(ft);
		} else {
			const int64_t b = glow_bucket(id, cx, cy);
			if (b >= 0) {
				frame.glow[static_cast<size_t>(b)].present = true;
				colour_counts[static_cast<size_t>(b)][static_cast<size_t>(tl.colour) & 7]++;
			}
		}
	});
	for (size_t b = 0; b < frame.glow.size(); b++) {
		if (!frame.glow[b].present) {
			continue;
		}
		int64_t best = -1;
		for (size_t c = 0; c < 8; c++) {
			if (colour_counts[b][c] > best) {
				best = colour_counts[b][c];
				frame.glow[b].colour = static_cast<uint8_t>(c);
			}
		}
	}
	std::vector<const sim::MirrorEntity *> unseen;
	for (const sim::MirrorEntity &e : entities) {
		if (e.id == o->self) {
			continue;
		}
		const Level level = sees_entity(id, e);
		if (level == Level::IDENTITY) {
			frame.identified.push_back(e.id);
		} else if (level == Level::TOKEN) {
			frame.tokens.push_back(FrameToken{table.token_class(e.kind, e.flags), e.x, e.y, e.id});
		} else {
			unseen.push_back(&e);
		}
	}
	// VIS-04's margin, from the miner's own lights. Timed for its budget (a diagnostic, never state).
	const auto margin_start = std::chrono::steady_clock::now();
	o->los.for_each([&](Coord t) {
		if (margin_band(id, t) > 0) {
			frame.margin_tiles.push_back(t);
		}
	});
	// NET-12's turn band: lit, in sight, just outside the cone but within what the miner can turn
	// into before this frame arrives. Never a bite, never small things; hidden until revealed.
	const bool banded = o->turn_band > 0.0 && !o->blinded;
	const Cone wide = Cone::make(o->x, o->y, o->facing, std::min(360.0, params.cone_deg + 2.0 * o->turn_band));
	for (const sim::MirrorEntity *e : unseen) {
		const PerceptionClass c = table.get(e->kind);
		const bool large = c.size == SizeClass::MINER || c.size == SizeClass::LARGE || c.size == SizeClass::LARGE_MOTIONLESS;
		if ((c.size == SizeClass::MINER || c.size == SizeClass::LARGE) && margin_band(id, tile_of(e->x, e->y)) == 2) {
			frame.margin_tokens.push_back(FrameToken{table.token_class(e->kind, e->flags), e->x, e->y, e->id});
			continue;
		}
		if (banded && large) {
			Unseen why = Unseen::UNKNOWN;
			if (entity_light(*o, wide, *e, why) >= params.seen_min && why == Unseen::SEEN) {
				frame.margin_tokens.push_back(FrameToken{table.token_class(e->kind, e->flags), e->x, e->y, e->id});
			}
		}
	}
	margin_nanos_ += std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now() - margin_start).count();
	return frame;
}

bool Vision::in_cone(uint32_t id, double x, double y) const {
	auto it = observers_.find(id);
	return it != observers_.end() && !it->second.blinded && cone_of(it->second).contains(x, y);
}

bool Vision::tile_seen(uint32_t id, Coord tile) {
	Observer *o = observer(id);
	if (o == nullptr) {
		return false;
	}
	if (o->blinded) {
		return false;
	}
	ensure_los(*o);
	int64_t light = 0;
	return tile_state(*o, cone_of(*o), tile, light) == Unseen::SEEN;
}

Level Vision::sees_entity(uint32_t id, const sim::MirrorEntity &e) {
	Observer *o = observer(id);
	const PerceptionClass c = table.get(e.kind);
	if (o == nullptr || o->blinded || c.size == SizeClass::NONE || e.id == o->self) {
		return Level::NONE;
	}
	ensure_los(*o);
	Unseen why = Unseen::UNKNOWN;
	const int64_t light = entity_light(*o, cone_of(*o), e, why);
	if (why != Unseen::SEEN) {
		return Level::NONE;
	}
	int64_t identity = c.identity_min >= 0 ? c.identity_min : params.identity_min;
	auto over = identity_override_.find(e.id);
	if (over != identity_override_.end()) {
		identity = over->second;
	}
	if (c.size == SizeClass::SMALL) {
		const int64_t small = c.identity_min >= 0 ? c.identity_min : params.small_min;
		return light >= small ? Level::IDENTITY : Level::NONE;
	}
	return light >= identity ? Level::IDENTITY : Level::TOKEN;
}

Unseen Vision::unseen_reason(uint32_t id, const sim::MirrorEntity &e) {
	Observer *o = observer(id);
	if (o == nullptr) {
		return Unseen::UNKNOWN;
	}
	if (o->blinded) {
		return Unseen::BLINDED;
	}
	ensure_los(*o);
	Unseen why = Unseen::UNKNOWN;
	entity_light(*o, cone_of(*o), e, why);
	return why;
}

int Vision::margin_band(uint32_t id, Coord tile) {
	Observer *o = observer(id);
	if (o == nullptr || o->blinded || o->self == 0) {
		return 0;
	}
	ensure_los(*o);
	int64_t light = 0;
	// Only dark tiles in sight and cone, not bitten: never the blind area, never a bite.
	if (tile_state(*o, cone_of(*o), tile, light) != Unseen::DARK) {
		return 0;
	}
	const double cx = static_cast<double>(tile.x) + 0.5, cy = static_cast<double>(tile.y) + 0.5;
	int band = 0;
	for (const light::LightGrid::OwnLight &l : light_.owned_lights(o->self)) {
		const double dx = cx - l.x, dy = cy - l.y;
		const double d2 = dx * dx + dy * dy;
		if (d2 <= l.radius * l.radius) {
			continue;
		}
		const double g = l.radius + params.margin_geometry;
		const double e = l.radius + params.margin_entity;
		if (d2 <= e * e) {
			return 2;
		}
		if (d2 <= g * g) {
			band = 1;
		}
	}
	return band;
}

bool Vision::is_seen_or_margin_of_any(Coord tile) {
	if (is_seen_by_any(tile)) {
		return true;
	}
	for (auto &[id, o] : observers_) {
		if (margin_band(id, tile) > 0) {
			return true;
		}
	}
	return false;
}

std::vector<Vision::SightTile> Vision::lit_in_sight(Coord from, double range, int64_t min_value,
		const std::vector<uint32_t> &excluded) const {
	std::vector<SightTile> out;
	LosField los;
	const int64_t r = static_cast<int64_t>(std::ceil(range));
	los.cast(from, r, [this](Coord t) { return map_.is_opaque(t); });
	const double r2 = range * range;
	los.for_each([&](Coord t) {
		const double dx = static_cast<double>(t.x - from.x), dy = static_cast<double>(t.y - from.y);
		if (dx * dx + dy * dy > r2) {
			return;
		}
		const std::pair<int64_t, uint32_t> v = light_.value_excluding(t, excluded);
		if (v.first <= 0) {
			return;
		}
		uint8_t colour = 0;
		if (std::optional<light::SourceDesc> d = light_.source(v.second)) {
			colour = static_cast<uint8_t>(d->colour);
		}
		if (v.first >= min_value || colour == static_cast<uint8_t>(light::ColourClass::EGG_GLOW)) {
			out.push_back({t, v.first, v.second, colour});
		}
	});
	return out;
}

bool Vision::is_seen_by_any(Coord tile) {
	for (auto &[id, o] : observers_) {
		if (o.blinded) {
			continue;
		}
		ensure_los(o);
		int64_t light = 0;
		if (tile_state(o, cone_of(o), tile, light) == Unseen::SEEN) {
			return true;
		}
	}
	return false;
}

} // namespace lb::core::vision
