class_name EnemyData
extends Resource

## One enemy variant, entirely as data. Adding a Husk elite means adding a [code].tres[/code], never
## a script — one [code]Enemy.tscn[/code] reads one of these ([code]CLAUDE.md §1[/code]).
##
## Health and stamina come from a [StatBlock] whose curve bases are authored directly (health_base
## 120, health_per_vigor 0), which keeps one derivation path for players and enemies alike.

## Display name, for the HUD and damage logs.
@export var display_name: String = "Husk"

## Pools and curves. Enemies author [member StatBlock.health_base] rather than allocating Vigor.
@export var stats: StatBlock

## Poise pool. Breaking it staggers the enemy and opens a riposte.
@export var max_poise: float = 40.0

## Flat defence, fed to the mitigation curve.
@export var defense: float = 24.0

## Embers dropped on death, at Biome 1 scale. Multiplied by the biome's `ember_multiplier`.
@export var ember_drop: int = 120

@export_group("Resistances")

## 0–1 fraction of damage ignored. **Negative is a weakness** and increases damage taken.
@export_range(-1.0, 0.95, 0.05) var resist_physical: float = 0.0

@export_range(-1.0, 0.95, 0.05) var resist_fire: float = 0.0

@export_range(-1.0, 0.95, 0.05) var resist_rot: float = 0.0

@export_range(-1.0, 0.95, 0.05) var resist_holy: float = 0.0

@export_group("Combat")

## Attacks this enemy can throw. Chosen by the Attack state.
@export var moveset: Array[AttackMove] = []

## Weapon supplying base damage and scaling. Enemies use flat stat blocks, so scaling mostly
## resolves to zero and `base_damage` does the work.
@export var weapon: WeaponData

@export_group("Movement & AI")

## Approach speed, m/s.
@export var move_speed: float = 1.8

## Distance at which Idle becomes Alert, metres.
@export var detect_range: float = 12.0

## Distance at which Approach becomes Attack, metres.
@export var attack_range: float = 1.9

## Preferred standoff while waiting for an attack token, metres.
@export var reposition_range: float = 3.5

## Seconds spent in Recover after an attack, before repositioning.
@export var recover_time: float = 0.6

@export_group("Archetype")

## Throws [member projectile_scene] instead of swinging. The Crow-Mask Cultist.
@export var is_ranged: bool = false

## Projectile thrown by a ranged enemy.
@export var projectile_scene: PackedScene

## Distance inside which a ranged enemy backs away rather than attacking, metres.
@export var retreat_range: float = 5.0

## Fraction of frontal damage a raised shield absorbs. The Warden must be parried or flanked; a
## straight trade with one is meant to lose.
@export_range(0.0, 1.0, 0.01) var shield_absorption: float = 0.0

## Status effect this enemy's hits build up. Null for a plain attacker.
@export var inflicts: StatusEffect

## Build-up applied per landed hit. Three is one full Rot meter from a Cultist.
@export_range(0.0, 8.0, 0.1) var inflict_buildup: float = 1.0

## Radius over which this enemy buffs its allies, metres. The Bell-Bearer. Zero means no aura.
@export var aura_radius: float = 0.0

## Damage multiplier granted to allies inside the aura.
@export var aura_damage_bonus: float = 0.35

## Lunges from beyond the screen edge rather than walking in. The Gravewretch.
@export var lunges_from_offscreen: bool = false

## Lunge launch speed, m/s.
@export var lunge_speed: float = 9.0


## Resistance fraction for [param type].
func resist_for(type: DamagePacket.Type) -> float:
	match type:
		DamagePacket.Type.PHYSICAL:
			return resist_physical
		DamagePacket.Type.FIRE:
			return resist_fire
		DamagePacket.Type.ROT:
			return resist_rot
		DamagePacket.Type.HOLY:
			return resist_holy
	return 0.0
