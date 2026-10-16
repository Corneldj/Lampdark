#pragma once
// GEN-08: spines (Gameplay §12.3; GDD §15.9). A spine runs from base camp to a planned point of
// interest: it leaves by the gate whose outward direction is nearest the target's bearing from
// the shaft (never the blind side; ties by hash), then steps a cell at a time (4-neighbour) toward
// the cell outside the target's door, on the axis with more distance left (ties by hash), never
// into base camp, the Deep (ring 4) or a point of interest's cells; where both steps toward it are
// barred it goes round by the shortest way (Proposed). Its last step enters the target through
// its door edge. Every edge it crosses is forced open (SpineSockets, after points of interest and
// main roads in GEN-05's precedence) at the offset and width the edge's own hash gives; its cells
// take no gas, armed collapse or old fall (is_spine_cell). Nothing marks a spine. Pure.

#include "core/gen/derive.h"

#include <set>

namespace lb::core::gen {

// Rings from this one on are the Deep: no spine enters them.
constexpr int64_t DEEP_RING = 4;

// The gate (an open side of base camp) whose outward direction is nearest the bearing of a target
// point given in doubled tile units relative to the shaft; `tie` breaks exact ties.
Edge spine_gate(const std::vector<Edge> &gates, int64_t dx2, int64_t dy2, uint64_t tie);

// The door point of a site (the middle of its door edge) in doubled tile units relative to the
// shaft.
std::pair<int64_t, int64_t> door_point2(const PlannedSite &site);

// The spine to `site` (index `site_index`) on replan `replan`: nullopt if no way avoids `blocked`
// (every point of interest's cells), base camp and the Deep.
std::optional<Spine> route_spine(uint64_t seed, int32_t site_index, const PlannedSite &site, const std::vector<Edge> &gates,
		const std::set<lb::core::world::Coord> &blocked, const std::vector<int64_t> &ring_bounds, int32_t replan);

// The edges a spine crosses: base camp's gate edge, each step, and its site's door edge.
std::vector<EdgeKey> spine_edges(const Spine &spine, const PlannedSite &site);

// Rule 4 of GEN-05's precedence: every spine edge open, at the offset and width the edge's hash
// gives among the widths both cells allow.
class SpineSockets : public SocketProvider {
public:
	SpineSockets(uint64_t seed, const RunPlan &plan, const CellClassifier &cells, SocketParams params);
	std::optional<Socket> query(const EdgeKey &edge) const override;
	bool is_spine_cell(lb::core::world::Coord c) const { return cells_.count(c) != 0; }
	const std::set<lb::core::world::Coord> &cells() const { return cells_; }

private:
	uint64_t seed_;
	const CellClassifier &classifier_;
	SocketParams params_;
	std::set<EdgeKey> edges_;
	std::set<lb::core::world::Coord> cells_;
};

} // namespace lb::core::gen
