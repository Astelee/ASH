extends GutTest

## The audio mix: bus layout, bank variation, voice stealing, ducking, stems, and the tells.
##
## Runs headless, where Godot uses a dummy audio driver — so this asserts the *decisions* (which
## voice, which bus, which gain) rather than that a sound was audible. That is the half worth
## testing anyway: whether a Gravewretch rattle survives a busy fight is a policy question, and
## policy is exactly what silently regresses.


func before_each() -> void:
	GameState.begin_new_run(null)
	# Headless uses a dummy audio driver where a generator stream never reports finishing, so voices
	# stay claimed across tests unless the pool is explicitly released.
	AudioDirector.stop_all()


func _bank(id: StringName, priority: int = 5, signal_flag: bool = false) -> SoundBank:
	var bank := SoundBank.new()
	bank.id = id
	bank.priority = priority
	bank.is_gameplay_signal = signal_flag
	bank.min_interval = 0.0
	bank.streams = [
		AudioStreamGenerator.new(), AudioStreamGenerator.new(), AudioStreamGenerator.new()
	]
	return bank


# ------------------------------------------------------------------ bus layout


func test_every_required_bus_exists() -> void:
	# docs/PLAN.md Phase 8: Master/Music/SFX/Ambience/UI plus a reverb send.
	for bus: String in ["Master", "Music", "SFX", "Ambience", "UI", "Reverb"]:
		assert_gte(AudioServer.get_bus_index(bus), 0, "bus '%s' exists" % bus)


func test_gameplay_buses_route_to_master() -> void:
	for bus: String in ["Music", "SFX", "Ambience", "UI"]:
		var index := AudioServer.get_bus_index(bus)
		assert_eq(AudioServer.get_bus_send(index), "Master", "%s sends to Master" % bus)


func test_reverb_starts_silent() -> void:
	# The send is a zone effect. A level that never sets it must not add reverb by accident.
	var index := AudioServer.get_bus_index("Reverb")
	assert_lt(AudioServer.get_bus_volume_db(index), -40.0, "silent until a mood asks for it")


func test_master_has_a_limiter() -> void:
	# Layered stems plus a boss plus adds will clip without one, and clipping on a phone speaker is
	# indistinguishable from a broken file.
	var index := AudioServer.get_bus_index("Master")
	assert_gt(AudioServer.get_bus_effect_count(index), 0, "Master carries an effect")


# ---------------------------------------------------------------- bank variation


func test_a_bank_never_repeats_the_previous_take() -> void:
	# The single most fatiguing thing a game can do is play one footstep sample 400 times a minute.
	var bank := _bank(&"step_gravel")
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345

	var previous: AudioStream = null
	for _i: int in 40:
		var take := bank.pick(rng)
		assert_ne(take, previous, "consecutive takes differ")
		previous = take


func test_a_single_take_bank_still_plays() -> void:
	# The anti-repeat rule must never make a bank unplayable.
	var bank := _bank(&"solo")
	bank.streams = [AudioStreamGenerator.new()]
	var rng := RandomNumberGenerator.new()
	assert_not_null(bank.pick(rng))
	assert_not_null(bank.pick(rng))


func test_an_empty_bank_returns_null_rather_than_crashing() -> void:
	var bank := SoundBank.new()
	assert_null(bank.pick(RandomNumberGenerator.new()))


func test_pitch_and_volume_jitter_stay_inside_their_bands() -> void:
	var bank := _bank(&"jittery")
	bank.volume_db = -6.0
	bank.volume_jitter_db = 2.0
	bank.pitch_jitter = 0.1
	var rng := RandomNumberGenerator.new()
	rng.seed = 99

	for _i: int in 200:
		var volume := bank.roll_volume(rng)
		assert_between(volume, -8.0, -4.0, "volume within the band")
		assert_between(bank.roll_pitch(rng), 0.9, 1.1, "pitch within the band")


# --------------------------------------------------------------- voice stealing


func test_the_pool_is_fixed_and_never_grows() -> void:
	# CLAUDE.md §3 forbids per-frame allocation, and audio is the most frequent spawn in a fight.
	AudioDirector.register_bank(_bank(&"noise", 1))
	for _i: int in AudioDirector.POOL_SIZE * 3:
		AudioDirector.play_3d(&"noise", Vector3.ZERO)
	assert_lte(AudioDirector.active_voices(), AudioDirector.POOL_SIZE, "the cap holds")


func test_a_low_priority_sound_cannot_silence_a_gameplay_signal() -> void:
	# The policy that matters: a footstep must never steal the voice carrying a Gravewretch rattle.
	# Losing that tell to a puddle of grass sounds costs the player a life.
	var quiet := _bank(&"step_grass", 1)
	var tell := _bank(&"gravewretch_lunge", 9, true)
	AudioDirector.register_banks([quiet, tell])

	# Fill the pool entirely with the high-priority signal.
	for _i: int in AudioDirector.POOL_SIZE:
		AudioDirector.play_3d(&"gravewretch_lunge", Vector3.ZERO)

	var stolen := AudioDirector.play_3d(&"step_grass", Vector3.ZERO)
	assert_null(stolen, "the footstep declines to play rather than stealing a tell")


