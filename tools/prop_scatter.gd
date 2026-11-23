@tool
class_name PropScatter
extends MultiMeshInstance3D

## Scatters a prop mesh across a volume as a single MultiMesh.
##
## Grass, gravestones, rubble, torches, crowd fill -- CLAUDE.md section 3 requires all of it to be
## MultiMesh rather than individual nodes, and this is the tool that makes obeying that rule easier
## than breaking it. Press "Rescatter" in the inspector and the field regenerates in the editor.
##
## Deterministic: the same seed gives the same field every time, so a level looks identical between
## runs and a visual bug is reproducible.

## Mesh instanced at every point.
@export var prop_mesh: Mesh:
	set(value):
		prop_mesh = value
		_rebuild()

## Material applied to the whole field. One material, one draw call.
@export var prop_material: Material:
	set(value):
		prop_material = value
		material_override = value

## How many to place.
@export var count: int = 120:
	set(value):
		count = maxi(0, value)
		_rebuild()

## Volume scattered through, metres. Y is usually near zero for ground cover.
@export var extents: Vector3 = Vector3(20.0, 0.0, 4.0):
	set(value):
		extents = value
		_rebuild()

## Uniform scale range.
@export var scale_min: float = 0.8:
	set(value):
		scale_min = value
		_rebuild()

@export var scale_max: float = 1.3:
	set(value):
		scale_max = value
		_rebuild()

## Random yaw. Off for props with a correct facing, like signposts.
@export var random_yaw: bool = true:
	set(value):
		random_yaw = value
		_rebuild()

## Deterministic seed.
@export var seed_value: int = 1:
	set(value):
		seed_value = value
		_rebuild()

## Tick to regenerate from the inspector.
@export var rescatter: bool = false:
	set(_value):
		rescatter = false
		_rebuild()

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if prop_mesh == null:
		return

	_rng.seed = seed_value
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = prop_mesh
	multimesh.instance_count = count

	if prop_material != null:
		material_override = prop_material

	for index: int in count:
		var scale := _rng.randf_range(scale_min, scale_max)
		var basis := Basis()
		if random_yaw:
			basis = basis.rotated(Vector3.UP, _rng.randf_range(0.0, TAU))
		basis = basis.scaled(Vector3.ONE * scale)

		var origin := Vector3(
			_rng.randf_range(-extents.x, extents.x) * 0.5,
			_rng.randf_range(-extents.y, extents.y) * 0.5,
			_rng.randf_range(-extents.z, extents.z) * 0.5
		)
		multimesh.set_instance_transform(index, Transform3D(basis, origin))
		# INSTANCE_CUSTOM.x is the per-instance phase foliage_wind and emissive_flicker both read.
		multimesh.set_instance_custom_data(index, Color(_rng.randf(), _rng.randf(), 0.0, 0.0))
