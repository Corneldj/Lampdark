// NET-04: per-client tokens: fresh on every re-entry, never shared between clients, never 0.
#include "doctest.h"

#include "net_fixture.h"

#include <set>

using namespace net_fixture;

namespace {

Desired with_entity(bool present) {
	Desired d = desired_at(0.5, 0.5);
	if (present) {
		add_token(d, 42, vision::SizeClass::MINER, 3.0, 0.5);
	}
	return d;
}

} // namespace

TEST_CASE("a token is never reused for an entity that left and came back") {
	ClientView server(99, 1);
	const ReplicationParams p = roomy();
	std::set<uint16_t> issued;
	uint32_t tick = 1;
	for (int round = 0; round < 50; round++) {
		server.build(tick++, with_entity(true), 0xFFFF, 0, p);
		const uint16_t t = server.token_of(42);
		CHECK(t != 0);
		CHECK(issued.count(t) == 0);
		issued.insert(t);
		server.build(tick++, with_entity(true), 0xFFFF, 0, p);
		CHECK(server.token_of(42) == t); // continuously present: the same token
		server.build(tick++, with_entity(false), 0xFFFF, 0, p);
		CHECK(server.token_of(42) == 0); // left: retired
	}
}

TEST_CASE("two clients never share a mapping") {
	ClientView a(5, 1), b(5, 2);
	const ReplicationParams p = roomy();
	int same = 0;
	for (uint32_t i = 0; i < 200; i++) {
		Desired d = desired_at(0.5, 0.5);
		add_token(d, 1000 + i, vision::SizeClass::LARGE, 2.0, 2.0);
		a.build(i + 1, d, 0xFFFF, 0, p);
		b.build(i + 1, d, 0xFFFF, 0, p);
		same += a.token_of(1000 + i) == b.token_of(1000 + i) ? 1 : 0;
	}
	CHECK(same <= 2); // independent 16-bit draws: a coincidence at most
}

TEST_CASE("tokens are ordered by token on the wire, never by kind") {
	ClientView server(11, 1);
	Client client;
	Desired d = desired_at(0.5, 0.5);
	for (uint32_t e = 1; e <= 20; e++) {
		add_token(d, e, e % 2 ? vision::SizeClass::MINER : vision::SizeClass::LARGE, 2.0 + e, 1.0);
	}
	REQUIRE(client.receive(server.build(1, d, 0xFFFF, 0, roomy())));
	uint16_t previous = 0;
	for (const auto &[token, v] : client.latest().entities) {
		CHECK(token > previous);
		previous = token;
	}
	CHECK(client.latest().entities.size() == 20);
}

TEST_CASE("a reset reissues every token and resyncs") {
	ClientView server(12, 1);
	const ReplicationParams p = roomy();
	server.build(1, with_entity(true), 0xFFFF, 0, p);
	const uint16_t before = server.token_of(42);
	server.reset();
	BuildStats st;
	server.build(2, with_entity(true), 0xFFFF, 0, p, &st);
	CHECK(st.full);
	CHECK(server.token_of(42) != before);
}
