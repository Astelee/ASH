extends GutTest

## The level cost curve from docs/GDD.md §7.2.
##
## The published table is *regenerated* from the formula here rather than hardcoded, so this suite
## fails the moment the design document and the code disagree — in either direction.

var _p: Progression


func before_each() -> void:
	_p = Progression.new()


func test_both_spec_anchors_hold() -> void:
	# The whole reason the exponent is 1.535 and not the spec's original 1.52: at 1.52 these two
	# could not both be true.
	assert_eq(_p.cost(1), 90, "level 1 -> 2 costs exactly 90")
	assert_eq(_p.cost(30), 16658, "level 30 -> 31 is the spec's '~17,000'")


func test_published_cost_table() -> void:
	var expected := {
		1: 90,
		2: 260,
		3: 485,
		4: 755,
		5: 1064,
		6: 1408,
		7: 1784,
		8: 2190,
		9: 2624,
		10: 3084,
		11: 3570,
		12: 4081,
		13: 4614,
		14: 5170,
		15: 5748,
		16: 6346,
		17: 6965,
		18: 7604,
		19: 8262,
		20: 8939,
		25: 12591,
		30: 16658,
	}
	for level: int in expected:
		assert_eq(_p.cost(level), expected[level], "cost(%d)" % level)


func test_published_cumulative_table() -> void:
	var expected := {2: 90, 5: 1590, 10: 10660, 15: 31179, 20: 66104, 25: 117929, 31: 205517}
	for level: int in expected:
		assert_eq(_p.cumulative_to_reach(level), expected[level], "reach L%d" % level)


func test_cost_rises_monotonically() -> void:
	for level: int in range(1, 60):
		assert_gt(_p.cost(level + 1), _p.cost(level), "cost must never plateau at L%d" % level)


func test_curve_is_gentler_than_a_cubic() -> void:
	# Deliberately not FromSoft's cubic: their games run to SL 800, Ashfall's useful range ends near
	# L40, and a cubic over 40 levels makes the last five cost more than everything before them.
	var ratio := float(_p.cost(40)) / float(_p.cost(10))
	assert_lt(ratio, 16.0, "a cubic over this range would exceed 16x")
	assert_gt(ratio, 4.0, "but it still has to climb")


func test_back_half_of_the_climb_costs_its_share() -> void:
	var to_thirty := _p.cumulative_to_reach(30)
	var to_forty := _p.cumulative_to_reach(40)
	var after := float(to_forty - to_thirty) / float(to_forty)
	assert_between(after, 0.45, 0.60, "roughly half the total spend happens after L30")


func test_stat_points_one_per_level_plus_a_fifth() -> void:
	for pair: Array in [[1, 0], [2, 1], [5, 5], [10, 11], [20, 23], [30, 35], [40, 47]]:
		assert_eq(_p.points_at_level(pair[0]), pair[1], "points at L%d" % pair[0])


func test_fifth_levels_grant_two_points() -> void:
	assert_eq(_p.points_for_level_up(4), 2, "reaching L5 grants the bonus point")
	assert_eq(_p.points_for_level_up(3), 1, "an ordinary level grants one")


func test_affordability() -> void:
	assert_true(_p.can_afford(1, 90), "exactly enough is enough")
	assert_false(_p.can_afford(1, 89), "one short is short")


func test_levels_affordable_spends_greedily() -> void:
	# 90 + 260 + 485 = 835 reaches L4 exactly.
	var result := _p.levels_affordable(1, 835)
	assert_eq(result[0], 4, "three levels bought")
	assert_eq(result[1], 0, "no change left")


func test_levels_affordable_returns_change() -> void:
	var result := _p.levels_affordable(1, 100)
	assert_eq(result[0], 2, "one level")
	assert_eq(result[1], 10, "and the remainder")


func test_biome_one_clear_lands_the_player_at_level_twelve() -> void:
	# The Ember economy solve from GDD §7.2b. Drop values are not free parameters -- they were
	# derived backwards from this curve, and changing one means redoing this sum.
	var census := {
		"husk": [60, 120],
		"wretch": [25, 60],
		"cultist": [15, 175],
		"warden": [6, 400],
		"bell": [2, 900]
	}
	var total := 4500  # Ser Cadwyn
	for key: String in census:
		total += census[key][0] * census[key][1]
	assert_eq(total, 20025, "one full clear of Ashfall Village")

	var reached: int = _p.levels_affordable(1, total)[0]
	assert_eq(reached, 12, "which is a genre-appropriate level for leaving a first area")
