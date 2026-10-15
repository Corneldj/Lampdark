#include "core/world/diff_store.h"

namespace lb::core::world {

namespace {

// "LBDL", then the format's version.
constexpr uint8_t MAGIC[4] = {'L', 'B', 'D', 'L'};
constexpr uint16_t VERSION = 1;
constexpr size_t BITSET_BYTES = (DiffStore::CELL_AREA + 7) / 8;

void put_u8(std::vector<uint8_t> &out, uint8_t v) {
	out.push_back(v);
}

void put_le(std::vector<uint8_t> &out, uint64_t v, int bytes) {
	for (int i = 0; i < bytes; i++) {
		out.push_back(static_cast<uint8_t>(v >> (8 * i)));
	}
}

void put_bytes(std::vector<uint8_t> &out, const uint8_t *p, size_t n) {
	out.insert(out.end(), p, p + n);
}

class Reader {
public:
	explicit Reader(const std::vector<uint8_t> &b) : bytes_(b) {}

	bool le(uint64_t &v, int n) {
		if (pos_ + n > bytes_.size()) {
			return false;
		}
		v = 0;
		for (int i = 0; i < n; i++) {
			v |= static_cast<uint64_t>(bytes_[pos_ + i]) << (8 * i);
		}
		pos_ += n;
		return true;
	}

	bool take(std::vector<uint8_t> &out, size_t n) {
		if (pos_ + n > bytes_.size()) {
			return false;
		}
		out.assign(bytes_.begin() + pos_, bytes_.begin() + pos_ + n);
		pos_ += n;
		return true;
	}

	bool text(std::string &out, size_t n) {
		if (pos_ + n > bytes_.size()) {
			return false;
		}
		out.assign(reinterpret_cast<const char *>(bytes_.data() + pos_), n);
		pos_ += n;
		return true;
	}

