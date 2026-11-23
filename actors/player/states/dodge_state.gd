class_name PlayerDodgeState
extends PlayerState

## The roll. Invulnerable from [member CombatTuning.iframe_start] to
## [member CombatTuning.iframe_end], extended by Finesse.
##
## i-frames are a window inside the roll, not the whole roll — the startup and the recovery are both
## punishable, which is what stops rolling from being a universal answer.

var _elapsed: float = 0.0
var _speed: float = 0.0
var _direction: int = 1


func enter(_previous: StringName) -> void:
	var tuning := player.combat_tuning
	_elapsed = 0.0
	_direction = player.facing
	var intent := player.move_intent()
	if not is_zero_approx(intent):
		_direction = 1 if intent > 0.0 else -1
		player.set_facing(_direction)
	_speed = tuning.dodge_distance / tuning.dodge_duration
	player.combatant.spend_stamina(tuning.dodge_stamina)


func exit() -> void:
	player.hurtbox.invulnerable = false


func physics_update(delta: float) -> StringName:
	var tuning := player.combat_tuning
	_elapsed += delta

	var window_end := tuning.iframe_end + player.combatant.stats.iframe_bonus()
	player.hurtbox.invulnerable = _elapsed >= tuning.iframe_start and _elapsed <= window_end

	player.velocity.x = float(_direction) * _speed
	if player.is_on_floor():
		player.velocity.y = -player.tuning.floor_stick_speed
	else:
		player.apply_gravity(delta)

	if _elapsed >= tuning.dodge_duration:
		return Player.STATE_IDLE
	return &""
