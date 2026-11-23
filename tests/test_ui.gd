extends GutTest

## Settings persistence, localization coverage, and the level-up screen.

const SETTINGS_PATH := "user://settings.cfg"

var _settings: Settings


func before_each() -> void:
	GameState.begin_new_run(null)
	_settings = Settings.new()
	Settings.override_for_test(_settings)


func after_all() -> void:
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(SETTINGS_PATH)
	Settings.override_for_test(null)


# ----------------------------------------------------------------- settings


func test_defaults_are_playable() -> void:
	# A corrupt or missing settings file must leave the game in a state you can actually play.
	assert_eq(_settings.quality_tier, QualityManager.Tier.MID)
	assert_true(_settings.damage_numbers)
	assert_almost_eq(_settings.brightness, 1.0, 0.001)
	assert_almost_eq(_settings.master_volume, 1.0, 0.001)
	assert_eq(_settings.sprint_mode, Settings.HoldMode.HOLD)


func test_settings_round_trip_through_disk() -> void:
	_settings.quality_tier = QualityManager.Tier.LOW
	_settings.brightness = 0.62
	_settings.damage_numbers = false
	_settings.subtitle_size = 48
	_settings.palette = Settings.Palette.DEUTERANOPIA
	_settings.sprint_mode = Settings.HoldMode.TOGGLE
	_settings.music_volume = 0.25
	_settings.save_to_disk()

	var loaded := Settings.new()
	loaded.load_from_disk()
	assert_eq(loaded.quality_tier, QualityManager.Tier.LOW)
	assert_almost_eq(loaded.brightness, 0.62, 0.001)
	assert_false(loaded.damage_numbers)
	assert_eq(loaded.subtitle_size, 48)
	assert_eq(loaded.palette, Settings.Palette.DEUTERANOPIA)
	assert_eq(loaded.sprint_mode, Settings.HoldMode.TOGGLE)
	assert_almost_eq(loaded.music_volume, 0.25, 0.001)


func test_control_layout_survives_a_round_trip() -> void:
	# The acceptance criterion: the layout editor must not lose the layout.
	_settings.set_offset(&"attack_light", Vector2(-40.0, 120.0))
	_settings.set_offset(&"dodge", Vector2(60.0, -30.0))

	var loaded := Settings.new()
	loaded.load_from_disk()
	assert_almost_eq(loaded.offset_for(&"attack_light").x, -40.0, 0.01)
	assert_almost_eq(loaded.offset_for(&"attack_light").y, 120.0, 0.01)
	assert_almost_eq(loaded.offset_for(&"dodge").y, -30.0, 0.01)


func test_an_unmoved_button_has_no_offset() -> void:
	assert_eq(_settings.offset_for(&"never_touched"), Vector2.ZERO)


func test_restore_defaults_resets_everything() -> void:
	_settings.brightness = 0.2
	_settings.subtitle_size = 64
	_settings.haptics = false
	_settings.restore_defaults()
	assert_almost_eq(_settings.brightness, 1.0, 0.001)
	assert_eq(_settings.subtitle_size, 32)
	assert_true(_settings.haptics)


func test_settings_survive_a_deleted_save() -> void:
	# Settings live in their own ConfigFile precisely so wiping a run does not cost the player their
	# control layout and accessibility options.
	_settings.subtitle_size = 56
	_settings.save_to_disk()
	SaveSystem.delete_slot(0)

	var loaded := Settings.new()
	loaded.load_from_disk()
	assert_eq(loaded.subtitle_size, 56, "settings outlive the save file")


func test_every_accessibility_option_from_the_brief_exists() -> void:
	# docs/PLAN.md Phase 7 names these explicitly. A missing one is a missing deliverable.
	for name: String in [
		"palette",
		"damage_numbers",
		"camera_shake",
		"subtitle_size",
		"sprint_mode",
		"block_mode",
		"brightness",
		"haptics",
	]:
		assert_true(name in _settings, "settings expose '%s'" % name)


# ------------------------------------------------------------- localization


func test_every_ui_string_is_in_the_csv() -> void:
	var file := FileAccess.open("res://ui/strings.csv", FileAccess.READ)
	assert_not_null(file, "the string table exists")
	var keys: Array[String] = []
	file.get_csv_line()  # header row
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() >= 2 and not row[0].is_empty():
			keys.append(row[0])
	file.close()

	assert_gt(keys.size(), 40, "the table is populated")
	for required: String in [
		"UI_YOU_DIED",
		"UI_RESUME",
		"UI_SETTINGS",
		"UI_LEVEL_UP",
		"UI_EMBERS",
		"UI_STAT_VIGOR",
		"UI_PALETTE",
		"UI_SPRINT_MODE",
		"UI_SUBTITLE_SIZE",
	]:
		assert_has(keys, required, "%s is translatable" % required)


func test_string_keys_are_unique() -> void:
	# A duplicate key silently wins or loses depending on load order, which is the worst kind of
	# localization bug: it only shows up in one language.
	var file := FileAccess.open("res://ui/strings.csv", FileAccess.READ)
	var seen: Array[String] = []
	file.get_csv_line()  # header row
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() >= 2 and not row[0].is_empty():
			assert_false(seen.has(row[0]), "duplicate key %s" % row[0])
			seen.append(row[0])
	file.close()


# ------------------------------------------------------- stat allocation


func test_levelling_and_allocating_are_separate_actions() -> void:
	# Buying a level banks a point; spending the point is a second decision. Merging them means a
	# misclick costs the level as well as the point.
	var screen := StatAllocation.new()
	add_child_autofree(screen)

	GameState.add_embers(90)
	assert_true(screen.buy_level(), "the level is affordable")
	assert_eq(GameState.level, 2)
	assert_eq(GameState.unspent_points, 1, "banked, not spent")

	assert_true(screen.allocate(StatBlock.Stat.VIGOR))
	assert_eq(GameState.unspent_points, 0)
	assert_eq(GameState.stats.vigor, 11)


func test_buying_a_level_you_cannot_afford_changes_nothing() -> void:
	var screen := StatAllocation.new()
	add_child_autofree(screen)
	GameState.add_embers(50)
	assert_false(screen.buy_level())
	assert_eq(GameState.level, 1)
	assert_eq(GameState.embers, 50, "the purse is untouched")


func test_allocating_raises_the_derived_pool() -> void:
	var screen := StatAllocation.new()
	add_child_autofree(screen)
	GameState.add_embers(90)
	screen.buy_level()

	var before := GameState.stats.max_health()
	screen.allocate(StatBlock.Stat.VIGOR)
	assert_almost_eq(GameState.stats.max_health(), before + 14.0, 0.01, "14 HP per Vigor")


func test_the_screen_covers_every_stat() -> void:
	assert_eq(StatAllocation.STATS.size(), 5, "all five are allocatable")
	for stat: StatBlock.Stat in StatAllocation.STATS:
		assert_true(StatAllocation.LABELS.has(stat), "stat %d has a label key" % stat)
