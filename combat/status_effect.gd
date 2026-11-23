class_name StatusEffect
extends Resource

## Base for timed effects applied to a [Combatant] — rot build-up, bleed, buffs from a Bell-Bearer.
##
## Carried on a [DamagePacket] and applied by whatever receives the hit; tracked per-target by a
## [StatusTracker] inside the [Combatant]. Concrete effects are [code].tres[/code] files under
## [code]data/status/[/code] — subclassing is only needed for an effect whose [method on_apply] has
## to do something beyond damage over time.
##
## Build-up, not damage-over-time: nothing happens until [member stacks_to_trigger] applications
## land. That threshold is what makes the effect a resource the player manages by retreating.

## Identifier, used for stacking rules and HUD icons.
@export var id: StringName = &"none"

## Display name.
@export var display_name: String = "Unnamed"

## Total lifetime, seconds. Zero means instantaneous.
@export var duration: float = 5.0

## Damage school this effect deals, if any.
@export var damage_type: DamagePacket.Type = DamagePacket.Type.ROT

## Damage per second while active. Zero for pure buffs and debuffs.
@export var damage_per_second: float = 0.0

## Applications needed before the effect triggers. Build-up meters like Rot use this.
@export var stacks_to_trigger: int = 1

## Whether reapplying refreshes the timer rather than adding a stack.
@export var refreshes: bool = true


## Damage this effect deals over [param delta] seconds.
func tick_damage(delta: float) -> float:
	return damage_per_second * delta


## Applied when the effect first triggers. Override in concrete effects.
func on_apply(_target: Combatant) -> void:
	pass


## Applied when the effect expires or is cleansed. Override in concrete effects.
func on_expire(_target: Combatant) -> void:
	pass
