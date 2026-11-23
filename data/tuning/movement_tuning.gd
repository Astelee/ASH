class_name MovementTuning
extends Resource

## Every number that decides how the player moves. Authored in
## [code]res://data/tuning/tuning_movement.tres[/code].
##
## Source of truth is [code]docs/GDD.md §5[/code]. Nothing in this table may appear as a literal in
## a script — if you would ever want to change it without a rebuild, it lives here.

@export_group("Ground")

## Default locomotion speed, m/s.
@export var walk_speed: float = 3.2

## Held-sprint speed, m/s.
@export var sprint_speed: float = 6.0

## How long the dodge button must be held before it becomes a sprint rather than a roll, seconds.
## The spec's input map has no sprint action, so sprint is a held dodge — the genre convention, and
## the reason a tap can still mean roll once Phase 2 adds it.
@export var sprint_hold_threshold: float = 0.18

## How fast the player reaches target speed on the ground, m/s².
@export var ground_accel: float = 45.0

## How fast the player sheds speed on the ground, m/s². Higher than accel so stopping reads as
## deliberate rather than slippery.
@export var ground_decel: float = 60.0

## Steepest surface the player can stand and walk on, degrees. Anything steeper is a slide.
@export_range(0.0, 89.0, 1.0, "degrees") var max_slope_deg: float = 46.0

## Constant downward speed held while grounded, m/s. Keeps [method CharacterBody3D.is_on_floor]
## true across slopes and small steps without letting gravity accumulate into a huge stored value.
@export var floor_stick_speed: float = 2.0

@export_group("Air")

## Fraction of [member ground_accel] available while airborne. 0.35 keeps jumps committed without
## making them feel like rails.
@export_range(0.0, 1.0, 0.01) var air_control: float = 0.35

## Peak height of a full jump, metres. [member jump_velocity] is derived from this and gravity, so
## tune the height you want to see and let the physics follow.
@export var jump_apex_height: float = 2.2

## Downward acceleration while rising, m/s². Matches
## [code]physics/3d/default_gravity[/code].
@export var gravity: float = 22.0

## Gravity multiplier once vertical velocity turns negative. > 1 makes the fall snappier than the
## rise, which is what makes a jump feel good rather than floaty.
@export var fall_gravity_multiplier: float = 1.6

## Downward speed cap, m/s.
@export var terminal_velocity: float = 40.0

@export_group("Forgiveness")

## Grace period after walking off a ledge during which a jump still works, seconds.
@export var coyote_time: float = 0.12

## How long before landing a jump press is remembered and fired on touchdown, seconds.
@export var jump_buffer: float = 0.15

@export_group("Ledges")

## How far ahead of the player a grabbable ledge is detected, metres.
@export var ledge_reach_forward: float = 0.5

## How far below grab height the ledge surface may sit and still be caught, metres.
@export var ledge_reach_down: float = 0.3

## Height above the player's feet at which the ledge is grabbed, metres. Roughly chest height.
@export var ledge_grab_height: float = 1.2

## How far back from the lip the body hangs while holding on, metres. Should exceed the capsule
## radius or the hang pose clips into the wall.
@export var ledge_hang_offset: float = 0.45

## How far past the lip the climb-up places the player, metres. Too small and they clip the corner
## and fall straight back off.
@export var ledge_climb_offset: float = 0.5

@export_group("Landing")

## Movement lockout after a normal landing, seconds.
@export var landing_recovery: float = 0.10

## Movement lockout after a fall past [member fall_damage_threshold], seconds.
@export var hard_landing_recovery: float = 0.28

## Fall distance above which landings hurt and become hard landings, metres.
@export var fall_damage_threshold: float = 6.0

## HP lost per metre fallen beyond [member fall_damage_threshold].
@export var fall_damage_per_metre: float = 8.0


## Initial upward velocity that reaches exactly [member jump_apex_height], m/s.
##
## The textbook answer is [code]sqrt(2 · g · h)[/code] = 9.8387, but that is the velocity for
## [i]continuous[/i] motion, and we integrate in discrete 60 Hz steps with gravity applied before
## the move. Each step therefore travels at the velocity from the [i]end[/i] of the interval rather
## than its midpoint, and the jump tops out at 2.118 m instead of 2.2 — a 3.7 % shortfall that no
## amount of staring at the tuning file would explain.
##
## Adding back half a step of gravity makes each step travel at its midpoint velocity, which is
## exact for constant acceleration. Measured apex after the correction: 2.1999 m.
func jump_velocity() -> float:
	var step := 1.0 / float(Engine.physics_ticks_per_second)
	return sqrt(2.0 * gravity * jump_apex_height) + gravity * step * 0.5


## Gravity to apply this frame, m/s². [param rising] selects the lighter rising value.
func gravity_for(rising: bool) -> float:
	return gravity if rising else gravity * fall_gravity_multiplier


## Ground acceleration scaled for the airborne case, m/s².
func accel_for(grounded: bool) -> float:
	return ground_accel if grounded else ground_accel * air_control


## HP lost for a fall of [param distance] metres. Zero at or below the threshold.
func fall_damage_for(distance: float) -> float:
	return maxf(0.0, (distance - fall_damage_threshold) * fall_damage_per_metre)
