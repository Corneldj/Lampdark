#pragma once
// GEN-05: derive_layout, the pure layout stage (Gameplay §12.3, §12.6; GDD §15.9). A cell's layout
// (its sockets, its template and the template fitted to them) depends only on the run header, the
// template set, the cell's class (GEN-06, GEN-07, GEN-09), its coordinates and the reroll index.
// It never reads loaded cells, the diff log, entities, time, threads or call order, so a cell is
// the same whichever way the mine is explored, after eviction and after a resume. Server-only.

#include "core/gen/stub_fill.h"

#include <atomic>
#include <list>
#include <memory>
#include <mutex>
#include <optional>

namespace lb::core::gen {

// What GEN-08's run plan fixes for generation. Until GEN-08, the seed, the socket numbers, the
// reroll limit (GEN-12's) and the sockets forced up front (base camp's, from GEN-02).
struct RunHeader {
	uint64_t seed = 0;
	SocketParams sockets;
	int32_t reroll_limit = 20; // mine.validator_max_rerolls
	FixedSockets forced;
};

// A cell's kind, biome and road widths (GEN-06's biome, GEN-07's main roads, GEN-09's points of
// interest). `templated` is false for base camp, which GEN-02 builds.
struct CellClass {
	TemplateKind kind = TemplateKind::BIOME_CELL;
	std::string biome;
	std::vector<int32_t> widths;
	bool templated = true;
};

class CellClassifier {
public:
	virtual ~CellClassifier() = default;
	virtual CellClass classify(lb::core::world::Coord cell) const = 0;
};

// GEN-05's stand-in until GEN-06, GEN-07 and GEN-09: base camp at (0, 0), every other cell a
// biome cell of one biome allowing every socket width.
class UniformCells : public CellClassifier {
public:
	UniformCells(std::string biome, std::vector<int32_t> widths) : biome_(std::move(biome)), widths_(std::move(widths)) {}
	CellClass classify(lb::core::world::Coord cell) const override;

private:
	std::string biome_;
	std::vector<int32_t> widths_;
};

struct Layout {
	lb::core::world::Coord coord;
	bool base_camp = false; // GEN-02's cell: sockets only
	bool fallback = false;
	std::string template_id;
	CellSockets sockets{};
	lb::core::world::Cell cell;
	uint64_t digest = 0; // the sockets, the template and the fitted cell's content
};

// Everything derive_layout may read.
struct DeriveInputs {
	const RunHeader *header = nullptr;
	const TemplateSet *templates = nullptr;
	const CellClassifier *cells = nullptr;
	// Forced-socket providers after the header's own, in precedence order (points of interest,
	// main roads, spines); the hash answers the rest.
	std::vector<const SocketProvider *> providers;
};

Socket derive_socket(const DeriveInputs &in, const EdgeKey &edge);
CellSockets derive_sockets(const DeriveInputs &in, lb::core::world::Coord cell);
// The layout, or nullopt when no template covers the sockets and the biome has no fallback.
std::optional<Layout> derive_layout(const DeriveInputs &in, lb::core::world::Coord cell, int32_t reroll);
uint64_t layout_digest(const Layout &layout);

// derive_layout with LRU caches of sockets and layouts that can never change a result. Thread-safe.
// With verify on, every derive runs again with the caches bypassed and must give the same digest.
class Deriver {
public:
	explicit Deriver(DeriveInputs inputs, size_t layout_capacity = 512, size_t socket_capacity = 4096);

	Socket socket(const EdgeKey &edge) const;
	CellSockets sockets(lb::core::world::Coord cell) const;
	std::optional<Layout> derive(lb::core::world::Coord cell, int32_t reroll) const;

	void set_caching(bool on);
	void clear_caches();
	void set_verify(bool on) { verify_ = on; }
	// Derives whose verify pass disagreed (always 0 unless a cache or an input is impure).
	uint64_t verify_failures() const { return verify_failures_.load(); }

private:
	template <typename K, typename V>
	struct Lru {
		size_t capacity = 0;
		std::list<std::pair<K, V>> order;
		std::map<K, typename std::list<std::pair<K, V>>::iterator> at;
		const V *get(const K &k);
		void put(const K &k, const V &v);
		void clear() {
			order.clear();
			at.clear();
		}
	};

	DeriveInputs in_;
	std::atomic<bool> caching_{true};
	std::atomic<bool> verify_{false};
	mutable std::mutex mutex_;
	mutable Lru<EdgeKey, Socket> sockets_;
	mutable Lru<std::tuple<int64_t, int64_t, int32_t>, std::optional<Layout>> layouts_;
	mutable std::atomic<uint64_t> verify_failures_{0};
};

} // namespace lb::core::gen
