shader_type spatial;
render_mode blend_add, depth_draw_never, cull_front, unshaded, shadows_disabled;

// Canopy shafts in Thornwood, window light in the Ossuary. An additive cone mesh -- our stand-in for
// the volumetric light the Mobile renderer does not have.
//
// cull_front rather than cull_back: viewed from inside the cone, the far surface is what should be
// visible. Culling the near faces also stops the shaft from flashing white as the camera passes
// through it.
//
// Three fades, and all three are needed. Without the view-angle fade the cone reads as solid
// geometry when seen side-on. Without the depth fade it visibly intersects the wall it is supposed
// to be landing on. Without the length fade it ends in a hard disc.

// Godot 4.7 removed the built-in DEPTH_TEXTURE; it is a hint_depth_texture uniform now.
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;
uniform sampler2D noise_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 ray_color : source_color = vec4(1.0, 0.86, 0.58, 1.0);
uniform float intensity : hint_range(0.0, 4.0) = 0.6;

uniform vec2 scroll_speed = vec2(0.02, 0.05);
uniform float noise_scale : hint_range(0.1, 6.0) = 1.2;

// How much the shaft dims when viewed perpendicular to its axis.
uniform float view_fade_power : hint_range(0.5, 8.0) = 2.0;

// Metres of softening where the cone meets geometry. 0 disables the depth read.
uniform float depth_fade : hint_range(0.0, 4.0) = 0.8;

// Fade along the cone's length, 0 at the source, 1 at the mouth.
uniform float length_fade_start : hint_range(0.0, 1.0) = 0.35;

varying float along;
varying float view_depth;

void vertex() {
	// UV.y runs the length of the cone mesh by convention; the scatter tool authors it that way.
	along = UV.y;
	view_depth = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
}

void fragment() {
	vec2 uv = UV * noise_scale + TIME * scroll_speed;
	float noise = texture(noise_texture, uv).r * texture(noise_texture, uv * 0.5 - TIME * scroll_speed * 0.4).r;

	// Grazing angles are where a real shaft is brightest, because you are looking along more of it.
	float facing = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
	float view_fade = pow(clamp(facing, 0.0, 1.0), view_fade_power);

	float length_fade = 1.0 - smoothstep(length_fade_start, 1.0, along);

	float occlusion = 1.0;
	if (depth_fade > 0.0) {
		float raw = texture(depth_tex, SCREEN_UV).r;
		vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
		float scene_depth = -(view.z / view.w);
		occlusion = clamp((scene_depth - view_depth) / depth_fade, 0.0, 1.0);
	}

	ALBEDO = vec3(0.0);
	EMISSION = ray_color.rgb * intensity * noise * view_fade * length_fade * occlusion;
	ALPHA = 1.0;
}
