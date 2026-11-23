extends GutTest

## Stat derivations from docs/GDD.md §7.3, including the Vigor soft cap.

var _stats: StatBlock


func before_each() -> void:
	_stats = StatBlock.new()


func _with_vigor(value: int) -> float:
	_stats.vigor = value
	return _stats.max_health()


func test_health_table_below_the_soft_cap() -> void:
	assert_almost_eq(_with_vigor(0), 100.0, 0.01, "base HP")
	assert_almost_eq(_with_vigor(10), 240.0, 0.01)
	assert_almost_eq(_with_vigor(20), 380.0, 0.01)
	assert_almost_eq(_with_vigor(30), 520.0, 0.01, "at the soft cap")


func test_health_table_past_the_soft_cap() -> void:
	# 14/point to 30, then roughly a quarter of that to 50, then a trickle.
	assert_almost_eq(_with_vigor(40), 560.0, 0.5, "diminished returns")
	assert_almost_eq(_with_vigor(50), 600.0, 0.5, "second breakpoint")
	assert_almost_eq(_with_vigor(60), 610.0, 0.5, "a token trickle")


func test_soft_cap_actually_bends_the_curve() -> void:
	# Without the taper a single-stat build would strictly dominate, because level cost never
	# depends on which stat you buy.
	var before := _with_vigor(30) - _with_vigor(29)
	var after := _with_vigor(31) - _with_vigor(30)
	assert_lt(after, before * 0.5, "a point past the cap is worth less than half")


func test_stamina_table() -> void:
	for pair: Array in [[0, 100.0], [10, 160.0], [20, 220.0], [30, 280.0], [40, 340.0]]:
		_stats.endurance = pair[0]
		assert_almost_eq(_stats.max_stamina(), pair[1], 0.01, "endurance %d" % pair[0])


func test_stamina_regen_table() -> void:
	for pair: Array in [[0, 18.0], [10, 22.0], [20, 26.0], [30, 30.0], [40, 34.0]]:
		_stats.endurance = pair[0]
		assert_almost_eq(_stats.stamina_regen(), pair[1], 0.01, "endurance %d" % pair[0])


func test_iframe_bonus_is_one_hundredth_per_ten_finesse() -> void:
	_stats.finesse = 40
	assert_almost_eq(_stats.iframe_bonus(), 0.04, 0.0001, "0.24 s window becomes 0.28 s")


func test_get_stat_reaches_every_stat() -> void:
	_stats.vigor = 1
	_stats.endurance = 2
	_stats.might = 3
	_stats.finesse = 4
	_stats.ember_bound = 5
	assert_eq(_stats.get_stat(StatBlock.Stat.VIGOR), 1)
	assert_eq(_stats.get_stat(StatBlock.Stat.ENDURANCE), 2)
	assert_eq(_stats.get_stat(StatBlock.Stat.MIGHT), 3)
	assert_eq(_stats.get_stat(StatBlock.Stat.FINESSE), 4)
	assert_eq(_stats.get_stat(StatBlock.Stat.EMBER_BOUND), 5)


func test_enemy_stat_blocks_author_flat_pools() -> void:
	# Enemies express "120 HP" by authoring the curve base rather than allocating Vigor, so players
	# and enemies share one derivation path.
	_stats.health_base = 120.0
	_stats.health_per_vigor = 0.0
	_stats.vigor = 0
	assert_almost_eq(_stats.max_health(), 120.0, 0.01, "the Husk")
