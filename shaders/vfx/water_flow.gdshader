shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_lambert, specular_schlick_ggx;

// Village troughs, Thornwood streams, Bastion rain pools.
//
// HIGH TIER ONLY for refraction. SCREEN_TEXTURE forces a full screen copy, which on a tile-based
// mobile GPU costs roughly what an extra fullscreen pass costs -- and CLAUDE.md allows exactly one
// of those, already spent on grade_and_grain.
//
// use_refraction is a uniform so QualityManager can switch it off on Low and Mid via
// allows_screen_texture(). The rest of the shader -- flowmap distortion, shoreline fade, fresnel --
// is cheap and runs on every tier, so water still reads as water without it.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear;

uniform sampler2D flow_map : hint_default_black, filter_linear;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap, repeat_enable;

uniform vec4 shallow_color : source_color = vec4(0.32, 0.48, 0.46, 0.55);
uniform vec4 deep_color : source_color = vec4(0.06, 0.14, 0.18, 0.92);

uniform float flow_speed : hint_range(0.0, 2.0) = 0.25;
uniform float normal_scale : hint_range(0.1, 8.0) = 2.0;
uniform float wave_strength : hint_range(0.0, 2.0) = 0.4;

// Metres over which the surface fades out at the shoreline. Without it the water plane ends in a
// hard line across the sand, which is the single most obvious tell of fake water.
uniform float shore_fade : hint_range(0.01, 4.0) = 0.6;

// Metres of depth over which shallow_color reaches deep_color.
uniform float depth_range : hint_range(0.1, 20.0) = 3.0;

uniform bool use_refraction = false;
uniform float refraction_strength : hint_range(0.0, 0.2) = 0.03;

varying float view_depth;

void vertex() {
	view_depth = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
}

void fragment() {
	// Flowmap UV cycling: two offset phases cross-faded, so the texture never visibly stretches the
	// way a single scrolling sample does.
	vec2 flow = (texture(flow_map, UV).rg * 2.0 - 1.0) * flow_speed;
	float cycle = fract(TIME * 0.5);
	float phase_a = cycle;
	float phase_b = fract(cycle + 0.5);
	float weight = abs(1.0 - 2.0 * cycle);

	vec3 n_a = texture(normal_texture, UV * normal_scale - flow * phase_a).rgb;
	vec3 n_b = texture(normal_texture, UV * normal_scale - flow * phase_b).rgb;
	vec3 surface_normal = mix(n_a, n_b, weight);
	NORMAL_MAP = surface_normal;
	NORMAL_MAP_DEPTH = wave_strength;

	// Scene depth behind the surface drives both the colour ramp and the shoreline fade.
	float raw = texture(depth_texture, SCREEN_UV).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
	float scene_depth = -(view.z / view.w);
	float water_depth = max(scene_depth - view_depth, 0.0);

	float ramp = clamp(water_depth / depth_range, 0.0, 1.0);
	vec4 tint = mix(shallow_color, deep_color, ramp);

	vec3 color = tint.rgb;
	if (use_refraction) {
		vec2 offset = (surface_normal.xy * 2.0 - 1.0) * refraction_strength;
		color = mix(texture(screen_texture, SCREEN_UV + offset).rgb, tint.rgb, tint.a);
	}

	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);

	ALBEDO = color;
	ROUGHNESS = mix(0.08, 0.25, ramp);
	METALLIC = 0.0;
	SPECULAR = 0.6 + fresnel * 0.4;
	ALPHA = tint.a * clamp(water_depth / shore_fade, 0.0, 1.0);
}
