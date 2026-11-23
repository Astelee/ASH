class_name LevelRoot
extends Node3D

## Root of every playable level. The one place that hands the level's [WorldEnvironment], sun, and
## camera to [code]MoodDirector[/code], and the one place that pushes quality-tier settings onto
## lights.
##
## Levels bind on ready and unbind on exit, so the director never holds a reference to a freed
## Environment after a scene change.

## Mood applied on entry, with no blend.
@export var starting_mood: BiomeMood

## The level's environment. Its [Environment] is what MoodDirector writes to.
@export var world_environment: WorldEnvironment

## The single shadow-casting directional light.
@export var sun: DirectionalLight3D

## The camera rig, for the FOV hook.
@export var camera_rig: PlayerCamera

## Identifier this level is known by in save data. Bloodstains record which level they are in.
@export var level_id: String = ""

## Scene placed where the player last died, if the bloodstain belongs to this level.
@export var bloodstain_scene: PackedScene


func _ready() -> void:
	MoodDirector.bind_world(world_environment, sun)
	if camera_rig != null:
		MoodDirector.bind_camera(_on_fov_changed)

	QualityManager.tier_changed.connect(_on_tier_changed)
	_on_tier_changed(QualityManager.tier())

	if starting_mood != null:
		MoodDirector.snap_to(starting_mood)

	_place_bloodstain()
	tree_exiting.connect(MoodDirector.unbind_world)


## Instantiate the pending bloodstain if it was dropped in this level.
##
## Closes the Phase 3 gap: GameState recorded where the Embers fell, but nothing put them back into
## the world. A stain from another level stays where it is -- there is only ever one, and walking
## into a different area must not quietly relocate it.
func _place_bloodstain() -> void:
	if bloodstain_scene == null or not GameState.has_bloodstain():
		return
	if GameState.bloodstain_level != _identity():
		return
	var stain := bloodstain_scene.instantiate() as Node3D
	if stain == null:
		return
	add_child(stain)
	stain.global_position = GameState.bloodstain_position


## This level's save identity, defaulting to the scene filename.
func _identity() -> String:
	if not level_id.is_empty():
		return level_id
	return scene_file_path.get_file().get_basename()


## Apply the tier's shadow settings to the actual light.
##
## QualityManager writes shadow size to ProjectSettings, which does NOT reach lights that already
## exist — a gap flagged when the tier table was written. The level owns its sun, so the level is
## where the setting lands.
func _on_tier_changed(_tier: QualityManager.Tier) -> void:
	if sun == null:
		return
	sun.shadow_enabled = QualityManager.setting("shadows_enabled")
	var splits: int = QualityManager.setting("shadow_splits")
	if splits <= 1:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	else:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 45.0


func _on_fov_changed(fov: float) -> void:
	if camera_rig != null:
		camera_rig.set_fov(fov)
