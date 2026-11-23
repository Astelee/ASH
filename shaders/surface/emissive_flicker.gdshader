shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

// Torches, braziers, lanterns, rune glow.
//
// The flicker is evaluated per-instance IN THE SHADER, seeded from world position and
// INSTANCE_CUSTOM -- never as a per-frame CPU animation. A village has dozens of torches; animating
// them from GDScript would be dozens of node updates a frame to accomplish what one noise call does
// for free, and they would all flicker in unison.

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, hint_default_white;
uniform vec4 albedo_color : source_color = vec4(0.28, 0.24, 0.20, 1.0);

uniform vec4 emission_color : source_color = vec4(1.0, 0.62, 0.24, 1.0);
uniform float emission_energy : hint_range(0.0, 16.0) = 4.0;

// Fraction of energy the flicker can remove. 0 is a steady lamp, 1 gutters out completely.
uniform float flicker_depth : hint_range(0.0, 1.0) = 0.35;
uniform float flicker_speed : hint_range(0.0, 20.0) = 7.0;

// Second, slower band. Two frequencies is the difference between "flame" and "faulty bulb".
uniform float flicker_slow_speed : hint_range(0.0, 8.0) = 1.3;

// Mask restricting emission to the flame area of the texture.
uniform sampler2D emission_mask : hint_default_white, filter_linear;

varying float seed;

float hash11(float x) {
	return fract(sin(x * 127.1) * 43758.5453);
}

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(vec3(0.0), 1.0)).xyz;
	// Seed from the instance origin so two torches a metre apart are out of phase, and from
	// INSTANCE_CUSTOM so a MultiMesh of them is too.
	seed = hash11(world.x * 3.7 + world.y * 11.3 + world.z * 7.1 + INSTANCE_CUSTOM.x * 53.0) * TAU;
}

void fragment() {
	vec4 base = texture(albedo_texture, UV) * albedo_color;
	ALBEDO = base.rgb;
	ROUGHNESS = 1.0;

	float fast = sin(TIME * flicker_speed + seed);
	float slow = sin(TIME * flicker_slow_speed + seed * 1.7);
	// Two bands multiplied, remapped to 0..1, then scaled by depth. Never reaches full black, so a
	// torch stays a landmark even at its lowest.
	float flicker = 1.0 - flicker_depth * (0.5 - 0.5 * (fast * 0.6 + slow * 0.4));

	float mask = texture(emission_mask, UV).r;
	EMISSION = emission_color.rgb * emission_energy * flicker * mask;
}
