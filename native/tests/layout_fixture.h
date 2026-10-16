#pragma once
// GEN-05's fixtures: a template set (two grid templates covering every socket set, at weights 1
// and 3; the base biome cell, which covers few; and the plain fallback) and a run header whose
// base camp sockets follow GEN-02's rule (blind side = gen.basecamp's hash, gates 3 wide at 10).

#include "core/gen/derive.h"
#include "core/generated/hash_domains.h"
#include "core/rng/hash.h"
#include "template_fixture.h"

#include <doctest.h>

#include <memory>

namespace layout_fixture {

using namespace template_fixture;

inline Template grid(const std::string &id, double weight) {
	Spec s = fallback_spec();
	s.id = id;
	s.kind = TemplateKind::BIOME_CELL;
	Template t = make(s);
	t.weight = weight;
	return t;
}

inline std::shared_ptr<TemplateSet> template_set() {
	std::vector<Template> list{grid("seam_grid_a", 1.0), grid("seam_grid_b", 3.0), make(Spec{}), make(fallback_spec())};
	auto set = std::make_shared<TemplateSet>();
	REQUIRE(set->load(encode_pack("fixture", list)));
	return set;
}

inline Edge blind_side(uint64_t seed) {
	const int64_t key = 0;
	return static_cast<Edge>(lb::core::hash_u64(seed, lb::core::hash_domain::GEN_BASECAMP, &key, 1) & 3u);
}

inline RunHeader header(uint64_t seed) {
	RunHeader h;
	h.seed = seed;
	for (int e = 0; e < 4; e++) {
		Socket s;
		s.open = static_cast<Edge>(e) != blind_side(seed);
		s.offset = s.open ? 10 : 0;
		s.width = s.open ? 3 : 0;
		h.forced.set(edge_of({0, 0}, static_cast<Edge>(e)), s);
	}
	return h;
}

// A run's derive inputs, owning what they point at.
struct Run {
	RunHeader head;
	std::shared_ptr<TemplateSet> set;
	UniformCells cells{"seam", {1, 2, 3}};
	DeriveInputs inputs() const {
		DeriveInputs in;
		in.header = &head;
		in.templates = set.get();
		in.cells = &cells;
		return in;
	}
};

inline Run run(uint64_t seed, std::shared_ptr<TemplateSet> set) {
	Run r;
	r.head = header(seed);
	r.set = std::move(set);
	return r;
}

} // namespace layout_fixture
