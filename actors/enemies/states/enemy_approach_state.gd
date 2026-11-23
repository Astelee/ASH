class_name EnemyApproachState
extends EnemyState

## Closing to attack range, then asking for a token.
##
## Requesting the token only once inside range keeps the queue meaningful — an enemy still walking
## across the arena has no business holding a slot.


func physics_update(delta: float) -> StringName:
	var distance := enemy.distance_to_target()
	if distance == INF:
		return Enemy.STATE_IDLE

	enemy.face_target()

	# A ranged enemy that has been closed on gives ground instead of committing. Standing and
	# fighting would make it a worse melee enemy rather than a different one.
	if enemy.should_retreat():
		return Enemy.STATE_RETREAT

	if distance <= enemy.commit_range():
		if enemy.request_attack_token():
			return enemy.commit_state()
		return Enemy.STATE_REPOSITION

	var target := enemy.resolve_target()
	var goal := target.global_position.x - float(enemy.facing) * enemy.data.attack_range * 0.8
	enemy.walk_toward(goal, 0.1, delta)
	return &""
