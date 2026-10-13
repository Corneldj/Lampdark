// Determinism digest (FND-06): 10 million mixed draws across every hash domain, written to
// stdout as little-endian bytes. tools/build/determinism_digest.sh hashes the stream with
// SHA-256; CI compares the digest between Windows and Linux (FND-04).

#include "core/generated/hash_domains.h"
#include "core/rng/rng.h"

#include <cstdio>
#include <cstdint>
#include <vector>

#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#endif

using namespace lb::core;

namespace {

std::vector<unsigned char> buffer;

void emit(uint64_t v) {
	for (int i = 0; i < 8; i++) {
		buffer.push_back(static_cast<unsigned char>(v >> (8 * i)));
	}
	if (buffer.size() >= (1 << 20)) {
		std::fwrite(buffer.data(), 1, buffer.size(), stdout);
		buffer.clear();
	}
}

} // namespace

int main() {
#ifdef _WIN32
	_setmode(_fileno(stdout), _O_BINARY); // no CR/LF translation of the byte stream
#endif
	constexpr uint64_t RUN_SEED = 0x4C414D50424C4143ULL; // "LAMPBLAC"
	constexpr int64_t DRAWS_PER_DOMAIN = 10000000 / static_cast<int64_t>(hash_domain::COUNT) + 1;
	const int64_t weights[6] = {0, 3, 1, 0, 7, 2};
	for (size_t d = 0; d < hash_domain::COUNT; d++) {
		const uint64_t domain = hash_domain::ALL[d].id;
		for (int64_t entity = 0; entity < 4; entity++) {
			const int64_t keys[2] = {entity, -entity * 7919};
			emit(hash_u64(RUN_SEED, domain, keys, 2));
			Rng rng(sub_seed(RUN_SEED, domain, keys, 2, 0));
			for (int64_t i = 0; i < DRAWS_PER_DOMAIN / 4; i++) {
				switch (i % 6) {
					case 0: emit(rng.next_u64()); break;
					case 1: emit(static_cast<uint64_t>(*rng.range(-1000, 1000))); break;
					case 2: emit(rng.chance_ppm(600000) ? 1 : 0); break;
					case 3: emit(*rng.pick_weighted(weights, 6)); break;
					case 4: emit(static_cast<uint64_t>(rng.unit_double() * 9007199254740992.0)); break;
					default: emit(static_cast<uint64_t>(*rng.range(INT64_MIN, INT64_MAX))); break;
				}
			}
		}
	}
	std::fwrite(buffer.data(), 1, buffer.size(), stdout);
	return 0;
}
