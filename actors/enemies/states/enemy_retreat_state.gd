class_name EnemyRetreatState
extends EnemyState

## Backing away from a player who has closed the distance. The Crow-Mask Cultist's whole defence.
##
## A ranged enemy that stands and fights once cornered is just a worse melee enemy. This one gives
## ground until it has room to throw again, which is what makes closing on it the correct answer.

## Multiplier on move speed while retreating. Below 1 so the player can always run it down.
const RETREAT_SPEED_SCALE: float = 0.85


func physics_update(_delta: float) -> StringName:
	var distance := enemy.distance_to_target()
	if distance == INF:
		return Enemy.STATE_IDLE

	enemy.face_target()

	if distance > enemy.data.retreat_range * 1.3:
		return Enemy.STATE_APPROACH

	var victim := enemy.resolve_target()
	var away := signf(enemy.global_position.x - victim.global_position.x)
	if is_zero_approx(away):
		away = 1.0
	enemy.velocity.x = away * enemy.data.move_speed * RETREAT_SPEED_SCALE
	return &""
