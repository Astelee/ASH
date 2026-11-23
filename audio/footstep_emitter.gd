class_name FootstepEmitter
extends Node3D

## Footsteps, tagged by the surface underfoot rather than by the actor.
##
## The tag lives on the ground, not the walker: a `SurfaceTag` node on a piece of geometry says
## "this is gravel", and anything that walks on it sounds like gravel. Tagging the actor instead is
## the common shortcut and it means every new surface needs every actor updated.
##
## Steps are driven by **distance travelled**, not a timer. A timer desynchronises the moment the
## actor changes speed — walk, sprint, or get shoved — and a footstep that lands off the stride is
## more distracting than no footstep at all.

## Metres of travel between steps at walk pace.
@export var stride_length: float = 1.55

## Bank id prefix. The surface tag is appended: `step_` + `gravel` → `step_gravel`.
@export var bank_prefix: String = "step_"

## Fallback surface when nothing underfoot is tagged.
@export var default_surface: StringName = &"stone"

## Downward probe used to identify the ground.
@export var ground_ray: RayCast3D

## The body whose motion drives the stride. Defaults to the parent.
@export var body: CharacterBody3D

## Steps are suppressed below this speed, so idling shuffles do not tick.
@export var minimum_speed: float = 0.35

var _travelled: float = 0.0
var _last_surface: StringName = &"stone"


func _ready() -> void:
	if body == null:
		body = get_parent() as CharacterBody3D


func _physics_process(delta: float) -> void:
	if body == null or not body.is_on_floor():
		# Airborne travel does not accumulate, but neither is it discarded: landing after a short hop
		# should not reset a stride that was most of the way to its next step.
		return

	var speed := absf(body.velocity.x)
	if speed < minimum_speed:
		return

	_travelled += speed * delta
	if _travelled < stride_length:
		return
	_travelled -= stride_length
	step()


## Play one footstep for whatever is underfoot. Exposed so an animation track can drive it instead
## once real animations exist — the distance model is the stand-in, not the intent.
func step() -> void:
	var surface := current_surface()
	_last_surface = surface
	AudioDirector.play_3d(StringName(bank_prefix + String(surface)), global_position)


## Surface tag under the emitter right now.
func current_surface() -> StringName:
	if ground_ray == null:
		return default_surface
	ground_ray.force_raycast_update()
	if not ground_ray.is_colliding():
		return default_surface

	var collider := ground_ray.get_collider()
	if collider == null:
		return default_surface

	var tag := SurfaceTag.find_on(collider)
	return tag.surface if tag != null else default_surface


## The surface the last step played on. For tests and the debug overlay.
func last_surface() -> StringName:
	return _last_surface


## Fraction of the way to the next step, 0 to 1.
func stride_progress() -> float:
	return clampf(_travelled / maxf(stride_length, 0.001), 0.0, 1.0)
