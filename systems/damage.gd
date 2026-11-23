class_name Damage
extends RefCounted

## The damage formula from [code]docs/GDD.md §6.4[/code], as pure static functions.
##
## No nodes, no scene tree, no side effects — every number the combat system produces can be
## reproduced headless from data alone. That is the whole reason this is not a method on the player.

## Constant in the mitigation curve. Defence equal to this value gives exactly 50 % reduction.
const MITIGATION_CONSTANT: float = 100.0

## Floor on resolved damage. A hit always does something, however armoured the target.
const MINIMUM_DAMAGE: float = 1.0


## Fraction of incoming damage removed by [param defense].
##
## [code]d / (d + 100)[/code] — diminishing, asymptotic, never 100 %. 0 at defence 0, 50 % at 100,
## 80 % at 400. There is no armour value that makes a target invulnerable.
static func mitigation(defense: float) -> float:
	if defense <= 0.0:
		return 0.0
	return defense / (defense + MITIGATION_CONSTANT)


## Summed scaling contribution across all five stats.
##
## A sum, not a single stat: the stat descriptions imply hybrids (Might for heavy, Finesse for
## fast), and a single-stat weapon just leaves the other four grades at NONE.
static func scaling_bonus(weapon: WeaponData, stats: StatBlock) -> float:
	var total := 0.0
	for stat: StatBlock.Stat in StatBlock.Stat.values():
		var coefficient := weapon.scaling_for(stat)
		if coefficient <= 0.0:
			continue
		total += coefficient * float(stats.get_stat(stat)) / StatBlock.SCALING_REFERENCE
	return total


## Pre-mitigation damage for a swing.
static func raw_damage(
	weapon: WeaponData,
	stats: StatBlock,
	move_multiplier: float,
	charge_multiplier: float,
	riposte_multiplier: float
) -> float:
	var scaled := weapon.base_damage * (1.0 + scaling_bonus(weapon, stats))
	return scaled * move_multiplier * charge_multiplier * riposte_multiplier


## Apply defence and resistance to [param raw]. [param resist] is a 0–1 fraction and may be
## negative, which is a weakness and increases the result.
static func after_defense(raw: float, defense: float, resist: float) -> float:
	return maxf(MINIMUM_DAMAGE, raw * (1.0 - mitigation(defense)) * (1.0 - resist))


## The complete chain: scaling, move multipliers, mitigation, resistance.
##
## Worked case from the GDD — Ashen Longsword (base 42, Might B) at Might 20, light-1, versus a Husk
## (defence 24, no physical resist) resolves to **43.19**.
static func compute(
	weapon: WeaponData,
	stats: StatBlock,
	defense: float,
	resist: float,
	move_multiplier: float = 1.0,
	charge_multiplier: float = 1.0,
	riposte_multiplier: float = 1.0
) -> float:
	var raw := raw_damage(weapon, stats, move_multiplier, charge_multiplier, riposte_multiplier)
	return after_defense(raw, defense, resist)


## Damage remaining after a shield absorbs its share.
##
## Applied *after* armour mitigation, never instead of it and never a second copy of it — the spec's
## original "absorbs 100 × mitigation%" would have run the defence curve twice and scaled blocking
## off the wrong stat. See [code]docs/GDD.md §6.1b[/code].
static func after_block(
	damage_after_armor: float, shield: ShieldData, type: DamagePacket.Type
) -> float:
	if shield == null:
		return damage_after_armor
	return maxf(MINIMUM_DAMAGE, damage_after_armor * (1.0 - shield.absorption_for(type)))


## Stamina spent absorbing a blocked hit.
##
## Scales with the *raw* blow rather than the post-armour figure, so a heavily-armoured defender
## does not get cheap blocks on top of cheap hits. Might reduces it through the shield's
## stability, capped so blocking is never free.
static func block_stamina_cost(
	raw: float, shield: ShieldData, might: int, tuning: CombatTuning
) -> float:
	var stability := shield.stability_for(might) if shield != null else 0.0
	var base := tuning.block_stamina_flat + raw * tuning.block_stamina_per_damage
	return maxf(0.0, base * (1.0 - stability))


## True when [param poise_damage] empties a pool holding [param current_poise].
## [code]INF[/code] poise damage is a guaranteed break.
static func breaks_poise(current_poise: float, poise_damage: float) -> bool:
	return poise_damage >= current_poise or is_inf(poise_damage)
