class_name Hurtbox
extends Area3D

## A damageable volume. Receives a [DamagePacket] and hands it to its actor to resolve.
##
## The hurtbox deliberately owns no rules — invulnerability, blocking, and parrying are actor state,
## and duplicating them here would be two places to get wrong. It is a receptionist, not a judge.
##
## The actor must implement [code]receive_hit(packet: DamagePacket) -> DamagePacket.Result[/code].

## Emitted after the actor has resolved the hit, carrying what actually happened.
signal hit_resolved(packet: DamagePacket, result: DamagePacket.Result)

## The actor this volume belongs to.
@export var actor: Node

## While true, every incoming packet resolves as [code]IMMUNE[/code]. Dodge i-frames set this.
var invulnerable: bool = false


func _ready() -> void:
	monitorable = true
	monitoring = false
	if actor == null:
		actor = get_parent()
	if not actor.has_method(&"receive_hit"):
		Log.error("Hurtbox", "%s: actor %s has no receive_hit()" % [get_path(), actor.name])


## Deliver [param packet]. Called by a [Hitbox]; returns how the hit landed so the attacker can
## react — a parry has to stagger the swinger, and only the defender knows it happened.
func take(packet: DamagePacket) -> DamagePacket.Result:
	if invulnerable:
		var dodged := DamagePacket.Result.IMMUNE
		hit_resolved.emit(packet, dodged)
		return dodged

	if actor == null or not actor.has_method(&"receive_hit"):
		return DamagePacket.Result.IMMUNE

	var result: DamagePacket.Result = actor.call(&"receive_hit", packet)
	hit_resolved.emit(packet, result)
	return result
