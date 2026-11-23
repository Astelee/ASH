class_name CameraTuning
extends Resource

## The camera rig's behaviour, authored in [code]res://data/tuning/tuning_camera.tres[/code].
##
## Source of truth is [code]docs/GDD.md §4[/code]. [member offset_z] was revised from the original
## spec's 12.5 to 8.0 so the player reads at ~29 % of screen height instead of 19 % — a 0.65 s
## enemy wind-up is not legible at the smaller size, and pulling in also strengthens parallax.

@export_group("Framing")

## Vertical field of view, degrees. Godot's [Camera3D] keeps height, so this fixes the vertical
## extent and the aspect ratio decides the width. [code]MoodDirector[/code] drives this per biome:
## 34 crypt, 42 default, 50 boss arena.
@export_range(10.0, 90.0, 0.5, "degrees") var fov: float = 42.0

## Distance from the action plane, metres. Frame height is
## [code]2 · offset_z · tan(fov / 2)[/code] — 6.14 m at the shipped values.
@export var offset_z: float = 8.0

## Height above the action plane's origin, metres.
@export var offset_y: float = 2.4

## Downward tilt, degrees. Negative looks down.
@export_range(-45.0, 45.0, 0.5, "degrees") var pitch_deg: float = -6.0

@export_group("Follow")

## Seconds to close the horizontal gap. Deliberately much faster than vertical.
@export var damping_horizontal: float = 0.12

## Seconds to close the vertical gap. Slow, so vertical motion reads as weight.
@export var damping_vertical: float = 0.28

## How far ahead of the player, in the facing direction, the camera aims. Metres.
@export var look_ahead: float = 1.8

## Radius around the target inside which the camera does not move at all, metres. Stops micro-jitter
## from small position corrections.
@export var dead_zone: float = 0.6

## When true the camera only tracks vertically while the player is grounded. This is what keeps the
## frame still during a jump instead of bobbing with it.
@export var vertical_snap_grounded_only: bool = true


## Visible frame height at [member offset_z], metres.
func frame_height() -> float:
	return 2.0 * offset_z * tan(deg_to_rad(fov) * 0.5)


## Visible frame width for [param aspect] (width / height), metres. A 20:9 phone is ~2.222.
func frame_width(aspect: float) -> float:
	return frame_height() * aspect


## Fraction of screen height a [param actor_height]-metre character occupies. The readability
## number — target band is roughly 0.25 to 0.35.
func screen_fraction_for(actor_height: float) -> float:
	return actor_height / frame_height()
