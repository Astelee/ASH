class_name PlayerDeathState
extends PlayerState

## Terminal. Phase 3 hangs the bloodstain and respawn flow off the EventBus signal emitted here;
## Phase 2 only needs the actor to stop.


func enter(_previous: StringName) -> void:
	player.is_blocking = false
	player.hurtbox.invulnerable = true
	player.hitbox.disarm()
	player.velocity = Vector3.ZERO
	EventBus.player_died.emit(player.global_position)


func physics_update(delta: float) -> StringName:
	player.velocity.x = move_toward(player.velocity.x, 0.0, player.tuning.ground_decel * delta)
	if not player.is_on_floor():
		player.apply_gravity(delta)
	return &""
