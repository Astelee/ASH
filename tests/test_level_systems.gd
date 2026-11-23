extends GutTest

## Phase 5 level systems: chunk snapping, encounter respawn, and the shortcut gate.
##
## The encounter and gate tests matter beyond Phase 5 — they are where the Phase 3 death loop
## finally closes. World enemies must come back on rest; bosses and opened shortcuts must not.


func before_each() -> void:
	GameState.begin_new_run(null)


# ----------------------------------------------------------------- chunk snapping


func _chunk(entry: Vector3, exit_point: Vector3) -> LevelChunk:
	var chunk := LevelChunk.new()
	chunk.entry_offset = entry
	chunk.exit_offset = exit_point
	add_child_autofree(chunk)
	return chunk


func test_chunk_reports_its_connectors_in_world_space() -> void:
	var chunk := _chunk(Vector3.ZERO, Vector3(24.0, 0.0, 0.0))
	chunk.global_position = Vector3(10.0, 2.0, 0.0)
	assert_almost_eq(chunk.entry_point().x, 10.0, 0.001, "entry follows the transform")
	assert_almost_eq(chunk.exit_point().x, 34.0, 0.001, "so does exit")


func test_chunk_span_is_the_connector_distance() -> void:
	assert_almost_eq(_chunk(Vector3.ZERO, Vector3(24.0, 0.0, 0.0)).span(), 24.0, 0.001)


func test_snapping_puts_the_entry_on_the_previous_exit() -> void:
	# The acceptance criterion: a designer drags chunks together and the geometry lines up.
	var first := _chunk(Vector3.ZERO, Vector3(24.0, 0.0, 0.0))
	first.global_position = Vector3.ZERO

	var second := _chunk(Vector3.ZERO, Vector3(18.0, 0.0, 0.0))
	second.snap_to = first

	assert_almost_eq(second.entry_point().x, first.exit_point().x, 0.001, "connectors meet")
	assert_almost_eq(second.exit_point().x, 42.0, 0.001, "and the chain extends")


func test_snapping_handles_a_nonzero_entry_offset() -> void:
	var first := _chunk(Vector3.ZERO, Vector3(20.0, 0.0, 0.0))
	first.global_position = Vector3.ZERO
	var second := _chunk(Vector3(-6.0, 0.0, 0.0), Vector3(14.0, 0.0, 0.0))
	second.snap_to = first
	assert_almost_eq(second.entry_point().x, 20.0, 0.001, "offset entry still lands on the exit")


func test_a_chunk_cannot_snap_to_itself() -> void:
	var chunk := _chunk(Vector3.ZERO, Vector3(24.0, 0.0, 0.0))
	chunk.global_position = Vector3(5.0, 0.0, 0.0)
	chunk.snap_to = chunk
	assert_almost_eq(chunk.global_position.x, 5.0, 0.001, "self-snap is ignored, not infinite")


# ----------------------------------------------------------------- shortcut gate


func test_shortcut_starts_closed_and_persists_once_opened() -> void:
	var gate := ShortcutGate.new()
	gate.gate_id = "village_shortcut"
	add_child_autofree(gate)
	assert_false(gate.is_open(), "closed on a fresh run")

	GameState.set_flag("shortcut:village_shortcut")
	assert_true(gate.is_open(), "the world flag is the whole state")


func test_an_opened_shortcut_survives_the_death_loop() -> void:
	# Dying must not close a shortcut. It is the one thing that makes the second run shorter.
	GameState.set_flag("shortcut:village_shortcut")
	GameState.add_embers(500)
	GameState.drop_bloodstain("ashfall_village", Vector3.ZERO)
	assert_true(GameState.has_flag("shortcut:village_shortcut"), "still open after death")


func test_an_opened_shortcut_survives_a_save_round_trip() -> void:
	GameState.set_flag("shortcut:village_shortcut")
	var snapshot := GameState.to_dict()
	GameState.begin_new_run(null)
	assert_false(GameState.has_flag("shortcut:village_shortcut"), "cleared")
	GameState.from_dict(snapshot)
	assert_true(GameState.has_flag("shortcut:village_shortcut"), "restored")


# -------------------------------------------------------------- encounter volume


func test_cleared_once_encounters_record_a_flag() -> void:
	var volume := EncounterVolume.new()
	volume.encounter_id = "gatehouse"
	volume.clear_once = true
	add_child_autofree(volume)

	GameState.set_flag("encounter_cleared:gatehouse")
	volume.respawn()
	assert_eq(volume.alive_count(), 0, "a one-shot encounter does not come back")


func test_ordinary_encounters_are_not_flagged() -> void:
	# Patrols must respawn on every rest; only scripted fights are permanent.
	var volume := EncounterVolume.new()
	volume.encounter_id = "patrol"
	volume.clear_once = false
	add_child_autofree(volume)
	volume.respawn()
	assert_false(GameState.has_flag("encounter_cleared:patrol"), "no flag raised")


func test_boss_defeats_and_encounter_clears_are_separate_records() -> void:
	# Bosses persist through rest; world enemies do not. Conflating them would resurrect a boss.
	GameState.record_boss_defeat("cadwyn")
	GameState.set_flag("encounter_cleared:gatehouse")
	assert_true(GameState.is_boss_defeated("cadwyn"))
	assert_true(GameState.has_flag("encounter_cleared:gatehouse"))
	assert_false(GameState.is_boss_defeated("gatehouse"), "an encounter is not a boss")


# -------------------------------------------------------------------- parallax


func test_parallax_factor_scales_camera_travel() -> void:
	var lane := ParallaxLane.new()
	lane.parallax_factor = 0.5
	var camera := Camera3D.new()
	add_child_autofree(camera)
	lane.camera = camera
	add_child_autofree(lane)
	lane.global_position = Vector3.ZERO

	camera.global_position = Vector3(10.0, 0.0, 0.0)
	lane._process(0.016)
	assert_almost_eq(lane.global_position.x, 5.0, 0.01, "half the camera travel")


func test_parallax_leaves_vertical_alone_by_default() -> void:
	# Vertical parallax makes the horizon bob during jumps, which reads as a loose world.
	var lane := ParallaxLane.new()
	lane.parallax_factor = 1.0
	var camera := Camera3D.new()
	add_child_autofree(camera)
	lane.camera = camera
	add_child_autofree(lane)
	lane.global_position = Vector3.ZERO

	camera.global_position = Vector3(0.0, 8.0, 0.0)
	lane._process(0.016)
	assert_almost_eq(lane.global_position.y, 0.0, 0.01, "no vertical drift")
