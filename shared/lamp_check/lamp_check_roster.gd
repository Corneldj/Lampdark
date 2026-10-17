class_name LampCheckRoster
extends RefCounted
## RSC-06 to MOD-01 (Gameplay §11.9, §13.2): a player's own outcome from Lamp Check's opening onto
## their roster. The miner they sent below for this run (Profile.send_below, MOD-03) comes back to
## the roster if they escaped, and leaves it for good if they died, were left below, or went with
## the whole crew in a wipe. The client applies it as Lamp Check opens and saves the profile
## (ProfileStore); applying it twice changes nothing (MOD-01 keys events by kind, run and miner).


## OutcomeEvent.Outcome for Lamp Check's own outcome ("escaped" | "dead" | "left_below"), -1 for none.
static func outcome_of(own: String, wipe: bool) -> int:
	if own.is_empty():
		return -1
	if wipe:
		return OutcomeEvent.Outcome.WIPE
	match own:
		"escaped":
			return OutcomeEvent.Outcome.ESCAPED
		"dead":
			return OutcomeEvent.Outcome.DEAD
		"left_below":
			return OutcomeEvent.Outcome.LEFT_BELOW
	return -1


## Applies it to the profile's miner below in `run_uuid`. False when there is no outcome, or no
## miner of this profile is below in that run.
static func apply(profile: Profile, run_uuid: String, own: String, wipe: bool, at: int) -> bool:
	var what: int = outcome_of(own, wipe)
	if what < 0 or run_uuid.is_empty() or profile == null:
		return false
	for m: RosterMiner in profile.state().roster:
		if m.below_run == run_uuid:
			profile.apply_outcome(run_uuid, m.id, what as OutcomeEvent.Outcome, at)
			return true
	return false
