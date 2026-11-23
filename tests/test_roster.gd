extends GutTest

## The Phase 6 roster and Ser Cadwyn.
##
## Every enemy's identity is meant to live in its `.tres`, so most of this reads data rather than
## driving behaviour — if a stat table and the GDD ever disagree, that is a real bug.

const ROSTER := {
	"enemy_husk": "Husk",
	"enemy_crow_mask": "Crow-Mask Cultist",
	"enemy_warden": "Warden",
	"enemy_gravewretch": "Gravewretch",
	"enemy_bell_bearer": "Bell-Bearer",
}


func before_each() -> void:
	GameState.begin_new_run(null)


func _data(name: String) -> EnemyData:
	return load("res://data/enemies/%s.tres" % name) as EnemyData


# ------------------------------------------------------------------- the roster


func test_all_five_enemies_exist_and_load() -> void:
	for file: String in ROSTER:
		var data := _data(file)
		assert_not_null(data, file)
		assert_eq(data.display_name, ROSTER[file])


func test_every_enemy_has_a_moveset_and_a_weapon() -> void:
	for file: String in ROSTER:
		var data := _data(file)
		assert_gt(data.moveset.size(), 0, "%s has at least one move" % file)
		assert_not_null(data.weapon, "%s has a weapon" % file)
		assert_not_null(data.stats, "%s has a stat block" % file)


func test_stat_table_matches_the_gdd() -> void:
	# docs/GDD.md §9. HP lives on the stat block's curve base; poise and defence on the enemy.
	var expected := {
		"enemy_husk": [120.0, 40.0, 24.0, 120],
		"enemy_crow_mask": [90.0, 25.0, 18.0, 175],
		"enemy_warden": [260.0, 95.0, 46.0, 400],
		"enemy_gravewretch": [55.0, 15.0, 12.0, 60],
		"enemy_bell_bearer": [340.0, 120.0, 40.0, 900],
	}
	for file: String in expected:
		var data := _data(file)
		var row: Array = expected[file]
		assert_almost_eq(data.stats.max_health(), row[0], 0.01, "%s HP" % file)
		assert_almost_eq(data.max_poise, row[1], 0.01, "%s poise" % file)
		assert_almost_eq(data.defense, row[2], 0.01, "%s defence" % file)
		assert_eq(data.ember_drop, row[3], "%s Embers" % file)


func test_resistances_match_the_gdd() -> void:
	assert_almost_eq(_data("enemy_crow_mask").resist_rot, 0.5, 0.01, "Rot +50 %")
	assert_almost_eq(_data("enemy_warden").resist_physical, 0.4, 0.01, "Phys +40 %")
	assert_almost_eq(_data("enemy_warden").resist_fire, -0.25, 0.01, "Fire -25 %, a weakness")
	assert_almost_eq(_data("enemy_gravewretch").resist_holy, -0.5, 0.01, "Holy -50 %")


func test_the_gravewretch_holy_weakness_actually_bites() -> void:
	# A negative resistance has to increase damage, not clamp to zero.
	var data := _data("enemy_gravewretch")
	var physical := Damage.after_defense(
		100.0, data.defense, data.resist_for(DamagePacket.Type.PHYSICAL)
	)
	var holy := Damage.after_defense(100.0, data.defense, data.resist_for(DamagePacket.Type.HOLY))
	assert_almost_eq(holy, physical * 1.5, 0.1, "Holy hits a wretch half again as hard")


# -------------------------------------------------------------- the archetypes


func test_each_enemy_has_exactly_one_archetype() -> void:
	# The four archetype flags are meant to be mutually exclusive. Two at once would make
	# commit_state() ambiguous, and the enemy would silently pick whichever branch came first.
	for file: String in ROSTER:
		var data := _data(file)
		var flags := 0
		flags += 1 if data.is_ranged else 0
		flags += 1 if data.lunges_from_offscreen else 0
		flags += 1 if data.shield_absorption > 0.0 else 0
		flags += 1 if data.aura_radius > 0.0 else 0
		assert_lt(flags, 2, "%s has at most one archetype" % file)


