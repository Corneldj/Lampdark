class_name BatteryRack
extends RefCounted
## LFT-01: after Power, basecamp.battery_rack_slots slots (Proposed 2), each charging an electric
## hand lamp linearly from empty to full in basecamp.battery_rack_full_charge_s. Behind MNR-08's
## feature flag (cut with the electric lamp).

var tile: Vector2i = Vector2i.ZERO
## slot -> charge 0-1 of the lamp in it (absent: empty slot)
var slots: Dictionary = {}


func install(seed_value: int, side: int) -> void:
	tile = Basecamp.fixture(seed_value, "battery_rack", side)[0]["position"]


func put(powered: bool, slot: int, charge: float) -> bool:
	if not powered or slot < 0 or slot >= Tuning.i(&"basecamp.battery_rack_slots") or slots.has(slot):
		return false
	slots[slot] = clampf(charge, 0.0, 1.0)
	return true


func take(slot: int) -> float:
	var c: float = Variants.number(slots.get(slot, -1.0))
	slots.erase(slot)
	return c


func tick(powered: bool) -> void:
	if not powered:
		return
	var step: float = 1.0 / (Tuning.f(&"basecamp.battery_rack_full_charge_s") * Tuning.f(&"net.tick_hz"))
	for raw: Variant in slots.keys():
		slots[raw] = minf(1.0, Variants.number(slots[raw]) + step)
