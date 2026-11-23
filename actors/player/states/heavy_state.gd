class_name PlayerHeavyState
extends PlayerState

## Heavy attack, chargeable to [member AttackMove.charge_max] for x1.8 damage and a guaranteed poise
## break.
##
## The charge accumulates during windup and the swing releases on button release or at full charge,
## whichever comes first. Holding past full gains nothing — the tell has to stay honest, or the
## enemy cannot read it.

var _elapsed: float = 0.0
var _charge: float = 0.0
var _charging: bool = true
var _armed: bool = false


func enter(_previous: StringName) -> void:
	_elapsed = 0.0
	_charge = 0.0
	_charging = true
	_armed = false
	player.active_move = player.heavy_move
	player.active_charge = 1.0
	player.combatant.spend_stamina(player.heavy_move.stamina_cost)


func exit() -> void:
	player.hitbox.disarm()
	player.active_move = null
	player.active_charge = 1.0
	_armed = false


func physics_update(delta: float) -> StringName:
	var move := player.heavy_move

	if _charging:
		_charge += delta
		if not Input.is_action_pressed(&"attack_heavy") or _charge >= move.charge_max:
			_charging = false
			player.active_charge = move.charge_multiplier_for(_charge)
	else:
		_elapsed += delta

	player.velocity.x = move_toward(player.velocity.x, 0.0, 60.0 * delta)
	if player.is_on_floor():
		player.velocity.y = -player.tuning.floor_stick_speed
	else:
		player.apply_gravity(delta)

	if not _charging:
		var active := move.is_active_at(_elapsed)
		if active and not _armed:
			player.hitbox.arm(move, player.facing)
			_armed = true
		elif not active and _armed:
			player.hitbox.disarm()
			_armed = false

		if _elapsed >= move.duration():
			return Player.STATE_IDLE

	return &""
