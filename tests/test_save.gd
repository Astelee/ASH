extends GutTest

## Save serialization, the checksum envelope, and the migration chain.
##
## Uses a scratch slot and deletes it in teardown, so the suite never touches a real run.

const TEST_SLOT: int = 2


func before_each() -> void:
	GameState.begin_new_run(null)


func after_all() -> void:
	SaveSystem.delete_slot(TEST_SLOT)


func _populate() -> void:
	GameState.level = 7
	GameState.embers = 1204
	GameState.unspent_points = 2
	GameState.stats.vigor = 14
	GameState.stats.might = 21
	GameState.flask_charges = 2
	GameState.flask_max_charges = 5
	GameState.ash_shards = ["village_well", "crypt_stair"]
	GameState.wayshrine = "village_gate"
	GameState.world_flags = ["shortcut_opened"]
	GameState.bosses_defeated = ["cadwyn"]
	GameState.bloodstain_level = "village_02"
	GameState.bloodstain_position = Vector3(12.5, 3.0, 0.0)
	GameState.bloodstain_embers = 480


# ------------------------------------------------------------------ round trip


func test_dictionary_round_trip_preserves_everything() -> void:
	_populate()
	var snapshot := GameState.to_dict()

	GameState.begin_new_run(null)
	assert_eq(GameState.level, 1, "cleared before restore")

	GameState.from_dict(snapshot)
	assert_eq(GameState.level, 7)
	assert_eq(GameState.embers, 1204)
	assert_eq(GameState.unspent_points, 2)
	assert_eq(GameState.stats.vigor, 14)
	assert_eq(GameState.stats.might, 21)
	assert_eq(GameState.flask_charges, 2)
	assert_eq(GameState.flask_max_charges, 5)
	assert_eq(GameState.ash_shards.size(), 2)
	assert_eq(GameState.wayshrine, "village_gate")
	assert_true(GameState.has_flag("shortcut_opened"))
	assert_true(GameState.is_boss_defeated("cadwyn"))
	assert_eq(GameState.bloodstain_embers, 480)
	assert_almost_eq(GameState.bloodstain_position.x, 12.5, 0.001)


func test_round_trip_survives_json() -> void:
	# The dictionary must survive an actual JSON encode/decode, not just a copy — JSON turns ints
	# into floats and typed arrays into untyped ones, which is where naive save code breaks.
	_populate()
	var text := JSON.stringify(GameState.to_dict())
	var parsed: Variant = JSON.parse_string(text)
	assert_true(parsed is Dictionary, "valid JSON")

	GameState.begin_new_run(null)
	GameState.from_dict(parsed)
	assert_eq(GameState.level, 7, "ints survive the float round trip")
	assert_eq(GameState.ash_shards.size(), 2, "arrays retype cleanly")


func test_partial_save_loads_with_defaults() -> void:
	# A hand-edited or truncated save must load, not crash.
	GameState.from_dict({"player": {"level": 3}})
	assert_eq(GameState.level, 3)
	assert_eq(GameState.embers, 0, "missing fields default")
	assert_eq(GameState.flask_max_charges, GameState.STARTING_FLASK_CHARGES)


# -------------------------------------------------------------------- envelope


func test_envelope_carries_version_and_checksum() -> void:
	var envelope := SaveSystem.build_envelope(GameState.to_dict())
	assert_eq(envelope["version"], SaveMigrations.CURRENT_VERSION)
	assert_true(str(envelope["checksum"]).begins_with("sha256:"))
	assert_true(SaveSystem.verify_envelope(envelope), "its own checksum validates")


func test_tampered_payload_fails_its_checksum() -> void:
	_populate()
	var envelope := SaveSystem.build_envelope(GameState.to_dict())
	envelope["payload"] = str(envelope["payload"]).replace("1204", "999999")
	assert_false(SaveSystem.verify_envelope(envelope), "edited Embers are detected")


