// GEN-14: the report the runs gather into (harness.h), and the repro dump.

#include "harness/harness.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <type_traits>

namespace lb::harness {

namespace {

// Text built by appending (no iostreams: the library's static libstdc++ keeps no locale for them
// inside a host process).
struct Text {
	std::string s;
	Text &operator<<(const std::string &v) {
		s += v;
		return *this;
	}
	Text &operator<<(const char *v) {
		s += v;
		return *this;
	}
	Text &operator<<(char v) {
		s += v;
		return *this;
	}
	template <typename T, typename = std::enable_if_t<std::is_integral_v<T> && !std::is_same_v<T, char>>>
	Text &operator<<(T v) {
		s += std::to_string(v);
		return *this;
	}
	std::string str() const { return s; }
};

std::string hex(uint64_t v) {
	char buf[24];
	std::snprintf(buf, sizeof(buf), "%016llx", static_cast<unsigned long long>(v));
	return buf;
}

// A decimal from integers alone, so every machine prints the same: `num / den` to `places`.
std::string decimal(int64_t num, int64_t den, int places) {
	if (den == 0) {
		return "0";
	}
	int64_t scale = 1;
	for (int i = 0; i < places; i++) {
		scale *= 10;
	}
	const bool negative = (num < 0) != (den < 0) && num != 0;
	const int64_t n = num < 0 ? -num : num;
	const int64_t d = den < 0 ? -den : den;
	// n * scale / d, rounded, without overflowing on a large n.
	const int64_t q = (n / d) * scale + ((n % d) * scale + d / 2) / d;
	std::string out = std::to_string(q / scale);
	if (places > 0) {
		std::string frac = std::to_string(q % scale);
		out += "." + std::string(static_cast<size_t>(places) - frac.size(), '0') + frac;
	}
	return negative ? "-" + out : out;
}

std::string percent(int64_t part, int64_t whole) {
	return decimal(part * 100, std::max<int64_t>(1, whole), 2) + "%";
}

std::string ppm_text(int64_t ppm) {
	return decimal(ppm, 1000000, 2);
}

std::string quote(const std::string &s) {
	std::string out = "\"";
	for (const char c : s) {
		switch (c) {
			case '"':
				out += "\\\"";
				break;
			case '\\':
				out += "\\\\";
				break;
			case '\n':
				out += "\\n";
				break;
			default:
				if (static_cast<unsigned char>(c) < 0x20) {
					char buf[8];
					std::snprintf(buf, sizeof(buf), "\\u%04x", static_cast<unsigned>(c));
					out += buf;
				} else {
					out += c;
				}
		}
	}
	return out + "\"";
}

// A small writer of canonical JSON: keys in the order given (callers give them sorted).
class Json {
public:
	void open(char c) {
		comma();
		out_ += c;
		first_ = true;
	}
	void close(char c) {
		out_ += c;
		first_ = false;
	}
	void key(const std::string &k) {
		comma();
		out_ += quote(k) + ":";
		first_ = true;
	}
	void raw(const std::string &v) {
		comma();
		out_ += v;
		first_ = false;
	}
	void num(int64_t v) { raw(std::to_string(v)); }
	void str(const std::string &v) { raw(quote(v)); }
	void boolean(bool v) { raw(v ? "true" : "false"); }
	void field(const std::string &k, int64_t v) {
		key(k);
		num(v);
	}
	void field_raw(const std::string &k, const std::string &v) {
		key(k);
		raw(v);
	}
	void field_str(const std::string &k, const std::string &v) {
		key(k);
		str(v);
	}
	void counts(const std::string &k, const std::map<std::string, int64_t> &m) {
		key(k);
		open('{');
		for (const auto &[name, n] : m) {
			field(name, n);
		}
		close('}');
	}
	std::string text() const { return out_ + "\n"; }

private:
	std::string out_;
	bool first_ = true;
	void comma() {
		if (!first_) {
			out_ += ",";
		}
		first_ = false;
	}
};

void histogram_json(Json &j, const std::string &k, const Histogram &h) {
	j.key(k);
	j.open('{');
	j.field("count", h.count);
	j.field("min", h.count > 0 ? h.min : 0);
	j.field("p50", h.quantile(0.5));
	j.field("p90", h.quantile(0.9));
	j.field("p99", h.quantile(0.99));
	j.field("max", h.count > 0 ? h.max : 0);
	j.field("sum", h.sum);
	j.close('}');
}

int64_t share_ppm(int64_t part, int64_t whole) {
	return whole > 0 ? (part / whole) * 1000000 + ((part % whole) * 1000000) / whole : 0;
}

// How many of a histogram's values lie outside [lo, hi]: its bins of 1 below its overflow bin.
int64_t outside(const Histogram &h, std::pair<int64_t, int64_t> band) {
	int64_t inside = 0;
	for (int64_t v = std::max<int64_t>(0, band.first); v <= band.second && v + 1 < static_cast<int64_t>(h.bins.size()); v++) {
		inside += h.bins[static_cast<size_t>(v)];
	}
	return h.count - inside;
}

} // namespace

void Histogram::add(int64_t v) {
	if (bins.empty()) {
		bins.assign(1, 0);
	}
	const int64_t at = v < 0 ? 0 : v / step;
	bins[static_cast<size_t>(std::min<int64_t>(at, static_cast<int64_t>(bins.size()) - 1))]++;
	count++;
	sum += v;
	min = std::min(min, v);
	max = std::max(max, v);
}

void Histogram::merge(const Histogram &o) {
	if (bins.size() < o.bins.size()) {
		bins.resize(o.bins.size(), 0);
	}
	for (size_t i = 0; i < o.bins.size(); i++) {
		bins[i] += o.bins[i];
	}
	count += o.count;
	sum += o.sum;
	min = std::min(min, o.min);
	max = std::max(max, o.max);
}

int64_t Histogram::quantile(double q) const {
	if (count <= 0) {
		return 0;
	}
	const int64_t want = std::max<int64_t>(1, static_cast<int64_t>(std::ceil(q * static_cast<double>(count))));
	int64_t seen = 0;
	for (size_t i = 0; i < bins.size(); i++) {
		seen += bins[i];
		if (seen >= want) {
			return i + 1 == bins.size() ? max : std::min(max, static_cast<int64_t>(i + 1) * step);
		}
	}
	return max;
}

void Report::set_range(uint64_t first_seed, uint64_t last_seed, std::vector<int32_t> lists) {
	first_seed_ = first_seed;
	last_seed_ = last_seed;
	lists_ = std::move(lists);
}

void Report::keep(const Failure &f) {
	// The lowest-keyed failures of each check, so any run order keeps the same ones.
	const auto at = std::lower_bound(kept_.begin(), kept_.end(), f, [](const Failure &a, const Failure &b) { return a.key() < b.key(); });
	kept_.insert(at, f);
	int64_t same = 0;
	for (auto it = kept_.begin(); it != kept_.end();) {
		if (it->check == f.check && ++same > p_.failures_kept_per_check) {
			it = kept_.erase(it);
		} else {
			++it;
		}
	}
}

void Report::add(const RunResult &r) {
	runs_++;
	ListStats &l = by_list_[r.list];
	l.runs++;
	l.plans_failed += r.planned ? 0 : 1;
	l.spines += r.spines;
	l.spines_reached += r.spines_reached;
	const int64_t limit = static_cast<int64_t>(std::llround(p_.road_ratio_max * 1000000.0));
	for (const int64_t ppm : r.road_ratio_ppm) {
		l.roads++;
		if (ppm < 0) {
			l.roads_missing++;
			continue;
		}
		l.road_ratio.add(ppm);
		l.roads_over += ppm > limit ? 1 : 0;
	}
	l.joined += r.joined_cells;
	l.ring_cells += r.ring_cells;
	const int64_t share = share_ppm(r.joined_cells, r.ring_cells);
	l.joined_share.add(share);
	l.runs_joined_under += share < static_cast<int64_t>(std::llround(p_.joined_min * 1000000.0)) ? 1 : 0;
	for (const auto &[name, n] : r.finds) {
		auto it = l.finds.find(name);
		if (it == l.finds.end()) {
			it = l.finds.emplace(name, Histogram(1, 201)).first;
		}
		it->second.add(n);
	}
	for (const auto &[kind, d] : r.sites) {
		auto it = l.sites.find(kind);
		if (it == l.sites.end()) {
			it = l.sites.emplace(kind, Histogram(10, 101)).first;
		}
		it->second.add(d);
	}
	if (r.roosts >= 0) {
		l.roosts.add(r.roosts);
		l.roosts_short += r.roosts < r.roosts_min ? 1 : 0;
	}
	if (r.hoard_lair_bearing >= 0) {
		l.hoard_lair.add(r.hoard_lair_bearing);
		l.hoard_lair_under += r.hoard_lair_bearing < static_cast<int64_t>(std::llround(p_.lair_min_bearing_deg)) ? 1 : 0;
	}
	order_cells_ += r.order_cells;
	order_differing_ += r.order_differing;
	cells_checked_ += r.cells_checked;
	cells_invalid_ += r.cells_invalid;
	for (const auto &[k, n] : r.cells_by_biome) {
		cells_by_biome_[k] += n;
	}
	for (const auto &[k, n] : r.fallbacks_by_biome) {
		fallbacks_by_biome_[k] += n;
	}
	for (const auto &[k, n] : r.rerolled_by_biome) {
		rerolled_by_biome_[k] += n;
	}
	for (const auto &[k, n] : r.templates) {
		templates_[k] += n;
	}
	for (const auto &[k, n] : r.counters) {
		counters_[k] += n;
	}
	for (const auto &[biome, list] : r.cell_us) {
		auto it = timing_.find(biome);
		if (it == timing_.end()) {
			it = timing_.emplace(biome, Histogram(5, 4001)).first;
		}
		for (const int64_t us : list) {
			it->second.add(us);
		}
	}
	for (const auto &[check, n] : r.failure_counts) {
		failures_by_check_[check] += n;
	}
	for (const Failure &f : r.failures) {
		keep(f);
	}
}

int64_t Report::failure_count(const std::string &check) const {
	const auto it = failures_by_check_.find(check);
	return it == failures_by_check_.end() ? 0 : it->second;
}

std::vector<Report::Gate> Report::gates() const {
	std::vector<Gate> out;
	int64_t plans_failed = 0;
	int64_t spines = 0;
	int64_t reached = 0;
	for (const auto &[list, l] : by_list_) {
		plans_failed += l.plans_failed;
		spines += l.spines;
		reached += l.spines_reached;
	}
	out.push_back({"plan", plans_failed > 0, std::to_string(plans_failed) + " of " + std::to_string(runs_) + " runs ran out of plan retries"});
	const int64_t reach_ppm = spines > 0 ? share_ppm(reached, spines) : 1000000;
	out.push_back({"spine_reach", reach_ppm < static_cast<int64_t>(std::llround(p_.spine_reach_min * 1000000.0)),
			std::to_string(reached) + " of " + std::to_string(spines) + " spines reach their target (" + percent(reached, spines) + ")"});
	out.push_back({"order", order_differing_ > 0,
			std::to_string(order_differing_) + " of " + std::to_string(order_cells_) + " cells differ between generation orders"});
	const int64_t camp = failure_count("base_camp");
	out.push_back({"validator", cells_invalid_ > 0 || camp > 0,
			std::to_string(cells_invalid_) + " of " + std::to_string(cells_checked_) + " final cells break a rule or have no layout; " + std::to_string(camp) +
					" runs place something in base camp"});
	std::string worst;
	bool fallback_failed = false;
	for (const auto &[biome, cells] : cells_by_biome_) {
		const auto it = fallbacks_by_biome_.find(biome);
		const int64_t fb = it == fallbacks_by_biome_.end() ? 0 : it->second;
		if (cells > 0 && share_ppm(fb, cells) > static_cast<int64_t>(std::llround(p_.fallback_rate_max * 1000000.0))) {
			fallback_failed = true;
			worst += (worst.empty() ? "" : ", ") + biome + " " + percent(fb, cells);
		}
	}
	out.push_back({"fallback_rate", fallback_failed,
			fallback_failed ? "over " + percent(static_cast<int64_t>(std::llround(p_.fallback_rate_max * 10000.0)), 10000) + " of cells take the plain fallback: " + worst
							: "every biome under " + percent(static_cast<int64_t>(std::llround(p_.fallback_rate_max * 10000.0)), 10000)});
	bool road_failed = false;
	std::string roads;
	for (const auto &[list, l] : by_list_) {
		const int64_t bad = l.roads_over + l.roads_missing;
		if (l.roads > 0 && share_ppm(bad, l.roads) > static_cast<int64_t>(std::llround(p_.road_ratio_share_max * 1000000.0))) {
			road_failed = true;
		}
		roads += (roads.empty() ? "" : "; ") + std::string(list_name(list)) + " " + std::to_string(bad) + " of " + std::to_string(l.roads);
	}
	out.push_back({"road_ratio", road_failed, "sites over " + decimal(static_cast<int64_t>(std::llround(p_.road_ratio_max * 100.0)), 100, 2) + " x the straight line or with no road: " + roads});
	bool joined_failed = false;
	std::string joined;
	for (const auto &[list, l] : by_list_) {
		const int64_t mean = l.joined_share.count > 0 ? l.joined_share.sum / l.joined_share.count : 0;
		if (l.runs > 0 && mean < static_cast<int64_t>(std::llround(p_.joined_min * 1000000.0))) {
			joined_failed = true;
		}
		joined += (joined.empty() ? "" : "; ") + std::string(list_name(list)) + " mean " + decimal(mean * 100, 1000000, 2) + "%";
	}
	out.push_back({"joined", joined_failed, "ring 0-" + std::to_string(p_.joined_max_ring) + " cells joined to base camp: " + joined});
	if (p_.timing_gate) {
		bool slow = false;
		std::string text;
		for (const auto &[biome, h] : timing_) {
			const int64_t p99 = h.quantile(0.99);
			if (static_cast<double>(p99) > p_.budget_ms * 1000.0) {
				slow = true;
			}
			text += (text.empty() ? "" : ", ") + biome + " p99 " + decimal(p99, 1000, 3) + " ms";
		}
		out.push_back({"generation_time", slow, "budget " + decimal(static_cast<int64_t>(std::llround(p_.budget_ms * 1000.0)), 1000, 3) + " ms on " + p_.machine + ": " + text});
	}
	return out;
}

bool Report::failed() const {
	for (const Gate &g : gates()) {
		if (g.failed) {
			return true;
		}
	}
	return false;
}

std::vector<std::string> Report::warnings() const {
	std::vector<std::string> out;
	for (const auto &[list, l] : by_list_) {
		const auto band = [&](const std::string &name, std::pair<int64_t, int64_t> b, bool standard_only) {
			if (standard_only && list != 1) {
				return;
			}
			const auto it = l.finds.find(name);
			if (it == l.finds.end() || it->second.count == 0) {
				return;
			}
			const int64_t n = outside(it->second, b);
			if (share_ppm(n, it->second.count) > static_cast<int64_t>(std::llround(p_.finds_warn_share * 1000000.0))) {
				const std::string want = b.second >= 1000 ? "under " + std::to_string(b.first) : "outside " + std::to_string(b.first) + "-" + std::to_string(b.second);
				out.push_back(std::string(list_name(list)) + ": " + name + " " + want + " in " + percent(n, it->second.count) + " of runs");
			}
		};
		band("lamps", p_.lamps, true);
		band("kits", p_.kits, true);
		band("flares_ring2", p_.flares_ring2, false);
		for (const auto &[name, h] : l.finds) {
			if (name.rfind("tools_ring2.", 0) == 0) {
				band(name, p_.tools_ring2, false);
			} else if (name.rfind("tools_ring1.", 0) == 0) {
				band(name, {1, 1000}, false);
			}
		}
		if (l.hoard_lair_under > 0) {
			out.push_back(std::string(list_name(list)) + ": the hoard and the lair under " + std::to_string(std::llround(p_.lair_min_bearing_deg)) +
					" degrees apart in " + std::to_string(l.hoard_lair_under) + " runs");
		}
		// GEN-16: the hoard's roosts in 95% or more of seeds.
		if (l.roosts.count > 0 && share_ppm(l.roosts_short, l.roosts.count) > 50000) {
			out.push_back(std::string(list_name(list)) + ": fewer roosts than mine.roosts_min in " + percent(l.roosts_short, l.roosts.count) +
					" of runs with a hoard (95% should have them)");
		}
	}
	return out;
}

std::vector<std::string> Report::timing_warnings() const {
	std::vector<std::string> out;
	if (p_.timing_gate) {
		return out;
	}
	for (const auto &[biome, h] : timing_) {
		if (static_cast<double>(h.quantile(0.99)) > p_.budget_ms * 1000.0) {
			out.push_back("timing (" + p_.machine + ", not gated): " + biome + " p99 " + decimal(h.quantile(0.99), 1000, 3) + " ms over the " +
					decimal(static_cast<int64_t>(std::llround(p_.budget_ms * 1000.0)), 1000, 3) + " ms budget");
		}
	}
	return out;
}

std::string Report::json(bool timing) const {
	Json j;
	j.open('{');
	j.key("checks");
	j.open('{');
	j.field("cells_checked", cells_checked_);
	j.field("cells_invalid", cells_invalid_);
	j.field("order_cells", order_cells_);
	j.field("order_differing", order_differing_);
	j.close('}');
	j.counts("counters", counters_);
	j.key("failures");
	j.open('[');
	for (const Failure &f : kept_) {
		j.open('{');
		j.key("cell");
		j.open('[');
		j.num(f.cell.x);
		j.num(f.cell.y);
		j.close(']');
		j.field_str("check", f.check);
		j.field_str("detail", f.detail);
		j.field_str("list", list_name(f.list));
		j.field_str("repro", f.repro());
		j.field("rule", f.rule);
		j.field_str("seed", std::to_string(f.seed));
		j.key("tile");
		j.open('[');
		j.num(f.tile.x);
		j.num(f.tile.y);
		j.close(']');
		j.close('}');
	}
	j.close(']');
	j.counts("failures_by_check", failures_by_check_);
	j.key("gates");
	j.open('[');
	for (const Gate &g : gates()) {
		j.open('{');
		j.field_str("detail", g.detail);
		j.key("failed");
		j.boolean(g.failed);
		j.field_str("name", g.name);
		j.close('}');
	}
	j.close(']');
	j.key("generator");
	j.open('{');
	j.counts("cells_by_biome", cells_by_biome_);
	j.counts("fallbacks_by_biome", fallbacks_by_biome_);
	j.counts("rerolled_by_biome", rerolled_by_biome_);
	j.counts("templates", templates_);
	j.close('}');
	j.key("lists");
	j.open('{');
	for (const auto &[list, l] : by_list_) {
		j.key(list_name(list));
		j.open('{');
		j.key("finds");
		j.open('{');
		for (const auto &[name, h] : l.finds) {
			histogram_json(j, name, h);
		}
		j.close('}');
		histogram_json(j, "hoard_lair_bearing_deg", l.hoard_lair);
		j.field("hoard_lair_under", l.hoard_lair_under);
		j.field("joined_cells", l.joined);
		histogram_json(j, "joined_share_ppm", l.joined_share);
		j.field("plans_failed", l.plans_failed);
		j.field("ring_cells", l.ring_cells);
		histogram_json(j, "road_ratio_ppm", l.road_ratio);
		j.field("roads", l.roads);
		j.field("roads_missing", l.roads_missing);
		j.field("roads_over", l.roads_over);
		histogram_json(j, "roosts", l.roosts);
		j.field("roosts_short", l.roosts_short);
		j.field("runs", l.runs);
		j.field("runs_joined_under", l.runs_joined_under);
		j.key("sites");
		j.open('{');
		for (const auto &[kind, h] : l.sites) {
			histogram_json(j, kind, h);
		}
		j.close('}');
		j.field("spines", l.spines);
		j.field("spines_reached", l.spines_reached);
		j.close('}');
	}
	j.close('}');
	j.field_str("pack", pack_);
	j.key("params");
	j.open('{');
	j.field("failures_kept_per_check", p_.failures_kept_per_check);
	j.field_raw("fallback_rate_max", decimal(static_cast<int64_t>(std::llround(p_.fallback_rate_max * 1000000.0)), 1000000, 6));
	j.field_raw("joined_min", decimal(static_cast<int64_t>(std::llround(p_.joined_min * 1000000.0)), 1000000, 6));
	j.field("order_cells", p_.order_cells);
	j.field("orders", p_.orders);
	j.field_raw("road_ratio_max", decimal(static_cast<int64_t>(std::llround(p_.road_ratio_max * 1000000.0)), 1000000, 6));
	j.close('}');
	j.key("range");
	j.open('{');
	j.field_str("first_seed", std::to_string(first_seed_));
	j.field_str("last_seed", std::to_string(last_seed_));
	j.key("lists");
	j.open('[');
	for (const int32_t l : lists_) {
		j.str(list_name(l));
	}
	j.close(']');
	j.close('}');
	j.field("runs", runs_);
	if (timing) {
		j.key("timing_us");
		j.open('{');
		j.field_str("machine", p_.machine);
		j.field_raw("budget_ms", decimal(static_cast<int64_t>(std::llround(p_.budget_ms * 1000.0)), 1000, 3));
		j.key("by_biome");
		j.open('{');
		for (const auto &[biome, h] : timing_) {
			histogram_json(j, biome, h);
		}
		j.close('}');
		j.key("warnings");
		j.open('[');
		for (const std::string &w : timing_warnings()) {
			j.str(w);
		}
		j.close(']');
		j.close('}');
	}
	j.key("warnings");
	j.open('[');
	for (const std::string &w : warnings()) {
		j.str(w);
	}
	j.close(']');
	j.close('}');
	return j.text();
}

std::string Report::markdown() const {
	Text md;
	md << "# Seed harness report\n\n";
	md << "Seeds " << first_seed_ << " to " << last_seed_ << ", lists";
	for (const int32_t l : lists_) {
		md << " " << list_name(l);
	}
	md << ": " << runs_ << " runs on template set `" << (pack_.empty() ? "?" : pack_) << "`.\n\n";
	md << "## Gates\n\n| Gate | Result | Detail |\n|---|---|---|\n";
	for (const Gate &g : gates()) {
		md << "| " << g.name << " | " << (g.failed ? "**FAIL**" : "pass") << " | " << g.detail << " |\n";
	}
	std::vector<std::string> warns = warnings();
	for (const std::string &w : timing_warnings()) {
		warns.push_back(w);
	}
	md << "\n## Warnings\n\n";
	if (warns.empty()) {
		md << "None.\n";
	}
	for (const std::string &w : warns) {
		md << "- " << w << "\n";
	}
	md << "\n## Fairness and banded sites, by list\n\n";
	for (const auto &[list, l] : by_list_) {
		md << "### " << list_name(list) << " (" << l.runs << " runs)\n\n";
		md << "- Spines: " << l.spines_reached << " of " << l.spines << " reach their target.\n";
		md << "- Road over the straight line: p50 " << ppm_text(l.road_ratio.quantile(0.5)) << ", p90 " << ppm_text(l.road_ratio.quantile(0.9)) << ", max "
		   << ppm_text(l.road_ratio.count > 0 ? l.road_ratio.max : 0) << "; " << l.roads_over << " of " << l.roads << " sites over "
		   << decimal(static_cast<int64_t>(std::llround(p_.road_ratio_max * 100.0)), 100, 2) << ", " << l.roads_missing << " with no road.\n";
		const int64_t mean = l.joined_share.count > 0 ? l.joined_share.sum / l.joined_share.count : 0;
		md << "- Ring 0-" << p_.joined_max_ring << " cells joined to base camp: mean " << decimal(mean * 100, 1000000, 2) << "%, worst "
		   << decimal((l.joined_share.count > 0 ? l.joined_share.min : 0) * 100, 1000000, 2) << "%; " << l.runs_joined_under << " runs under "
		   << decimal(static_cast<int64_t>(std::llround(p_.joined_min * 10000.0)), 100, 2) << "%.\n";
		if (l.roosts.count > 0) {
			md << "- The Moth's roosts: p50 " << l.roosts.quantile(0.5) << ", min " << l.roosts.min << ", max " << l.roosts.max << "; " << l.roosts_short << " of "
			   << l.roosts.count << " runs with a hoard short of mine.roosts_min.\n";
		}
		if (l.hoard_lair.count > 0) {
			md << "- The hoard and the lair seen from the shaft: min " << l.hoard_lair.min << " degrees apart, p50 " << l.hoard_lair.quantile(0.5) << "; "
			   << l.hoard_lair_under << " runs under " << std::llround(p_.lair_min_bearing_deg) << ".\n";
		}
		md << "\n| Site | Count | Door from the shaft (tiles): min | p50 | p90 | max |\n|---|---|---|---|---|---|\n";
		for (const auto &[kind, h] : l.sites) {
			md << "| " << kind << " | " << h.count << " | " << h.min << " | " << h.quantile(0.5) << " | " << h.quantile(0.9) << " | " << h.max << " |\n";
		}
		md << "\n| Finds (explored cells) | Mean | min | p50 | p90 | max |\n|---|---|---|---|---|---|\n";
		for (const auto &[name, h] : l.finds) {
			md << "| " << name << " | " << decimal(h.sum, std::max<int64_t>(1, h.count), 2) << " | " << (h.count > 0 ? h.min : 0) << " | " << h.quantile(0.5)
			   << " | " << h.quantile(0.9) << " | " << (h.count > 0 ? h.max : 0) << " |\n";
		}
		md << "\n";
	}
	md << "## Generation\n\n| Biome | Cells | Plain fallback | Rerolled |\n|---|---|---|---|\n";
	for (const auto &[biome, cells] : cells_by_biome_) {
		const auto fb = fallbacks_by_biome_.find(biome);
		const auto rr = rerolled_by_biome_.find(biome);
		md << "| " << biome << " | " << cells << " | " << percent(fb == fallbacks_by_biome_.end() ? 0 : fb->second, cells) << " | "
		   << percent(rr == rerolled_by_biome_.end() ? 0 : rr->second, cells) << " |\n";
	}
	md << "\nValidator counts:";
	for (const auto &[k, n] : counters_) {
		md << " `" << k << "` " << n << ";";
	}
	md << "\n\n| Template | Cells |\n|---|---|\n";
	for (const auto &[id, n] : templates_) {
		md << "| " << id << " | " << n << " |\n";
	}
	md << "\n## Timing (" << p_.machine << ", budget " << decimal(static_cast<int64_t>(std::llround(p_.budget_ms * 1000.0)), 1000, 3) << " ms"
	   << (p_.timing_gate ? ", gated" : ", reported") << ")\n\n| Biome | Cells | p50 ms | p99 ms | max ms |\n|---|---|---|---|---|\n";
	for (const auto &[biome, h] : timing_) {
		md << "| " << biome << " | " << h.count << " | " << decimal(h.quantile(0.5), 1000, 3) << " | " << decimal(h.quantile(0.99), 1000, 3) << " | "
		   << decimal(h.count > 0 ? h.max : 0, 1000, 3) << " |\n";
	}
	md << "\n## Failures\n\n";
	if (kept_.empty()) {
		md << "None.\n";
	}
	for (const auto &[check, n] : failures_by_check_) {
		if (n > 0) {
			md << "- " << check << ": " << n << " (the first " << std::min<int64_t>(n, p_.failures_kept_per_check) << " listed)\n";
		}
	}
	if (!kept_.empty()) {
		md << "\n| Check | Seed | List | Rule | Detail | Repro |\n|---|---|---|---|---|---|\n";
		for (const Failure &f : kept_) {
			md << "| " << f.check << " | " << f.seed << " | " << list_name(f.list) << " | " << f.rule << " | " << f.detail << " | `" << f.repro() << "` |\n";
		}
	}
	return md.str();
}

std::string repro(const Run &run, const RunFactory &fresh, const Params &p, const std::string &check, std::optional<Coord> cell) {
	Text out;
	const gen::RunHeader &h = run.header();
	out << "seed " << h.seed << ", list " << list_name(h.list_kind) << ", check " << (check.empty() ? "all" : check) << "\n";
	const RunResult r = check_run(run, fresh, p);
	int64_t shown = 0;
	for (const Failure &f : r.failures) {
		if (!check.empty() && f.check != check) {
			continue;
		}
		if (cell && !(f.cell.x == cell->x && f.cell.y == cell->y)) {
			continue;
		}
		out << "  " << f.check << " cell (" << f.cell.x << ", " << f.cell.y << ") rule " << f.rule << ": " << f.detail << "\n";
		shown++;
	}
	out << (shown == 0 ? "  (no such failure in this run)\n" : "");
	if (!cell) {
		return out.str();
	}
	const Coord c = *cell;
	const std::optional<gen::Layout> layout = run.world().layout(c);
	out << "\ncell (" << c.x << ", " << c.y << ")";
	if (!layout) {
		out << ": no layout (no template or fallback fits)\n";
	} else {
		out << ": template " << layout->template_id << ", reroll " << layout->reroll << (layout->fallback ? ", the plain fallback" : "")
			<< (layout->base_camp ? ", base camp" : "") << "\n";
		static const char MATERIALS[] = {'.', '#', 'c', 'B', 'T', 'S', 'D'};
		for (int64_t y = 0; y < lb::core::world::CELL_TILES; y++) {
			out << "  ";
			for (int64_t x = 0; x < lb::core::world::CELL_TILES; x++) {
				const uint8_t m = layout->cell.tiles[static_cast<size_t>(lb::core::world::Cell::index_of(x, y))].material;
				out << (m < sizeof(MATERIALS) ? MATERIALS[m] : '?');
			}
			out << "\n";
		}
		out << "anchors:\n";
		for (const lb::core::world::Anchor &a : layout->cell.anchors) {
			out << "  type " << static_cast<int>(a.type) << " at (" << a.x << ", " << a.y << ") " << a.w << "x" << a.h << (a.kind.empty() ? "" : " kind " + a.kind);
			for (const std::string &t : a.tags) {
				out << " #" << t;
			}
			out << "\n";
		}
	}
	if (const gen::DeriveInputs *in = run.derive_inputs()) {
		std::vector<gen::LayoutTry> tried;
		gen::derive_final(*in, c, &tried);
		out << "phase 1 tries:" << (tried.empty() ? " none failed\n" : "\n");
		for (const gen::LayoutTry &t : tried) {
			out << "  reroll " << t.reroll << " " << t.template_id << ": " << gen::describe(t.verdict) << "\n";
		}
	}
	const gen::PlacedCell placed = gen::place_validated(run.world(), run.placement_params(), run.validator_params(), c);
	out << "phase 2: retry " << placed.retry << (placed.strict ? ", strict mode, " + std::to_string(placed.dropped) + " dropped" : "") << ", "
		<< placed.list.size() << " placements\n";
	for (const gen::Verdict &v : placed.failures) {
		out << "  " << gen::describe(v) << "\n";
	}
	if (check == "order" || check.empty()) {
		const std::vector<Coord> cells = nearest_cells(p.order_cells);
		for (int32_t k = 0; k < std::max(1, p.orders); k++) {
			const std::unique_ptr<Run> w = fresh();
			uint64_t digest = 0;
			for (const Coord &o : shuffled(cells, h.seed, k)) {
				const std::optional<gen::Layout> l = w->world().layout(o);
				const gen::PlacedCell pc = l ? gen::place_validated(w->world(), w->placement_params(), w->validator_params(), o) : gen::PlacedCell{};
				if (o.x == c.x && o.y == c.y) {
					digest = cell_digest(l, pc);
				}
			}
			out << "order " << k << ": digest " << hex(digest) << "\n";
		}
	}
	return out.str();
}

} // namespace lb::harness
