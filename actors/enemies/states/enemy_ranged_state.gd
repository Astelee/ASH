class_name EnemyRangedState
extends EnemyState

## Throwing rather than swinging. The Crow-Mask Cultist.
##
## The wind-up is deliberately long and the arc is deliberately visible: a ranged enemy the player
## cannot see coming is not a threat to read, it is a tax.

var _move: AttackMove
var _elapsed: float = 0.0
var _thrown: bool = false


func enter(_previous: StringName) -> void:
	_elapsed = 0.0
	_thrown = false
	_move = enemy.data.moveset[0] if not enemy.data.moveset.is_empty() else null
	enemy.active_move = _move
	enemy.face_target()


func exit() -> void:
	enemy.active_move = null
	enemy.release_attack_token()


func physics_update(delta: float) -> StringName:
	if _move == null or enemy.data.projectile_scene == null:
		return Enemy.STATE_REPOSITION

	_elapsed += delta
	enemy.velocity.x = move_toward(enemy.velocity.x, 0.0, 30.0 * delta)

	if not _thrown and _elapsed >= _move.windup:
		_thrown = true
		_throw()

	if _elapsed >= _move.duration():
		return Enemy.STATE_RECOVER
	return &""


func _throw() -> void:
	var victim := enemy.resolve_target()
	if victim == null:
		return
	var packet := enemy.build_damage_packet()
	if packet == null:
		return

	var flask := enemy.data.projectile_scene.instantiate() as Projectile
	if flask == null:
		return
	enemy.get_parent().add_child(flask)

	var origin := enemy.global_position + Vector3(0.0, 1.2, 0.0)
	# Aim at the chest, not the feet: the arc has to end where the player is, not under them.
	flask.launch(origin, victim.global_position + Vector3(0.0, 0.9, 0.0), packet)
