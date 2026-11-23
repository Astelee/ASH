class_name BiomeMood
extends Resource

## Every parameter that decides how a place feels, in one Resource.
##
## [b]All mood is one call.[/b] `MoodDirector.transition_to(mood, duration)` lerps every field here
## together over one curve — fog, light, grade, grain, wind, camera, audio. That single fact is what
## makes the Ossuary read as intentional rather than as a pile of effects that happened to be
## switched on at the same time.
##
## Retuning an area must never require touching code or a scene. If you find yourself reaching for
## either, a field is missing from this file.

@export_group("Identity")

## Stable id, used by save data and the debug overlay.
@export var id: StringName = &"village"

## Human-readable name.
@export var display_name: String = "Ashfall Village"

@export_group("Fog")

## Depth-fog colour. Also the colour distant geometry dissolves into.
@export var fog_color: Color = Color("#C78A4B")

## Fog density per metre. The Ossuary runs 4x the Village.
@export_range(0.0, 0.2, 0.001) var fog_density: float = 0.012

## Height at which height-fog begins, metres.
@export var fog_height_min: float = -2.0

## Height at which height-fog has fully thinned, metres.
@export var fog_height_max: float = 14.0

## Density multiplier for the MultiMesh fog cards, on top of the quality tier's count.
@export_range(0.0, 2.0, 0.05) var fog_card_density: float = 1.0

@export_group("Light")

## Ambient colour. The Mobile renderer uses a flat colour source, never a sky contribution.
@export var ambient_color: Color = Color(0.45, 0.5, 0.6)

## Ambient energy. 0.15 in the Ossuary is what makes the lantern the only readable light.
@export_range(0.0, 4.0, 0.01) var ambient_energy: float = 0.55

## Sun/moon colour.
@export var sun_color: Color = Color("#FFC785")

## Sun/moon energy.
@export_range(0.0, 8.0, 0.05) var sun_energy: float = 1.60

## Sun elevation, degrees. Negative points downward.
@export_range(-90.0, 0.0, 1.0) var sun_elevation: float = -32.0

## Sun azimuth, degrees.
@export_range(-180.0, 180.0, 1.0) var sun_azimuth: float = 155.0

## Rim colour written globally to every character shader, so actors always read against this fog.
@export var rim_color: Color = Color(1.0, 0.85, 0.6)

@export_group("Exposure & tonemap")

## Exposure in stops, applied before the filmic curve. This is a photographer's exposure, not a
## brightness slider — it slides the whole image along the ACES shoulder.
@export_range(-4.0, 4.0, 0.05) var exposure_ev: float = 0.0

## White point handed to the ACES tonemapper. Below 1 clips sooner; above 1 holds more highlight.
@export_range(0.5, 8.0, 0.1) var white_point: float = 1.6

## Post-tonemap contrast, pivoting on 18 % grey.
@export_range(0.5, 2.0, 0.01) var contrast: float = 1.0

## Post-tonemap saturation. ACES over-saturates bright colour and usually wants pulling back.
@export_range(0.0, 2.0, 0.01) var saturation: float = 0.95

@export_group("Sky & scattering")

## Horizon colour of the procedural sky. A flat background colour is the single most obvious tell
## of an unfinished 3D scene; a gradient sky with a sun disk costs nothing on Mobile.
@export var sky_horizon: Color = Color(0.62, 0.48, 0.36)

## Zenith colour.
@export var sky_top: Color = Color(0.24, 0.32, 0.46)

## Ground bounce colour beneath the horizon.
@export var sky_ground: Color = Color(0.16, 0.13, 0.11)

## How strongly distant geometry takes the sky's colour. Aerial perspective is what makes a
## backdrop read as far away rather than as a flat painted card.
@export_range(0.0, 1.0, 0.01) var aerial_perspective: float = 0.6

## How much the fog brightens when looking toward the sun. Real haze scatters forward; without this
## fog reads as a uniform grey wash.
@export_range(0.0, 1.0, 0.01) var fog_sun_scatter: float = 0.35

## Bloom strength. Kept low — heavy bloom is the other classic tell of an amateur render.
@export_range(0.0, 1.0, 0.01) var glow_strength: float = 0.22

## 32x32x32 LUT strip. Null keeps the previous LUT and only blends weight.
@export var lut_texture: Texture2D

## How strongly the LUT is applied, 0–1.
@export_range(0.0, 1.0, 0.01) var lut_blend: float = 1.0

@export_range(0.0, 1.0, 0.01) var vignette_strength: float = 0.18

