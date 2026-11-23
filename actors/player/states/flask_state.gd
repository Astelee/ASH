class_name PlayerFlaskState
extends PlayerState

## Drinking the Ashen Flask. Fully committed: walk speed only, no dodge cancel.
##
## The heal lands at [constant HEAL_AT], halfway through a [constant DURATION] animation — not on
## the first frame. That single number is what makes healing a decision rather than a reflex:
## drinking inside an enemy's attack window gets you hit before the HP arrives.

## Total committed duration, seconds.
const DURATION: float = 1.10

## Seconds in at which the HP actually arrives.
const HEAL_AT: float = 0.55

## Fraction of walk speed retained while drinking.
const CREEP: float = 0.35

var _elapsed: float = 0.0
var _healed: bool = false
var _charge_taken: bool = false


func enter(_previous: StringName) -> void:
	_elapsed = 0.0
	_healed = false
	# The charge is spent up front. Being interrupted has to cost something, or drinking becomes a
	# free gamble the player takes every time.
	_charge_taken = GameState.use_flask()


func physics_update(delta: float) -> StringName:
	if not _charge_taken:
		return Player.STATE_IDLE

	_elapsed += delta

	var intent := player.move_intent()
	var creep := player.tuning.walk_speed * CREEP
	player.velocity.x = move_toward(
		player.velocity.x, intent * creep, player.tuning.ground_accel * delta
	)
	if player.is_on_floor():
		player.velocity.y = -player.tuning.floor_stick_speed
	else:
		player.apply_gravity(delta)

	if not _healed and _elapsed >= HEAL_AT:
		_healed = true
		player.combatant.heal(GameState.flask_heal_amount())

	if _elapsed >= DURATION:
		return Player.STATE_IDLE
	return &""
