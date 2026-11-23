class_name PlayerFallState
extends PlayerState

## Airborne and descending. Owns three exits, and their order is the whole feel of the state:
##
## [br]1. A [b]buffered jump on the landing frame[/b] fires immediately rather than going through
##    [PlayerLandState]. Routing it through the landing lockout would swallow the press, which is
##    exactly what the buffer exists to prevent.
## [br]2. A [b]coyote jump[/b], for the window after walking off a ledge.
## [br]3. A [b]ledge grab[/b], checked before landing so a lip catches instead of a long drop.


func physics_update(delta: float) -> StringName:
	player.apply_gravity(delta)
	player.apply_horizontal(delta, player.move_intent())

	if player.is_on_floor():
		if player.has_buffered_jump():
			return Player.STATE_JUMP
		return Player.STATE_LAND

	if player.has_buffered_jump() and player.has_coyote():
		return Player.STATE_JUMP

	if player.find_ledge():
		return Player.STATE_LEDGE_GRAB

	return &""
