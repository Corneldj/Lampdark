// NET-04: byte packing, and the exact layout of a shape-token record.
#include "doctest.h"

#include "net_fixture.h"

#include "core/net/byte_io.h"

using namespace net_fixture;

TEST_CASE("little-endian writing and reading, signed and unsigned") {
	ByteWriter w;
	w.u8(250);
	w.u16(0xBEEF);
	w.u32(0xDEADBEEFu);
	w.i8(-3);
	w.i16(-1234);
	w.i32(-70000);
	const std::vector<uint8_t> &b = w.bytes();
	CHECK(b.size() == 14);
	CHECK(b[1] == 0xEF);
	CHECK(b[2] == 0xBE);
	ByteReader r(b.data(), b.size());
	CHECK(r.u8() == 250);
	CHECK(r.u16() == 0xBEEF);
	CHECK(r.u32() == 0xDEADBEEFu);
	CHECK(r.i8() == -3);
	CHECK(r.i16() == -1234);
	CHECK(r.i32() == -70000);
	CHECK(r.done());
	CHECK(r.ok());
	CHECK(r.u8() == 0);
	CHECK_FALSE(r.ok()); // an underrun is caught, never read past the end
}

namespace {

// The bytes of the single entity record in a frame that sends one entity and nothing else.
std::vector<uint8_t> entity_record(uint32_t entity, vision::SizeClass size, uint32_t slot) {
	ClientView server(77, slot);
	Desired d = desired_at(0.5, 0.5);
	add_token(d, entity, size, 4.25, 1.5);
	const std::vector<uint8_t> bytes = server.build(1, d, 0xFFFF, 0, roomy());
	// header 13, own 17 (VIS-08's flame byte), tile counts 2 + 2, geometry count 2, entity count 2:
	// the record follows.
	const size_t at = 13 + 17 + 2 + 2 + 2 + 2;
	return std::vector<uint8_t>(bytes.begin() + at, bytes.begin() + at + 8);
}

} // namespace

TEST_CASE("a shape token is a token, a size class and a position: nothing else") {
	const std::vector<uint8_t> heap = entity_record(12, vision::SizeClass::LARGE_MOTIONLESS, 3);
	const std::vector<uint8_t> moth = entity_record(99, vision::SizeClass::LARGE_MOTIONLESS, 3);
	REQUIRE(heap.size() == 8);
	CHECK(heap[2] == 1); // level: token
	CHECK(heap[3] == static_cast<uint8_t>(vision::SizeClass::LARGE_MOTIONLESS));
	CHECK(heap[4] == 0x10);
	CHECK(heap[5] == 0x01); // dx 4.25 tiles - own tile 0 = 272 / 64ths
	// A coat heap and the sleeping Moth: byte-identical apart from the token, a random value
	// drawn per client that says nothing of the entity behind it.
	CHECK(std::vector<uint8_t>(heap.begin() + 2, heap.end()) == std::vector<uint8_t>(moth.begin() + 2, moth.end()));
}
