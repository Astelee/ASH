class_name FogCardField
extends MultiMeshInstance3D

## A volume of fog cards, scattered once and drawn as a single MultiMesh.
##
## One draw call for the whole field, which is the only reason this technique is affordable at all —
## a hundred individual quads would eat most of the 130-draw-call budget on atmosphere alone.
##
## Card count is the product of three things: the authored [member card_count], the quality
## tier's fraction (25 / 60 / 100 %), and the mood's [member BiomeMood.fog_card_density]. The tier
## decides what the device can afford; the mood decides what the place should feel like.

## Cards at full quality and full mood density.
@export var card_count: int = 60

## Volume the cards are scattered through, metres.
@export var extents: Vector3 = Vector3(24.0, 4.0, 6.0)

## Card size range, metres. Varied so a field does not read as a repeating stamp.
@export var size_min: float = 2.5

@export var size_max: float = 6.0

## Material carrying [code]fog_card.gdshader[/code].
@export var card_material: ShaderMaterial

## Deterministic scatter. The same seed gives the same field every run, so a level looks the same
## twice and a bug is reproducible.
@export var seed_value: int = 20260813

## Rebuild whenever the quality tier changes. Off for fields that must never restructure mid-fight.
@export var follow_quality: bool = true

var _rng := RandomNumberGenerator.new()
var _authored_transforms: Array[Transform3D] = []


func _ready() -> void:
	_build_authored()
	_apply_budget()

	if follow_quality:
		QualityManager.tier_changed.connect(_on_tier_changed)
	MoodDirector.mood_changed.connect(_on_mood_changed)
	_on_mood_changed(MoodDirector.current, 1.0)


## Cards actually drawn right now.
func visible_count() -> int:
	return multimesh.visible_instance_count if multimesh != null else 0


## Scatter every card once. Transforms are kept so a tier change re-slices the same field rather
## than re-randomising it — the fog must not visibly rearrange when the resolution drops.
func _build_authored() -> void:
	_rng.seed = seed_value
	_authored_transforms.clear()

	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE

	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	multimesh.instance_count = card_count

	if card_material != null:
		material_override = card_material

	for index: int in card_count:
		var scale := _rng.randf_range(size_min, size_max)
		var basis := Basis().scaled(Vector3(scale, scale * 0.6, scale))
		var origin := Vector3(
			_rng.randf_range(-extents.x, extents.x) * 0.5,
			_rng.randf_range(0.0, extents.y),
			_rng.randf_range(-extents.z, extents.z) * 0.5
		)
		var card := Transform3D(basis, origin)
		_authored_transforms.append(card)
		multimesh.set_instance_transform(index, card)
		# Per-instance phase, so cards do not all scroll their noise in lockstep.
		multimesh.set_instance_custom_data(index, Color(_rng.randf(), _rng.randf(), 0.0, 0.0))


func _apply_budget() -> void:
	if multimesh == null:
		return
	var fraction := QualityManager.fog_card_fraction()
	var mood_density := (
		MoodDirector.current.fog_card_density if MoodDirector.current != null else 1.0
	)
	var wanted := int(round(float(card_count) * fraction * clampf(mood_density, 0.0, 2.0)))
	multimesh.visible_instance_count = clampi(wanted, 0, card_count)


func _on_tier_changed(_tier: QualityManager.Tier) -> void:
	_apply_budget()


func _on_mood_changed(mood: BiomeMood, _progress: float) -> void:
	if mood == null:
		return
	_apply_budget()
	if card_material != null:
		card_material.set_shader_parameter(&"fog_color", mood.fog_color)
		# Depth fog and card density share one authored knob, so a designer tunes "how foggy" once.
		card_material.set_shader_parameter(&"density", clampf(mood.fog_density * 40.0, 0.0, 1.5))
