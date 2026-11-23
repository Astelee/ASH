extends Node

## The single entry point for atmosphere. Holds one active [BiomeMood] and lerps every parameter in
## it together over one duration.
##
## Levels drive it with [Area3D] triggers calling [method transition_to]. **Nothing else in the
## project may poke [WorldEnvironment], the sun, or the grade shader directly** — that rule is the
## entire reason the eerie shift reads as intentional instead of as stacked effects.
##
## Degrades gracefully: with no environment or sun registered it still tracks state and still drives
## the global shader uniforms, so a scene opened on its own with F6 renders rather than erroring.

## Emitted every frame of a transition, with the blended mood and progress 0–1.
signal mood_changed(mood: BiomeMood, progress: float)

## Emitted once a transition completes.
signal transition_finished(mood: BiomeMood)

## Global shader uniform every character shader reads for its rim light. Declared in
## project.godot under [shader_globals] -- global_shader_parameter_add() is editor-only and
## warns at runtime, so the default lives in the project file and only writes happen here.
const RIM_UNIFORM: StringName = &"ashfall_rim_color"

## Global shader uniform the foliage shader reads.
const WIND_UNIFORM: StringName = &"ashfall_wind_strength"

## The mood currently applied. Never null after [method _ready].
var current: BiomeMood

var _from: BiomeMood
var _to: BiomeMood
var _elapsed: float = 0.0
var _duration: float = 0.0
var _environment: Environment
var _sun: DirectionalLight3D
var _camera_hook: Callable
var _grade: ShaderMaterial


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	current = BiomeMood.new()
	_apply(current)


func _process(delta: float) -> void:
	if _to == null:
		return

	_elapsed += delta
	var t := 1.0 if _duration <= 0.0 else clampf(_elapsed / _duration, 0.0, 1.0)
	current = BiomeMood.blend(_from, _to, t)
	_apply(current)
	mood_changed.emit(current, t)

	if t >= 1.0:
		var finished := _to
		_from = null
		_to = null
		set_process(false)
		transition_finished.emit(finished)


## Blend to [param mood] over [param duration] seconds. Zero duration snaps.
##
## Interrupting a transition blends from wherever it currently *is*, not from where it started —
## walking back out of a trigger volume halfway must not pop.
func transition_to(mood: BiomeMood, duration: float = 2.0) -> void:
	if mood == null:
		Log.warn("MoodDirector", "transition_to(null) ignored")
		return

	_from = current
	_to = mood
	_elapsed = 0.0
	_duration = maxf(0.0, duration)

	if _duration <= 0.0:
		current = mood
		_apply(current)
		# A snap still announces. Without this, entering a level sets the visuals and silently skips
		# every listener that only hears about gradual transitions -- which is the entire audio mix.
		mood_changed.emit(current, 1.0)
		transition_finished.emit(mood)
		_to = null
		return
	set_process(true)


## Snap to [param mood] with no blend. Scene entry and respawns, where easing in from the previous
## area's look would read as a bug.
func snap_to(mood: BiomeMood) -> void:
	transition_to(mood, 0.0)


## Register the level's [WorldEnvironment] and sun. Levels call this on ready.
func bind_world(environment: WorldEnvironment, sun: DirectionalLight3D) -> void:
	_environment = environment.environment if environment != null else null
	_sun = sun
	_apply(current)


## Register a callback receiving the blended camera FOV, so the rig stays the only thing that
## touches its own [Camera3D].
func bind_camera(hook: Callable) -> void:
	_camera_hook = hook
	if current != null and _camera_hook.is_valid():
		_camera_hook.call(current.camera_fov)


## Register the fullscreen grade material. [ColorGrade] calls this; nothing else may.
func bind_grade(material: ShaderMaterial) -> void:
	_grade = material
	_apply(current)


## Release the grade material on scene teardown.
func unbind_grade() -> void:
	_grade = null


## Release level-owned references. Called on scene teardown so a freed Environment is never touched.
func unbind_world() -> void:
	_environment = null
	_sun = null
	_camera_hook = Callable()


## True while a blend is running.
func is_transitioning() -> bool:
	return _to != null


