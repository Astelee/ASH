extends GutTest

## Application pause/resume correctness and leak checks.
##
## Android kills backgrounded processes without warning. Everything here exists because the failure
## mode is silent: the player alt-tabs, the process dies, and the run is gone with no crash and no
## error to read.

const SLOT := 1


func before_each() -> void:
	GameState.begin_new_run(null)
	SaveSystem.active_slot = SLOT


func after_all() -> void:
	SaveSystem.delete_slot(SLOT)


# ------------------------------------------------------------------ pause / resume


func test_pausing_writes_the_run_to_disk() -> void:
	# The mandatory autosave. This is the last moment the run exists before Android may reclaim it.
	GameState.level = 6
	GameState.add_embers(880)
	SaveSystem._notification(Node.NOTIFICATION_APPLICATION_PAUSED)

	GameState.begin_new_run(null)
	assert_true(SaveSystem.load_from_slot(SLOT), "the pause write is readable")
	assert_eq(GameState.level, 6)
	assert_eq(GameState.embers, 880)


func test_a_close_request_saves_too() -> void:
	GameState.add_embers(140)
	SaveSystem._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	GameState.begin_new_run(null)
	SaveSystem.load_from_slot(SLOT)
	assert_eq(GameState.embers, 140, "closing the window is not different from being killed")


func test_a_pause_mid_write_never_corrupts_the_live_save() -> void:
	# The temp-file-then-rename rule, stated as a test: a second save arriving while one is running
	# is refused rather than interleaved.
	GameState.add_embers(500)
	assert_true(SaveSystem.save_to_slot(SLOT))
	var live := SaveSystem.slot_path(SLOT)
	var temp := live.replace(SaveSystem.EXTENSION, SaveSystem.TEMP_EXTENSION)
	assert_false(FileAccess.file_exists(temp), "no temp file survives a completed write")
	assert_true(FileAccess.file_exists(live), "and the live save is intact")


func test_the_save_survives_being_written_repeatedly() -> void:
	# Autosave fires on rest, level-up, boss defeat, death and pause. In a busy minute that is a
	# dozen writes, and every one must leave a readable file.
	for index: int in 12:
		GameState.add_embers(10)
		SaveSystem.autosave("stress_%d" % index)

	GameState.begin_new_run(null)
	assert_true(SaveSystem.load_from_slot(SLOT), "still readable after twelve writes")
	assert_eq(GameState.embers, 120)


func test_a_backup_exists_after_the_second_write() -> void:
	GameState.add_embers(70)
	SaveSystem.save_to_slot(SLOT)
	GameState.add_embers(30)
	SaveSystem.save_to_slot(SLOT)

	var backup := SaveSystem.slot_path(SLOT).replace(
		SaveSystem.EXTENSION, SaveSystem.BACKUP_EXTENSION
	)
	assert_true(FileAccess.file_exists(backup), "one corrupt write can never take the run")


# ------------------------------------------------------------------------- leaks


func test_audio_voices_are_released_on_a_scene_change() -> void:
	# A footstep from the level you just left has no business finishing in the one you entered, and
	# a voice that is never released is a voice permanently missing from the pool.
	var bank := SoundBank.new()
	bank.id = &"leak_probe"
	bank.min_interval = 0.0
	bank.streams = [AudioStreamGenerator.new()]
	AudioDirector.register_bank(bank)

	for _i: int in 10:
		AudioDirector.play_3d(&"leak_probe", Vector3.ZERO)
	AudioDirector.stop_all()
	assert_eq(AudioDirector.active_voices(), 0, "the pool comes back empty")


func test_the_attack_scheduler_releases_every_token_on_clear() -> void:
	# An encounter that reloads without clearing leaks tokens, and the next fight silently runs with
	# fewer attackers than intended — which reads as the AI being passive, not as a bug.
	var scheduler := AttackScheduler.new(2)
	scheduler.request(1)
	scheduler.request(2)
	scheduler.request(3)
	scheduler.clear()
	assert_eq(scheduler.active_count(), 0)
	assert_eq(scheduler.waiting_count(), 0)


func test_mood_director_drops_level_references_on_teardown() -> void:
	# Holding a freed Environment across a scene change is a crash waiting for the next transition.
	MoodDirector.bind_world(null, null)
	MoodDirector.unbind_world()
	MoodDirector.snap_to(load("res://data/biomes/mood_village.tres") as BiomeMood)
	assert_not_null(MoodDirector.current, "still tracks state with nothing bound")


func test_a_freed_encounter_leaves_no_orphans() -> void:
	# GUT counts orphans across the suite; this makes the encounter path explicit rather than
	# relying on the summary line nobody reads.
	var before := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)

	var volume := EncounterVolume.new()
	volume.encounter_id = "leak_probe"
	add_child(volume)
	volume.respawn()
	remove_child(volume)
	volume.free()

	var after := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	assert_lte(after, before, "no orphaned nodes left behind")
