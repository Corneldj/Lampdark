class_name SaveResume
extends RefCounted
## NET-09 (Gameplay §13.11, §12.6, GDD §15.10): resuming a friends or Night Shift run from a save,
## a knock-off save or the last snapshot after an abnormal end (FND-03's `--resume <path>`).
##
## `open_file` checks the seal (a tampered save is refused whole) and the versions it resumes on,
## and reads the journal beside it: the entries of the same run whose seal and chain hold. The
## caller creates the run from `head` (seed, mode, map), installs its systems and loads the map
## without its placements; `apply` then restores the snapshot and lets every journaled fall and
## death after it stand. Server-only.

const ERR_MISSING: String = "missing"
const ERR_FORMAT: String = "format"
const ERR_SEAL: String = "seal"
const ERR_VERSIONS: String = "versions"
## LFT-11: the run has ended (its journal closes with an end entry).
const ERR_ENDED: String = "ended"


## {ok, error ("" | missing | format | seal | versions | ended), message (plain, for the player), header,
## head (the sealed run header), sections, journal, bytes}.
static func open_file(path: String, carried: PackedStringArray = PackedStringArray()) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _refused(ERR_MISSING, "There is no save at %s." % path)
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var opened: Dictionary = SaveContainer.open(bytes)
	if not Variants.flag(opened["ok"]):
		if str(opened["error"]) == ERR_SEAL:
			return _refused(ERR_SEAL, "This save has been changed or damaged, and cannot be resumed.")
		return _refused(ERR_FORMAT, "This is not a LAMPBLACK save.")
	var header: Dictionary = opened["header"]
	var why: String = refusal(header, carried)
	if not why.is_empty():
		return _refused(ERR_VERSIONS, why, header)
	var sections: Dictionary = opened["sections"]
	var journal: Array[Dictionary] = read_journal(path.get_base_dir().path_join(Saves.JOURNAL_FILE), str(header.get("run_uuid", "")))
	for e: Dictionary in journal:
		if str(e.get("kind", "")) == Journal.KIND_ENDED:
			return _refused(ERR_ENDED, "This run has ended, so it cannot be resumed.", header)
	return {"ok": true, "error": "", "message": "", "header": header, "head": Snapshot.run_header(sections),
		"sections": sections, "journal": journal, "bytes": bytes}


## Why a save cannot resume in this build ("" when it can). A run resumes in the mine it began in:
## its generator and templates must be ones this build carries (a fixed map; a generated mine's
## generator, GEN-08's version; GEN-04's template sets, the previous update's among them: MOD-05 then
## loads the save's set, never the build's newest). `carried`: the sets this process holds besides
## the build's packs (a dev server's --template-pack, a test's own pack). A public run is never resumed.
static func refusal(header: Dictionary, carried: PackedStringArray = PackedStringArray()) -> String:
	if int(Variants.number(header.get("mode", -1))) == ServerConfig.Mode.PUBLIC:
		return "A public run is never saved, so it cannot be resumed."
	var generator: String = str(header.get("generator", ""))
	if generator.begins_with("fixed:"):
		var map_name: String = generator.trim_prefix("fixed:")
		if FixedMapLoader.manifest(map_name).is_empty():
			return "This run began in a mine (%s) that this version of the game no longer has." % map_name
	elif generator.begins_with("gen:"):
		if generator != "gen:%d" % LbLayouts.generator_version():
			return "This run began in a mine this version of the game cannot make (generator %s)." % generator
	elif generator != "none":
		return "This run began in a mine this version of the game cannot make (generator %s)." % generator
	var templates: String = str(header.get("templates", ""))
	if templates != "none" and not carried.has(templates) and not FileAccess.file_exists(MineLayouts.TEMPLATES.path_join("packs/%s.lbtp" % templates)):
		return "This run began with rooms this version of the game no longer has (templates %s)." % templates
	return ""


## The run's journal: the entries of `uuid` whose seal holds, up to the first break in the chain.
static func read_journal(path: String, uuid: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not FileAccess.file_exists(path):
		return out
	var prev: String = ""
	for e: Dictionary in Saves.read_journal(path):
		if str(e.get("run_uuid", "")) != uuid:
			continue
		if str(e.get("prev", "")) != prev or str(e.get("hash", "")) != Journal.hash_of(e):
			break
		out.append(e)
		prev = str(e["hash"])
	return out


## The snapshot into the fresh run (systems installed, map loaded without placements), the journal
## after it applied, and the save chain continued from it. Returns Snapshot.restore's summary.
static func apply(run: RunState, net: ServerNet, opened: Dictionary) -> Dictionary:
	var journal: Array[Dictionary] = []
	journal.assign(Variants.array(opened.get("journal", [])))
	var sections: Dictionary = opened["sections"]
	var out: Dictionary = Snapshot.restore(run, net, sections, journal)
	if run.saves != null:
		var header: Dictionary = opened["header"]
		var bytes: PackedByteArray = opened["bytes"]
		run.saves.seq = int(Variants.number(header.get("seq", 0)))
		run.saves.parent_hash = SaveContainer.hash_of(bytes)
		run.saves.journal.entries = journal
		run.saves.journal.after_seq = run.saves.seq
	return out


static func _refused(error: String, message: String, header: Dictionary = {}) -> Dictionary:
	return {"ok": false, "error": error, "message": message, "header": header, "head": {}, "sections": {},
		"journal": [] as Array[Dictionary], "bytes": PackedByteArray()}
