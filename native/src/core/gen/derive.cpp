#include "core/gen/derive.h"

#include "core/gen/main_roads.h"
#include "core/gen/validator.h"

#include "core/generated/hash_domains.h"
#include "core/rng/hash.h"

namespace lb::core::gen {

using lb::core::world::Coord;

CellClass UniformCells::classify(Coord cell) const {
	CellClass c;
	c.biome = biome_;
	c.widths = widths_;
	if (cell.x == 0 && cell.y == 0) {
		c.kind = TemplateKind::BASE_CAMP;
		c.templated = false;
	}
	return c;
}

Socket derive_socket(const DeriveInputs &in, const EdgeKey &edge) {
	if (std::optional<Socket> s = in.header->forced.query(edge)) {
		return *s;
	}
	for (const SocketProvider *p : in.providers) {
		if (std::optional<Socket> s = p->query(edge)) {
			s->forced = true;
			return *s;
		}
	}
	const Coord a{edge.x, edge.y};
	const Coord b = edge.axis == Axis::EAST ? Coord{edge.x + 1, edge.y} : Coord{edge.x, edge.y + 1};
	const std::vector<int32_t> widths =
			shared_widths(in.cells->classify(a).widths, in.cells->classify(b).widths, in.header->sockets);
	return hashed_socket(in.header->seed, edge, in.header->sockets, widths);
}

CellSockets derive_sockets(const DeriveInputs &in, Coord cell) {
	CellSockets out{};
	for (size_t e = 0; e < out.size(); e++) {
		out[e] = derive_socket(in, edge_of(cell, static_cast<Edge>(e)));
	}
	return out;
}

namespace {

std::optional<Layout> layout_from(const DeriveInputs &in, Coord cell, int32_t reroll, const CellSockets &sockets) {
	Layout out;
	out.coord = cell;
	out.sockets = sockets;
	const CellClass cls = in.cells->classify(cell);
	if (!cls.templated) {
		out.base_camp = true;
		out.digest = layout_digest(out);
		return out;
	}
	if (cls.kind == TemplateKind::POI && cls.poi_template != nullptr) {
		// GEN-09: a point of interest's cell is its placed template's, whatever the reroll.
		out.template_id = cls.poi_template->id;
		out.cell = fill_stubs(*cls.poi_template, sockets, cell, cls.poi_cell);
		out.digest = layout_digest(out);
		return out;
	}
	const Choice choice = choose_template(*in.templates, cls, sockets, in.header->seed, cell, reroll, in.header->reroll_limit);
	if (choice.chosen == nullptr) {
		return std::nullopt;
	}
	out.fallback = choice.fallback;
	out.template_id = choice.chosen->id;
	out.cell = fill_stubs(*choice.chosen, sockets, cell);
	if (choice.chosen->kind == TemplateKind::MAIN_ROAD) {
		dress(out.cell, cls.dress); // GEN-07: main-road templates take their faces from the biome they cross
	}
	out.digest = layout_digest(out);
	return out;
}

} // namespace

std::optional<Layout> derive_layout(const DeriveInputs &in, Coord cell, int32_t reroll) {
	return layout_from(in, cell, reroll, derive_sockets(in, cell));
}

uint64_t layout_digest(const Layout &layout) {
	std::vector<int64_t> keys{layout.coord.x, layout.coord.y, layout.base_camp ? 1 : 0, layout.fallback ? 1 : 0};
	for (const Socket &s : layout.sockets) {
		keys.push_back(s.open ? 1 : 0);
		keys.push_back(s.offset);
		keys.push_back(s.width);
		keys.push_back(s.forced ? 1 : 0);
	}
	for (char ch : layout.template_id) {
		keys.push_back(static_cast<unsigned char>(ch));
	}
	keys.push_back(layout.base_camp ? 0 : static_cast<int64_t>(lb::core::world::content_digest(layout.cell)));
	return hash_u64(0, hash_domain::GEN_CELL_DIGEST, keys.data(), keys.size());
}

template <typename K, typename V>
const V *Deriver::Lru<K, V>::get(const K &k) {
	auto it = at.find(k);
	if (it == at.end()) {
		return nullptr;
	}
	order.splice(order.begin(), order, it->second);
	return &it->second->second;
}

template <typename K, typename V>
void Deriver::Lru<K, V>::put(const K &k, const V &v) {
	if (capacity == 0) {
		return;
	}
	auto it = at.find(k);
	if (it != at.end()) {
		it->second->second = v;
		order.splice(order.begin(), order, it->second);
		return;
	}
	order.emplace_front(k, v);
	at[k] = order.begin();
	if (order.size() > capacity) {
		at.erase(order.back().first);
		order.pop_back();
	}
}

Deriver::Deriver(DeriveInputs inputs, size_t layout_capacity, size_t socket_capacity) : in_(std::move(inputs)) {
	layouts_.capacity = layout_capacity;
	finals_.capacity = layout_capacity;
	sockets_.capacity = socket_capacity;
}

Socket Deriver::socket(const EdgeKey &edge) const {
	if (caching_) {
		std::lock_guard<std::mutex> lock(mutex_);
		if (const Socket *s = sockets_.get(edge)) {
			return *s;
		}
	}
	const Socket s = derive_socket(in_, edge);
	if (caching_) {
		std::lock_guard<std::mutex> lock(mutex_);
		sockets_.put(edge, s);
	}
	return s;
}

CellSockets Deriver::sockets(Coord cell) const {
	CellSockets out{};
	for (size_t e = 0; e < out.size(); e++) {
		out[e] = socket(edge_of(cell, static_cast<Edge>(e)));
	}
	return out;
}

std::optional<Layout> Deriver::derive(Coord cell, int32_t reroll) const {
	const std::tuple<int64_t, int64_t, int32_t> key{cell.x, cell.y, reroll};
	std::optional<Layout> out;
	bool hit = false;
	if (caching_) {
		std::lock_guard<std::mutex> lock(mutex_);
		if (const std::optional<Layout> *l = layouts_.get(key)) {
			out = *l;
			hit = true;
		}
	}
	if (!hit) {
		out = layout_from(in_, cell, reroll, sockets(cell));
		if (caching_) {
			std::lock_guard<std::mutex> lock(mutex_);
			layouts_.put(key, out);
		}
	}
	if (verify_) {
		const std::optional<Layout> fresh = derive_layout(in_, cell, reroll);
		if (fresh.has_value() != out.has_value() || (fresh && fresh->digest != out->digest)) {
			verify_failures_++;
		}
	}
	return out;
}

std::optional<Layout> Deriver::derive_final(Coord cell) const {
	const std::pair<int64_t, int64_t> key{cell.x, cell.y};
	std::optional<Layout> out;
	bool hit = false;
	if (caching_) {
		std::lock_guard<std::mutex> lock(mutex_);
		if (const std::optional<Layout> *l = finals_.get(key)) {
			out = *l;
			hit = true;
		}
	}
	if (!hit) {
		std::vector<LayoutTry> tried;
		out = gen::derive_final(in_, cell, &tried, [&](int32_t reroll) { return derive(cell, reroll); });
		if (in_.counters != nullptr && in_.validator != nullptr) {
			in_.counters->count_layout(cell, in_.cells->classify(cell).biome, out, tried);
		}
		if (caching_) {
			std::lock_guard<std::mutex> lock(mutex_);
			finals_.put(key, out);
		}
	}
	if (verify_) {
		const std::optional<Layout> fresh = gen::derive_final(in_, cell);
		if (fresh.has_value() != out.has_value() || (fresh && (fresh->digest != out->digest || fresh->reroll != out->reroll))) {
			verify_failures_++;
		}
	}
	return out;
}

void Deriver::set_caching(bool on) {
	std::lock_guard<std::mutex> lock(mutex_);
	caching_ = on;
	if (!on) {
		sockets_.clear();
		layouts_.clear();
		finals_.clear();
	}
}

void Deriver::clear_caches() {
	std::lock_guard<std::mutex> lock(mutex_);
	sockets_.clear();
	layouts_.clear();
	finals_.clear();
}

} // namespace lb::core::gen
