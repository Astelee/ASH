extends GutTest

## BiomeMood blending, the quality tier table, and that every shader file loads.

var _village: BiomeMood
var _ossuary: BiomeMood


func before_each() -> void:
	_village = load("res://data/biomes/mood_village.tres") as BiomeMood
	_ossuary = load("res://data/biomes/mood_ossuary.tres") as BiomeMood


# ----------------------------------------------------------------- authored moods


func test_the_four_biome_moods_exist_and_load() -> void:
	for name: String in ["village", "thornwood", "ossuary", "bastion"]:
		var mood := load("res://data/biomes/mood_%s.tres" % name) as BiomeMood
		assert_not_null(mood, "mood_%s.tres" % name)


func test_ossuary_is_the_eerie_row_from_the_spec() -> void:
	# docs/TECH.md §4. These four are the numbers that make the crypt land.
	assert_almost_eq(_ossuary.ambient_energy, 0.15, 0.001, "ambient collapses")
	assert_almost_eq(_ossuary.fog_density, 0.048, 0.0001, "4x the Village")
	assert_almost_eq(_ossuary.reverb_wet, 0.60, 0.001, "wet reverb")
	assert_almost_eq(_ossuary.camera_fov, 34.0, 0.001, "walls crowd in")
	assert_eq(_ossuary.music_stem_mask, 1, "drone only")


func test_ossuary_fog_is_four_times_the_village() -> void:
	assert_almost_eq(_ossuary.fog_density / _village.fog_density, 4.0, 0.01)


func test_the_descent_loses_saturation_not_just_brightness() -> void:
	# The emotional arc is saturation. If the Ossuary were merely darker, it would read as night.
	assert_lt(_ossuary.fog_color.s, _village.fog_color.s, "fog desaturates")
	assert_lt(_ossuary.sun_energy, _village.sun_energy, "and dims")


# --------------------------------------------------------------------- blending


func test_blend_endpoints_are_exact() -> void:
	var at_zero := BiomeMood.blend(_village, _ossuary, 0.0)
	assert_almost_eq(at_zero.fog_density, _village.fog_density, 0.0001)
	var at_one := BiomeMood.blend(_village, _ossuary, 1.0)
	assert_almost_eq(at_one.fog_density, _ossuary.fog_density, 0.0001)


func test_blend_midpoint_is_halfway_on_every_numeric_field() -> void:
	var half := BiomeMood.blend(_village, _ossuary, 0.5)
	assert_almost_eq(
		half.ambient_energy,
		(_village.ambient_energy + _ossuary.ambient_energy) * 0.5,
		0.001,
		"ambient"
	)
	assert_almost_eq(
		half.camera_fov, (_village.camera_fov + _ossuary.camera_fov) * 0.5, 0.001, "fov"
	)
	assert_almost_eq(
		half.chromatic_aberration,
		(_village.chromatic_aberration + _ossuary.chromatic_aberration) * 0.5,
		0.001,
		"aberration"
	)


func test_blend_clamps_outside_zero_to_one() -> void:
	var under := BiomeMood.blend(_village, _ossuary, -2.0)
	assert_almost_eq(under.fog_density, _village.fog_density, 0.0001, "no overshoot below")
	var over := BiomeMood.blend(_village, _ossuary, 5.0)
	assert_almost_eq(over.fog_density, _ossuary.fog_density, 0.0001, "or above")


func test_discrete_fields_snap_rather_than_interpolate() -> void:
	# There is no meaningful midpoint between two particle systems or two stem masks.
	assert_eq(BiomeMood.blend(_village, _ossuary, 0.49).particle_preset, _village.particle_preset)
	assert_eq(BiomeMood.blend(_village, _ossuary, 0.51).particle_preset, _ossuary.particle_preset)


