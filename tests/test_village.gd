extends GutTest

## Ashfall Village structure, against the Phase 5 acceptance criteria.
##
## Loads the real level rather than a fixture, so a node deleted or renamed in the scene fails here.

const VILLAGE := "res://levels/biomes/ashfall_village.tscn"

var _level: Node3D


func before_each() -> void:
	GameState.begin_new_run(null)
	_level = (load(VILLAGE) as PackedScene).instantiate() as Node3D
	add_child_autofree(_level)


func _find(type_name: StringName) -> Array[Node]:
	return _level.find_children("*", type_name, true, false)


func test_level_declares_its_save_identity() -> void:
	# The bloodstain records which level it fell in; an empty id would put it in every level at once.
	var root := _level as LevelRoot
	assert_not_null(root, "root is a LevelRoot")
	assert_eq(root.level_id, "ashfall_village")


func test_two_wayshrines() -> void:
	var shrines := _find(&"Wayshrine")
	assert_eq(shrines.size(), 2, "one at the gate, one on the upper street")
	var ids: Array[String] = []
	for shrine: Node in shrines:
		ids.append((shrine as Wayshrine).shrine_id)
	assert_has(ids, "village_gate")
	assert_has(ids, "village_square")


func test_three_encounters_with_eight_husks() -> void:
	var volumes := _find(&"EncounterVolume")
	assert_eq(volumes.size(), 3, "the brief asks for three")

	var total := 0
	for node: Node in volumes:
		var volume := node as EncounterVolume
		assert_not_null(volume.enemy_scene, "%s has an enemy scene" % volume.encounter_id)
		assert_not_null(volume.spawn_parent, "%s has spawn markers" % volume.encounter_id)
		assert_eq(volume.max_attackers, 2, "the token cap holds per encounter")
		total += volume.spawn_parent.get_child_count()
	assert_eq(total, 8, "eight spawn markers across the level")


func test_encounters_respawn_on_rest_but_are_not_one_shot() -> void:
	for node: Node in _find(&"EncounterVolume"):
		assert_false((node as EncounterVolume).clear_once, "village patrols must come back")


func test_shortcut_gate_exists_and_starts_closed() -> void:
	var gates := _find(&"ShortcutGate")
	assert_eq(gates.size(), 1)
	var gate := gates[0] as ShortcutGate
	assert_eq(gate.gate_id, "village_shortcut")
	assert_false(gate.is_open(), "closed on a fresh run")
	assert_not_null(gate.barrier, "and it has something to remove")


func test_the_shortcut_is_actually_shorter() -> void:
	# Acceptance criterion 3, as geometry rather than as a claim.
	#
	# The level is a switchback: the street runs east along the lower tier, climbs at the far end,
	# and runs back west along an upper tier, so the gatehouse sits almost directly above the
	# starting Wayshrine. A passage from the far end back to the start would have been exactly as
	# long as the walk it replaced.
	var shrines := _find(&"Wayshrine")
	var start: Wayshrine
	for shrine: Node in shrines:
		if (shrine as Wayshrine).shrine_id == "village_gate":
			start = shrine as Wayshrine
	assert_not_null(start)

	var gate := _find(&"ShortcutGate")[0] as ShortcutGate
	var drop := start.global_position.distance_to(gate.global_position)

	# The long way: east along the lower street to the climb, then back west along the upper.
	var long_route := 2.0 * absf(gate.global_position.x - 74.0)

	assert_lt(drop, 15.0, "the shortcut is a short drop")
	assert_gt(long_route, 100.0, "the long way is a real walk")
	assert_lt(drop, long_route * 0.2, "and the shortcut saves at least 80 percent of it")


func test_three_parallax_lanes_at_the_gdd_depths() -> void:
	var lanes := _find(&"ParallaxLane")
	assert_eq(lanes.size(), 3, "near, mid, far")
	var depths: Array[float] = []
	for lane: Node in lanes:
		depths.append((lane as Node3D).position.z)
	depths.sort()
	# docs/GDD.md §4: backdrop layers at Z -6, -14, -40.
	assert_almost_eq(depths[2], -6.0, 0.1)
	assert_almost_eq(depths[1], -14.0, 0.1)
	assert_almost_eq(depths[0], -40.0, 0.1)


func test_far_lanes_drift_more_than_near_ones() -> void:
	for lane: Node in _find(&"ParallaxLane"):
		var node := lane as ParallaxLane
		if is_equal_approx(node.position.z, -6.0):
			assert_lt(node.parallax_factor, 0.3, "the near backdrop barely moves")
		elif is_equal_approx(node.position.z, -40.0):
			assert_gt(node.parallax_factor, 0.6, "the far silhouette nearly follows the camera")


func test_atmosphere_is_present_and_multimeshed() -> void:
	# CLAUDE.md §3: repeated props are MultiMesh, never individual nodes.
	var fields := _find(&"FogCardField")
	assert_eq(fields.size(), 1, "one fog field")
	var scatters := _find(&"PropScatter")
	assert_eq(scatters.size(), 1, "grass is scattered, not placed")
	assert_gt((scatters[0] as PropScatter).count, 100, "and there is enough of it to matter")
