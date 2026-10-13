class_name PeerStats
extends RefCounted
## Per-connection statistics (NET-02): round trip, loss, bytes and last-heard time.

var rtt_ms: float = 0.0
var loss: float = 0.0
var bytes_in: int = 0
var bytes_out: int = 0
## Monotonic µs of the last packet received from this peer.
var last_heard_usec: int = 0
