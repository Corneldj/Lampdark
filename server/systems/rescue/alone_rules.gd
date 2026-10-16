class_name AloneRules
extends RefCounted
## DIR-05's alone predicate (Gameplay §11.11, §13.5), the one definition every M1 caller uses
## (the crew count, the Pull, the heard rule, two-miner jobs, grabs). RSC-09 adds the solo rules
## and an alone_changed signal on top, without changing this API.
##  - Solo: Night Shift, or a friends lobby of one.
##  - A lone human: the only conscious human in the mine in a public lobby, or the last conscious
##    human of a friends crew that began with exactly two. Base camp counts as in the mine.
##    A second conscious human, revived or rejoined, ends it at once.


static func is_alone(run: RunState, miner: int) -> bool:
	if run.crew == null:
		return false
	return is_solo(run.crew) or is_lone_human(run, run.crew, miner)


static func is_solo(census: CrewCensus) -> bool:
	return census.lobby == CrewCensus.Lobby.SOLO or (census.lobby == CrewCensus.Lobby.FRIENDS and census.humans_at_start == 1)


static func is_lone_human(run: RunState, census: CrewCensus, miner: int) -> bool:
	if Variants.flag(census.is_hand_driven.call(miner)) or not CrewCensus.is_conscious(run, miner):
		return false
	for e: int in census.humans(run):
		if e != miner and CrewCensus.is_conscious(run, e):
			return false
	if census.lobby == CrewCensus.Lobby.PUBLIC:
		return true
	return census.lobby == CrewCensus.Lobby.FRIENDS and census.humans_at_start == 2


## RSC-09: whether `miner` is alone as they fall: solo, or no other conscious human in the mine in a
## lobby whose lone-human rule applies (public; a friends crew that began with two). The lone-human
## test without the faller's own consciousness (they are falling). Hands never are.
static func alone_at_fall(run: RunState, miner: int) -> bool:
	if run.crew == null or Variants.flag(run.crew.is_hand_driven.call(miner)):
		return false
	if is_solo(run.crew):
		return true
	for e: int in run.crew.humans(run):
		if e != miner and CrewCensus.is_conscious(run, e):
			return false
	if run.crew.lobby == CrewCensus.Lobby.PUBLIC:
		return true
	return run.crew.lobby == CrewCensus.Lobby.FRIENDS and run.crew.humans_at_start == 2

