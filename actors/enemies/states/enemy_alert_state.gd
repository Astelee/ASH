class_name EnemyAlertState
extends EnemyState

## The moment of noticing. A deliberate beat before closing, so the player gets a readable cue that
## something has woken up rather than being charged from off-screen.

## Seconds spent reacting before the approach begins.
const REACT_TIME: float = 0.45

var _elapsed: float = 0.0


func enter(_previous: StringName) -> void:
	_elapsed = 0.0
	enemy.velocity.x = 0.0
	enemy.face_target()


func physics_update(delta: float) -> StringName:
	_elapsed += delta
	enemy.velocity.x = 0.0
	if _elapsed >= REACT_TIME:
		return Enemy.STATE_APPROACH
	return &""
