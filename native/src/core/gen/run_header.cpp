#include "core/gen/run_header.h"

#include <algorithm>

namespace lb::core::gen {

using lb::core::world::Coord;

namespace {

const char *const KIND_NAMES[] = {"lamp_cabin", "fitters_shop", "stores", "fuel_store", "electricians_cabin", "substation",
		"haulage_engine_house", "deep_workshop", "first_aid_station", "powder_magazine", "refuge", "stables", "capped_shaft", "hoard",
		"lair"};
static_assert(sizeof(KIND_NAMES) / sizeof(KIND_NAMES[0]) == static_cast<size_t>(PoiKind::COUNT));

const uint8_t MAGIC[4] = {'L', 'B', 'R', 'H'};
constexpr uint16_t FORMAT = 1;

class Writer {
public:
	std::vector<uint8_t> out;

	void u8(uint8_t v) { out.push_back(v); }
	void u16(uint16_t v) { put(v, 2); }
	void u32(uint32_t v) { put(v, 4); }
	void u64(uint64_t v) { put(v, 8); }
	void i32(int32_t v) { put(static_cast<uint32_t>(v), 4); }
	void i64(int64_t v) { put(static_cast<uint64_t>(v), 8); }
	void str(const std::string &s) {
		u32(static_cast<uint32_t>(s.size()));
		out.insert(out.end(), s.begin(), s.end());
	}
	void bytes(const std::vector<uint8_t> &b) {
		u32(static_cast<uint32_t>(b.size()));
		out.insert(out.end(), b.begin(), b.end());
	}
	void coord(const Coord &c) {
		i64(c.x);
		i64(c.y);
	}
	void count(size_t n) { u16(static_cast<uint16_t>(n)); }

private:
	void put(uint64_t v, int n) {
		for (int i = 0; i < n; i++) {
			out.push_back(static_cast<uint8_t>((v >> (8 * i)) & 0xFF));
		}
	}
};

class Reader {
public:
	explicit Reader(const std::vector<uint8_t> &b) : b_(b) {}
	bool ok = true;

