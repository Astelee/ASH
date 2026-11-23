class_name ShortcutGate
extends Area3D

## A one-way gate that becomes two-way once opened, and stays open across death and reload.
##
## This is the entire Souls-like shortcut idea in one node: the first traversal is long, the player
## opens the gate from the far side, and every run after that is a third the length. The open state
## is a world flag, so it survives the bloodstain loop and the save file.

## Emitted when the gate opens for the first time.
signal opened(gate_id: String)

## Identifier, stored as a world flag.
@export var gate_id: String = "village_shortcut"

## Geometry hidden and de-collided once open.
@export var barrier: Node3D

## Side the gate can be opened from. The player must be beyond this X to work the mechanism.
@export var openable_from_x: float = 0.0

## True when the gate opens from the right-hand side rather than the left.
@export var opens_from_right: bool = true

var _player_in_range: bool = false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	body_entered.connect(func(body: Node3D) -> void: _player_in_range = body is Player)
	body_exited.connect(
		func(body: Node3D) -> void: _player_in_range = not (body is Player) and _player_in_range
	)

	if GameState.has_flag(_flag()):
		_set_open(true)


func _unhandled_input(event: InputEvent) -> void:
	if not _player_in_range or not event.is_action_pressed(&"interact"):
		return
	if GameState.has_flag(_flag()):
		return
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	if player == null:
		return
	var beyond := player.global_position.x > openable_from_x
	if beyond != opens_from_right:
		return

	GameState.set_flag(_flag())
	_set_open(true)
	opened.emit(gate_id)
	SaveSystem.autosave("shortcut_opened")
	get_viewport().set_input_as_handled()


## True when this gate has already been opened in the current run.
func is_open() -> bool:
	return GameState.has_flag(_flag())


func _set_open(open: bool) -> void:
	if barrier == null:
		return
	barrier.visible = not open
	for child: Node in barrier.get_children():
		var shape := child as CollisionShape3D
		if shape != null:
			shape.disabled = open
	var body := barrier as CollisionObject3D
	if body != null:
		body.process_mode = Node.PROCESS_MODE_DISABLED if open else Node.PROCESS_MODE_INHERIT


func _flag() -> String:
	return "shortcut:%s" % gate_id