func test_the_cultist_is_ranged_and_carries_a_projectile() -> void:
	var data := _data("enemy_crow_mask")
	assert_true(data.is_ranged)
	assert_not_null(data.projectile_scene, "a cultist with no flask is a cultist that cannot fight")
	assert_gt(data.retreat_range, 0.0, "and it backs away when closed on")
	assert_gt(data.attack_range, data.retreat_range, "throwing out-ranges its comfort zone")


func test_the_warden_shield_makes_trading_a_losing_move() -> void:
	var data := _data("enemy_warden")
	assert_gt(data.shield_absorption, 0.5, "a straight trade is meant to lose")
	assert_lt(data.shield_absorption, 1.0, "but never total, or chip damage would be impossible")


func test_the_bell_bearer_buffs_and_is_worth_killing_first() -> void:
	var data := _data("enemy_bell_bearer")
	assert_gt(data.aura_radius, 0.0)
	assert_gt(data.aura_damage_bonus, 0.0)
	assert_gt(data.ember_drop, _data("enemy_warden").ember_drop, "and pays for the priority")


func test_the_gravewretch_lunges() -> void:
	var data := _data("enemy_gravewretch")
	assert_true(data.lunges_from_offscreen)
	assert_gt(data.lunge_speed, data.move_speed * 2.0, "the pounce must outpace the walk")
	assert_gt(data.detect_range, 15.0, "it commits from beyond comfortable reading distance")


# ------------------------------------------------------------------- Ser Cadwyn


func test_cadwyn_data_is_boss_scale() -> void:
	var data := _data("boss_cadwyn")
	assert_gt(data.stats.max_health(), 1000.0, "a boss pool, not an elite one")
	assert_eq(data.ember_drop, 4500, "the §7.2b economy solve depends on this")


func test_cadwyn_scene_declares_two_phases() -> void:
	var scene := load("res://actors/bosses/SerCadwyn.tscn") as PackedScene
	assert_not_null(scene)
	var boss := scene.instantiate() as Boss
	assert_not_null(boss, "SerCadwyn is a Boss, not a plain Enemy")
	autofree(boss)

	assert_eq(boss.boss_id, "cadwyn")
	assert_eq(boss.phase_thresholds.size(), 1, "one threshold means two phases")
	assert_almost_eq(boss.phase_thresholds[0], 0.55, 0.001, "GDD §9: phase 2 at 55 % HP")
	assert_eq(boss.phase_movesets.size(), 1, "phase 2 swaps in its own move")
	assert_not_null(boss.add_scene, "and brings adds")
	assert_eq(boss.adds_per_phase, 2)


func test_the_phase_two_move_is_a_guaranteed_break() -> void:
	# The rust slam is the escalation: phase 2 has to change how the fight is fought, not just how
	# much HP is left.
	var slam := load("res://data/moves/cadwyn_rust_slam.tres") as AttackMove
	assert_true(slam.guaranteed_poise_break, "it breaks poise regardless of the pool")
	assert_gt(slam.windup, 0.8, "and telegraphs long enough to be dodged")


func test_a_defeated_boss_does_not_return() -> void:
	GameState.record_boss_defeat("cadwyn")
	assert_true(GameState.is_boss_defeated("cadwyn"))
	# Resting respawns world enemies; a boss must ignore it entirely.
	EventBus.rested_at_wayshrine.emit("village_gate")
	assert_true(GameState.is_boss_defeated("cadwyn"), "rest does not resurrect a boss")


func test_a_defeated_boss_survives_a_save_round_trip() -> void:
	GameState.record_boss_defeat("cadwyn")
	var snapshot := GameState.to_dict()
	GameState.begin_new_run(null)
	GameState.from_dict(snapshot)
	assert_true(GameState.is_boss_defeated("cadwyn"))


func test_the_fog_gate_opens_once_the_boss_is_dead() -> void:
	var gate := FogGate.new()
	gate.boss_id = "cadwyn"
	add_child_autofree(gate)
	assert_false(gate.is_open(), "sealed while the boss lives")

	GameState.record_boss_defeat("cadwyn")
	assert_true(gate.is_open(), "and open forever after")
