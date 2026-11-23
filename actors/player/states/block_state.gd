class_name PlayerBlockState
extends PlayerState

## Guard up. The first [member CombatTuning.parry_window_button] seconds are also the parry window —
## a parry is not a separate button, it is the start of a block.
##
## The window is device-dependent (0.18 s button, 0.24 s touch) because Android touch latency would
## otherwise leave roughly 80 ms of real reaction budget on a mechanic the Warden is designed to
## require. See docs/TECH.md §6.
##
## Resolution lives in [method Player.receive_hit]; this state only holds the flags and the clock.


func enter(_previous: StringName) -> void:
	player.is_blocking = true
	player.block_elapsed = 0.0


func exit() -> void:
	player.is_blocking = false
	player.block_elapsed = 0.0


func physics_update(delta: float) -> StringName:
	player.block_elapsed += delta

	# Blocking walks, it does not run. Committing to a guard has to cost mobility.
	var intent := player.move_intent()
	var creep := player.tuning.walk_speed * 0.4
	player.velocity.x = move_toward(
		player.velocity.x, intent * creep, player.tuning.ground_accel * delta
	)
	if player.is_on_floor():
		player.velocity.y = -player.tuning.floor_stick_speed
	else:
		player.apply_gravity(delta)

	if not Input.is_action_pressed(&"block"):
		return Player.STATE_IDLE
	if not player.is_on_floor():
		return Player.STATE_FALL
	return &""
