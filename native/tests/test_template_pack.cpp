// GEN-04: the packed template binary (data/templates/packs/<set_version>.lbtp).

#include "template_fixture.h"

#include <doctest.h>

#include <chrono>

using namespace template_fixture;

namespace {

std::vector<Template> sample() {
	Template base = make(Spec{});
	base.weight = 2.5;
	base.author_version = 7;
	base.cells[0].anchors[0].tags = {"high"};
	Template poi = make(poi_spec());
	poi.footprint_w = 1;
	Template fallback = make(fallback_spec());
	return {base, poi, fallback};
}

void check_same(const Template &a, const Template &b) {
	CHECK(a.id == b.id);
	CHECK(a.kind == b.kind);
	CHECK(a.biome == b.biome);
	CHECK(a.poi_kind == b.poi_kind);
	CHECK(a.footprint_w == b.footprint_w);
	CHECK(a.footprint_h == b.footprint_h);
	CHECK(a.weight == b.weight);
	CHECK(a.author_version == b.author_version);
	REQUIRE(a.stubs.size() == b.stubs.size());
	for (size_t i = 0; i < a.stubs.size(); i++) {
		CHECK(a.stubs[i].cell == b.stubs[i].cell);
		CHECK(a.stubs[i].edge == b.stubs[i].edge);
		CHECK(a.stubs[i].offset == b.stubs[i].offset);
		CHECK(a.stubs[i].max_width == b.stubs[i].max_width);
		CHECK(a.stubs[i].depth == b.stubs[i].depth);
		CHECK(a.stubs[i].door == b.stubs[i].door);
	}
	REQUIRE(a.rib.size() == b.rib.size());
	REQUIRE(a.cells.size() == b.cells.size());
	for (size_t i = 0; i < a.cells.size(); i++) {
		CHECK(content_digest(a.cells[i]) == content_digest(b.cells[i]));
		REQUIRE(a.cells[i].collapses.size() == b.cells[i].collapses.size());
		for (size_t k = 0; k < a.cells[i].collapses.size(); k++) {
			CHECK(a.cells[i].collapses[k].zones.size() == b.cells[i].collapses[k].zones.size());
			CHECK(a.cells[i].collapses[k].fallen_road_graph == b.cells[i].collapses[k].fallen_road_graph);
		}
	}
}

} // namespace

TEST_CASE("GEN-04 a pack round-trips byte for byte") {
	const std::vector<Template> templates = sample();
	const std::vector<uint8_t> bytes = encode_pack("3f2a9c4e01d7b6a5", templates);
	REQUIRE(bytes.size() > 8);
	CHECK(bytes[0] == 'L');
	CHECK(bytes[3] == 'P');
	const std::optional<Pack> pack = decode_pack(bytes);
	REQUIRE(pack.has_value());
	CHECK(pack->set_version == "3f2a9c4e01d7b6a5");
	REQUIRE(pack->templates.size() == templates.size());
	for (size_t i = 0; i < templates.size(); i++) {
		check_same(templates[i], pack->templates[i]);
	}
	CHECK(encode_pack(pack->set_version, pack->templates) == bytes);
	CHECK(encode_pack("3f2a9c4e01d7b6a5", sample()) == bytes); // the same templates, the same bytes
	CHECK(validate(pack->templates[0], ValidateParams{}).empty());
}

TEST_CASE("GEN-04 a pack names its set version and refuses anything but a whole pack") {
	const std::vector<uint8_t> bytes = encode_pack("aaaa", sample());
	CHECK(decode_pack(encode_pack("bbbb", sample()))->set_version == "bbbb");
	CHECK(encode_pack("bbbb", sample()) != bytes);
	std::vector<uint8_t> magic = bytes;
	magic[0] = 'X';
	CHECK_FALSE(decode_pack(magic).has_value());
	std::vector<uint8_t> format = bytes;
	format[4] = static_cast<uint8_t>(PACK_FORMAT + 1);
	CHECK_FALSE(decode_pack(format).has_value());
	for (size_t cut : {size_t{0}, size_t{3}, size_t{9}, bytes.size() / 2, bytes.size() - 1}) {
		CHECK_FALSE(decode_pack(std::vector<uint8_t>(bytes.begin(), bytes.begin() + static_cast<std::ptrdiff_t>(cut))).has_value());
	}
	std::vector<uint8_t> trailing = bytes;
	trailing.push_back(0);
	CHECK_FALSE(decode_pack(trailing).has_value());
}

TEST_CASE("GEN-04 a pack of 140 templates loads in under 200 ms") {
	std::vector<Template> templates;
	const std::vector<Template> three = sample();
	for (int i = 0; i < 140; i++) {
		Template t = three[static_cast<size_t>(i % 3)];
		t.id += "_" + std::to_string(i);
		templates.push_back(t);
	}
	const std::vector<uint8_t> bytes = encode_pack("load", templates);
	const auto start = std::chrono::steady_clock::now();
	const std::optional<Pack> pack = decode_pack(bytes);
	const double ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start).count();
	REQUIRE(pack.has_value());
	CHECK(pack->templates.size() == 140);
	MESSAGE("140 templates (", bytes.size(), " bytes) decoded in ", ms, " ms");
	CHECK(ms < 200.0);
}
