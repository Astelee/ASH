class_name PlayerLandState
extends PlayerState

## Touchdown recovery. Length depends on the drop: a normal landing costs
## [member MovementTuning.landing_recovery], a fall past the damage threshold costs
## [member MovementTuning.hard_landing_recovery] and hurts.
##
## Horizontal control is off for the duration. That lockout is the only thing making height feel
## like a commitment rather than a free traversal option.

var _remaining: float = 0.0


func enter(_previous: StringName) -> void:
	var hard := player.fall_distance > player.tuning.fall_damage_threshold
	_remaining = player.tuning.hard_landing_recovery if hard else player.tuning.landing_recovery


func physics_update(delta: float) -> StringName:
	player.velocity.y = -player.tuning.floor_stick_speed
	# Intent 0 rather than the player's actual input: this is a lockout, not sluggish steering.
	player.apply_horizontal(delta, 0.0)

	_remaining -= delta
	if _remaining > 0.0:
		return &""

	var transition := grounded_transitions()
	if transition != &"":
		return transition
	if not is_zero_approx(player.move_intent()):
		return Player.STATE_RUN
	return Player.STATE_IDLE
