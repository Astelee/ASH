class_name EnemyIdleState
extends EnemyState

## Unaware. Holds position until the player comes inside detect range.


func enter(_previous: StringName) -> void:
	enemy.velocity.x = 0.0


func physics_update(delta: float) -> StringName:
	enemy.velocity.x = move_toward(enemy.velocity.x, 0.0, enemy.data.move_speed * 4.0 * delta)
	if enemy.distance_to_target() <= enemy.data.detect_range:
		return Enemy.STATE_ALERT
	return &""
