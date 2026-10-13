class_name LinkFilter
extends TransportFilter
## A client connection's link emulation (FND-09 installs it, NET-12 implements it): bots take
## `--link rtt_ms,loss_pct`, and the scenario kit sets it per miner. Until NET-12 lands this
## filter only records its settings and passes everything through unchanged.

var rtt_ms: int = 0
var loss_pct: float = 0.0
## True until NET-12 gives the filter its delay and loss.
var pass_through: bool = true


func _init(wrapped: Transport, link_rtt_ms: int = 0, link_loss_pct: float = 0.0) -> void:
	super(wrapped)
	configure(link_rtt_ms, link_loss_pct)


func configure(link_rtt_ms: int, link_loss_pct: float) -> void:
	rtt_ms = link_rtt_ms
	loss_pct = link_loss_pct
