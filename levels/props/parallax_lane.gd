class_name ParallaxLane
extends Node3D

## A backdrop layer that drifts against the camera to fake distance.
##
## The depth lanes in docs/GDD.md section 4 sit at Z -6, -14 and -40. True perspective already gives
## some separation, but not enough at a 42-degree FOV over a 14-metre frame -- a wall 40 m back
## barely moves. This nudges each lane by a fraction of the camera's travel so the far silhouette
## reads as far away rather than as a painted flat.
##
## Purely visual. No collision, no gameplay, and it never touches the action plane at Z 0.

## Fraction of camera movement this lane copies. 0 pins it to the world, 1 pins it to the camera.
## Far lanes want values near 1; the near backdrop wants ~0.15.
@export_range(0.0, 1.0, 0.01) var parallax_factor: float = 0.35

## Also drift vertically. Off by default -- vertical parallax on a platformer makes the horizon
## bob during jumps, which reads as the world being loose.
@export var affect_vertical: bool = false

## Camera to track. Found by group when left empty.
@export var camera: Camera3D

var _origin: Vector3
var _camera_origin: Vector3


func _ready() -> void:
	_origin = global_position
	if camera == null:
		var rig := get_tree().get_first_node_in_group(&"camera_rig") as PlayerCamera
		if rig != null:
			camera = rig.camera
	if camera != null:
		_camera_origin = camera.global_position


func _process(_delta: float) -> void:
	if camera == null:
		return
	var travel := camera.global_position - _camera_origin
	global_position.x = _origin.x + travel.x * parallax_factor
	if affect_vertical:
		global_position.y = _origin.y + travel.y * parallax_factor
