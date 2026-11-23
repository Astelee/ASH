class_name PlayerJumpState
extends PlayerState

## Rising. Ends the moment vertical velocity turns over, handing off to [PlayerFallState] — the
## heavier fall gravity lives there, and that asymmetry is most of what makes the jump feel good.


func enter(_previous: StringName) -> void:
	player.do_jump()


func physics_update(delta: float) -> StringName:
	player.apply_gravity(delta)
	player.apply_horizontal(delta, player.move_intent())

	if player.velocity.y <= 0.0:
		return Player.STATE_FALL
	return &""
