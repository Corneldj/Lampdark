#include "core/light/falloff.h"

#include <doctest.h>

using namespace lb::core::light;

TEST_CASE("falloff for R = 4: 1.0 at 0, 0.30 at 2.4, 0.12 at 4.0, 0 beyond") {
	const LightParams p;
	CHECK(falloff(0.0, 4.0, 1.0, p) == doctest::Approx(1.0).epsilon(0.001));
	CHECK(falloff(2.4, 4.0, 1.0, p) == doctest::Approx(0.30).epsilon(0.001));
	CHECK(falloff(4.0, 4.0, 1.0, p) == doctest::Approx(0.12).epsilon(0.001));
	CHECK(falloff(4.0001, 4.0, 1.0, p) == 0.0);
	CHECK(falloff_milli(2.4, 4.0, 1.0, p) == 300);
	CHECK(falloff_milli(4.0, 4.0, 1.0, p) == 120);
}

TEST_CASE("the 0.60 reach is 0.86, 1.37 and 1.89 tiles by wick, and 4.80 for a flare") {
	const LightParams p;
	CHECK(reach_of(0.6, 2.5, 1.0, p) == doctest::Approx(0.86).epsilon(0.01));
	CHECK(reach_of(0.6, 4.0, 1.0, p) == doctest::Approx(1.37).epsilon(0.01));
	CHECK(reach_of(0.6, 5.5, 1.0, p) == doctest::Approx(1.89).epsilon(0.01));
	CHECK(reach_of(0.6, 14.0, 1.0, p) == doctest::Approx(4.80).epsilon(0.01));
	CHECK(falloff(reach_of(0.6, 4.0, 1.0, p), 4.0, 1.0, p) == doctest::Approx(0.6));
}

TEST_CASE("a wick-down lamp gives 0.21 at 2 tiles, so two give about 0.42") {
	const LightParams p;
	CHECK(falloff(2.0, 2.5, 1.0, p) == doctest::Approx(0.21).epsilon(0.001));
	CHECK(2 * falloff_milli(2.0, 2.5, 1.0, p) == 420);
}

TEST_CASE("guttering (radius x0.7): a wick-up core of 2.31, a normal lamp's 0.50 at 1.2") {
	const LightParams p;
	CHECK(p.core_fraction * 5.5 * 0.7 == doctest::Approx(2.31));
	CHECK(reach_of(0.5, 4.0 * 0.7, 1.0, p) == doctest::Approx(1.2).epsilon(0.005));
}

TEST_CASE("a belt-hook lamp (radius 2.5) gives 0.30 to 1.5 tiles") {
	const LightParams p;
	CHECK(reach_of(0.30, 2.5, 1.0, p) == doctest::Approx(1.5));
}

TEST_CASE("a peak at or below the core value falls linearly to the edge (egg-glow)") {
	const LightParams p;
	CHECK(falloff(0.0, 1.5, 0.2, p) == doctest::Approx(0.2));
	CHECK(falloff(0.75, 1.5, 0.2, p) == doctest::Approx(0.16));
	CHECK(falloff(1.5, 1.5, 0.2, p) == doctest::Approx(0.12));
}
