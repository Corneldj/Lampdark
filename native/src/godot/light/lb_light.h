#pragma once
// GDScript faces of core/light (VIS-02). LbLightGrid is server-only; LbLightMath holds the
// pure falloff the client uses to predict its own lamp (NET-05, VIS-06).

#include "core/light/light_grid.h"
#include "godot/world/lb_mine.h"

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/rect2.hpp>

#include <memory>

namespace lb::godot {

class LbLightGrid : public ::godot::RefCounted {
	GDCLASS(LbLightGrid, ::godot::RefCounted)

protected:
	static void _bind_methods();

public:
	void attach(const ::godot::Ref<LbMine> &mine);
	void set_params(double core_fraction, double core_value, double edge_value, double cap, int64_t scale);

	int64_t add_point(const ::godot::String &kind, int64_t colour, int64_t owner, int64_t flags, double radius,
			double peak, ::godot::Vector2 position, int64_t lifetime_ticks);
	int64_t add_area(const ::godot::String &kind, int64_t colour, int64_t owner, double value, const ::godot::Array &tiles);
	int64_t add_spill(const ::godot::String &kind, int64_t colour, int64_t owner, const ::godot::Array &doorway,
			::godot::Vector2i outward, double length, double start_value, double end_value);
	int64_t add_spot(int64_t owner, ::godot::Vector2i tile, double value, int64_t lifetime_ticks);
	bool update_point(int64_t id, ::godot::Vector2 position, double radius, double peak);
	bool set_radius_modifier(int64_t id, double multiplier, const ::godot::String &cause);
	bool set_flags(int64_t id, int64_t flags);
	// CRT-04: a source's description ({} if none): kind, owner, flags, shape, colour, position,
	// radius, peak.
	::godot::Dictionary source_info(int64_t id) const;
	bool remove_source(int64_t id);
	bool has_source(int64_t id) const;
	::godot::Vector2 velocity(int64_t id) const;

	void on_cell_loaded(::godot::Vector2i cell);
	void on_cell_unloading(::godot::Vector2i cell);
	void on_tiles_changed(::godot::Vector2i cell, ::godot::Rect2i rect, const ::godot::String &reason);

	void begin_tick(double tick_hz);
	void update();

	int64_t value(::godot::Vector2i tile) const;
	int64_t value_at(::godot::Vector2 position) const;
	int64_t value_from(::godot::Vector2i tile, const ::godot::PackedInt64Array &owners) const;
	int64_t colour_class(::godot::Vector2i tile) const;
	// {id, position, radius}; id 0 when unlit.
	::godot::Dictionary brightest_source(::godot::Vector2i tile) const;
	::godot::Array tiles_at_or_above(int64_t threshold, ::godot::Rect2i rect) const;
	::godot::PackedInt64Array flame_sources(::godot::Rect2 rect) const;
	int64_t digest() const;
	int64_t last_update_usec() const;
	int64_t source_count() const;
	// The largest radius, after modifiers, of an owner's own point lights; 0 when none is lit.
	double owned_radius(int64_t owner) const;
	// The core grid, for other native stages (VIS-03's seen sets); null before attach().
	const lb::core::light::LightGrid *core() const { return grid_.get(); }

private:
	::godot::Ref<LbMine> mine_;
	std::unique_ptr<lb::core::light::LightGrid> grid_;
	void emit_events();
};

class LbLightMath : public ::godot::RefCounted {
	GDCLASS(LbLightMath, ::godot::RefCounted)

protected:
	static void _bind_methods();

public:
	// Thousandths of light at distance d from a source of this radius and peak, with the
	// design's falloff and the given parameters (light.* tuning).
	static int64_t falloff_milli(double distance, double radius, double peak, double core_fraction, double core_value,
			double edge_value);
};

} // namespace lb::godot
