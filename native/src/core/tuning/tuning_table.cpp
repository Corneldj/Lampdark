#include "core/tuning/tuning_table.h"

#include <atomic>
#include <cmath>

namespace lb::core {

namespace {

std::shared_ptr<const TuningTable> &current_slot() {
	static std::shared_ptr<const TuningTable> slot = std::make_shared<const TuningTable>();
	return slot;
}

template <typename T>
std::optional<T> get_as(const TuningTable &table, std::string_view key) {
	const TuningValue *value = table.find(key);
	if (value == nullptr) {
		return std::nullopt;
	}
	if (const T *typed = std::get_if<T>(value)) {
		return *typed;
	}
	return std::nullopt;
}

} // namespace

void TuningTable::set(std::string key, TuningValue value) {
	values_.insert_or_assign(std::move(key), std::move(value));
}

bool TuningTable::has(std::string_view key) const {
	return values_.find(std::string(key)) != values_.end();
}

const TuningValue *TuningTable::find(std::string_view key) const {
	auto it = values_.find(std::string(key));
	return it == values_.end() ? nullptr : &it->second;
}

std::optional<double> TuningTable::get_f64(std::string_view key) const {
	const TuningValue *value = find(key);
	if (value == nullptr) {
		return std::nullopt;
	}
	if (const double *d = std::get_if<double>(value)) {
		return *d;
	}
	if (const int64_t *i = std::get_if<int64_t>(value)) {
		return static_cast<double>(*i);
	}
	return std::nullopt;
}

std::optional<int64_t> TuningTable::get_i64(std::string_view key) const {
	return get_as<int64_t>(*this, key);
}

std::optional<bool> TuningTable::get_bool(std::string_view key) const {
	return get_as<bool>(*this, key);
}

std::optional<std::string> TuningTable::get_string(std::string_view key) const {
	return get_as<std::string>(*this, key);
}

std::optional<std::vector<double>> TuningTable::get_f64_list(std::string_view key) const {
	return get_as<std::vector<double>>(*this, key);
}

std::optional<std::vector<int64_t>> TuningTable::get_i64_list(std::string_view key) const {
	return get_as<std::vector<int64_t>>(*this, key);
}

std::optional<TuningNumberTable> TuningTable::get_table(std::string_view key) const {
	return get_as<TuningNumberTable>(*this, key);
}

std::optional<int64_t> TuningTable::get_ppm(std::string_view key) const {
	std::optional<double> p = get_f64(key);
	if (!p) {
		return std::nullopt;
	}
	return static_cast<int64_t>(std::llround(*p * 1000000.0));
}

std::shared_ptr<const TuningTable> TuningTable::current() {
	return std::atomic_load(&current_slot());
}

void TuningTable::set_current(std::shared_ptr<const TuningTable> table) {
	std::atomic_store(&current_slot(), std::move(table));
}

} // namespace lb::core
