extends GutTest

## The death → bloodstain → recovery loop and the level-up economy, driven through GameState.
##
## These are acceptance criteria 1, 3, and 4 of Phase 3 expressed as assertions rather than as
## something to remember to try by hand.


func before_each() -> void:
	GameState.begin_new_run(null)


# ------------------------------------------------------------------ levelling


func test_level_up_spends_embers_and_grants_a_point() -> void:
	GameState.add_embers(90)
	assert_eq(GameState.next_level_cost(), 90, "L1 -> L2 costs 90")
	assert_true(GameState.level_up(), "affordable")
	assert_eq(GameState.level, 2)
	assert_eq(GameState.embers, 0, "the purse was spent")
	assert_eq(GameState.unspent_points, 1)


func test_level_up_is_refused_when_short() -> void:
	GameState.add_embers(89)
	assert_false(GameState.level_up(), "one Ember short")
	assert_eq(GameState.level, 1, "and nothing changed")
	assert_eq(GameState.embers, 89, "including the purse")


func test_fifth_level_grants_the_bonus_point() -> void:
	GameState.add_embers(100000)
	for _i: int in 4:
		GameState.level_up()
	assert_eq(GameState.level, 5)
	assert_eq(GameState.unspent_points, 5, "four levels plus the L5 bonus")


func test_allocating_a_point_raises_the_stat_and_the_pool() -> void:
	GameState.add_embers(90)
	GameState.level_up()
	var before := GameState.stats.max_health()
	assert_true(GameState.allocate_point(StatBlock.Stat.VIGOR))
	assert_eq(GameState.unspent_points, 0, "the point was consumed")
	assert_almost_eq(GameState.stats.max_health(), before + 14.0, 0.01, "14 HP per Vigor")


func test_allocating_without_points_fails() -> void:
	assert_false(GameState.allocate_point(StatBlock.Stat.MIGHT), "nothing banked")


# --------------------------------------------------------------- death loop


func test_death_drops_the_whole_purse() -> void:
	GameState.add_embers(1200)
	GameState.drop_bloodstain("village_02", Vector3(12.5, 3.0, 0.0))
	assert_eq(GameState.embers, 0, "carried Embers are gone")
	assert_eq(GameState.bloodstain_embers, 1200, "and waiting at the death site")
	assert_true(GameState.has_bloodstain())


func test_recovery_returns_everything() -> void:
	GameState.add_embers(1200)
	GameState.drop_bloodstain("village_02", Vector3.ZERO)
	var reclaimed := GameState.recover_bloodstain()
	assert_eq(reclaimed, 1200)
	assert_eq(GameState.embers, 1200, "back in the purse")
	assert_false(GameState.has_bloodstain(), "and the stain is gone")


func test_dying_twice_destroys_the_first_stain() -> void:
	# The rule that gives death its weight: there is exactly one stain, ever.
	GameState.add_embers(1200)
	GameState.drop_bloodstain("village_02", Vector3.ZERO)
	GameState.add_embers(300)
	GameState.drop_bloodstain("village_03", Vector3(50.0, 0.0, 0.0))

	assert_eq(GameState.bloodstain_embers, 300, "only the newest survives")
	assert_eq(GameState.bloodstain_level, "village_03")
	assert_eq(GameState.recover_bloodstain(), 300, "the first 1200 are gone for good")


func test_dying_with_nothing_still_clears_the_old_stain() -> void:
	GameState.add_embers(500)
	GameState.drop_bloodstain("a", Vector3.ZERO)
	GameState.drop_bloodstain("b", Vector3.ZERO)
	assert_eq(GameState.bloodstain_embers, 0, "an empty purse still replaces the stain")


# -------------------------------------------------------------------- flask


func test_flask_starts_full_and_drains() -> void:
	assert_eq(GameState.flask_charges, 3)
	assert_true(GameState.use_flask())
	assert_eq(GameState.flask_charges, 2)


func test_flask_refuses_when_empty() -> void:
	for _i: int in 3:
		GameState.use_flask()
	assert_false(GameState.use_flask(), "no charges left")


func test_resting_refills_the_flask_and_sets_respawn() -> void:
	GameState.use_flask()
	GameState.use_flask()
	GameState.rest_at("village_gate")
	assert_eq(GameState.flask_charges, GameState.flask_max_charges, "topped up")
	assert_eq(GameState.wayshrine, "village_gate", "respawn point moved")


func test_flask_potency_scales_with_ember_bound() -> void:
	GameState.stats.ember_bound = 0
	assert_almost_eq(GameState.flask_heal_amount(), 90.0, 0.01, "base heal")
	GameState.stats.ember_bound = 20
	assert_almost_eq(GameState.flask_heal_amount(), 117.0, 0.01, "GDD §7.7: 90 x 1.30")


func test_ash_shard_raises_capacity_once() -> void:
	assert_true(GameState.collect_ash_shard("village_well"))
	assert_eq(GameState.flask_max_charges, 4)
	assert_false(GameState.collect_ash_shard("village_well"), "a shard cannot be farmed twice")
	assert_eq(GameState.flask_max_charges, 4)


# -------------------------------------------------------------------- world


func test_world_flags_are_one_shot() -> void:
	assert_true(GameState.set_flag("shortcut_opened"))
	assert_false(GameState.set_flag("shortcut_opened"), "raising twice is a no-op")
	assert_true(GameState.has_flag("shortcut_opened"))


func test_boss_defeats_persist_through_death() -> void:
	GameState.record_boss_defeat("cadwyn")
	GameState.add_embers(500)
	GameState.drop_bloodstain("arena", Vector3.ZERO)
	assert_true(GameState.is_boss_defeated("cadwyn"), "bosses stay dead; world enemies do not")


func test_enemy_death_credits_embers_through_the_bus() -> void:
	# The wiring, not just the model: Enemy emits, GameState credits, nothing calls anything else.
	EventBus.enemy_died.emit(null, 120)
	assert_eq(GameState.embers, 120, "a Husk is worth 120 at Biome 1 scale")
