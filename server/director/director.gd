class_name Director
extends RefCounted
## The Director's systems (DIR-*): installed for runs that pace their creatures. A generated run
## (M2 on) always has them; a fixed map only when asked (--director, or the scenario kit's
## "director"), so QA-01's kill test on the grey box runs with none, as its build promises (no
## Draught, no Pull). DIR-01's Draught, DIR-02's relax rules, DIR-03's Pull. Install after ServerSystems: the Director binds to the rescue, sound and
## creature systems it reads. Server-only.


static func install(run: RunState) -> void:
	run.draught = Draught.new()
	run.draught.bind(run)
	run.add_system(run.draught)
	run.relax = RelaxRules.new()
	run.relax.bind(run, run.draught)
	run.add_system(run.relax)
	run.pull = Pull.new()
	run.pull.bind(run)
	run.add_system(run.pull)
