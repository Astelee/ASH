class_name EnemyDeadState
extends EnemyState

## Terminal. Disables collision so the corpse stops blocking movement, then waits for the dissolve
## budget before freeing. Phase 4 replaces the delay with the dissolve shader.

## Seconds the body remains before being freed.
const LINGER: float = 1.6

var _elapsed: float = 0.0


func enter(_previous: StringName) -> void:
	_elapsed = 0.0
	enemy.hitbox.disarm()
	enemy.hurtbox.monitorable = false
	enemy.velocity.x = 0.0
	enemy.set_collision_layer_value(3, false)


func physics_update(delta: float) -> StringName:
	_elapsed += delta
	enemy.velocity.x = move_toward(enemy.velocity.x, 0.0, 30.0 * delta)
	if _elapsed >= LINGER:
		enemy.queue_free()
	return &""
