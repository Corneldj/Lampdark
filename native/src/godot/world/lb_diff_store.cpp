#include "godot/world/lb_diff_store.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>

using namespace godot;
namespace world = lb::core::world;

namespace lb::godot {

namespace {

world::Coord to_coord(Vector2i v) {
	return {v.x, v.y};
}

Vector2i to_vec(world::Coord c) {
	return Vector2i(static_cast<int32_t>(c.x), static_cast<int32_t>(c.y));
}

std::string utf8(const String &s) {
	const CharString c = s.utf8();
	return std::string(c.get_data(), static_cast<size_t>(c.length()));
}

String from_utf8(const std::string &s) {
	return String::utf8(s.data(), static_cast<int64_t>(s.size()));
}

std::vector<uint8_t> to_bytes(const PackedByteArray &b) {
	return std::vector<uint8_t>(b.ptr(), b.ptr() + b.size());
}

PackedByteArray from_bytes(const std::vector<uint8_t> &b) {
	PackedByteArray out;
	out.resize(static_cast<int64_t>(b.size()));
	if (!b.empty()) {
		std::copy(b.begin(), b.end(), out.ptrw());
	}
	return out;
}

Variant canonical(const Variant &v) {
	if (v.get_type() == Variant::DICTIONARY) {
		const Dictionary d = v;
		const Array keys = d.keys();
		std::vector<std::pair<String, Variant>> sorted;
		sorted.reserve(static_cast<size_t>(keys.size()));
		for (int64_t i = 0; i < keys.size(); i++) {
			sorted.emplace_back(String(keys[i]), keys[i]);
		}
		std::stable_sort(sorted.begin(), sorted.end(), [](const auto &a, const auto &b) { return a.first < b.first; });
		Dictionary out;
		for (const auto &[_, k] : sorted) {
			out[k] = canonical(d[k]);
		}
		return out;
	}
	if (v.get_type() == Variant::ARRAY) {
		const Array a = v;
		Array out;
		out.resize(a.size());
		for (int64_t i = 0; i < a.size(); i++) {
			out[i] = canonical(a[i]);
		}
		return out;
	}
	return v;
}

} // namespace

void LbDiffStore::_bind_methods() {
	ClassDB::bind_static_method("LbDiffStore", D_METHOD("encode", "payload"), &LbDiffStore::encode);
	ClassDB::bind_method(D_METHOD("put", "cell", "kind", "key", "tick", "payload"), &LbDiffStore::put);
	ClassDB::bind_method(D_METHOD("erase", "cell", "kind", "key"), &LbDiffStore::erase);
	ClassDB::bind_method(D_METHOD("get_record", "cell", "kind", "key"), &LbDiffStore::get_record);
	ClassDB::bind_method(D_METHOD("records", "cell"), &LbDiffStore::records);
	ClassDB::bind_method(D_METHOD("decoded_records", "cell", "blood_kind"), &LbDiffStore::decoded_records);
	ClassDB::bind_method(D_METHOD("cells"), &LbDiffStore::cells);
	ClassDB::bind_method(D_METHOD("record_count"), &LbDiffStore::record_count);
	ClassDB::bind_method(D_METHOD("mark_blood", "tile", "direction"), &LbDiffStore::mark_blood);
	ClassDB::bind_method(D_METHOD("erase_blood", "tile"), &LbDiffStore::erase_blood);
	ClassDB::bind_method(D_METHOD("blood_at", "tile"), &LbDiffStore::blood_at);
	ClassDB::bind_method(D_METHOD("blood", "cell"), &LbDiffStore::blood);
	ClassDB::bind_method(D_METHOD("blood_count"), &LbDiffStore::blood_count);
	ClassDB::bind_method(D_METHOD("section_put", "section", "key", "payload"), &LbDiffStore::section_put);
	ClassDB::bind_method(D_METHOD("section_erase", "section", "key"), &LbDiffStore::section_erase);
	ClassDB::bind_method(D_METHOD("section_has", "section", "key"), &LbDiffStore::section_has);
	ClassDB::bind_method(D_METHOD("section_get", "section", "key"), &LbDiffStore::section_get);
	ClassDB::bind_method(D_METHOD("section_keys", "section"), &LbDiffStore::section_keys);
	ClassDB::bind_method(D_METHOD("sections"), &LbDiffStore::sections);
	ClassDB::bind_method(D_METHOD("cells_bytes"), &LbDiffStore::cells_bytes);
	ClassDB::bind_method(D_METHOD("section_bytes", "section"), &LbDiffStore::section_bytes);
	ClassDB::bind_method(D_METHOD("serialise"), &LbDiffStore::serialise);
	ClassDB::bind_method(D_METHOD("deserialise", "bytes"), &LbDiffStore::deserialise);
	ClassDB::bind_method(D_METHOD("digest"), &LbDiffStore::digest);
	ClassDB::bind_method(D_METHOD("clear"), &LbDiffStore::clear);
}

void LbDiffStore::put(Vector2i cell, int64_t kind, const String &key, int64_t tick, const PackedByteArray &payload) {
	ERR_FAIL_COND_MSG(kind < 0 || kind > 255, "LbDiffStore: a kind is 0-255");
	store_.put(to_coord(cell), static_cast<uint8_t>(kind), utf8(key), tick, to_bytes(payload));
}

bool LbDiffStore::erase(Vector2i cell, int64_t kind, const String &key) {
	return kind >= 0 && kind <= 255 && store_.erase(to_coord(cell), static_cast<uint8_t>(kind), utf8(key));
}

Dictionary LbDiffStore::get_record(Vector2i cell, int64_t kind, const String &key) const {
	Dictionary out;
	if (kind < 0 || kind > 255) {
		return out;
	}
	const std::optional<world::DiffRecord> r = store_.get(to_coord(cell), static_cast<uint8_t>(kind), utf8(key));
	if (r) {
		out["tick"] = r->tick;
		out["payload"] = from_bytes(r->payload);
	}
	return out;
}

Array LbDiffStore::records(Vector2i cell) const {
	Array out;
	for (const auto &[a, r] : store_.records(to_coord(cell))) {
		Dictionary d;
		d["kind"] = static_cast<int64_t>(a.kind);
		d["key"] = from_utf8(a.key);
		d["tick"] = r.tick;
		d["payload"] = from_bytes(r.payload);
		out.push_back(d);
	}
	return out;
}

Array LbDiffStore::decoded_records(Vector2i cell, int64_t blood_kind) const {
	Array out;
	const world::Coord c = to_coord(cell);
	const Array smears = blood(cell);
	bool blood_done = smears.is_empty();
	auto add_blood = [&]() {
		Dictionary payload;
		payload["smears"] = smears;
		Dictionary row;
		row["kind"] = blood_kind;
		row["key"] = String("blood");
		row["tick"] = static_cast<int64_t>(-1);
		row["payload"] = payload;
		out.push_back(row);
		blood_done = true;
	};
	for (const auto &[a, r] : store_.records(c)) {
		if (!blood_done && static_cast<int64_t>(a.kind) > blood_kind) {
			add_blood();
		}
		Dictionary d;
		d["kind"] = static_cast<int64_t>(a.kind);
		d["key"] = from_utf8(a.key);
		d["tick"] = r.tick;
		d["payload"] = r.payload.empty() ? Variant(Dictionary()) : UtilityFunctions::bytes_to_var(from_bytes(r.payload));
		out.push_back(d);
	}
	if (!blood_done) {
		add_blood();
	}
	return out;
}

Array LbDiffStore::cells() const {
	Array out;
	for (const world::Coord &c : store_.cells()) {
		out.push_back(to_vec(c));
	}
	return out;
}

int64_t LbDiffStore::record_count() const {
	return static_cast<int64_t>(store_.record_count());
}

void LbDiffStore::mark_blood(Vector2i tile, int64_t direction) {
	store_.mark_blood(to_coord(tile), direction);
}

bool LbDiffStore::erase_blood(Vector2i tile) {
	return store_.erase_blood(to_coord(tile));
}

int64_t LbDiffStore::blood_at(Vector2i tile) const {
	return store_.blood_at(to_coord(tile));
}

Array LbDiffStore::blood(Vector2i cell) const {
	Array out;
	for (const auto &[t, dir] : store_.blood(to_coord(cell))) {
		Dictionary d;
		d["tile"] = to_vec(t);
		d["direction"] = dir;
		out.push_back(d);
	}
	return out;
}

int64_t LbDiffStore::blood_count() const {
	return static_cast<int64_t>(store_.blood_count());
}

void LbDiffStore::section_put(const String &section, const String &key, const PackedByteArray &payload) {
	store_.section_put(utf8(section), utf8(key), to_bytes(payload));
}

bool LbDiffStore::section_erase(const String &section, const String &key) {
	return store_.section_erase(utf8(section), utf8(key));
}

bool LbDiffStore::section_has(const String &section, const String &key) const {
	return store_.section_get(utf8(section), utf8(key)).has_value();
}

PackedByteArray LbDiffStore::section_get(const String &section, const String &key) const {
	const std::optional<std::vector<uint8_t>> p = store_.section_get(utf8(section), utf8(key));
	return p ? from_bytes(*p) : PackedByteArray();
}

PackedStringArray LbDiffStore::section_keys(const String &section) const {
	PackedStringArray out;
	for (const std::string &k : store_.section_keys(utf8(section))) {
		out.push_back(from_utf8(k));
	}
	return out;
}

PackedStringArray LbDiffStore::sections() const {
	PackedStringArray out;
	for (const std::string &s : store_.sections()) {
		out.push_back(from_utf8(s));
	}
	return out;
}

int64_t LbDiffStore::cells_bytes() const {
	return static_cast<int64_t>(store_.cells_bytes());
}

int64_t LbDiffStore::section_bytes(const String &section) const {
	return static_cast<int64_t>(store_.section_bytes(utf8(section)));
}

PackedByteArray LbDiffStore::serialise() const {
	return from_bytes(store_.serialise());
}

bool LbDiffStore::deserialise(const PackedByteArray &bytes) {
	return store_.deserialise(to_bytes(bytes));
}

PackedByteArray LbDiffStore::encode(const Variant &payload) {
	return UtilityFunctions::var_to_bytes(canonical(payload));
}

int64_t LbDiffStore::digest() const {
	return static_cast<int64_t>(store_.digest());
}

void LbDiffStore::clear() {
	store_.clear();
}

} // namespace lb::godot
