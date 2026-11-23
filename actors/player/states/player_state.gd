class_name PlayerState
extends State

## Base for every player locomotion state. Resolves the typed actor reference once so no state
## reaches through the tree for it.

var player: Player


func setup() -> void:
	player = machine.actor as Player
	if player == null:
		Log.error("PlayerState", "%s: machine.actor is not a Player" % name)


## Transitions every grounded state shares, in priority order. Returns [code]&""[/code] when none
## apply, so a caller can fall through to its own logic.
##
## Jump outranks everything: a buffered press must survive the frame it lands on, or the buffer
## does nothing. Combat actions are gated on stamina here rather than inside the states, so an
## unaffordable press leaves the player put instead of entering a move that immediately aborts.
func grounded_transitions() -> StringName:
	var next := &""

	if player.has_buffered_jump() and player.can_jump():
		next = Player.STATE_JUMP
	elif (
		Input.is_action_just_pressed(&"attack_light")
		and not player.light_combo.is_empty()
		and can_afford(player.light_combo[0].stamina_cost)
	):
		next = Player.STATE_ATTACK
	elif (
		Input.is_action_just_pressed(&"attack_heavy")
		and player.heavy_move != null
		and can_afford(player.heavy_move.stamina_cost)
	):
		next = Player.STATE_HEAVY

	# Consumed unconditionally so a tap taken while out of stamina cannot fire later.
	var tapped := InputRouter.consume_dodge_tap()
	if next == &"" and tapped and can_afford(player.combat_tuning.dodge_stamina):
		next = Player.STATE_DODGE
	elif next == &"" and Input.is_action_just_pressed(&"item_use") and GameState.flask_charges > 0:
		next = Player.STATE_FLASK
	elif next == &"" and Input.is_action_pressed(&"block"):
		next = Player.STATE_BLOCK
	elif next == &"" and not player.is_on_floor():
		next = Player.STATE_FALL

	return next


## True when the player has [param cost] stamina to spend.
func can_afford(cost: float) -> bool:
	return player.combatant != null and player.combatant.stamina >= cost
