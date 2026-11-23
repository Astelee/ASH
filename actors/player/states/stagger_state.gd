class_name PlayerStaggerState
extends PlayerState

## Poise broken or guard broken. Fully committed, no input, and the next hit taken is riposte-tier.
##
## Entered by signal from [Combatant] rather than by a transition check, because the break happens
## inside damage resolution and the state machine must not have to poll for it.

var _remaining: float = 0.0


func enter(_previous: StringName) -> void:
	_remaining = player.combat_tuning.poise_break_stagger
	player.is_blocking = false
	EventBus.poise_broken.emit(player)


func exit() -> void:
	player.combatant.recover_stagger()


func physics_update(delta: float) -> StringName:
	_remaining -= delta
	player.velocity.x = move_toward(player.velocity.x, 0.0, player.tuning.ground_decel * delta)
	if player.is_on_floor():
		player.velocity.y = -player.tuning.floor_stick_speed
	else:
		player.apply_gravity(delta)

	if _remaining <= 0.0:
		return Player.STATE_IDLE
	return &""