func test_envelope_body_decodes_back() -> void:
	_populate()
	var envelope := SaveSystem.build_envelope(GameState.to_dict())
	var body := SaveSystem.envelope_body(envelope)
	assert_eq(int(body["player"]["level"]), 7, "the payload string parses back to the model")


# ------------------------------------------------------------------- file i/o


func test_file_round_trip() -> void:
	_populate()
	assert_true(SaveSystem.save_to_slot(TEST_SLOT), "write succeeds")
	assert_true(SaveSystem.slot_exists(TEST_SLOT), "the live file exists")

	GameState.begin_new_run(null)
	assert_true(SaveSystem.load_from_slot(TEST_SLOT), "read succeeds")
	assert_eq(GameState.level, 7, "state came back")
	assert_eq(GameState.embers, 1204)


func test_second_write_rotates_a_backup() -> void:
	# Two writes must leave two readable files. A single corrupt write should never be able to take
	# the run with it.
	_populate()
	SaveSystem.save_to_slot(TEST_SLOT)
	GameState.embers = 5000
	SaveSystem.save_to_slot(TEST_SLOT)

	var backup := SaveSystem.slot_path(TEST_SLOT).replace(
		SaveSystem.EXTENSION, SaveSystem.BACKUP_EXTENSION
	)
	assert_true(FileAccess.file_exists(backup), "the previous write was rotated, not overwritten")


func test_no_temp_file_survives_a_successful_write() -> void:
	_populate()
	SaveSystem.save_to_slot(TEST_SLOT)
	var temp := SaveSystem.slot_path(TEST_SLOT).replace(
		SaveSystem.EXTENSION, SaveSystem.TEMP_EXTENSION
	)
	assert_false(FileAccess.file_exists(temp), "the temp file was renamed, not copied")


func test_loading_an_empty_slot_fails_cleanly() -> void:
	SaveSystem.delete_slot(TEST_SLOT)
	assert_false(SaveSystem.load_from_slot(TEST_SLOT), "returns false rather than crashing")


# ------------------------------------------------------------------ migrations


func test_v1_save_migrates_to_current() -> void:
	# The acceptance criterion: a hand-written v1 payload, with no flask and no gear, must arrive
	# playable. A returning player reloading into a run with no healing would be a silent,
	# unwinnable state rather than an obvious bug.
	var v1 := {
		"player": {"level": 5, "embers": 300, "stats": {"vigor": 12}},
		"world": {"wayshrine": "village_gate", "flags": [], "bosses_defeated": []},
		"bloodstain": {"level_id": "", "position": [0.0, 0.0, 0.0], "embers": 0},
	}
	var migrated := SaveMigrations.migrate(v1, 1)

	assert_true(migrated.has("flask"), "v2 added the flask")
	assert_eq(migrated["flask"]["charges"], 3, "and it arrives full, not empty")
	assert_true(migrated.has("gear"), "v2 added gear")
	assert_eq(migrated["player"]["level"], 5, "v1 data is untouched")


func test_migration_does_not_mutate_its_input() -> void:
	var v1 := {"player": {"level": 5}}
	SaveMigrations.migrate(v1, 1)
	assert_false(v1.has("flask"), "the caller's dictionary is left alone")


func test_current_version_migration_is_a_no_op() -> void:
	var payload := {"player": {"level": 9}, "flask": {"charges": 1}}
	var result := SaveMigrations.migrate(payload, SaveMigrations.CURRENT_VERSION)
	assert_eq(result["flask"]["charges"], 1, "an existing flask is not reset")


func test_a_newer_save_is_refused_not_guessed_at() -> void:
	assert_false(SaveMigrations.can_load(SaveMigrations.CURRENT_VERSION + 1))
	var reason := SaveMigrations.rejection_reason(SaveMigrations.CURRENT_VERSION + 1)
	assert_string_contains(reason, "newer version", "and says so in words a player can act on")


func test_supported_versions_load() -> void:
	for version: int in range(SaveMigrations.OLDEST_SUPPORTED, SaveMigrations.CURRENT_VERSION + 1):
		assert_true(SaveMigrations.can_load(version), "v%d is readable" % version)
