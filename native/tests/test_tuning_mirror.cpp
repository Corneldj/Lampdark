#include "core/tuning/tuning_table.h"

#include <doctest.h>

#include <thread>

using lb::core::TuningNumberTable;
using lb::core::TuningTable;

TEST_CASE("typed reads return the stored values") {
	TuningTable table;
	table.set("moth.windup_s", 1.0);
	table.set("moth.lamps", int64_t{3});
	table.set("moth.on", true);
	table.set("moth.kind", std::string("brightest"));
	table.set("depth.relax_s", std::vector<double>{60, 60, 45, 30, 30});
	table.set("moth.ints", std::vector<int64_t>{1, 2, 3});
	table.set("moth.weights", TuningNumberTable{{"brightest", 1.0}, {"widow", 2.0}});
	table.set("mine.edge_open_probability", 0.6);

	CHECK(table.get_f64("moth.windup_s").value() == 1.0);
	CHECK(table.get_i64("moth.lamps").value() == 3);
	CHECK(table.get_f64("moth.lamps").value() == 3.0);
	CHECK(table.get_bool("moth.on").value());
	CHECK(table.get_string("moth.kind").value() == "brightest");
	CHECK(table.get_f64_list("depth.relax_s").value()[2] == 45.0);
	CHECK(table.get_i64_list("moth.ints").value().size() == 3);
	CHECK(table.get_table("moth.weights").value().at("widow") == 2.0);
	CHECK(table.get_ppm("mine.edge_open_probability").value() == 600000);
}

TEST_CASE("unknown keys and wrong types are errors, never defaults") {
	TuningTable table;
	table.set("moth.windup_s", 1.0);
	CHECK_FALSE(table.get_f64("moth.no_such").has_value());
	CHECK_FALSE(table.get_i64("moth.windup_s").has_value());
	CHECK_FALSE(table.get_bool("moth.windup_s").has_value());
	CHECK_FALSE(table.has("moth.no_such"));
}

TEST_CASE("readers keep their snapshot while a new table is published") {
	auto first = std::make_shared<TuningTable>();
	first->set("moth.lamps", int64_t{3});
	TuningTable::set_current(first);

	std::shared_ptr<const TuningTable> held = TuningTable::current();
	auto second = std::make_shared<TuningTable>();
	second->set("moth.lamps", int64_t{9});
	std::thread publisher([&] { TuningTable::set_current(second); });
	publisher.join();

	CHECK(held->get_i64("moth.lamps").value() == 3);
	CHECK(TuningTable::current()->get_i64("moth.lamps").value() == 9);
}
