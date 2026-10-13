#pragma once
// Little-endian byte writing and reading for NET-04's frames. The reader never reads past the
// end: an underrun sets ok() false and returns zeros, so a malformed frame decodes to nothing.

#include <cstddef>
#include <cstdint>
#include <vector>

namespace lb::core::net {

class ByteWriter {
public:
	void u8(uint32_t v) { bytes_.push_back(static_cast<uint8_t>(v)); }
	void u16(uint32_t v) {
		u8(v & 0xFFu);
		u8((v >> 8) & 0xFFu);
	}
	void u32(uint32_t v) {
		u16(v & 0xFFFFu);
		u16((v >> 16) & 0xFFFFu);
	}
	void i8(int32_t v) { u8(static_cast<uint32_t>(v) & 0xFFu); }
	void i16(int32_t v) { u16(static_cast<uint32_t>(v) & 0xFFFFu); }
	void i32(int32_t v) { u32(static_cast<uint32_t>(v)); }
	// Overwrites a u16 written earlier (a count filled in once known).
	void patch_u16(size_t at, uint32_t v) {
		bytes_[at] = static_cast<uint8_t>(v & 0xFFu);
		bytes_[at + 1] = static_cast<uint8_t>((v >> 8) & 0xFFu);
	}
	size_t size() const { return bytes_.size(); }
	const std::vector<uint8_t> &bytes() const { return bytes_; }
	std::vector<uint8_t> take() { return std::move(bytes_); }

private:
	std::vector<uint8_t> bytes_;
};

class ByteReader {
public:
	ByteReader(const uint8_t *data, size_t size) : data_(data), size_(size) {}
	uint32_t u8() {
		if (pos_ + 1 > size_) {
			ok_ = false;
			return 0;
		}
		return data_[pos_++];
	}
	uint32_t u16() {
		const uint32_t lo = u8();
		return lo | (u8() << 8);
	}
	uint32_t u32() {
		const uint32_t lo = u16();
		return lo | (u16() << 16);
	}
	int32_t i8() { return static_cast<int8_t>(static_cast<uint8_t>(u8())); }
	int32_t i16() { return static_cast<int16_t>(static_cast<uint16_t>(u16())); }
	int32_t i32() { return static_cast<int32_t>(u32()); }
	bool ok() const { return ok_; }
	bool done() const { return pos_ == size_; }

private:
	const uint8_t *data_;
	size_t size_;
	size_t pos_ = 0;
	bool ok_ = true;
};

} // namespace lb::core::net