func test_a_high_priority_sound_does_steal_from_a_low_one() -> void:
	AudioDirector.register_banks([_bank(&"chatter", 1), _bank(&"boss_slam", 9)])
	for _i: int in AudioDirector.POOL_SIZE:
		AudioDirector.play_3d(&"chatter", Vector3.ZERO)
	assert_not_null(AudioDirector.play_3d(&"boss_slam", Vector3.ZERO), "the slam gets a voice")


func test_rate_limiting_stops_a_multi_hit_becoming_a_click() -> void:
	var bank := _bank(&"impact")
	bank.min_interval = 0.25
	AudioDirector.register_bank(bank)

	assert_not_null(AudioDirector.play_3d(&"impact", Vector3.ZERO), "first plays")
	assert_null(AudioDirector.play_3d(&"impact", Vector3.ZERO), "second is inside the window")


func test_an_unregistered_bank_is_a_no_op() -> void:
	assert_null(AudioDirector.play_3d(&"nothing_here", Vector3.ZERO))


# --------------------------------------------------------------------- ducking


func test_ducking_takes_the_deepest_request() -> void:
	AudioDirector.duck(0.3)
	AudioDirector.duck(0.9)
	AudioDirector.duck(0.2)
	assert_almost_eq(AudioDirector.duck_amount(), 0.9, 0.001, "the loudest hit wins")


func test_ducking_holds_before_it_releases() -> void:
	# Duck-on-trigger with an instant release pumps the moment two hits land close together.
	AudioDirector.duck(1.0)
	AudioDirector._advance_duck(0.1)
	assert_almost_eq(AudioDirector.duck_amount(), 1.0, 0.001, "still held")


func test_ducking_recovers_after_the_hold() -> void:
	AudioDirector.duck(1.0)
	AudioDirector._advance_duck(AudioDirector.DUCK_HOLD + 0.01)
	AudioDirector._advance_duck(0.5)
	assert_lt(AudioDirector.duck_amount(), 1.0, "and then eases back")


func test_release_is_slower_than_attack() -> void:
	assert_gt(AudioDirector.DUCK_RELEASE, AudioDirector.DUCK_ATTACK * 4.0, "no pumping")


# ----------------------------------------------------------------------- stems


func test_the_ossuary_mask_leaves_only_the_drone() -> void:
	# GDD §8: the Ossuary drops to sub-bass drone only. Mask 1 is bit 0, the drone stem.
	AudioDirector.set_stem_mask(1)
	for _i: int in 400:
		AudioDirector._advance_stems(0.05)

	assert_gt(AudioDirector.stem_volume_db(0), -6.0, "the drone is audible")
	for index: int in range(1, AudioDirector.STEM_COUNT):
		assert_lt(AudioDirector.stem_volume_db(index), -40.0, "stem %d is silent" % index)


func test_the_full_mask_brings_everything_back() -> void:
	AudioDirector.set_stem_mask(31)
	for _i: int in 400:
		AudioDirector._advance_stems(0.05)
	for index: int in AudioDirector.STEM_COUNT:
		assert_gt(AudioDirector.stem_volume_db(index), -6.0, "stem %d returns" % index)


func test_a_mood_drives_the_mix_without_anyone_calling_audio() -> void:
	# All mood is one call: walking into the Ossuary must change the score and the reverb with no
	# level script touching AudioDirector.
	var ossuary := load("res://data/biomes/mood_ossuary.tres") as BiomeMood
	MoodDirector.snap_to(ossuary)
	assert_almost_eq(AudioDirector.reverb_wet(), 0.60, 0.01, "wet reverb in the crypt")
	assert_eq(ossuary.music_stem_mask, 1, "and drone only")


# ------------------------------------------------------------------ surfaces


func test_every_known_surface_has_a_name() -> void:
	assert_gte(SurfaceTag.KNOWN.size(), 5, "stone, gravel, wood, grass, water at minimum")
	for surface: StringName in [&"stone", &"gravel", &"wood", &"grass", &"water", &"bone"]:
		assert_has(SurfaceTag.KNOWN, surface, "%s is a known surface" % surface)


func test_a_surface_tag_is_found_from_a_child_collider() -> void:
	# The raycast hits a collider several levels below the chunk the designer tagged.
	var chunk := Node3D.new()
	add_child_autofree(chunk)
	var tag := SurfaceTag.new()
	tag.surface = &"gravel"
	chunk.add_child(tag)

	var collider := StaticBody3D.new()
	chunk.add_child(collider)
	var shape := CollisionShape3D.new()
	collider.add_child(shape)

	var found := SurfaceTag.find_on(shape)
	assert_not_null(found, "the tag is found by walking up")
	assert_eq(found.surface, &"gravel")


func test_untagged_geometry_falls_back_rather_than_going_silent() -> void:
	var lonely := StaticBody3D.new()
	add_child_autofree(lonely)
	assert_null(SurfaceTag.find_on(lonely), "no tag found")

	var emitter := FootstepEmitter.new()
	emitter.default_surface = &"stone"
	add_child_autofree(emitter)
	assert_eq(emitter.current_surface(), &"stone", "an untagged floor still makes a sound")


func test_steps_are_driven_by_distance_not_time() -> void:
	# A timer desynchronises the moment the actor changes speed; distance never does.
	var emitter := FootstepEmitter.new()
	emitter.stride_length = 2.0
	add_child_autofree(emitter)
	assert_almost_eq(emitter.stride_progress(), 0.0, 0.001, "a standing actor never steps")
