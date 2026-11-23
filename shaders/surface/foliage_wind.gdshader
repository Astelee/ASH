shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha, diffuse_lambert, specular_disabled;

// Grass, canopy, hanging cloth. Vertex sway seeded from world position so neighbouring instances
// never move in lockstep, with a per-instance phase offset on top from INSTANCE_CUSTOM.
//
// alpha_scissor ONLY -- never blend. Overlapping transparent quads covering a field of grass is the
// fastest way to lose mobile fill rate, and foliage is the largest-area cutout in the game.
// depth_prepass_alpha keeps the scissored edges sorting correctly without a transparent pass.
//
// Wind strength is the global uniform MoodDirector writes, so a whole biome's foliage responds to
// one write per frame.

global uniform float ashfall_wind_strength;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, hint_default_white;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.5;

// Metres of sway at full wind, at the top of the mesh.
uniform float sway_amplitude : hint_range(0.0, 1.0) = 0.18;
uniform float sway_speed : hint_range(0.0, 8.0) = 1.6;

// Spatial frequency of the wind field. Low values make broad gusts, high values make chatter.
uniform float gust_scale : hint_range(0.01, 2.0) = 0.18;

// Wind direction in world XZ.
uniform vec2 wind_direction = vec2(1.0, 0.35);

// Height at which sway reaches full amplitude. Below this the mesh is anchored, so grass does not
// slide out of the ground.
uniform float anchor_height : hint_range(0.05, 8.0) = 1.0;

// Transmission: light bleeding through a leaf lit from behind.
uniform float translucency : hint_range(0.0, 2.0) = 0.7;
uniform vec4 translucency_color : source_color = vec4(0.55, 0.75, 0.35, 1.0);

// How tightly the glow focuses around the sun. Low values wash the whole plant; high values give a
// narrow halo only when the sun is almost directly behind the leaf, which is what real foliage does.
uniform float translucency_power : hint_range(1.0, 16.0) = 4.0;

// How much INSTANCE_CUSTOM.y (per-instance thickness) modulates transmission. 0 disables it.
uniform float thickness_variation : hint_range(0.0, 1.0) = 0.0;

// INSTANCE_CUSTOM is a vertex-stage builtin; light() cannot see it, so it travels as a varying.
varying float instance_thickness;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// INSTANCE_CUSTOM.x carries a per-instance phase written by the MultiMesh scatterer. Without it
	// an entire field pulses as one organism, which reads as a bug rather than as wind.
	float phase = INSTANCE_CUSTOM.x * TAU;
	instance_thickness = INSTANCE_CUSTOM.y;

	float gust = sin(world.x * gust_scale + TIME * sway_speed + phase)
		* cos(world.z * gust_scale * 0.7 + TIME * sway_speed * 0.6 + phase);

	// Anchored at the base, full sway at the top: bend, not translation.
	float influence = clamp(VERTEX.y / anchor_height, 0.0, 1.0);
	influence *= influence;

	vec2 dir = normalize(wind_direction);
	float amount = gust * sway_amplitude * ashfall_wind_strength * influence;
	VERTEX.x += dir.x * amount;
	VERTEX.z += dir.y * amount;
}

void fragment() {
	vec4 sampled = texture(albedo_texture, UV) * tint;
	ALBEDO = sampled.rgb;
	ALPHA = sampled.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;
	ROUGHNESS = 1.0;
	NORMAL_MAP_DEPTH = 1.0;
}

void light() {
	vec3 l = normalize(LIGHT);
	vec3 n = normalize(NORMAL);

	// Wrapped rather than clamped N.L. A leaf is a thin sheet; light reaching one edge lights most
	// of it, so a hard Lambert terminator across a grass blade is wrong at any distance.
	float wrapped = clamp((dot(n, l) + 0.5) / 1.5, 0.0, 1.0);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * wrapped * 0.667;

	// View-dependent transmission. Real translucency is forward-scattering: a leaf only glows when
	// you are looking roughly INTO the light through it. The old inverted-N.L version glowed from
	// every angle, which made a canopy read as self-illuminated plastic. This is the standard cheap
	// approximation -- dot(V, -L) raised to a power -- and it costs three instructions.
	vec3 v = normalize(VIEW);
	float transmit = pow(clamp(dot(v, -l), 0.0, 1.0), translucency_power);

	// Thin geometry transmits more than thick. INSTANCE_CUSTOM.y carries a per-instance thickness
	// from the scatterer where one exists; thickness_variation at 0 simply disables the variation.
	float thickness = mix(1.0, clamp(instance_thickness, 0.0, 1.0), thickness_variation);

	DIFFUSE_LIGHT += (
		translucency_color.rgb * ALBEDO * LIGHT_COLOR * ATTENUATION
		* transmit * translucency * thickness
	);
}