@export_range(0.0, 0.3, 0.005) var grain_amount: float = 0.02

@export_range(0.0, 1.0, 0.01) var chromatic_aberration: float = 0.0

@export_group("World")

## Global wind strength driving the foliage shader.
@export_range(0.0, 2.0, 0.05) var wind_strength: float = 0.35

## Camera field of view. 34 crypt, 42 default, 50 boss arena.
@export_range(10.0, 90.0, 0.5) var camera_fov: float = 42.0

@export_group("Audio")

## Reverb wet on the zone send, 0–1.
@export_range(0.0, 1.0, 0.01) var reverb_wet: float = 0.12

## Bitmask of music stems allowed to play. The Ossuary drops to a drone-only mask.
@export_flags("Drone", "Low strings", "Percussion", "Lead", "Choir") var music_stem_mask: int = 31

## Particle preset id spawned by the ambience system.
@export var particle_preset: StringName = &"ember_drift"


## Linear blend between [param a] and [param b] at [param t].
##
## Static and pure so the transition is testable without a scene tree. Every numeric field
## interpolates; ids, textures, and the stem mask snap at the halfway point, because there is no
## meaningful midpoint between two LUTs or two particle systems.
static func blend(a: BiomeMood, b: BiomeMood, t: float) -> BiomeMood:
	var out := BiomeMood.new()
	var k := clampf(t, 0.0, 1.0)
	var past_half := k >= 0.5

	out.id = b.id if past_half else a.id
	out.display_name = b.display_name if past_half else a.display_name

	out.fog_color = a.fog_color.lerp(b.fog_color, k)
	out.fog_density = lerpf(a.fog_density, b.fog_density, k)
	out.fog_height_min = lerpf(a.fog_height_min, b.fog_height_min, k)
	out.fog_height_max = lerpf(a.fog_height_max, b.fog_height_max, k)
	out.fog_card_density = lerpf(a.fog_card_density, b.fog_card_density, k)

	out.ambient_color = a.ambient_color.lerp(b.ambient_color, k)
	out.ambient_energy = lerpf(a.ambient_energy, b.ambient_energy, k)
	out.sun_color = a.sun_color.lerp(b.sun_color, k)
	out.sun_energy = lerpf(a.sun_energy, b.sun_energy, k)
	out.sun_elevation = lerpf(a.sun_elevation, b.sun_elevation, k)
	out.sun_azimuth = lerpf(a.sun_azimuth, b.sun_azimuth, k)
	out.rim_color = a.rim_color.lerp(b.rim_color, k)

	out.exposure_ev = lerpf(a.exposure_ev, b.exposure_ev, k)
	out.white_point = lerpf(a.white_point, b.white_point, k)
	out.contrast = lerpf(a.contrast, b.contrast, k)
	out.saturation = lerpf(a.saturation, b.saturation, k)

	out.sky_horizon = a.sky_horizon.lerp(b.sky_horizon, k)
	out.sky_top = a.sky_top.lerp(b.sky_top, k)
	out.sky_ground = a.sky_ground.lerp(b.sky_ground, k)
	out.aerial_perspective = lerpf(a.aerial_perspective, b.aerial_perspective, k)
	out.fog_sun_scatter = lerpf(a.fog_sun_scatter, b.fog_sun_scatter, k)
	out.glow_strength = lerpf(a.glow_strength, b.glow_strength, k)

	out.lut_texture = b.lut_texture if past_half else a.lut_texture
	out.lut_blend = lerpf(a.lut_blend, b.lut_blend, k)
	out.vignette_strength = lerpf(a.vignette_strength, b.vignette_strength, k)
	out.grain_amount = lerpf(a.grain_amount, b.grain_amount, k)
	out.chromatic_aberration = lerpf(a.chromatic_aberration, b.chromatic_aberration, k)

	out.wind_strength = lerpf(a.wind_strength, b.wind_strength, k)
	out.camera_fov = lerpf(a.camera_fov, b.camera_fov, k)

	out.reverb_wet = lerpf(a.reverb_wet, b.reverb_wet, k)
	out.music_stem_mask = b.music_stem_mask if past_half else a.music_stem_mask
	out.particle_preset = b.particle_preset if past_half else a.particle_preset
	return out


## Sun rotation as Euler radians, from elevation and azimuth.
func sun_euler() -> Vector3:
	return Vector3(deg_to_rad(sun_elevation), deg_to_rad(sun_azimuth), 0.0)
