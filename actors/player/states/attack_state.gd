class_name PlayerAttackState
extends PlayerState

## The light-attack chain. One state drives all three steps by index rather than three
## near-identical states, because nothing about the behaviour differs — only the numbers,
## which are data.
##
## Windup / active / recovery are read from the [AttackMove], and the hitbox is armed and disarmed
## on those boundaries. Buffering the next step is allowed from the moment the active window
## closes; it fires when recovery ends, so a combo reads as continuous without letting input skip
## recovery.

var _index: int = 0
var _elapsed: float = 0.0
var _move: AttackMove
var _armed: bool = false
var _queued: bool = false


func enter(previous: StringName) -> void:
	if previous != Player.STATE_ATTACK:
		_index = 0
	_begin()


func exit() -> void:
	player.hitbox.disarm()
	player.active_move = null
	_armed = false
	_queued = false


func physics_update(delta: float) -> StringName:
	_elapsed += delta

	# Committed: no steering, and only the lunge carries the actor forward.
	var lunge := _move.lunge_speed if _elapsed < _move.windup + _move.active else 0.0
	player.velocity.x = move_toward(player.velocity.x, float(player.facing) * lunge, 40.0 * delta)
	if player.is_on_floor():
		player.velocity.y = -player.tuning.floor_stick_speed
	else:
		player.apply_gravity(delta)

	_drive_hitbox()

	if Input.is_action_just_pressed(&"attack_light") and _elapsed >= _move.windup + _move.active:
		_queued = true

	if _elapsed < _move.duration():
		return &""

	if _queued and _index + 1 < player.light_combo.size():
		_index += 1
		_begin()
		return &""

	return Player.STATE_IDLE


func handle_input(_event: InputEvent) -> StringName:
	return &""


func _begin() -> void:
	_move = player.light_combo[_index]
	_elapsed = 0.0
	_armed = false
	_queued = false
	player.active_move = _move
	player.active_charge = 1.0
	player.combatant.spend_stamina(_move.stamina_cost)


func _drive_hitbox() -> void:
	var should_be_active := _move.is_active_at(_elapsed)
	if should_be_active and not _armed:
		player.hitbox.arm(_move, player.facing)
		_armed = true
	elif not should_be_active and _armed:
		player.hitbox.disarm()
		_armed = false
