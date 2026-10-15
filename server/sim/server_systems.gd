class_name ServerSystems
extends RefCounted
## The one list of systems a server run registers, shared by the server entry (FND-03) and
## FND-09's scenario kit, so a scenario runs exactly the systems a server runs. Each ticket
## that adds a system adds it here.


## FND-08: the debug channel's server end, loaded by path outside release builds only.
const DEBUG_INSTALL: String = "res://server/debug/debug_install.gd"


## Registers the network stages, the input pipeline and, with a mine, the world systems.
## `secret` seeds per-client tokens and event ordering (NET-04): never the run seed. 0 draws one
## from the OS; the scenario kit passes one derived from its own seed so its runs replay.
static func install(run: RunState, net: ServerNet, mine: Mine = null, secret: int = 0) -> void:
	run.add_system(net)
	# GEN-13: first, so every owner registers its handlers as it binds; bound near the end.
	run.diff_log = DiffLog.new()
	run.inputs = InputService.new(net)
	run.add_system(run.inputs)
	run.now_judge = NowJudge.new()
	run.add_system(run.now_judge)
	if mine != null:
		run.mine = mine
		run.add_system(MineCommitSystem.new(mine))
		run.light = LightSystem.new(mine)
		run.light.register_into(run)
		run.flame_states = FlameStates.new()
		run.add_system(run.flame_states)
		run.road_graph = RoadGraphService.new(mine, run.header.run_seed)
		run.vision = VisionSystem.new(mine, run.light)
		run.vision.rtt_ms = func(slot: int) -> float:
			for session: Sessions.Session in net.sessions.welcomed():
				if session.slot == slot:
					return net.transport.stats(session.peer).rtt_ms
			return 0.0
		run.add_system(run.vision)
		run.add_system(BiteSystem.new())  # VIS-10
	run.noise = NoiseSystem.new(run.road_graph)
	run.add_system(run.noise)
	run.movement = MovementSystem.new(mine)
	run.add_system(run.movement)
	run.miner_state = MinerStateSystem.new()
	run.miner_state.register_into(run)
	run.inventory = InventorySystem.new()
	run.inventory.bind(run)
	run.add_system(run.inventory)
	run.feel = FeelSystem.new()
	run.feel.bind(run)
	run.add_system(run.feel)
	run.ring = RingSystem.new()
	run.add_system(run.ring)
	run.lamps = LampSystem.new()
	run.lamps.bind(run)
	run.add_system(run.lamps)
	run.electric = ElectricLamps.new()
	run.electric.bind(run)
	run.add_system(run.electric)
	run.rewind = Rewind.new()
	run.rewind.bind(run)
	run.add_system(run.rewind)
	run.defender = DefenderRule.new()
	run.add_system(run.defender)
	run.creatures = CreatureSystem.new()
	run.creatures.bind(run)
	run.add_system(run.creatures)
	run.rewind.radius_of = run.creatures.body_radius_of
	# CRT-09's Tapper drops a pinned miner's lamp at the wall when the pin runs out (MNR-06).
	run.creatures.spawned.connect(func(c: Creature) -> void:
		if c is Tapper:
			(c as Tapper).drop_lamp = run.lamps.drop_at_wall
		# CRT-14: the Stythe's tell reaches SND-08's crackle and VIS-10's bite.
		if c is StytheCreature:
			var st: StytheCreature = c as StytheCreature
			# MNR-08: its snuff drains an electric lamp's battery instead.
			st.snuff.electric_sources = run.electric.lit_sources
			st.electric_drain = run.electric.drain_source
			# CRT-15: its lair, and its blood trail smeared through VIS-10's trail (GEN-13 keeps it).
			run.stythe_lair.attach(run, st)
			if run.vision != null:
				run.stythe_lair.trail.smear = run.vision.mark_trail
				run.stythe_lair.trail.wipe = run.vision.erase_trail
			if run.voice != null:
				run.voice.conditions.stythe_tells = func() -> Array: return st.tell_points(run)
			if run.vision != null:
				run.vision.bite_sources = func(r: RunState) -> Array:
					var out: Array = []
					for p: Variant in st.tell_points(r):
						out.append({"position": p, "thin": st.thin})
					return out)
	run.stythe_lair = StytheLair.new()
	run.stythe_lair.bind(run)
	run.add_system(run.stythe_lair)
	run.crew = CrewCensus.new()
	run.crew.bind(run)
	run.add_system(run.crew)
	run.cap = ActiveCap.new(run.crew, run.creatures.gate)
	run.holds = Holds.new()
	run.holds.bind(run)
	run.add_system(run.holds)
	run.falls = FallSystem.new()
	run.falls.bind(run)
	run.add_system(run.falls)
	run.carry = FiremanCarry.new()
	run.carry.bind(run)
	run.add_system(run.carry)
	run.ring.bind(run)
	run.revival = Revival.new()
	run.revival.bind(run)
	run.add_system(run.revival)
	run.closeups = CloseupState.new()
	run.closeups.bind(run, net)
	run.add_system(run.closeups)
	# MNR-09's candles, flares and stones.
	run.candles = Candles.new()
	run.candles.bind(run)
	run.add_system(run.candles)
	run.flares = Flares.new()
	run.flares.bind(run)
	run.add_system(run.flares)
	run.stones = Stones.new()
	run.stones.bind(run)
	run.add_system(run.stones)
	run.tools_parts = ToolsParts.new()
	run.tools_parts.bind(run)
	run.add_system(run.tools_parts)
	run.chalk = Chalk.new()
	run.chalk.bind(run)
	run.add_system(run.chalk)
	run.revolver = Revolver.new()
	run.revolver.bind(run)
	run.add_system(run.revolver)
	# SND-12's lamp signals and rock taps.
	run.lamp_signals = LampSignals.new()
	run.lamp_signals.bind(run)
	run.add_system(run.lamp_signals)
	run.rock_taps = RockTaps.new()
	run.add_system(run.rock_taps)
	run.add_system(RockTapLines.new())
	# A retreat drops the grab (CRT-01); a grab's end stands its creature's hunt down.
	run.creatures.grab_release = func(_c: Creature, miner: int) -> void:
		var g: GrabHold = run.holds.grab_of(miner)
		if g != null:
			run.holds.end_grab(run, g.id, GrabHold.Outcome.RETREAT)
	run.holds.grab_ended.connect(func(grab_id: int, outcome: GrabHold.Outcome) -> void:
		var g: GrabHold = run.holds.grabs[grab_id]
		var c: Creature = run.creatures.creature_of(g.creature)
		if c != null:
			c.on_grab_ended(run, g, outcome))
	run.creatures.gate.hunt_started.connect(func(c: Creature, miner: int, _chosen: bool) -> void:
		var target: SimEntity = run.registry.get_entity(miner)
		Log.info("telemetry hunt_committed creature=%s target=%d target_ring=%d crew_count=%d run_time=%.1f" % [c.kind_name(), miner,
			WorldCoords.ring_of_point(target.position) if target != null else -1, run.crew.count, run.tick / Tuning.f(&"net.tick_hz")]))
	if secret == 0:
		secret = Crypto.new().generate_random_bytes(8).decode_s64(0)
	run.replication = Replication.new(net, run.vision, mine, secret)
	run.add_system(run.replication)
	# SND-03: every player delivery, tell and local emitter goes through the masks to NET-04.
	run.audio = AudioDelivery.new()
	run.audio.bind(run)
	run.audio.sink = run.replication.queue_audio
	run.deafen = Deafen.new()
	run.deafen.bind(run)
	run.add_system(run.deafen)
	run.voice = VoiceSystem.new()
	run.voice.bind(run, net)
	run.add_system(run.voice)
	run.voice_noise = VoiceNoise.new()
	run.voice_noise.bind(run)
	run.heard = HeardTracker.new()
	run.heard.bind(run)
	run.add_system(run.heard)
	run.voice_facts = VoiceFacts.new()
	run.voice_facts.bind(run)
	run.add_system(run.voice_facts)
	run.fall_audio = FallAudio.new()
	run.fall_audio.bind(run)
	run.add_system(run.fall_audio)
	run.callouts = CalloutSystem.new()
	run.callouts.bind(run, net)
	run.add_system(run.callouts)
	run.dark = DarkSystem.new()
	run.dark.bind(run, net)
	run.add_system(run.dark)
	run.tells = OverheadTells.new()
	run.tells.bind(run)
	if mine != null:
		run.air_doors = AirDoorSystem.new()
		run.air_doors.bind(run)
		run.add_system(run.air_doors)
	# GEN-13: after every owner, so a committed cell replays once their own load hooks have run.
	if run.vision != null:
		run.vision.trail_changed.connect(func(tile: Vector2i, direction: int) -> void:
			if direction < 0:
				run.diff_log.erase_blood(tile)
			else:
				run.diff_log.mark_blood(tile, direction))
		run.diff_log.register(DiffLog.Kind.BLOOD, func(r: RunState, _cell: Vector2i, _key: String, p: Dictionary, _t: int) -> void:
			for raw: Variant in Variants.array(p["smears"]):
				var smear: Dictionary = raw
				var tile: Vector2i = smear["tile"]
				var direction: int = int(Variants.number(smear["direction"]))
				# Usually still in the vision's memory (it outlives the cell): only a resume needs it.
				if int(Variants.number(r.vision.trails.get(tile, -1))) != direction:
					r.vision.mark_trail(tile, direction))
	run.diff_log.bind(run)
	run.add_system(run.diff_log)
	# NET-07: last, so every signal it listens to exists.
	# NET-11: drops by the miner's state, and retaking the seat.
	run.drops = DropHandler.new()
	run.drops.bind(run, net)
	run.add_system(run.drops)
	# NET-09: snapshots every 30 s, the journal, knock-off saves (never in public).
	run.saves = Saves.new()
	run.saves.bind(run, net)
	run.add_system(run.saves)
	run.record = RunRecord.new()
	run.record.bind(run, net)
	run.add_system(run.record)
	# FND-08: dev and QA servers only; server/debug/ is not in a release pack.
	if net.flavour != BuildInfo.Flavour.RELEASE and ResourceLoader.exists(DEBUG_INSTALL):
		var installer: GDScript = load(DEBUG_INSTALL)
		installer.call(&"install", run, net)
