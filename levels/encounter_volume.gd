class_name EncounterVolume
extends Area3D

## A group of enemies that spawn together, share an [AttackScheduler], and respawn on rest.
##
## This is where the Phase 3 death loop finally closes: world enemies come back when the player
## rests at a Wayshrine, but a boss recorded in [code]GameState.bosses_defeated[/code] never does.
## Clearing a boss stays cleared; clearing a patrol does not.
##
## Spawning is deferred until the player is near, so a level of twenty encounters does not pay for
## twenty groups of AI on load.

## Emitted when every enemy in this encounter is dead.
signal cleared(encounter_id: String)

## Identifier. Used as a world flag when [member clear_once] is set.
@export var encounter_id: String = "encounter"

## Enemy scene spawned at each marker.
@export var enemy_scene: PackedScene

## Markers to spawn at. Children of this node named anything; only [Marker3D] children count.
@export var spawn_parent: Node3D

## Concurrent attackers for this encounter. A boss arena can serialise its adds by setting 1.
@export var max_attackers: int = 2

## Metres from the player at which the group spawns.
@export var activation_range: float = 26.0

## When true the encounter is recorded as a world flag on clear and never respawns — for scripted
## one-off fights rather than patrols.
@export var clear_once: bool = false

var _director: EncounterDirector
var _alive: Array[Enemy] = []
var _spawned: bool = false


func _ready() -> void:
	add_to_group(&"encounter_volume")

	_director = EncounterDirector.new()
	_director.max_attackers = max_attackers
	_director.name = "EncounterDirector"
	add_child(_director)

	EventBus.rested_at_wayshrine.connect(_on_rested)

	if clear_once and GameState.has_flag(_flag()):
		set_physics_process(false)
		return
	set_physics_process(true)


func _physics_process(_delta: float) -> void:
	if _spawned:
		return
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	if player == null:
		return
	if global_position.distance_to(player.global_position) <= activation_range:
		spawn()


## Spawn the group. Safe to call directly; the tests do.
func spawn() -> void:
	if _spawned or enemy_scene == null or spawn_parent == null:
		return
	_spawned = true

	for child: Node in spawn_parent.get_children():
		var marker := child as Marker3D
		if marker == null:
			continue
		var enemy := enemy_scene.instantiate() as Enemy
		if enemy == null:
			continue
		get_parent().add_child(enemy)
		enemy.global_transform = marker.global_transform
		enemy.bind_scheduler(_director.scheduler)
		enemy.combatant.died.connect(_on_enemy_died.bind(enemy))
		_alive.append(enemy)


## Kill and forget the current group, then allow it to spawn again.
##
## Called on rest. Enemies are freed rather than reset because an enemy mid-attack with a token held
## is a mess of state, and a fresh instance is both simpler and provably correct.
func respawn() -> void:
	if clear_once and GameState.has_flag(_flag()):
		return
	for enemy: Enemy in _alive:
		if is_instance_valid(enemy):
			enemy.queue_free()
	_alive.clear()
	_director.scheduler.clear()
	_spawned = false
	set_physics_process(true)


## Enemies still standing.
func alive_count() -> int:
	var count := 0
	for enemy: Enemy in _alive:
		if is_instance_valid(enemy) and not enemy.combatant.is_dead:
			count += 1
	return count


func _on_enemy_died(_enemy: Enemy) -> void:
	if alive_count() > 0:
		return
	if clear_once:
		GameState.set_flag(_flag())
	cleared.emit(encounter_id)


func _on_rested(_shrine_id: String) -> void:
	respawn()


func _flag() -> String:
	return "encounter_cleared:%s" % encounter_id
