class_name ServerConfig
extends RefCounted
## Everything the server needs to start, built by boot from launch arguments, or directly by
## tools such as FND-09's scenario kit. No global state: the server reads only this.

enum Mode { FRIENDS, PUBLIC, NIGHTSHIFT }
enum TransportKind { ENET, SDR, LOOPBACK }

var build: BuildInfo = BuildInfo.new()
var mode: Mode = Mode.FRIENDS
var transport: TransportKind = TransportKind.ENET
## 0 means the transport's default port (NET-02).
var port: int = 0
var offline: bool = false
## Private-host lifecycle (STM-04). 0 means none.
var parent_pid: int = 0
var control_port: int = 0
var resume_path: String = ""
## A fixed run seed (dev and QA only). Unsigned 64-bit, held in an int's bits.
var has_seed: bool = false
var run_seed: int = 0
var qa_token: String = ""
## Stop after this many ticks and exit 0 (smoke tests). 0 means run until stopped.
var exit_after_ticks: int = 0
## FND-09: write every applied input here, in the replay format (dev and QA only).
var record_inputs_path: String = ""
## NET-08: audit every record sent and write the report here as JSON at exit (dev and QA only).
var stream_audit_path: String = ""
## FND-09: write tick costs, input counters and the final state hash here as JSON at exit.
var stats_path: String = ""
## A tuning profile from data/tuning/profiles/ (dev and QA only). Empty means the base data.
var tuning_profile: String = ""
## Poll the tuning files and apply edits at tick boundaries. Dev runs always do; QA builds
## only with --tuning-hot-reload; release builds never.
var tuning_hot_reload: bool = false
