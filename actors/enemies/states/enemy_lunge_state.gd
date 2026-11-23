class_name EnemyLungeState
extends EnemyState

## The Gravewretch's pounce.
##
## Fires from beyond comfortable reading distance and covers ground fast. In the shipped game the
## tell is audio -- a rattle half a second before it commits -- which is Phase 8's job. The timing
## window exists here so that hooking the sound up later changes nothing about the behaviour.

## Seconds of telegraph before the launch. Phase 8 plays the rattle across this window.
const TELL_TIME: float = 0.5

var _elapsed: float = 0.0
var _launched: bool = false


func enter(_previous: StringName) -> void:
	_elapsed = 0.0
	_launched = false
	enemy.face_target()
	enemy.velocity.x = 0.0
	EventBus.enemy_telegraphed.emit(enemy, &"gravewretch_lunge", TELL_TIME)


func exit() -> void:
	enemy.hitbox.disarm()
	enemy.active_move = null
	enemy.release_attack_token()


func physics_update(delta: float) -> StringName:
	_elapsed += delta

	if not _launched:
		# Dead still through the tell. A wretch that drifts while winding up is unreadable.
		enemy.velocity.x = 0.0
		if _elapsed >= TELL_TIME:
			_launched = true
			enemy.velocity.x = float(enemy.facing) * enemy.data.lunge_speed
			enemy.velocity.y = 3.5
			if not enemy.data.moveset.is_empty():
				enemy.active_move = enemy.data.moveset[0]
				enemy.hitbox.arm(enemy.active_move, enemy.facing)
		return &""

	if enemy.is_on_floor() and _elapsed > TELL_TIME + 0.15:
		return Enemy.STATE_RECOVER
	return &""
