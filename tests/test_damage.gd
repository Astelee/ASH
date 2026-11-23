extends GutTest

## The damage formula from docs/GDD.md §6.4 and the block model from §6.1b.
##
## Every worked example printed in the GDD is asserted here. If a number in the design doc changes,
## this file fails — which is the point.

var _weapon: WeaponData
var _stats: StatBlock
var _shield: ShieldData
var _tuning: CombatTuning


func before_each() -> void:
	_weapon = WeaponData.new()
	_weapon.base_damage = 42.0
	_weapon.scaling_might = WeaponData.Grade.B
	_weapon.damage_type = DamagePacket.Type.PHYSICAL

	_stats = StatBlock.new()
	_stats.might = 20

	_shield = ShieldData.new()
	_shield.absorb_physical = 0.65
	_shield.stability_base = 0.30

	_tuning = CombatTuning.new()


# --------------------------------------------------------------- mitigation curve


func test_mitigation_is_zero_without_defense() -> void:
	assert_eq(Damage.mitigation(0.0), 0.0, "no defence means no reduction")


func test_mitigation_curve_matches_gdd_table() -> void:
	# docs/GDD.md §6.4 — the reason no armour value grants invulnerability.
	assert_almost_eq(Damage.mitigation(25.0), 0.2, 0.0001, "defence 25 -> 20 %")
	assert_almost_eq(Damage.mitigation(50.0), 1.0 / 3.0, 0.0001, "defence 50 -> 33.3 %")
	assert_almost_eq(Damage.mitigation(100.0), 0.5, 0.0001, "defence 100 -> 50 %")
	assert_almost_eq(Damage.mitigation(200.0), 2.0 / 3.0, 0.0001, "defence 200 -> 66.7 %")
	assert_almost_eq(Damage.mitigation(400.0), 0.8, 0.0001, "defence 400 -> 80 %")


func test_mitigation_never_reaches_one() -> void:
	assert_lt(Damage.mitigation(100000.0), 1.0, "asymptotic, never total")


# ------------------------------------------------------------------- scaling


func test_scaling_sums_across_stats() -> void:
	# A quality weapon scaling off two stats must add both contributions, not pick one.
	_weapon.scaling_finesse = WeaponData.Grade.D
	_stats.finesse = 40
	# Might B at 20 -> 0.55 * 0.5 = 0.275; Finesse D at 40 -> 0.25 * 1.0 = 0.25
	assert_almost_eq(Damage.scaling_bonus(_weapon, _stats), 0.525, 0.0001, "contributions add")


func test_s_scaling_at_reference_stat_doubles_base() -> void:
	_weapon.scaling_might = WeaponData.Grade.S
	_stats.might = int(StatBlock.SCALING_REFERENCE)
	assert_almost_eq(Damage.scaling_bonus(_weapon, _stats), 1.0, 0.0001, "S at 40 -> +100 %")


func test_unscaled_stats_contribute_nothing() -> void:
	_stats.ember_bound = 99
	assert_almost_eq(Damage.scaling_bonus(_weapon, _stats), 0.275, 0.0001, "grade NONE adds zero")


# --------------------------------------------------------- the GDD worked cases


func test_worked_example_light_one_versus_husk() -> void:
	# GDD §6.4: raw 53.55, mitigation 0.19355, final 43.19.
	var raw := Damage.raw_damage(_weapon, _stats, 1.0, 1.0, 1.0)
	assert_almost_eq(raw, 53.55, 0.001, "raw before mitigation")

	var final_damage := Damage.compute(_weapon, _stats, 24.0, 0.0, 1.0)
	assert_almost_eq(final_damage, 43.1855, 0.01, "light-1 at Might 20 versus a Husk")


func test_worked_example_riposte_versus_husk() -> void:
	# GDD §6.4: 53.55 x 2.2 = 117.81 -> x 0.80645 = 95.01.
	var final_damage := Damage.compute(_weapon, _stats, 24.0, 0.0, 1.0, 1.0, 2.2)
	assert_almost_eq(final_damage, 95.0129, 0.01, "riposte multiplier applies before mitigation")


