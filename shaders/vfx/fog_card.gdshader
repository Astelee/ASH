shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

// The volumetric-fog replacement. Camera-facing quads with scrolling noise, instanced via MultiMesh.
//
// PERFORMANCE WARNING -- read before editing.
//
// The soft-particle depth fade samples the depth texture. On tile-based mobile GPUs (Adreno, Mali) a
// depth read in a transparent pass forces the tile buffer to resolve, and it interacts badly with
// MSAA, which is on from Mid tier upward. This is the single most likely place for this project to
// lose its frame budget, and it was flagged as such before a line of it was written.
//
// soft_particles is therefore a uniform, not a hardcoded branch. If the device measurement says the
// depth read is too expensive, set it to 0 on the affected tiers and accept that cards visibly slice
// through geometry. Measure before assuming either way -- the fallback is a materially worse-looking
// game, so do not reach for it on suspicion alone.

// Godot 4.7 removed the built-in DEPTH_TEXTURE; it is a hint_depth_texture uniform now.
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;
uniform sampler2D noise_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 fog_color : source_color = vec4(0.78, 0.54, 0.29, 1.0);
uniform float density : hint_range(0.0, 2.0) = 0.6;

uniform vec2 scroll_speed = vec2(0.012, 0.004);
uniform float noise_scale : hint_range(0.1, 8.0) = 1.4;

// Metres over which a card fades as it nears geometry. 0 disables the depth read entirely.
uniform float soft_particles : hint_range(0.0, 4.0) = 1.2;

// Distance fade, metres. Cards thin out before the far plane rather than popping.
uniform float fade_start : hint_range(0.0, 200.0) = 30.0;
uniform float fade_end : hint_range(0.0, 200.0) = 70.0;

// Height gradient, world space. Knee-height in Thornwood, floor-hugging in the Ossuary.
uniform float height_bottom = 0.0;
uniform float height_top = 3.0;

varying vec3 world_position;
varying float view_depth;

void vertex() {
	// Y-billboard rather than full camera-facing: a bank of cards has to read as a volume, and
	// full-facing quads all rotating together read as a wall of stickers.
	mat4 mv = VIEW_MATRIX * MODEL_MATRIX;
	vec3 scale = vec3(
		length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz)
	);
	mv[0] = vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)) * scale.x, 0.0);
	mv[1] = vec4(0.0, scale.y, 0.0, 0.0);
	mv[2] = vec4(normalize(cross(mv[0].xyz, vec3(0.0, 1.0, 0.0))) * scale.z, 0.0);
	MODELVIEW_MATRIX = mv;

	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	view_depth = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
}

void fragment() {
	vec2 uv = UV * noise_scale + TIME * scroll_speed;
	float noise_a = texture(noise_texture, uv).r;
	float noise_b = texture(noise_texture, uv * 0.6 - TIME * scroll_speed * 0.7).r;
	float mask = noise_a * noise_b;

	// Soften the quad's own border, so a card never shows its silhouette.
	vec2 centred = abs(UV - 0.5) * 2.0;
	float edge = (1.0 - smoothstep(0.6, 1.0, centred.x)) * (1.0 - smoothstep(0.6, 1.0, centred.y));

	float height = 1.0 - smoothstep(height_bottom, height_top, world_position.y);
	float distance_fade = 1.0 - smoothstep(fade_start, fade_end, view_depth);

	float depth_fade = 1.0;
	if (soft_particles > 0.0) {
		float raw = texture(depth_tex, SCREEN_UV).r;
		vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
		float scene_depth = -(view.z / view.w);
		depth_fade = clamp((scene_depth - view_depth) / soft_particles, 0.0, 1.0);
	}

	ALBEDO = fog_color.rgb;
	ALPHA = fog_color.a * density * mask * edge * height * distance_fade * depth_fade;
}
