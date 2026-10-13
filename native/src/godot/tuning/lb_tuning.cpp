#include "godot/tuning/lb_tuning.h"

#include "core/tuning/tuning_table.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;
using lb::core::TuningNumberTable;
using lb::core::TuningTable;
using lb::core::TuningValue;

namespace lb::godot {

namespace {

std::string to_std(const String &s) {
	CharString utf8 = s.utf8();
	return std::string(utf8.get_data(), static_cast<size_t>(utf8.length()));
}

bool all_of_type(const Array &array, Variant::Type type) {
	for (int64_t i = 0; i < array.size(); i++) {
		if (array[i].get_type() != type) {
			return false;
		}
	}
	return true;
}

// Converts one tuning value. Lists keep their element type: ints, floats or strings.
bool convert(const Variant &in, TuningValue &out) {
	switch (in.get_type()) {
		case Variant::BOOL:
			out = static_cast<bool>(in);
			return true;
		case Variant::INT:
			out = static_cast<int64_t>(in);
			return true;
		case Variant::FLOAT:
			out = static_cast<double>(in);
			return true;
		case Variant::STRING:
		case Variant::STRING_NAME:
			out = to_std(in);
			return true;
		case Variant::ARRAY: {
			Array array = in;
			if (all_of_type(array, Variant::INT) && array.size() > 0) {
				std::vector<int64_t> ints;
				for (int64_t i = 0; i < array.size(); i++) {
					ints.push_back(static_cast<int64_t>(array[i]));
				}
				out = std::move(ints);
				return true;
			}
			if (all_of_type(array, Variant::STRING) && array.size() > 0) {
				std::vector<std::string> strings;
				for (int64_t i = 0; i < array.size(); i++) {
					strings.push_back(to_std(array[i]));
				}
				out = std::move(strings);
				return true;
			}
			std::vector<double> floats;
			for (int64_t i = 0; i < array.size(); i++) {
				Variant::Type t = array[i].get_type();
				if (t != Variant::FLOAT && t != Variant::INT) {
					return false;
				}
				floats.push_back(static_cast<double>(array[i]));
			}
			out = std::move(floats);
			return true;
		}
		case Variant::DICTIONARY: {
			Dictionary dict = in;
			TuningNumberTable table;
			Array keys = dict.keys();
			for (int64_t i = 0; i < keys.size(); i++) {
				Variant v = dict[keys[i]];
				if (v.get_type() != Variant::FLOAT && v.get_type() != Variant::INT) {
					return false;
				}
				table[to_std(keys[i])] = static_cast<double>(v);
			}
			out = std::move(table);
			return true;
		}
		default:
			return false;
	}
}

struct ToVariant {
	Variant operator()(bool v) const { return v; }
	Variant operator()(int64_t v) const { return v; }
	Variant operator()(double v) const { return v; }
	Variant operator()(const std::string &v) const { return String::utf8(v.c_str()); }
	Variant operator()(const std::vector<int64_t> &v) const {
		Array a;
		for (int64_t x : v) {
			a.push_back(x);
		}
		return a;
	}
	Variant operator()(const std::vector<double> &v) const {
		Array a;
		for (double x : v) {
			a.push_back(x);
		}
		return a;
	}
	Variant operator()(const std::vector<std::string> &v) const {
		Array a;
		for (const std::string &x : v) {
			a.push_back(String::utf8(x.c_str()));
		}
		return a;
	}
	Variant operator()(const TuningNumberTable &v) const {
		Dictionary d;
		for (const auto &[name, number] : v) {
			d[String::utf8(name.c_str())] = number;
		}
		return d;
	}
};

} // namespace

void LbTuning::_bind_methods() {
	ClassDB::bind_static_method("LbTuning", D_METHOD("set_values", "values"), &LbTuning::set_values);
	ClassDB::bind_static_method("LbTuning", D_METHOD("get_value", "key"), &LbTuning::get_value);
	ClassDB::bind_static_method("LbTuning", D_METHOD("count"), &LbTuning::count);
	ClassDB::bind_static_method("LbTuning", D_METHOD("ppm", "key"), &LbTuning::ppm);
}

bool LbTuning::set_values(const Dictionary &values) {
	auto table = std::make_shared<TuningTable>();
	Array keys = values.keys();
	for (int64_t i = 0; i < keys.size(); i++) {
		TuningValue value;
		if (!convert(values[keys[i]], value)) {
			UtilityFunctions::push_error("LbTuning: cannot mirror the value of ", keys[i]);
			return false;
		}
		table->set(to_std(keys[i]), std::move(value));
	}
	TuningTable::set_current(std::move(table));
	return true;
}

Variant LbTuning::get_value(const String &key) {
	std::shared_ptr<const TuningTable> table = TuningTable::current();
	const TuningValue *value = table->find(to_std(key));
	if (value == nullptr) {
		return Variant();
	}
	return std::visit(ToVariant{}, *value);
}

int64_t LbTuning::count() {
	return static_cast<int64_t>(TuningTable::current()->size());
}

int64_t LbTuning::ppm(const String &key) {
	return TuningTable::current()->get_ppm(to_std(key)).value_or(-1);
}

} // namespace lb::godot
