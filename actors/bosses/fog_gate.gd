class_name FogGate
extends Area3D

## The wall of fog at a boss arena. Passable inward, solid behind you until the boss is dead.
##
## Two jobs: it stops the player wandering out mid-fight, and it gives them a clear moment of
## decision before the fight starts. Once the boss is recorded as defeated it opens permanently.

## Boss this gate seals in. Matched against [code]GameState.bosses_defeated[/code].
@export var boss_id: String = "cadwyn"

## Barrier blocking retreat. Disabled once the boss is dead.
@export var barrier: StaticBody3D

## Visual fog plane, hidden once the fight is won.
@export var fog_visual: Node3D


func _ready() -> void:
	add_to_group(&"fog_gate")
	body_entered.connect(_on_body_entered)
	EventBus.enemy_died.connect(_on_enemy_died)
	_refresh()


## True when the fight behind this gate is already won.
func is_open() -> bool:
	return GameState.is_boss_defeated(boss_id)


func _on_body_entered(body: Node3D) -> void:
	# Sealing on entry rather than on sight: the player crosses deliberately, and a gate that slams
	# because you walked near it is a gate that steals the decision.
	if body is Player and not is_open():
		_set_sealed(true)


func _on_enemy_died(enemy: Node, _embers: int) -> void:
	var boss := enemy as Boss
	if boss != null and boss.boss_id == boss_id:
		_refresh()


func _refresh() -> void:
	_set_sealed(false)
	if fog_visual != null:
		fog_visual.visible = not is_open()


func _set_sealed(sealed: bool) -> void:
	if barrier == null:
		return
	var active := sealed and not is_open()
	for child: Node in barrier.get_children():
		var shape := child as CollisionShape3D
		if shape != null:
			shape.set_deferred(&"disabled", not active)
