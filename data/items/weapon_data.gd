class_name WeaponData
extends Resource

## A weapon: base damage, a per-stat scaling vector, a damage school, and a moveset id.
##
## Scaling is a sum across all five stats ([code]docs/GDD.md §6.4[/code]), authored as letter grades
## because that is what the UI shows and what players already know how to read. A single-stat weapon
## simply leaves the other four at [code]NONE[/code].

## Scaling grades. Coefficients per [code]docs/GDD.md §6.4[/code].
enum Grade { NONE, E, D, C, B, A, S }

## Grade → coefficient. S at stat 40 doubles base damage.
const GRADE_COEFFICIENT: Dictionary[Grade, float] = {
	Grade.NONE: 0.0,
	Grade.E: 0.10,
	Grade.D: 0.25,
	Grade.C: 0.40,
	Grade.B: 0.55,
	Grade.A: 0.75,
	Grade.S: 1.00,
}

## Display name.
@export var display_name: String = "Unnamed"

## Base damage before scaling and move multipliers.
@export var base_damage: float = 42.0

## Damage school this weapon deals.
@export var damage_type: DamagePacket.Type = DamagePacket.Type.PHYSICAL

## Which moveset the attack states drive. Matched against a [Moveset] resource.
@export var moveset_id: StringName = &"longsword"

## Equip weight, feeding the armour weight tier.
@export var weight: float = 6.0

@export_group("Scaling")

@export var scaling_vigor: Grade = Grade.NONE
@export var scaling_endurance: Grade = Grade.NONE
@export var scaling_might: Grade = Grade.B
@export var scaling_finesse: Grade = Grade.NONE
@export var scaling_ember_bound: Grade = Grade.NONE


## Coefficient for [param stat], 0.0 when this weapon does not scale off it.
func scaling_for(stat: StatBlock.Stat) -> float:
	return GRADE_COEFFICIENT[_grade_for(stat)]


## Grade for [param stat], for UI display.
func grade_for(stat: StatBlock.Stat) -> Grade:
	return _grade_for(stat)


func _grade_for(stat: StatBlock.Stat) -> Grade:
	match stat:
		StatBlock.Stat.VIGOR:
			return scaling_vigor
		StatBlock.Stat.ENDURANCE:
			return scaling_endurance
		StatBlock.Stat.MIGHT:
			return scaling_might
		StatBlock.Stat.FINESSE:
			return scaling_finesse
		StatBlock.Stat.EMBER_BOUND:
			return scaling_ember_bound
	return Grade.NONE
