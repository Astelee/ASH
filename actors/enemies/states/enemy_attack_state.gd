class_name EnemyAttackState
extends EnemyState

## One swing from the moveset, arming the hitbox across its active window.
##
## Releases the token in [method exit] rather than at the end of recovery, so every path out — a
## finished swing, a poise break, a parry, death — returns it exactly once.

var _move: AttackMove
var _elapsed: float = 0.0
var _armed: bool = false


func enter(_previous: StringName) -> void:
	# The shield comes down to swing. A Warden that guards while attacking has no opening at all,
	# and "must be parried or flanked" would become "cannot be fought".
	enemy.guard_up = false
	_elapsed = 0.0
	_armed = false
	_move = _pick_move()
	enemy.active_move = _move
	enemy.face_target()


func exit() -> void:
	enemy.guard_up = true
	enemy.hitbox.disarm()
	enemy.active_move = null
	enemy.release_attack_token()
	_armed = false


func physics_update(delta: float) -> StringName:
	if _move == null:
		return Enemy.STATE_REPOSITION

	_elapsed += delta
	var lunging := _elapsed < _move.windup + _move.active
	enemy.velocity.x = move_toward(
		enemy.velocity.x,
		float(enemy.facing) * (_move.lunge_speed if lunging else 0.0),
		30.0 * delta
	)

	var active := _move.is_active_at(_elapsed)
	if active and not _armed:
		enemy.hitbox.arm(_move, enemy.facing)
		_armed = true
	elif not active and _armed:
		enemy.hitbox.disarm()
		_armed = false

	if _elapsed >= _move.duration():
		return Enemy.STATE_RECOVER
	return &""


func _pick_move() -> AttackMove:
	if enemy.data.moveset.is_empty():
		return null
	return enemy.data.moveset[randi() % enemy.data.moveset.size()]