	uint8_t u8() { return static_cast<uint8_t>(get(1)); }
	uint16_t u16() { return static_cast<uint16_t>(get(2)); }
	uint32_t u32() { return static_cast<uint32_t>(get(4)); }
	uint64_t u64() { return get(8); }
	int32_t i32() { return static_cast<int32_t>(static_cast<uint32_t>(get(4))); }
	int64_t i64() { return static_cast<int64_t>(get(8)); }
	std::string str() {
		const uint32_t n = u32();
		if (!ok || at_ + n > b_.size()) {
			ok = false;
			return {};
		}
		std::string s(b_.begin() + static_cast<std::ptrdiff_t>(at_), b_.begin() + static_cast<std::ptrdiff_t>(at_ + n));
		at_ += n;
		return s;
	}
	std::vector<uint8_t> bytes() {
		const uint32_t n = u32();
		if (!ok || at_ + n > b_.size()) {
			ok = false;
			return {};
		}
		std::vector<uint8_t> v(b_.begin() + static_cast<std::ptrdiff_t>(at_), b_.begin() + static_cast<std::ptrdiff_t>(at_ + n));
		at_ += n;
		return v;
	}
	Coord coord() {
		const int64_t x = i64();
		const int64_t y = i64();
		return {x, y};
	}
	bool done() const { return ok && at_ == b_.size(); }

private:
	uint64_t get(int n) {
		if (!ok || at_ + static_cast<size_t>(n) > b_.size()) {
			ok = false;
			return 0;
		}
		uint64_t v = 0;
		for (int i = 0; i < n; i++) {
			v |= static_cast<uint64_t>(b_[at_ + static_cast<size_t>(i)]) << (8 * i);
		}
		at_ += static_cast<size_t>(n);
		return v;
	}
	const std::vector<uint8_t> &b_;
	size_t at_ = 0;
};

void write_coords(Writer &w, const std::vector<Coord> &cells) {
	w.count(cells.size());
	for (const Coord &c : cells) {
		w.coord(c);
	}
}

std::vector<Coord> read_coords(Reader &r) {
	const uint16_t n = r.u16();
	std::vector<Coord> out;
	for (uint16_t i = 0; i < n && r.ok; i++) {
		out.push_back(r.coord());
	}
	return out;
}

} // namespace

const char *poi_kind_name(PoiKind kind) {
	const size_t i = static_cast<size_t>(kind);
	return i < static_cast<size_t>(PoiKind::COUNT) ? KIND_NAMES[i] : "";
}

std::optional<PoiKind> poi_kind_from(const std::string &name) {
	for (size_t i = 0; i < static_cast<size_t>(PoiKind::COUNT); i++) {
		if (name == KIND_NAMES[i]) {
			return static_cast<PoiKind>(i);
		}
	}
	return std::nullopt;
}

int32_t PlannedSite::count_of(const std::string &item) const {
	for (const Holding &h : holds) {
		if (h.item == item) {
			return h.count;
		}
	}
	return 0;
}

void PlannedSite::add(const std::string &item, int32_t count) {
	for (Holding &h : holds) {
		if (h.item == item) {
			h.count += count;
			return;
		}
	}
	holds.push_back({item, count});
}

bool RunHeader::has_job(const std::string &job) const {
	return std::find(jobs.begin(), jobs.end(), job) != jobs.end();
}

std::vector<uint8_t> serialise_header(const RunHeader &h) {
	Writer w;
	for (uint8_t b : MAGIC) {
		w.u8(b);
	}
	w.u16(FORMAT);
	w.u64(h.seed);
	w.i32(h.list_kind);
	w.i32(h.cans);
	w.u8(h.solo ? 1 : 0);
	w.count(h.jobs.size());
	for (const std::string &j : h.jobs) {
		w.str(j);
	}
	w.count(h.draw.size());
	for (const std::string &d : h.draw) {
		w.str(d);
	}
	w.str(h.staging);
	w.str(h.hard_variant);
	w.u32(h.generator_version);
	w.u64(h.hash_version);
	w.str(h.template_version);
	w.str(h.data_version);
	const RunPlan &p = h.plan;
	w.str(p.error);
	w.count(p.sites.size());
	for (const PlannedSite &s : p.sites) {
		w.u8(static_cast<uint8_t>(s.kind));
		w.str(s.need);
		w.coord(s.door);
		w.u8(static_cast<uint8_t>(s.door_side));
		write_coords(w, s.cells);
		w.count(s.holds.size());
		for (const Holding &hold : s.holds) {
			w.str(hold.item);
			w.i32(hold.count);
		}
		w.u8(s.spine ? 1 : 0);
		w.i32(s.attempt);
	}
	w.count(p.spines.size());
	for (const Spine &s : p.spines) {
		w.i32(s.site);
		w.u8(static_cast<uint8_t>(s.gate));
		w.i32(s.replan);
		write_coords(w, s.cells);
	}
	w.u8(p.revolver ? 1 : 0);
	w.coord(p.revolver_cell);
	write_coords(w, p.box_cells);
	w.count(h.homes.size());
	for (const auto &[key, value] : h.homes) {
		w.str(key);
		w.bytes(value);
	}
	return w.out;
}

std::optional<RunHeader> parse_header(const std::vector<uint8_t> &bytes) {
	Reader r(bytes);
	for (uint8_t b : MAGIC) {
		if (r.u8() != b) {
			return std::nullopt;
		}
	}
	if (r.u16() != FORMAT) {
		return std::nullopt;
	}
	RunHeader h;
	h.seed = r.u64();
	h.list_kind = r.i32();
	h.cans = r.i32();
	h.solo = r.u8() != 0;
	const uint16_t jobs = r.u16();
	for (uint16_t i = 0; i < jobs && r.ok; i++) {
		h.jobs.push_back(r.str());
	}
	const uint16_t draws = r.u16();
	for (uint16_t i = 0; i < draws && r.ok; i++) {
		h.draw.push_back(r.str());
	}
	h.staging = r.str();
	h.hard_variant = r.str();
	h.generator_version = r.u32();
	h.hash_version = r.u64();
	h.template_version = r.str();
	h.data_version = r.str();
	RunPlan &p = h.plan;
	p.error = r.str();
	const uint16_t sites = r.u16();
	for (uint16_t i = 0; i < sites && r.ok; i++) {
		PlannedSite s;
		const uint8_t kind = r.u8();
		if (kind >= static_cast<uint8_t>(PoiKind::COUNT)) {
			return std::nullopt;
		}
		s.kind = static_cast<PoiKind>(kind);
		s.need = r.str();
		s.door = r.coord();
		const uint8_t side = r.u8();
		if (side >= static_cast<uint8_t>(Edge::COUNT)) {
			return std::nullopt;
		}
		s.door_side = static_cast<Edge>(side);
		s.cells = read_coords(r);
		const uint16_t holds = r.u16();
		for (uint16_t k = 0; k < holds && r.ok; k++) {
			Holding hold;
			hold.item = r.str();
			hold.count = r.i32();
			s.holds.push_back(hold);
		}
		s.spine = r.u8() != 0;
		s.attempt = r.i32();
		p.sites.push_back(s);
	}
	const uint16_t spines = r.u16();
	for (uint16_t i = 0; i < spines && r.ok; i++) {
		Spine s;
		s.site = r.i32();
		const uint8_t gate = r.u8();
		if (gate >= static_cast<uint8_t>(Edge::COUNT)) {
			return std::nullopt;
		}
		s.gate = static_cast<Edge>(gate);
		s.replan = r.i32();
		s.cells = read_coords(r);
		p.spines.push_back(s);
	}
	p.revolver = r.u8() != 0;
	p.revolver_cell = r.coord();
	p.box_cells = read_coords(r);
	const uint16_t homes = r.u16();
	for (uint16_t i = 0; i < homes && r.ok; i++) {
		std::string key = r.str();
		h.homes[key] = r.bytes();
	}
	if (!r.done()) {
		return std::nullopt;
	}
	return h;
}

uint64_t bytes_digest(const std::vector<uint8_t> &bytes) {
	uint64_t h = mix64(0xCBF29CE484222325ULL ^ static_cast<uint64_t>(bytes.size()));
	for (size_t i = 0; i < bytes.size(); i += 8) {
		uint64_t word = 0;
		for (size_t k = 0; k < 8 && i + k < bytes.size(); k++) {
			word |= static_cast<uint64_t>(bytes[i + k]) << (8 * k);
		}
		h = mix64(h ^ mix64(word + GOLDEN_GAMMA * (i / 8 + 1)));
	}
	return h;
}

uint64_t header_digest(const RunHeader &h) {
	return bytes_digest(serialise_header(h));
}

} // namespace lb::core::gen
