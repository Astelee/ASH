class_name AttackMove
extends Resource

## One attack in a moveset: its timing, its multipliers, and the volume it swings.
##
## Shared by the player and every enemy — an enemy's "telegraphed overhead" and the player's light-1
## are the same structure with different numbers. That is what keeps the attack state machine single
## and data-driven rather than one implementation per actor.

## Animation clip name. Must exist in [code]docs/ANIMATIONS.md[/code] — never invented here.
@export var anim: StringName = &"attack_light_1"

@export_group("Timing")

## Telegraph, seconds. The window in which the move is readable and still punishable.
@export var windup: float = 0.30

## Hitbox-enabled window, seconds.
@export var active: float = 0.10

## Committed recovery, seconds. This is what makes a whiff cost something.
@export var recovery: float = 0.35

## Seconds after [member active] ends during which the next combo step may be queued. Zero means the
## move does not chain.
@export var combo_window: float = 0.45

## Maximum hold time for a chargeable move, seconds. Zero means not chargeable.
@export var charge_max: float = 0.0

## Damage multiplier at full charge.
@export var charge_multiplier: float = 1.8

@export_group("Effect")

## Move multiplier from [code]docs/GDD.md §6.2[/code].
@export var damage_multiplier: float = 1.0

## Poise damage dealt on hit.
@export var poise_damage: float = 12.0

## Stamina spent on startup.
@export var stamina_cost: float = 12.0

## When true this move always breaks poise regardless of the target's pool (charged heavy).
@export var guaranteed_poise_break: bool = false

## Damage school. Usually inherited from the weapon; set only for moves that differ.
@export var override_damage_type: bool = false

@export var damage_type: DamagePacket.Type = DamagePacket.Type.PHYSICAL

@export_group("Hitbox")

## Hitbox centre relative to the actor, metres. X is forward-relative and mirrors with facing.
@export var hitbox_offset: Vector3 = Vector3(0.9, 1.0, 0.0)

## Hitbox extents, metres.
@export var hitbox_size: Vector3 = Vector3(1.4, 1.2, 1.0)

@export_group("Motion")

## Forward lunge applied over the windup, m/s.
@export var lunge_speed: float = 0.0


## Total committed duration, seconds.
func duration() -> float:
	return windup + active + recovery


## True while [param elapsed] falls inside the active window.
func is_active_at(elapsed: float) -> bool:
	return elapsed >= windup and elapsed < windup + active


## Charge multiplier for a hold of [param held] seconds. 1.0 when the move is not chargeable, and
## interpolated up to [member charge_multiplier] at full hold.
func charge_multiplier_for(held: float) -> float:
	if charge_max <= 0.0:
		return 1.0
	return lerpf(1.0, charge_multiplier, clampf(held / charge_max, 0.0, 1.0))


## True when a hold of [param held] seconds guarantees a poise break.
func breaks_poise_at(held: float) -> bool:
	if guaranteed_poise_break:
		return true
	return charge_max > 0.0 and held >= charge_max
