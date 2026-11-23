class_name PlayerRunState
extends PlayerState

## Grounded and moving. Covers both walk and sprint — the speed difference is a tuning value, not a
## separate state, because nothing else about the behaviour changes.

## Below this speed with no input, the player has effectively stopped. Not a tuning value: it is a
## floating-point epsilon, not a design decision.
const STOP_EPSILON: float = 0.05


func physics_update(delta: float) -> StringName:
	player.velocity.y = -player.tuning.floor_stick_speed

	var intent := player.move_intent()
	player.apply_horizontal(delta, intent)

	var transition := grounded_transitions()
	if transition != &"":
		return transition
	if is_zero_approx(intent) and absf(player.velocity.x) < STOP_EPSILON:
		return Player.STATE_IDLE
	return &""
