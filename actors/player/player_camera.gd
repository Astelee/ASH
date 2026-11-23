class_name PlayerCamera
extends Node3D

## Side-on follow rig. Sits in the level rather than under the player, so player motion does not
## drag the camera one-for-one — everything here is deliberate lag.
##
## Three mechanisms, in application order: a [b]dead zone[/b] the target may drift inside without
## moving the camera at all, [b]look-ahead[/b] biasing the frame toward where the player is facing,
## and [b]asymmetric damping[/b] that closes horizontal gaps more than twice as fast as vertical
## ones. Vertical tracking is additionally frozen while airborne, which is what stops the frame
## bobbing through every jump.

## Follow target. Left empty, the rig finds the player by group so the scene still works on F6.
@export var target: Node3D

## Camera behaviour and framing. See [code]docs/GDD.md §4[/code].
@export var tuning: CameraTuning

## The camera this rig drives. Its transform is overwritten from [member tuning] on ready.
@export var camera: Camera3D

var _focus: Vector3 = Vector3.ZERO


func _ready() -> void:
	if tuning == null:
		Log.error("PlayerCamera", "no CameraTuning assigned; falling back to defaults")
		tuning = CameraTuning.new()

	if target == null:
		target = get_tree().get_first_node_in_group(&"player") as Node3D
	if target == null:
		Log.warn("PlayerCamera", "no target; rig will hold its starting position")

	_apply_framing()
	_focus = target.global_position if target != null else global_position
	global_position = _focus


func _physics_process(delta: float) -> void:
	if target == null:
		return

	_advance_focus(delta)

	global_position.x = _damp(global_position.x, _focus.x, tuning.damping_horizontal, delta)
	global_position.y = _damp(global_position.y, _focus.y, tuning.damping_vertical, delta)
	global_position.z = 0.0


## Set the camera's field of view. Called by [LevelRoot] from [code]MoodDirector[/code], so the rig
## stays the only thing that touches its own [Camera3D].
func set_fov(value: float) -> void:
	if camera != null:
		camera.fov = value


## Reposition instantly, skipping all damping. For respawns and scene entry, where easing in from
## the previous location would look like a mistake.
func snap_to_target() -> void:
	if target == null:
		return
	_focus = _desired_focus()
	global_position = Vector3(_focus.x, _focus.y, 0.0)


func _advance_focus(_delta: float) -> void:
	var desired := _desired_focus()

	# The dead zone is applied to the focus point, not the camera: the camera never chases inside
	# the zone, but the moment the target leaves it the focus is dragged along exactly far enough to
	# keep it on the boundary. Damping alone would still creep.
	var offset_x := desired.x - _focus.x
	if absf(offset_x) > tuning.dead_zone:
		_focus.x += offset_x - signf(offset_x) * tuning.dead_zone

	if _should_track_vertically():
		var offset_y := desired.y - _focus.y
		if absf(offset_y) > tuning.dead_zone:
			_focus.y += offset_y - signf(offset_y) * tuning.dead_zone


func _desired_focus() -> Vector3:
	var point := target.global_position
	var player := target as Player
	if player != null:
		point.x += float(player.facing) * tuning.look_ahead
	return point


func _should_track_vertically() -> bool:
	if not tuning.vertical_snap_grounded_only:
		return true
	var body := target as CharacterBody3D
	return body == null or body.is_on_floor()


## Frame-rate independent exponential approach. [param tau] is the time constant in seconds — the
## damping values in [CameraTuning] read directly as "seconds to close the gap".
func _damp(current: float, goal: float, tau: float, delta: float) -> float:
	if tau <= 0.0:
		return goal
	return lerpf(current, goal, 1.0 - exp(-delta / tau))


func _apply_framing() -> void:
	if camera == null:
		Log.error("PlayerCamera", "no Camera3D assigned; framing not applied")
		return
	camera.fov = tuning.fov
	camera.position = Vector3(0.0, tuning.offset_y, tuning.offset_z)
	camera.rotation = Vector3(deg_to_rad(tuning.pitch_deg), 0.0, 0.0)
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
