class_name EnemyRecoverState
extends EnemyState

## The punish window. The enemy is committed and vulnerable, which is what makes a dodge worth
## timing rather than spamming.

var _remaining: float = 0.0


func enter(_previous: StringName) -> void:
	_remaining = enemy.data.recover_time


func physics_update(delta: float) -> StringName:
	_remaining -= delta
	enemy.velocity.x = move_toward(enemy.velocity.x, 0.0, enemy.data.move_speed * 4.0 * delta)
	if _remaining <= 0.0:
		return Enemy.STATE_REPOSITION
	return &""
