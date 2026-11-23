class_name PlayerIdleState
extends PlayerState

## Grounded and not asking to move. Still decelerates, so arriving here at speed slides to a stop
## rather than snapping.


func physics_update(delta: float) -> StringName:
	player.velocity.y = -player.tuning.floor_stick_speed

	var intent := player.move_intent()
	player.apply_horizontal(delta, intent)

	var transition := grounded_transitions()
	if transition != &"":
		return transition
	if not is_zero_approx(intent):
		return Player.STATE_RUN
	return &""