func _apply(mood: BiomeMood) -> void:
	if mood == null:
		return

	# Global shader parameters reach every material at once without a per-material loop, which is
	# what keeps a whole biome's worth of foliage and characters on one write per frame.
	RenderingServer.global_shader_parameter_set(RIM_UNIFORM, mood.rim_color)
	RenderingServer.global_shader_parameter_set(WIND_UNIFORM, mood.wind_strength)

	if _environment != null:
		_environment.fog_enabled = true
		_environment.fog_light_color = mood.fog_color
		_environment.fog_density = mood.fog_density
		# Godot expresses height fog as a single height plus a density falloff, so the authored
		# min/max pair becomes a midpoint and a rate. Applying only the max, as this did before,
		# silently discarded half of every authored fog profile.
		_environment.fog_height = (mood.fog_height_min + mood.fog_height_max) * 0.5
		var span := maxf(mood.fog_height_max - mood.fog_height_min, 0.01)
		_environment.fog_height_density = mood.fog_density / span
		_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		_environment.ambient_light_color = mood.ambient_color
		_environment.ambient_light_energy = mood.ambient_energy

		# Aerial perspective and sun scatter are the two fog settings that separate depth from a
		# grey wash, and both are supported on the Mobile renderer.
		_environment.fog_aerial_perspective = mood.aerial_perspective
		_environment.fog_sun_scatter = mood.fog_sun_scatter

		# ACES rather than Linear or Reinhard. An untonemapped buffer clips highlights flat and is
		# most of why an otherwise-good scene reads as plastic.
		_environment.tonemap_mode = Environment.TONE_MAPPER_ACES
		_environment.tonemap_exposure = exp(mood.exposure_ev * 0.6931472)
		_environment.tonemap_white = mood.white_point

		# Contrast, saturation and the LUT ride the tonemap resolve rather than a second fullscreen
		# quad. Same result, no extra pass, no back buffer.
		_environment.adjustment_enabled = true
		_environment.adjustment_contrast = mood.contrast
		_environment.adjustment_saturation = mood.saturation
		_environment.adjustment_color_correction = mood.lut_texture

		# Glow is the tier's call, not the mood's. Enabling it allocates a mip chain of the whole
		# framebuffer -- measured at 16 MB of a 60 MB budget -- so a mood asking for bloom on a
		# device that cannot afford it gets none.
		var tier_glow: bool = QualityManager.setting("glow_enabled")
		_environment.glow_enabled = tier_glow and mood.glow_strength > 0.0
		if _environment.glow_enabled:
			_environment.glow_intensity = mood.glow_strength
			_environment.glow_bloom = mood.glow_strength * 0.25
			_environment.glow_hdr_threshold = 1.0

		_apply_sky(mood)

	if _sun != null:
		_sun.light_color = mood.sun_color
		_sun.light_energy = mood.sun_energy
		_sun.rotation = mood.sun_euler()

	if _camera_hook.is_valid():
		_camera_hook.call(mood.camera_fov)

	if _grade != null:
		# Only the effects that cannot be folded into the tonemap resolve. Exposure, ACES, contrast,
		# saturation and the LUT are all applied above by Environment; repeating any of them here
		# would grade the image twice.
		_grade.set_shader_parameter(&"vignette_strength", mood.vignette_strength)
		_grade.set_shader_parameter(&"grain_amount", mood.grain_amount)
		# Declared only by the screen-sampling variant. Setting an absent uniform is a no-op, which
		# is what lets one code path drive both tier materials.
		_grade.set_shader_parameter(&"chromatic_aberration", mood.chromatic_aberration)


## Build or update the procedural sky for [param mood].
##
## A flat background colour is the most obvious tell of an unfinished 3D scene. A gradient sky with
## a real sun disk costs one shader on geometry drawn behind everything else, and it gives the
## depth fog something honest to blend distant geometry into rather than a painted constant.
##
## The [Sky] and its material are created once and then mutated, because reallocating them every
## frame of a transition would rebuild the radiance cubemap sixty times a second.
func _apply_sky(mood: BiomeMood) -> void:
	if _environment == null:
		return

	var sky := _environment.sky
	if sky == null:
		sky = Sky.new()
		# 32, not 128. Ambient light comes from a flat colour on this renderer, so the radiance map
		# only feeds specular reflections -- and 128 measured 5.7 MB against a 60 MB budget.
		sky.radiance_size = Sky.RADIANCE_SIZE_32
		_environment.sky = sky

	var material := sky.sky_material as ProceduralSkyMaterial
	if material == null:
		material = ProceduralSkyMaterial.new()
		sky.sky_material = material

	material.sky_top_color = mood.sky_top
	material.sky_horizon_color = mood.sky_horizon
	material.ground_bottom_color = mood.sky_ground
	material.ground_horizon_color = mood.sky_horizon
	material.sun_angle_max = 8.0
	material.sun_curve = 0.18
	_environment.background_mode = Environment.BG_SKY
