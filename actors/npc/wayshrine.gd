class_name Wayshrine
extends Area3D

## Rest point: restores pools, refills the flask, sets the respawn point, respawns world enemies,
## and autosaves.
##
## Bosses are deliberately excluded from the respawn — [code]GameState.bosses_defeated[/code]
## persists, so clearing one stays cleared.

## Emitted when the player rests here, so the level can respawn its encounters.
signal rested(shrine_id: String)

## Stable identifier, stored in the save as the respawn point. Must be unique in a level.
@export var shrine_id: String = "village_gate"

## Shown when the player is in range.
@export var prompt: String = "Rest"

var _player_in_range: bool = false


func _ready() -> void:
	add_to_group(&"wayshrine")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _unhandled_input(event: InputEvent) -> void:
	if _player_in_range and event.is_action_pressed(&"interact"):
		rest()
		get_viewport().set_input_as_handled()


## Perform the rest. Safe to call directly, which is what the tests do.
func rest() -> void:
	GameState.rest_at(shrine_id)

	var player := get_tree().get_first_node_in_group(&"player") as Player
	if player != null and player.combatant != null:
		player.combatant.reset()

	rested.emit(shrine_id)
	EventBus.rested_at_wayshrine.emit(shrine_id)
	SaveSystem.autosave("wayshrine_rest")
	Log.info("Wayshrine", "rested at %s" % shrine_id)


func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		_player_in_range = true


func _on_body_exited(body: Node3D) -> void:
	if body is Player:
		_player_in_range = false
