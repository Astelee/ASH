class_name EnemyReposition
extends EnemyState

## Circling at standoff distance while another enemy holds a token.
##
## This is where the attack-token system becomes visible: enemies without a turn hover at
## reposition_range instead of crowding, so the player always has somewhere to roll.


func physics_update(delta: float) -> StringName:
	var distance := enemy.distance_to_target()
	if distance == INF:
		return Enemy.STATE_IDLE

	enemy.face_target()

	if enemy.should_retreat():
		return Enemy.STATE_RETREAT

	if enemy.request_attack_token() and distance <= enemy.commit_range() * 1.2:
		return enemy.commit_state()

	var target := enemy.resolve_target()
	var side := signf(enemy.global_position.x - target.global_position.x)
	if is_zero_approx(side):
		side = 1.0
	var goal := target.global_position.x + side * enemy.data.reposition_range
	enemy.walk_toward(goal, 0.35, delta)

	if distance > enemy.data.detect_range * 1.5:
		enemy.release_attack_token()
		return Enemy.STATE_IDLE
	return &""
