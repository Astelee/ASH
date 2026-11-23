shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Cliffs and ground. Triplanar projection so level geometry never needs a UV1 unwrap -- chunks can
// be built, cut and rescaled in the editor without an artist touching them.
//
// NOTE: this removes the need for UV1 only. LightmapGI still requires a UV2 unwrap on every static
// mesh, which Godot generates at import. Triplanar does not get you out of that, and the Phase 0
// spec's claim that it did was wrong.
//
// Two material sets blended by vertex colour: paint red in the editor to expose rock through grass.

uniform sampler2D albedo_a : source_color, filter_linear_mipmap, repeat_enable, hint_default_white;
uniform sampler2D normal_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec4 tint_a : source_color = vec4(0.42, 0.44, 0.38, 1.0);
uniform float roughness_a : hint_range(0.0, 1.0) = 0.95;

uniform sampler2D albedo_b : source_color, filter_linear_mipmap, repeat_enable, hint_default_white;
uniform sampler2D normal_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec4 tint_b : source_color = vec4(0.35, 0.31, 0.28, 1.0);
uniform float roughness_b : hint_range(0.0, 1.0) = 0.85;

// World-space tiling, metres per texture repeat.
uniform float texture_scale : hint_range(0.05, 4.0) = 0.35;

// How sharply the three projections cut over. High values band; low values smear.
uniform float blend_sharpness : hint_range(1.0, 16.0) = 4.0;

// Vertex-colour channel driving the A/B blend.
uniform float vertex_blend_strength : hint_range(0.0, 1.0) = 1.0;

// Biome 4 rain. Darkens albedo and drops roughness, which is all "wet" actually is.
uniform float wetness : hint_range(0.0, 1.0) = 0.0;
uniform vec4 wet_tint : source_color = vec4(0.55, 0.58, 0.62, 1.0);

// --- realism layers -------------------------------------------------------------------------
//
// MACRO VARIATION IS THE SINGLE BIGGEST REALISM WIN ON TERRAIN. Visible tiling is what makes ground
// read as a texture rather than as a place, and no amount of texture resolution fixes it. A very
// low-frequency noise multiplied into albedo breaks the repeat at the scale the eye actually notices
// -- tens of metres -- for one extra fetch.
uniform sampler2D macro_noise : filter_linear_mipmap, repeat_enable, hint_default_white;
uniform float macro_scale : hint_range(0.001, 0.2) = 0.018;
uniform float macro_strength : hint_range(0.0, 1.0) = 0.4;

// Detail normal, tiled far tighter than the base. Gives close ground surface breakup the base map
// cannot hold at this texel density.
uniform sampler2D detail_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float detail_scale : hint_range(0.5, 16.0) = 6.0;
uniform float detail_strength : hint_range(0.0, 2.0) = 0.6;

// Slope auto-blend. Steep faces expose rock without anyone painting vertex colour, so a chunk that
// gets rescaled or re-cut in the editor stays correct instead of showing grass on a cliff.
uniform float slope_blend_strength : hint_range(0.0, 1.0) = 0.7;
uniform float slope_threshold : hint_range(0.0, 1.0) = 0.62;
uniform float slope_sharpness : hint_range(0.01, 0.5) = 0.16;

// Baked cavity/AO in the vertex-colour green channel, multiplied into ambient only.
uniform float vertex_ao_strength : hint_range(0.0, 1.0) = 1.0;

varying vec3 tri_position;
varying vec3 tri_world;
varying vec3 tri_normal;
varying float blend_mask;
varying float vertex_ao;

void vertex() {
	// World position kept UNSCALED as well: the macro noise and the detail layer need their own
	// frequencies, and folding texture_scale in here would lock all three together.
	tri_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	tri_position = tri_world * texture_scale;
	tri_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	blend_mask = clamp(COLOR.r * vertex_blend_strength, 0.0, 1.0);
	vertex_ao = mix(1.0, COLOR.g, vertex_ao_strength);
}

vec4 triplanar(sampler2D tex, vec3 pos, vec3 weights) {
	return texture(tex, pos.zy) * weights.x
		+ texture(tex, pos.xz) * weights.y
		+ texture(tex, pos.xy) * weights.z;
}

void fragment() {
	vec3 weights = pow(abs(tri_normal), vec3(blend_sharpness));
	weights /= (weights.x + weights.y + weights.z);

	// Painted mask plus slope. A near-vertical face gets rock whether or not anyone painted it,
	// which is what keeps a re-cut chunk correct without an art pass.
	float slope = 1.0 - clamp(abs(tri_normal.y), 0.0, 1.0);
	float slope_mask = smoothstep(
		slope_threshold - slope_sharpness, slope_threshold + slope_sharpness, slope
	);
	float mask = clamp(max(blend_mask, slope_mask * slope_blend_strength), 0.0, 1.0);

	vec4 a = triplanar(albedo_a, tri_position, weights) * tint_a;
	vec4 b = triplanar(albedo_b, tri_position, weights) * tint_b;
	vec3 base = mix(a.rgb, b.rgb, mask);

	// Macro variation. Centred on 1.0 so it modulates brightness without shifting the average, and
	// sampled from world XZ only -- a vertical gradient on a cliff would read as a lighting error.
	float macro = triplanar(macro_noise, tri_world * macro_scale, weights).r;
	base *= mix(1.0, macro * 2.0, macro_strength);

	float rough = mix(roughness_a, roughness_b, mask);

	// Roughness also takes the macro noise. Uniform roughness across a whole hillside is a strong
	// synthetic tell -- real ground varies in how polished it is patch to patch.
	rough = clamp(rough * mix(1.0, 0.6 + macro * 0.8, macro_strength * 0.5), 0.04, 1.0);

	// Wet ground is darker and smoother, never shinier in albedo.
	ALBEDO = mix(base, base * wet_tint.rgb * 0.65, wetness);
	ROUGHNESS = mix(rough, rough * 0.25, wetness);
	METALLIC = 0.0;

	vec3 n = mix(
		triplanar(normal_a, tri_position, weights).rgb,
		triplanar(normal_b, tri_position, weights).rgb,
		mask
	) * 2.0 - 1.0;

	vec3 detail = triplanar(detail_normal, tri_world * detail_scale, weights).rgb * 2.0 - 1.0;
	detail.xy *= detail_strength;

	// Partial-derivative blend: keeps the detail layer from flattening the base map the way a naive
	// add does. Standing water also flattens normals, so wetness pulls the whole result toward flat.
	vec3 blended = normalize(vec3(n.xy + detail.xy, n.z * detail.z));
	blended = normalize(mix(blended, vec3(0.0, 0.0, 1.0), wetness * 0.6));
	NORMAL_MAP = blended * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;

	// Ambient only. Folding baked AO into direct light reads as dirt, not as occlusion.
	AO = vertex_ao;
	AO_LIGHT_AFFECT = 0.0;
}
