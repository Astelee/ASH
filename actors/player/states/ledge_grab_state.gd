class_name PlayerLedgeGrabState
extends PlayerState

## Hanging from a lip. Gravity is off and position is pinned, so this is the one state where the
## player is airborne but not falling.
##
## Two exits: jump climbs up, steering away lets go. Letting go is deliberate rather than
## automatic — a grab that drops you the instant your thumb wobbles is worse than no grab at all.

## Steering must exceed this, away from the wall, to release. Above joystick noise, below any
## deliberate push.
const RELEASE_INTENT: float = 0.5

var _lip: Vector3 = Vector3.ZERO


func enter(_previous: StringName) -> void:
	_lip = player.ledge_point()
	player.velocity = Vector3.ZERO

	# Pin the body so the hands read as being on the lip regardless of where the grab triggered.
	player.global_position = Vector3(
		_lip.x - float(player.facing) * player.tuning.ledge_hang_offset,
		_lip.y - player.tuning.ledge_grab_height,
		0.0
	)
	# Landing from a climb should never be treated as a fall.
	player.fall_distance = 0.0


func physics_update(_delta: float) -> StringName:
	player.velocity = Vector3.ZERO

	if player.has_buffered_jump():
		_climb()
		return Player.STATE_IDLE

	var intent := player.move_intent()
	if absf(intent) > RELEASE_INTENT and signf(intent) != signf(float(player.facing)):
		return Player.STATE_FALL

	return &""


func _climb() -> void:
	player.global_position = Vector3(
		_lip.x + float(player.facing) * player.tuning.ledge_climb_offset, _lip.y, 0.0
	)
	player.velocity = Vector3.ZERO
