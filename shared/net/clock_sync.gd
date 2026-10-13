class_name ClockSync
extends RefCounted
## Clock sync and RTT (NET-02): a ping on the control lane every net.clock_sync_interval_s.
## Each pong gives an RTT sample and an NTP-style offset; the estimate is the median of the
## recent samples, which shrugs off a delayed outlier. Shared by NET-03, NET-05, NET-06, NET-12.

const WINDOW: int = 8

var interval_usec: int = 1000000
var _rtts: PackedInt64Array = PackedInt64Array()
var _offsets: PackedInt64Array = PackedInt64Array()
var _last_ping_usec: int = -1


func _init() -> void:
	if Tuning.current.has_key(&"net.clock_sync_interval_s"):
		interval_usec = roundi(Tuning.f(&"net.clock_sync_interval_s") * 1000000.0)


## True when a ping is due; the caller sends Protocol.ping(now) on the control lane.
func ping_due(now_usec: int) -> bool:
	if _last_ping_usec < 0 or now_usec - _last_ping_usec >= interval_usec:
		_last_ping_usec = now_usec
		return true
	return false


func on_pong(client_sent_usec: int, server_time_usec: int, now_usec: int) -> void:
	var rtt: int = now_usec - client_sent_usec
	if rtt < 0:
		return
	_rtts.append(rtt)
	_offsets.append(server_time_usec + rtt / 2 - now_usec)
	if _rtts.size() > WINDOW:
		_rtts.remove_at(0)
		_offsets.remove_at(0)


func has_estimate() -> bool:
	return not _rtts.is_empty()


func rtt_usec() -> int:
	return _median(_rtts)


func rtt_ms() -> float:
	return rtt_usec() / 1000.0


## The server's clock now, as best this side can tell.
func server_time_estimate(now_usec: int) -> int:
	return now_usec + _median(_offsets)


func samples() -> int:
	return _rtts.size()


static func _median(values: PackedInt64Array) -> int:
	if values.is_empty():
		return 0
	var sorted: PackedInt64Array = values.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]