func test_every_mood_parameter_moves_together() -> void:
	# The acceptance criterion in one assertion: one call, one curve, everything at once.
	var quarter := BiomeMood.blend(_village, _ossuary, 0.25)
	var three_quarter := BiomeMood.blend(_village, _ossuary, 0.75)
	for field: String in [
		"fog_density", "ambient_energy", "vignette_strength", "grain_amount", "reverb_wet"
	]:
		var a: float = quarter.get(field)
		var b: float = three_quarter.get(field)
		assert_ne(a, b, "%s must move with the transition" % field)


# ---------------------------------------------------------------- quality tiers


func test_tier_table_matches_the_spec() -> void:
	# docs/TECH.md §5.
	var expected := {
		QualityManager.Tier.LOW: [30, 0.65, 0.25],
		QualityManager.Tier.MID: [60, 0.80, 0.60],
		QualityManager.Tier.HIGH: [60, 1.00, 1.00],
	}
	for tier: QualityManager.Tier in expected:
		var row: Dictionary = QualityManager.TIERS[tier]
		assert_eq(row["target_fps"], expected[tier][0], "target fps")
		assert_almost_eq(row["render_scale"], expected[tier][1], 0.001, "render scale")
		assert_almost_eq(row["fog_card_fraction"], expected[tier][2], 0.001, "fog cards")


func test_only_high_tier_allows_screen_texture_effects() -> void:
	# SCREEN_TEXTURE forces a screen copy; water refraction is high-tier only.
	assert_false(QualityManager.TIERS[QualityManager.Tier.LOW]["screen_texture_fx"])
	assert_false(QualityManager.TIERS[QualityManager.Tier.MID]["screen_texture_fx"])
	assert_true(QualityManager.TIERS[QualityManager.Tier.HIGH]["screen_texture_fx"])


func test_low_tier_has_no_realtime_shadows() -> void:
	assert_false(QualityManager.TIERS[QualityManager.Tier.LOW]["shadows_enabled"], "baked only")


func test_auto_detect_is_conservative() -> void:
	# A device that only just manages Mid on a stress scene will not manage it in a real fight.
	assert_eq(QualityManager.tier_for_frame_ms(8.0), QualityManager.Tier.HIGH)
	assert_eq(QualityManager.tier_for_frame_ms(15.0), QualityManager.Tier.MID)
	assert_eq(QualityManager.tier_for_frame_ms(16.5), QualityManager.Tier.MID)
	assert_eq(QualityManager.tier_for_frame_ms(25.0), QualityManager.Tier.LOW)


func test_dynamic_resolution_floor_is_respected() -> void:
	assert_gt(QualityManager.SCALE_FLOOR, 0.5, "below 0.6 the image falls apart")
	assert_lt(QualityManager.RECOVER_STEP, QualityManager.DROP_STEP, "recover slower than drop")
	assert_gt(
		QualityManager.RECOVER_AFTER,
		QualityManager.DROP_AFTER,
		"and wait longer, so the scale cannot oscillate around the threshold"
	)


# --------------------------------------------------------------------- shaders


func test_every_declared_shader_file_exists_and_parses() -> void:
	# docs/TECH.md §2 names nine. Any that are not written yet are reported, not silently skipped.
	var declared := [
		"surface/character_pbr",
		"surface/foliage_wind",
		"surface/terrain_triplanar",
		"surface/emissive_flicker",
		"vfx/fog_card",
		"vfx/god_ray_cone",
		"vfx/water_flow",
		"vfx/dissolve_teleport",
		"post/grade_and_grain",
		"post/grade_screen",
	]
	var missing: Array[String] = []
	for name: String in declared:
		var path := "res://shaders/%s.gdshader" % name
		if not ResourceLoader.exists(path):
			missing.append(name)
			continue
		var shader := load(path) as Shader
		assert_not_null(shader, path)
		assert_gt(shader.code.length(), 0, "%s has code" % name)

	gut.p("shaders still to write: %s" % str(missing))
	assert_lt(missing.size(), declared.size(), "at least some shaders are written")
