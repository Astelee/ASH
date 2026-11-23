class_name EnemyStaggerState
extends EnemyState

## Poise broken or parried. Open to a riposte for the duration.

var _remaining: float = 0.0


func enter(_previous: StringName) -> void:
	enemy.hitbox.disarm()
	enemy.velocity.x = 0.0
	_remaining = maxf(enemy.combat_tuning.poise_break_stagger, enemy.riposte_vulnerable)


func exit() -> void:
	enemy.combatant.recover_stagger()


func physics_update(delta: float) -> StringName:
	_remaining -= delta
	enemy.velocity.x = move_toward(enemy.velocity.x, 0.0, 20.0 * delta)
	if _remaining <= 0.0:
		return Enemy.STATE_REPOSITION
	return &""
