#pragma once
// The native mirror of the tuning table (FND-05). GDScript's Tuning validates the data and
// pushes the effective values here after every load and swap; C++ never opens tuning files.
//
// Thread-safety: a TuningTable is immutable once built. The current table is published
// through set_current()/current() as a shared_ptr swapped atomically, so worker threads
// (GEN-11) can hold a consistent snapshot while the main thread publishes a new one.

#include <cstdint>
#include <map>
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <unordered_map>
#include <variant>
#include <vector>

namespace lb::core {

using TuningNumberTable = std::map<std::string, double>;
using TuningValue = std::variant<bool, int64_t, double, std::string, std::vector<int64_t>,
		std::vector<double>, std::vector<std::string>, TuningNumberTable>;

class TuningTable {
public:
	void set(std::string key, TuningValue value);

	bool has(std::string_view key) const;
	size_t size() const { return values_.size(); }
	const TuningValue *find(std::string_view key) const;

	// Typed reads. An unknown key or a wrong type gives std::nullopt, never a default.
	// get_f64 also accepts an integer value.
	std::optional<double> get_f64(std::string_view key) const;
	std::optional<int64_t> get_i64(std::string_view key) const;
	std::optional<bool> get_bool(std::string_view key) const;
	std::optional<std::string> get_string(std::string_view key) const;
	std::optional<std::vector<double>> get_f64_list(std::string_view key) const;
	std::optional<std::vector<int64_t>> get_i64_list(std::string_view key) const;
	std::optional<TuningNumberTable> get_table(std::string_view key) const;

	// A probability as an integer per million, round(p × 10^6), as GDScript's Tuning.ppm.
	std::optional<int64_t> get_ppm(std::string_view key) const;

	// The table every reader sees. Never null after the first set_current().
	static std::shared_ptr<const TuningTable> current();
	static void set_current(std::shared_ptr<const TuningTable> table);

private:
	std::unordered_map<std::string, TuningValue> values_;
};

} // namespace lb::core
