extends RefCounted
## LFT-12's tests: phones on a fixture's road, numbered as their first generation would number them
## and given their road home (no generated mine lies under a fixture: GEN-05's routing has its own
## tests), with power on or off.

const Scenario = preload("res://tests/scenario/kit/scenario.gd")
const MinerHandle = preload("res://tests/scenario/kit/miner_handle.gd")
const FixtureMap = preload("res://tests/scenario/kit/fixture_map.gd")


## A road 3 tiles high and `length` long, spots a (west) and b (east).
static func road(length: int = 40) -> FixtureMap:
	var rows: PackedStringArray = ["#".repeat(length)]
	rows.append("#" + ".".repeat(length - 2) + "#")
	rows.append("#a" + ".".repeat(length - 4) + "b#")
	rows.append("#" + ".".repeat(length - 2) + "#")
	rows.append("#".repeat(length))
	return FixtureMap.from_ascii(rows)


## A phone first generated at `tile` with its road home (crossing `crossings`), its entity made.
static func phone(s: Scenario, id: String, tile: Vector2i, crossings: Array = [], routed: bool = true) -> PitPhone:
	var p: PitPhone = s.run.phones.meet(s.run, id, tile, {"found": routed, "tiles": 12, "cells": [WorldCoords.cell_of(tile)], "crossings": crossings})
	var e: int = s.run.registry.create(WorldIds.EntityKind.PHONE, Vector2(tile) + Vector2(0.5, 0.5)).id
	s.run.phones.attach(s.run, id, e)
	return p


static func power(s: Scenario, on: bool = true) -> void:
	s.run.power.switch_closed = on


## A miner standing still at a tile's centre.
static func miner(s: Scenario, name: String, tile: Vector2i) -> MinerHandle:
	var h: MinerHandle = s.add_miner(name, tile)
	h.brain = null
	return h


## Holds interact `ticks` (a fresh press: works the phone in reach), then lets go.
static func press(s: Scenario, h: MinerHandle, ticks: int = 4) -> void:
	h.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, ticks)
	s.step(ticks + 4)


static func events_of(s: Scenario, type: NoiseTypes.Type) -> Array[NoiseSystem.Event]:
	var out: Array[NoiseSystem.Event] = []
	for e: NoiseSystem.Event in s.run.noise.event_log:
		if e.type == type:
			out.append(e)
	return out
