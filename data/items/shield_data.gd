class_name ShieldData
extends Resource

## A shield: per-school damage absorption, and a stability base that decides stamina cost.
##
## Two independent numbers on purpose ([code]docs/GDD.md §6.1b[/code]). **Absorption** belongs to
## the shield alone and never scales with a stat — a 95 % greatshield is a gear decision, not a
## build decision. **Stability** is where Might pays off, as that stat's description promises.

## Ceiling on stability, so blocking is never free no matter how much Might is invested.
const MAX_STABILITY: float = 0.70

## Stability gained per point of Might.
const STABILITY_PER_MIGHT: float = 0.006

## Display name.
@export var display_name: String = "Unnamed"

## Equip weight.
@export var weight: float = 4.5

@export_group("Absorption")

## Fraction of incoming physical damage absorbed when blocking, 0–0.95.
@export_range(0.0, 0.95, 0.01) var absorb_physical: float = 0.65

@export_range(0.0, 0.95, 0.01) var absorb_fire: float = 0.35

@export_range(0.0, 0.95, 0.01) var absorb_rot: float = 0.30

@export_range(0.0, 0.95, 0.01) var absorb_holy: float = 0.30

@export_group("Stability")

## Stamina-cost reduction before Might is applied.
@export_range(0.0, 0.7, 0.01) var stability_base: float = 0.30


## Absorption fraction for [param type].
func absorption_for(type: DamagePacket.Type) -> float:
	match type:
		DamagePacket.Type.PHYSICAL:
			return absorb_physical
		DamagePacket.Type.FIRE:
			return absorb_fire
		DamagePacket.Type.ROT:
			return absorb_rot
		DamagePacket.Type.HOLY:
			return absorb_holy
	return 0.0


## Stamina-cost reduction for a wielder with [param might], clamped to [constant MAX_STABILITY].
func stability_for(might: int) -> float:
	return clampf(stability_base + float(might) * STABILITY_PER_MIGHT, 0.0, MAX_STABILITY)
