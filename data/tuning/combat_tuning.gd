class_name CombatTuning
extends Resource

## Every combat number that is not part of a specific move. Authored in
## [code]res://data/tuning/tuning_combat.tres[/code]. Source of truth is
## [code]docs/GDD.md §6[/code].

@export_group("Dodge")

## Total roll duration, seconds.
@export var dodge_duration: float = 0.50

## Seconds into the roll at which invulnerability begins.
@export var iframe_start: float = 0.08

## Seconds into the roll at which invulnerability ends. Finesse extends this.
@export var iframe_end: float = 0.32

## Ground distance covered by a medium-weight roll, metres.
@export var dodge_distance: float = 3.4

## Stamina spent on a roll.
@export var dodge_stamina: float = 20.0

@export_group("Block & parry")

## Parry window on a low-latency device, seconds.
@export var parry_window_button: float = 0.18

## Parry window on touch, seconds. **Unvalidated** — see [code]docs/TECH.md §6[/code]; Phase 2 must
## measure real touch latency and re-derive this rather than trusting the estimate.
@export var parry_window_touch: float = 0.24

## How long a parried attacker stays riposte-vulnerable, seconds.
@export var riposte_window: float = 1.5

## Stamina refunded to the defender on a successful parry.
@export var parry_stamina_gain: float = 15.0

## Flat stamina cost of absorbing a blocked hit, before stability.
@export var block_stamina_flat: float = 15.0

## Additional stamina per point of raw incoming damage, before stability.
@export var block_stamina_per_damage: float = 0.5

## Stagger duration when stamina is emptied by a block, seconds.
@export var guard_break_stagger: float = 1.2

@export_group("Poise")

## Damage multiplier on a riposte or a hit against a staggered target.
@export var riposte_multiplier: float = 2.2

## Stagger duration when poise breaks, seconds.
@export var poise_break_stagger: float = 1.4

## Player poise recovered per second.
@export var player_poise_regen: float = 25.0

## Idle seconds before player poise begins recovering.
@export var player_poise_delay: float = 1.0

## Enemy poise recovered per second.
@export var enemy_poise_regen: float = 15.0

## Idle seconds before enemy poise begins recovering.
@export var enemy_poise_delay: float = 2.0

@export_group("Hitstop")

## Freeze on a light hit, seconds.
@export var hitstop_light: float = 0.060

## Freeze on a heavy hit, seconds.
@export var hitstop_heavy: float = 0.110

## Freeze on a riposte or a killing blow, seconds.
@export var hitstop_riposte: float = 0.180

@export_group("Scheduling")

## Maximum enemies allowed in the Attack state at once, per encounter. The single system that
## separates a fair fight from a pile-on.
@export var attack_tokens: int = 2

@export_group("Feedback")

## How long the shader hit flash stays lit, seconds.
@export var hit_flash_duration: float = 0.12

## Seconds a damage number lives before returning to the pool.
@export var damage_number_lifetime: float = 0.9


## Parry window for the currently active input device. Touch gets a wider window because Android
## touch-to-photon latency would otherwise leave ~80 ms to parry a mechanic the Warden requires.
func parry_window_for_touch(is_touch: bool) -> float:
	return parry_window_touch if is_touch else parry_window_button


## Hitstop for a hit of the given weight.
func hitstop_for(is_heavy: bool, is_riposte: bool) -> float:
	if is_riposte:
		return hitstop_riposte
	return hitstop_heavy if is_heavy else hitstop_light
