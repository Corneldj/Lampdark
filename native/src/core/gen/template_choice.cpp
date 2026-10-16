#include "core/gen/template_choice.h"

#include "core/generated/hash_domains.h"
#include "core/rng/hash.h"

#include <algorithm>
#include <cmath>

namespace lb::core::gen {

using lb::core::world::Coord;

bool TemplateSet::load(const std::vector<uint8_t> &pack) {
	std::optional<Pack> decoded = decode_pack(pack);
	version_.clear();
	templates_.clear();
	index_.clear();
	if (!decoded) {
		return false;
	}
	version_ = decoded->set_version;
	templates_ = std::move(decoded->templates);
	std::sort(templates_.begin(), templates_.end(), [](const Template &a, const Template &b) { return a.id < b.id; });
	build_index();
	return true;
}

void TemplateSet::build_index() {
	for (const Template &t : templates_) {
		index_[{t.kind, t.biome}].push_back(&t);
	}
}

const std::vector<const Template *> &TemplateSet::of(TemplateKind kind, const std::string &biome) const {
	static const std::vector<const Template *> NONE;
	auto it = index_.find({kind, biome});
	return it == index_.end() ? NONE : it->second;
}

const Template *TemplateSet::fallback(const std::string &biome) const {
	const std::vector<const Template *> &list = of(TemplateKind::FALLBACK, biome);
	return list.empty() ? nullptr : list.front();
}

bool covers(const Template &t, const CellSockets &sockets) {
	if (t.footprint_w != 1 || t.footprint_h != 1) {
		return false;
	}
	for (size_t e = 0; e < sockets.size(); e++) {
		const Socket &s = sockets[e];
		if (!s.open) {
			continue;
		}
		bool fits = false;
		for (const Stub &stub : t.stubs) {
			fits = fits || (stub.edge == static_cast<Edge>(e) && stub.offset == s.offset && stub.max_width >= s.width);
		}
		if (!fits) {
			return false;
		}
	}
	return true;
}

Choice choose_template(const TemplateSet &set, TemplateKind kind, const std::string &biome, const CellSockets &sockets,
		uint64_t seed, Coord cell, int32_t reroll, int32_t reroll_limit) {
	Choice out;
	if (reroll < reroll_limit) {
		// Weights as whole thousandths, so the pick is integer arithmetic on every machine.
		std::vector<std::pair<const Template *, uint64_t>> candidates;
		uint64_t total = 0;
		for (const Template *t : set.of(kind, biome)) {
			const uint64_t w = t->weight > 0.0 ? static_cast<uint64_t>(std::llround(t->weight * 1000.0)) : 0;
			if (w > 0 && covers(*t, sockets)) {
				candidates.emplace_back(t, w);
				total += w;
			}
		}
		if (total > 0) {
			const int64_t keys[2] = {cell.x, cell.y};
			uint64_t r = sub_seed(seed, hash_domain::GEN_TEMPLATE, keys, 2, reroll) % total;
			for (const auto &[t, w] : candidates) {
				if (r < w) {
					out.chosen = t;
					return out;
				}
				r -= w;
			}
		}
	}
	out.chosen = set.fallback(biome);
	out.fallback = out.chosen != nullptr;
	return out;
}

} // namespace lb::core::gen
