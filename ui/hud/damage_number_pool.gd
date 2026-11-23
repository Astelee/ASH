class_name DamageNumberPool
extends Node3D

## Pooled floating damage numbers. Listens on [EventBus] and needs no wiring from either combatant.
##
## Pre-allocated at ready and never grown during play: [code]CLAUDE.md §3[/code] forbids per-frame
## allocation, and damage numbers are the most frequent spawn in the game. Exhausting the pool
## recycles the oldest rather than instantiating, so a pathological hit-rate degrades visually
## instead of stuttering.

## Labels allocated up front. Sized for a boss plus adds, all connecting at once.
@export var pool_size: int = 24

## Seconds a number stays visible.
@export var lifetime: float = 0.9

## Metres travelled upward over that lifetime.
@export var rise: float = 1.1

## Normal hit colour.
@export var normal_color: Color = Color(1.0, 0.95, 0.85)

## Riposte and critical colour.
@export var riposte_color: Color = Color(1.0, 0.72, 0.35)

var _labels: Array[Label3D] = []
var _ages: PackedFloat32Array = PackedFloat32Array()
var _next: int = 0


func _ready() -> void:
	_labels.resize(pool_size)
	_ages.resize(pool_size)
	for index: int in pool_size:
		var label := Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.font_size = 48
		label.outline_size = 10
		label.visible = false
		add_child(label)
		_labels[index] = label
		_ages[index] = -1.0

	EventBus.damage_dealt.connect(_on_damage_dealt)


func _process(delta: float) -> void:
	for index: int in _labels.size():
		var age := _ages[index]
		if age < 0.0:
			continue
		age += delta
		if age >= lifetime:
			_ages[index] = -1.0
			_labels[index].visible = false
			continue
		_ages[index] = age
		var t := age / lifetime
		var label := _labels[index]
		label.position.y += rise * delta
		label.modulate.a = 1.0 - t * t


## Show [param amount] at [param at]. Called from the bus, and directly by anything that needs a
## number without a damage packet.
func show_damage(amount: float, at: Vector3, is_riposte: bool) -> void:
	var index := _claim()
	var label := _labels[index]
	label.text = "%d" % roundi(amount)
	label.modulate = riposte_color if is_riposte else normal_color
	label.font_size = 64 if is_riposte else 48
	label.global_position = at + Vector3(randf_range(-0.2, 0.2), 0.4, 0.3)
	label.visible = true
	_ages[index] = 0.0


func _claim() -> int:
	# Round-robin. The oldest number is the least interesting one to lose.
	var index := _next
	_next = (_next + 1) % _labels.size()
	return index


func _on_damage_dealt(_target: Node, packet: DamagePacket, result: DamagePacket.Result) -> void:
	if result == DamagePacket.Result.IMMUNE or packet.amount <= 0.0:
		return
	show_damage(packet.amount, packet.impact_point, packet.is_riposte)