func test_husk_dies_in_three_light_hits() -> void:
	# The enemy stat block was sized against this: 120 HP, ~43 per swing.
	var per_hit := Damage.compute(_weapon, _stats, 24.0, 0.0, 1.0)
	assert_lt(per_hit * 2.0, 120.0, "two hits must not kill")
	assert_gt(per_hit * 3.0, 120.0, "three hits must kill")


# ------------------------------------------------------------- resistances


func test_resistance_reduces_damage() -> void:
	var plain := Damage.compute(_weapon, _stats, 24.0, 0.0, 1.0)
	var resisted := Damage.compute(_weapon, _stats, 24.0, 0.5, 1.0)
	assert_almost_eq(resisted, plain * 0.5, 0.01, "50 % resist halves the hit")


func test_negative_resistance_is_a_weakness() -> void:
	var plain := Damage.compute(_weapon, _stats, 24.0, 0.0, 1.0)
	var weak := Damage.compute(_weapon, _stats, 24.0, -0.5, 1.0)
	assert_almost_eq(weak, plain * 1.5, 0.01, "the Gravewretch's Holy weakness")


func test_damage_floors_at_one() -> void:
	var final_damage := Damage.compute(_weapon, _stats, 100000.0, 0.95, 0.01)
	assert_eq(final_damage, Damage.MINIMUM_DAMAGE, "a hit always does something")


# ----------------------------------------------------------------- blocking


func test_block_worked_example() -> void:
	# GDD §6.1b: 100 raw, 20 % armour mitigation, wooden kite, Might 20 -> 28.0 through.
	var after_armor := 100.0 * (1.0 - Damage.mitigation(25.0))
	assert_almost_eq(after_armor, 80.0, 0.001, "armour first")

	var through := Damage.after_block(after_armor, _shield, DamagePacket.Type.PHYSICAL)
	assert_almost_eq(through, 28.0, 0.01, "shield absorbs 65 % of what armour left")


func test_block_stamina_worked_example() -> void:
	# stability 0.30 + 20 x 0.006 = 0.42; (15 + 100 x 0.5) x 0.58 = 37.7
	assert_almost_eq(_shield.stability_for(20), 0.42, 0.0001, "Might feeds stability")
	var cost := Damage.block_stamina_cost(100.0, _shield, 20, _tuning)
	assert_almost_eq(cost, 37.7, 0.01, "stamina scales with the raw blow")


func test_stability_is_capped() -> void:
	assert_almost_eq(
		_shield.stability_for(999), ShieldData.MAX_STABILITY, 0.0001, "blocking is never free"
	)


func test_block_does_not_apply_armour_mitigation_twice() -> void:
	# The spec's original wording would have run the defence curve a second time. A defenceless
	# target and an armoured one must absorb the same *fraction* through the shield.
	var naked := Damage.after_block(100.0, _shield, DamagePacket.Type.PHYSICAL)
	assert_almost_eq(naked, 35.0, 0.01, "shield absorption is independent of defence")


func test_block_absorption_is_per_damage_type() -> void:
	var physical := Damage.after_block(100.0, _shield, DamagePacket.Type.PHYSICAL)
	var fire := Damage.after_block(100.0, _shield, DamagePacket.Type.FIRE)
	assert_gt(fire, physical, "a wooden shield is worse against fire")


func test_blocking_without_a_shield_absorbs_nothing() -> void:
	assert_almost_eq(
		Damage.after_block(80.0, null, DamagePacket.Type.PHYSICAL),
		80.0,
		0.001,
		"no shield, no help"
	)


# -------------------------------------------------------------------- poise


func test_poise_breaks_when_damage_meets_pool() -> void:
	assert_true(Damage.breaks_poise(40.0, 40.0), "exactly emptying the pool breaks it")
	assert_false(Damage.breaks_poise(40.0, 39.0), "one short does not")


func test_infinite_poise_damage_always_breaks() -> void:
	assert_true(Damage.breaks_poise(999.0, INF), "a fully charged heavy is a guaranteed break")
