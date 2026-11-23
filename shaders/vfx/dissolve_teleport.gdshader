shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

// Wayshrine warps, boss arrivals, the Hollow Choir's bodies swapping places.
//
// Separate from character_toon_pbr's dissolve on purpose. That one is a death effect on a lit
// character and has to keep its lighting intact; this one is a full-body transition where the
// silhouette itself is the effect, so it runs unlit-ish and burns along a world-space axis rather
// than through UV noise. Merging them would mean one shader with two mutually exclusive halves.

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, hint_default_white;
uniform vec4 albedo_color : source_color = vec4(0.63, 0.65, 0.70, 1.0);

uniform sampler2D dissolve_noise : hint_default_white, filter_linear, repeat_enable;
uniform float noise_scale : hint_range(0.1, 16.0) = 4.0;

// 0 = fully present, 1 = fully gone. Driven by a Tween from the teleport system.
uniform float progress : hint_range(0.0, 1.0) = 0.0;

// When true the effect runs in reverse: materialising rather than vanishing.
uniform bool arriving = false;

uniform vec4 edge_color : source_color = vec4(0.55, 0.78, 1.0, 1.0);
uniform float edge_width : hint_range(0.0, 0.4) = 0.08;
uniform float edge_energy : hint_range(0.0, 16.0) = 6.0;

// Burns bottom-to-top in world space rather than uniformly, so a teleport reads as a direction
// instead of a fizzle.
uniform float axis_bias : hint_range(0.0, 1.0) = 0.6;
uniform float mesh_height : hint_range(0.1, 8.0) = 1.8;

varying float axis_position;

void vertex() {
	axis_position = clamp(VERTEX.y / mesh_height, 0.0, 1.0);
}

void fragment() {
	float amount = arriving ? 1.0 - progress : progress;

	// Blend the noise with a vertical gradient. At axis_bias 0 the dissolve is pure noise; at 1 it
	// is a clean sweep up the body.
	float noise = texture(dissolve_noise, UV * noise_scale).r;
	float threshold = mix(noise, axis_position, axis_bias);

	if (threshold < amount) {
		discard;
	}

	vec4 base = texture(albedo_texture, UV) * albedo_color;
	ALBEDO = base.rgb;
	ROUGHNESS = 0.9;

	// The burn edge is what makes this read as energy rather than as a rendering glitch.
	float edge = 1.0 - smoothstep(amount, amount + edge_width, threshold);
	EMISSION = edge_color.rgb * edge * edge_energy;
}
