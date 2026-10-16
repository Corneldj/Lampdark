#pragma once
// GEN-05: the template set the server holds (GEN-04's pack, decoded once) and the hash choice of a
// cell's template among those whose stubs cover its open sockets. Pure: the same set, seed, cell
// and reroll give the same template on every machine.

#include "core/gen/sockets.h"
#include "core/gen/template.h"

#include <array>
#include <map>
#include <string>
#include <utility>
#include <vector>

namespace lb::core::gen {

// A cell's four sockets, indexed by Edge (north, east, south, west).
using CellSockets = std::array<Socket, 4>;

class TemplateSet {
public:
	TemplateSet() = default;
	TemplateSet(const TemplateSet &) = delete; // its index points into its own templates
	TemplateSet &operator=(const TemplateSet &) = delete;

	// Decodes a pack and indexes it. False (and empty) for bytes that are not a whole pack.
	bool load(const std::vector<uint8_t> &pack);
	const std::string &set_version() const { return version_; }
	const std::vector<Template> &templates() const { return templates_; }
	// The templates of a kind and biome, sorted by id.
	const std::vector<const Template *> &of(TemplateKind kind, const std::string &biome) const;
	// The biome's plain fallback (its first by id), or nullptr.
	const Template *fallback(const std::string &biome) const;

private:
	std::string version_;
	std::vector<Template> templates_;
	std::map<std::pair<TemplateKind, std::string>, std::vector<const Template *>> index_;
	void build_index();
};

// True if every open socket has a stub on its edge at its offset at least as wide (a one-cell
// template; points of interest are GEN-09's).
bool covers(const Template &t, const CellSockets &sockets);

struct Choice {
	const Template *chosen = nullptr; // nullptr: no candidate and no fallback
	bool fallback = false;
};

// The weighted hash pick (gen.template, keyed by the cell and the reroll) among the covering
// templates of the cell's kind and biome, sorted by id; the biome's fallback when none covers or
// at the reroll limit (GEN-12's).
Choice choose_template(const TemplateSet &set, TemplateKind kind, const std::string &biome, const CellSockets &sockets,
		uint64_t seed, lb::core::world::Coord cell, int32_t reroll, int32_t reroll_limit);

} // namespace lb::core::gen
