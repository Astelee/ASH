extends GutTest

## Two things that were fully implemented and then never reached the screen.
##
## The bloodstain is the whole Souls loop: die, lose the purse, walk back for it. `GameState` had
## always tracked it correctly and `LevelRoot._place_bloodstain` had always been called — but there
## was no `Bloodstain.tscn` for `bloodstain_scene` to point at, so the pickup never existed and the
## Embers were unreclaimable in practice. These tests assert the scene end of that contract.
##
## `HitFeedback` is the same class of gap: the shader uniforms existed and nothing wrote them.

const BLOODSTAIN: PackedScene = preload("res://actors/npc/Bloodstain.tscn")
const PLAYER: PackedScene = preload("res://actors/player/Player.tscn")


func before_each() -> void:
	GameState.begin_new_run(null)


# ----------------------------------------------------------------- bloodstain


func test_bloodstain_scene_carries_the_pickup_contract() -> void:
	var stain := BLOODSTAIN.instantiate() as Area3D
	add_child_autofree(stain)
	assert_not_null(stain, "Bloodstain.tscn instantiates as an Area3D")
	assert_true(stain is Bloodstain, "and carries the Bloodstain script")
	assert_true(stain.is_in_group(&"bloodstain"), "joins its group so levels can find it")
	# Layer 8 is `interactable`, mask 2 is `player_body`. Wrong layers is how a pickup silently
	# becomes scenery.
	assert_eq(stain.collision_layer, 128, "sits on the interactable layer")
	assert_eq(stain.collision_mask, 2, "and only ever notices the player")


func test_walking_into_the_stain_returns_the_whole_purse() -> void:
	GameState.add_embers(750)
	GameState.drop_bloodstain("ashfall_village", Vector3(12.0, 0.0, 0.0))
	assert_eq(GameState.embers, 0, "dying empties the purse")
	assert_true(GameState.has_bloodstain(), "and leaves a stain behind")

	# Both at the origin, so the real Area3D overlap fires. Driving the handler by hand would prove
	# only that the handler works; the defect being guarded against here is a pickup whose layers or
	# shape mean it never notices the player at all.
	var stain := BLOODSTAIN.instantiate() as Bloodstain
	add_child_autofree(stain)
	var player := PLAYER.instantiate() as Player
	add_child_autofree(player)
	await wait_physics_frames(4)

	assert_eq(GameState.embers, 750, "walking into it returns every Ember")
	assert_false(GameState.has_bloodstain(), "and the stain is spent")
	assert_false(is_instance_valid(stain), "and removes itself")


func test_a_second_death_destroys_the_first_stain() -> void:
	GameState.add_embers(500)
	GameState.drop_bloodstain("ashfall_village", Vector3(12.0, 0.0, 0.0))
	GameState.add_embers(200)
	GameState.drop_bloodstain("ashfall_village", Vector3(40.0, 0.0, 0.0))

	# This is the rule that gives death teeth: the 500 is gone from the economy for good.
	assert_eq(GameState.bloodstain_embers, 200, "only the newest purse survives")
	assert_eq(GameState.recover_bloodstain(), 200, "and that is all you get back")


func test_a_stain_in_another_level_is_not_placed_here() -> void:
	GameState.add_embers(300)
	GameState.drop_bloodstain("cadwyn_arena", Vector3(5.0, 0.0, 0.0))

	var level := LevelRoot.new()
	level.level_id = "ashfall_village"
	level.bloodstain_scene = BLOODSTAIN
	add_child_autofree(level)
	await wait_physics_frames(2)

	assert_eq(
		level.get_tree().get_nodes_in_group(&"bloodstain").size(),
		0,
		"there is only ever one stain; entering another area must not relocate it"
	)


# ----------------------------------------------------------------- hit feedback


func _rig() -> HitFeedback:
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	add_child_autofree(mesh)

	var feedback := HitFeedback.new()
	feedback.meshes = [mesh]
	feedback.actor = mesh
	feedback.combat_tuning = CombatTuning.new()
	add_child_autofree(feedback)
	return feedback


func test_a_hit_lights_the_flash_and_it_decays() -> void:
	var feedback := _rig()
	var mesh: MeshInstance3D = feedback.meshes[0]

	assert_eq(mesh.get_instance_shader_parameter(&"hit_flash"), 0.0, "starts dark")

	# Checked before any frame has run: the lit frame must not depend on the frame rate.
	feedback.flash()
	assert_eq(
		mesh.get_instance_shader_parameter(&"hit_flash"),
		1.0,
		"a hit lights the per-instance uniform immediately, not a frame later"
	)

	# Past the tuned duration it must be fully off, or a flurry leaves actors glowing white.
	await wait_seconds(feedback.combat_tuning.hit_flash_duration + 0.1)
	assert_eq(mesh.get_instance_shader_parameter(&"hit_flash"), 0.0, "and it decays to nothing")


func test_feedback_stops_processing_once_idle() -> void:
	# Per CLAUDE.md §3 an idle crowd must not each cost a shader write per frame.
	var feedback := _rig()
	feedback.flash()
	await wait_seconds(feedback.combat_tuning.hit_flash_duration + 0.2)
	assert_false(feedback.is_processing(), "an idle actor costs nothing")


func test_an_actor_ignores_hits_aimed_at_someone_else() -> void:
	var feedback := _rig()
	var mesh: MeshInstance3D = feedback.meshes[0]
	var other := Node3D.new()
	add_child_autofree(other)

	var packet := DamagePacket.create(10.0, 10.0, DamagePacket.Type.PHYSICAL, other, Vector3.ZERO)
	EventBus.damage_dealt.emit(other, packet, DamagePacket.Result.HIT)
	await wait_physics_frames(2)

	assert_eq(
		mesh.get_instance_shader_parameter(&"hit_flash"),
		0.0,
		"one enemy taking a hit must not flash the whole screen"
	)
