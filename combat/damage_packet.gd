class_name DamagePacket
extends RefCounted

## One resolved hit travelling from a [Hitbox] to a [Hurtbox].
##
## Carries the *result* of the damage calculation, not the inputs — the maths happens once in
## [Damage] before the packet is built, so nothing downstream can recompute it differently. This is
## the entire shared vocabulary between the player and enemies; neither knows the other's scene.

## Damage schools. Resistances are per-type and may be negative, which is a weakness.
enum Type { PHYSICAL, FIRE, ROT, HOLY }

## How a hit was received. Set by the [Hurtbox] owner, read by the attacker for reaction logic.
enum Result { HIT, BLOCKED, PARRIED, IMMUNE }

## Final HP damage after mitigation, resistance, and any block.
var amount: float = 0.0

## Poise damage applied on top. [code]INF[/code] means a guaranteed break (charged heavy).
var poise_damage: float = 0.0

## Damage school, for resistances and VFX tinting.
var type: Type = Type.PHYSICAL

## The actor that swung. May be null if the source has already been freed.
var source: Node = null

## World position of the impact, for VFX and damage-number placement.
var impact_point: Vector3 = Vector3.ZERO

## Direction of the blow, used for knockback and hit-reaction facing.
var direction: Vector3 = Vector3.RIGHT

## Hitstop applied to both actors on a successful hit, seconds.
var hitstop: float = 0.0

## True when this hit came from a riposte on a staggered target.
var is_riposte: bool = false

## Pre-mitigation damage. Blocking costs stamina proportional to the raw blow, so a heavily-armoured
## defender does not get cheap blocks as well.
var raw_amount: float = 0.0

## Status effect this hit builds up, if any. Null for an ordinary blow.
##
## Carried on the packet rather than looked up from the weapon, because the packet is the entire
## shared vocabulary between the player and enemies — a Hurtbox must never have to ask what hit it.
var status: StatusEffect = null

## Build-up applied per landed hit, before the target resistance.
var status_buildup: float = 1.0


## Convenience constructor. Keeps [Hitbox] free of eleven assignment lines.
static func create(
	final_amount: float, raw: float, packet_type: Type, from: Node, at: Vector3
) -> DamagePacket:
	var packet := DamagePacket.new()
	packet.amount = final_amount
	packet.raw_amount = raw
	packet.type = packet_type
	packet.source = from
	packet.impact_point = at
	return packet
