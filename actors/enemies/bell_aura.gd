class_name BellAura
extends Node3D

## The Bell-Bearer's buff. Every enemy inside the radius swings harder.
##
## Written as a node on the Bell-Bearer rather than as a status effect on its allies, because the
## buff must vanish the instant the Bearer dies. That is the entire design of the enemy: it is a
## kill priority, and a buff that outlived it would remove the reason to prioritise it.

## Owner. Its [member EnemyData.aura_radius] and bonus drive the effect.
@export var bearer: Enemy

var _buffed: Array[Enemy] = []


func _ready() -> void:
	if bearer == null:
		bearer = get_parent() as Enemy


func _physics_process(_delta: float) -> void:
	_clear()
	if bearer == null or bearer.combatant == null or bearer.combatant.is_dead:
		return
	if bearer.data.aura_radius <= 0.0:
		return

	for node: Node in get_tree().get_nodes_in_group(&"enemy"):
		var ally := node as Enemy
		if ally == null or ally == bearer or ally.combatant.is_dead:
			continue
		if ally.global_position.distance_to(bearer.global_position) > bearer.data.aura_radius:
			continue
		ally.aura_bonus = bearer.data.aura_damage_bonus
		_buffed.append(ally)


func _exit_tree() -> void:
	_clear()


## Allies currently receiving the buff.
func buffed_count() -> int:
	return _buffed.size()


func _clear() -> void:
	for ally: Enemy in _buffed:
		if is_instance_valid(ally):
			ally.aura_bonus = 0.0
	_buffed.clear()
