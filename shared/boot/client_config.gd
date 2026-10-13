class_name ClientConfig
extends RefCounted
## Everything the client needs to start, built by boot from launch arguments.

var build: BuildInfo = BuildInfo.new()
## Direct connect target "host:port" (dev and QA only). Empty means the dev lobby.
var connect_target: String = ""
## Steam's `+connect_lobby <id>` (STM-02). Empty when absent.
var connect_lobby: String = ""
var no_steam: bool = false
var persona_name: String = ""
var qa_token: String = ""
## Headless bot brain (FND-09): tools/bots/brains/<name>.gd. Empty for a player.
var bot_script: String = ""
var bot_seed: int = 0
## --link: NET-12's link emulation on this client's connection; -1 means none.
var link_rtt_ms: int = -1
var link_loss_pct: float = 0.0
## A bot's log of every received message with its receive time.
var receive_log_path: String = ""
## Stop after this many 50 ms ticks and exit 0 (smoke tests). 0 means run until closed.
var exit_after_ticks: int = 0