	bool done() const { return pos_ == bytes_.size(); }

private:
	const std::vector<uint8_t> &bytes_;
	size_t pos_ = 0;
};

size_t local_index(Coord tile) {
	const Coord l = local_of(tile);
	return static_cast<size_t>(l.y * CELL_TILES + l.x);
}

} // namespace

void DiffStore::put(Coord cell, uint8_t kind, const std::string &key, int64_t tick, std::vector<uint8_t> payload) {
	cells_[cell].records[DiffAddress{kind, key}] = DiffRecord{tick, std::move(payload)};
}

bool DiffStore::erase(Coord cell, uint8_t kind, const std::string &key) {
	auto it = cells_.find(cell);
	if (it == cells_.end() || it->second.records.erase(DiffAddress{kind, key}) == 0) {
		return false;
	}
	prune(cell);
	return true;
}

std::optional<DiffRecord> DiffStore::get(Coord cell, uint8_t kind, const std::string &key) const {
	auto it = cells_.find(cell);
	if (it == cells_.end()) {
		return std::nullopt;
	}
	auto r = it->second.records.find(DiffAddress{kind, key});
	if (r == it->second.records.end()) {
		return std::nullopt;
	}
	return r->second;
}

std::vector<std::pair<DiffAddress, DiffRecord>> DiffStore::records(Coord cell) const {
	std::vector<std::pair<DiffAddress, DiffRecord>> out;
	auto it = cells_.find(cell);
	if (it != cells_.end()) {
		out.assign(it->second.records.begin(), it->second.records.end());
	}
	return out;
}

std::vector<Coord> DiffStore::cells() const {
	std::vector<Coord> out;
	out.reserve(cells_.size());
	for (const auto &[c, _] : cells_) {
		out.push_back(c);
	}
	return out;
}

size_t DiffStore::record_count() const {
	size_t n = 0;
	for (const auto &[_, c] : cells_) {
		n += c.records.size();
	}
	return n;
}

void DiffStore::mark_blood(Coord tile, int64_t direction) {
	Cell &c = cells_[cell_of(tile)];
	uint8_t &slot = c.blood[local_index(tile)];
	if (slot == NO_BLOOD) {
		c.smeared++;
	}
	slot = static_cast<uint8_t>(floor_mod(direction, 8) + 1);
}

bool DiffStore::erase_blood(Coord tile) {
	const Coord cell = cell_of(tile);
	auto it = cells_.find(cell);
	if (it == cells_.end()) {
		return false;
	}
	uint8_t &slot = it->second.blood[local_index(tile)];
	if (slot == NO_BLOOD) {
		return false;
	}
	slot = NO_BLOOD;
	it->second.smeared--;
	prune(cell);
	return true;
}

int64_t DiffStore::blood_at(Coord tile) const {
	auto it = cells_.find(cell_of(tile));
	if (it == cells_.end()) {
		return -1;
	}
	const uint8_t slot = it->second.blood[local_index(tile)];
	return slot == NO_BLOOD ? -1 : slot - 1;
}

std::vector<std::pair<Coord, int64_t>> DiffStore::blood(Coord cell) const {
	std::vector<std::pair<Coord, int64_t>> out;
	auto it = cells_.find(cell);
	if (it == cells_.end()) {
		return out;
	}
	for (int64_t i = 0; i < CELL_AREA; i++) {
		const uint8_t slot = it->second.blood[static_cast<size_t>(i)];
		if (slot != NO_BLOOD) {
			out.emplace_back(tile_of(cell, Coord{i % CELL_TILES, i / CELL_TILES}), slot - 1);
		}
	}
	return out;
}

size_t DiffStore::blood_count() const {
	size_t n = 0;
	for (const auto &[_, c] : cells_) {
		n += c.smeared;
	}
	return n;
}

void DiffStore::section_put(const std::string &section, const std::string &key, std::vector<uint8_t> payload) {
	sections_[section][key] = std::move(payload);
}

bool DiffStore::section_erase(const std::string &section, const std::string &key) {
	auto it = sections_.find(section);
	if (it == sections_.end() || it->second.erase(key) == 0) {
		return false;
	}
	if (it->second.empty()) {
		sections_.erase(it);
	}
	return true;
}

std::optional<std::vector<uint8_t>> DiffStore::section_get(const std::string &section, const std::string &key) const {
	auto it = sections_.find(section);
	if (it == sections_.end()) {
		return std::nullopt;
	}
	auto e = it->second.find(key);
	if (e == it->second.end()) {
		return std::nullopt;
	}
	return e->second;
}

std::vector<std::string> DiffStore::section_keys(const std::string &section) const {
	std::vector<std::string> out;
	auto it = sections_.find(section);
	if (it != sections_.end()) {
		for (const auto &[k, _] : it->second) {
			out.push_back(k);
		}
	}
	return out;
}

std::vector<std::string> DiffStore::sections() const {
	std::vector<std::string> out;
	for (const auto &[name, _] : sections_) {
		out.push_back(name);
	}
	return out;
}

size_t DiffStore::cell_bytes(const Cell &c) {
	size_t n = 4 + 4 + 4; // cx, cy, record count
	for (const auto &[a, r] : c.records) {
		n += 1 + 2 + a.key.size() + 8 + 4 + r.payload.size();
	}
	n += 2; // smeared count
	if (c.smeared > 0) {
		n += BITSET_BYTES + (c.smeared + 1) / 2;
	}
	return n;
}

size_t DiffStore::cells_bytes() const {
	size_t n = 4;
	for (const auto &[_, c] : cells_) {
		n += cell_bytes(c);
	}
	return n;
}

size_t DiffStore::section_bytes(const std::string &section) const {
	auto it = sections_.find(section);
	if (it == sections_.end()) {
		return 0;
	}
	size_t n = 2 + section.size() + 4;
	for (const auto &[k, p] : it->second) {
		n += 2 + k.size() + 4 + p.size();
	}
	return n;
}

std::vector<uint8_t> DiffStore::serialise() const {
	std::vector<uint8_t> out;
	put_bytes(out, MAGIC, 4);
	put_le(out, VERSION, 2);
	put_le(out, cells_.size(), 4);
	for (const auto &[cell, c] : cells_) {
		put_le(out, static_cast<uint32_t>(static_cast<int32_t>(cell.x)), 4);
		put_le(out, static_cast<uint32_t>(static_cast<int32_t>(cell.y)), 4);
		put_le(out, c.records.size(), 4);
		for (const auto &[a, r] : c.records) {
			put_u8(out, a.kind);
			put_le(out, a.key.size(), 2);
			put_bytes(out, reinterpret_cast<const uint8_t *>(a.key.data()), a.key.size());
			put_le(out, static_cast<uint64_t>(r.tick), 8);
			put_le(out, r.payload.size(), 4);
			put_bytes(out, r.payload.data(), r.payload.size());
		}
		put_le(out, c.smeared, 2);
		if (c.smeared == 0) {
			continue;
		}
		// Which tiles are smeared, then one direction nibble per smeared tile in tile order.
		std::array<uint8_t, BITSET_BYTES> bits{};
		std::vector<uint8_t> nibbles((c.smeared + 1) / 2, 0);
		size_t n = 0;
		for (size_t i = 0; i < static_cast<size_t>(CELL_AREA); i++) {
			if (c.blood[i] == NO_BLOOD) {
				continue;
			}
			bits[i / 8] |= static_cast<uint8_t>(1u << (i % 8));
			nibbles[n / 2] |= static_cast<uint8_t>((c.blood[i] - 1) << ((n % 2) * 4));
			n++;
		}
		put_bytes(out, bits.data(), bits.size());
		put_bytes(out, nibbles.data(), nibbles.size());
	}
	put_le(out, sections_.size(), 4);
	for (const auto &[name, entries] : sections_) {
		put_le(out, name.size(), 2);
		put_bytes(out, reinterpret_cast<const uint8_t *>(name.data()), name.size());
		put_le(out, entries.size(), 4);
		for (const auto &[k, p] : entries) {
			put_le(out, k.size(), 2);
			put_bytes(out, reinterpret_cast<const uint8_t *>(k.data()), k.size());
			put_le(out, p.size(), 4);
			put_bytes(out, p.data(), p.size());
		}
	}
	return out;
}

bool DiffStore::deserialise(const std::vector<uint8_t> &bytes) {
	clear();
	Reader r(bytes);
	std::vector<uint8_t> magic;
	uint64_t v = 0;
	if (!r.take(magic, 4) || magic != std::vector<uint8_t>(MAGIC, MAGIC + 4) || !r.le(v, 2) || v != VERSION) {
		return false;
	}
	uint64_t ncells = 0;
	bool ok = r.le(ncells, 4);
	for (uint64_t i = 0; ok && i < ncells; i++) {
		uint64_t cx = 0, cy = 0, nrec = 0;
		ok = r.le(cx, 4) && r.le(cy, 4) && r.le(nrec, 4);
		const Coord cell{static_cast<int32_t>(static_cast<uint32_t>(cx)), static_cast<int32_t>(static_cast<uint32_t>(cy))};
		Cell &c = cells_[cell];
		for (uint64_t j = 0; ok && j < nrec; j++) {
			uint64_t kind = 0, klen = 0, tick = 0, plen = 0;
			DiffAddress a;
			DiffRecord rec;
			ok = r.le(kind, 1) && r.le(klen, 2) && r.text(a.key, klen) && r.le(tick, 8) && r.le(plen, 4) && r.take(rec.payload, plen);
			a.kind = static_cast<uint8_t>(kind);
			rec.tick = static_cast<int64_t>(tick);
			c.records[a] = std::move(rec);
		}
		uint64_t smeared = 0;
		ok = ok && r.le(smeared, 2) && smeared <= static_cast<uint64_t>(CELL_AREA);
		if (ok && smeared > 0) {
			std::vector<uint8_t> bits, nibbles;
			ok = r.take(bits, BITSET_BYTES) && r.take(nibbles, (smeared + 1) / 2);
			size_t n = 0;
			for (size_t t = 0; ok && t < static_cast<size_t>(CELL_AREA); t++) {
				if ((bits[t / 8] >> (t % 8)) & 1u) {
					ok = n < smeared;
					if (ok) {
						c.blood[t] = static_cast<uint8_t>(((nibbles[n / 2] >> ((n % 2) * 4)) & 0x7u) + 1);
						n++;
					}
				}
			}
			ok = ok && n == smeared;
			c.smeared = static_cast<uint32_t>(n);
		}
		if (ok && c.empty()) {
			cells_.erase(cell);
		}
	}
	uint64_t nsections = 0;
	ok = ok && r.le(nsections, 4);
	for (uint64_t i = 0; ok && i < nsections; i++) {
		uint64_t nlen = 0, n = 0;
		std::string name;
		ok = r.le(nlen, 2) && r.text(name, nlen) && r.le(n, 4);
		for (uint64_t j = 0; ok && j < n; j++) {
			uint64_t klen = 0, plen = 0;
			std::string k;
			std::vector<uint8_t> p;
			ok = r.le(klen, 2) && r.text(k, klen) && r.le(plen, 4) && r.take(p, plen);
			if (ok) {
				sections_[name][k] = std::move(p);
			}
		}
	}
	if (!ok || !r.done()) {
		clear();
		return false;
	}
	return true;
}

uint64_t DiffStore::digest() const {
	uint64_t h = 1469598103934665603ULL;
	for (uint8_t b : serialise()) {
		h ^= b;
		h *= 1099511628211ULL;
	}
	return h;
}

void DiffStore::clear() {
	cells_.clear();
	sections_.clear();
}

bool DiffStore::operator==(const DiffStore &o) const {
	return serialise() == o.serialise();
}

void DiffStore::prune(Coord cell) {
	auto it = cells_.find(cell);
	if (it != cells_.end() && it->second.empty()) {
		cells_.erase(it);
	}
}

} // namespace lb::core::world
