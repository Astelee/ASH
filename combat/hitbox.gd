class_name Hitbox
extends Area3D

## An attack volume, enabled only during a move's active frames.
##
## Detects overlap and asks its actor to build the [DamagePacket] — the maths stays with whoever
## owns the weapon and stats, and this node stays ignorant of both. It never learns what it hit past
## "a [Hurtbox]", which is what lets the player and enemy scenes stay unaware of each other.
##
## The actor must implement [code]build_damage_packet() -> DamagePacket[/code].

## Emitted for each hurtbox struck, with the defender's resolution.
signal hit_landed(hurtbox: Hurtbox, result: DamagePacket.Result)

## The actor swinging.
@export var actor: Node

## The collision shape resized per move.
@export var shape: CollisionShape3D

var _move: AttackMove
var _already_hit: Array[int] = []


func _ready() -> void:
	monitoring = false
	monitorable = false
	if actor == null:
		actor = get_parent()
	area_entered.connect(_on_area_entered)
	if not actor.has_method(&"build_damage_packet"):
		Log.error("Hitbox", "%s: actor %s has no build_damage_packet()" % [get_path(), actor.name])


## Open the hitbox for [param move], mirrored to [param facing].
##
## The hit list is cleared here rather than on disable, so one swing can never strike the same
## target twice however many physics frames the active window spans.
func arm(move: AttackMove, facing: int) -> void:
	_move = move
	_already_hit.clear()

	if shape != null:
		var box := shape.shape as BoxShape3D
		if box != null:
			box.size = move.hitbox_size
		shape.position = Vector3(
			move.hitbox_offset.x * float(facing), move.hitbox_offset.y, move.hitbox_offset.z
		)

	monitoring = true


## Close the hitbox. Idempotent.
func disarm() -> void:
	monitoring = false
	_move = null


## The move currently being swung, or null when disarmed.
func current_move() -> AttackMove:
	return _move


func _on_area_entered(area: Area3D) -> void:
	var hurtbox := area as Hurtbox
	if hurtbox == null or hurtbox.actor == actor:
		return

	var id := hurtbox.get_instance_id()
	if _already_hit.has(id):
		return
	_already_hit.append(id)

	var packet: DamagePacket = actor.call(&"build_damage_packet")
	if packet == null:
		return
	packet.impact_point = hurtbox.global_position
	packet.direction = (hurtbox.global_position - global_position).normalized()

	var result := hurtbox.take(packet)
	hit_landed.emit(hurtbox, result)
