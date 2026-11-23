shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Realistic character shading. Replaces character_toon_pbr's 3-band quantized diffuse with a full
// energy-conserving PBR response.
//
// WHY THIS IS STILL MOBILE-SAFE
//
// Realism on a tile-based GPU comes from material response and tonemapping, not from screen-space
// effects. There is no SSAO, SSR, SSGI or subsurface scattering on Godot's Mobile renderer, and this
// shader asks for none of them. What it does instead:
//
//   * Full GGX specular with a real Fresnel term, driven by an ORM texture rather than sliders.
//   * A DETAIL NORMAL layer that tiles far tighter than the base map. Close-up surface breakup is
//     most of what separates "realistic" from "clean 3D", and it costs one extra texture fetch.
//   * BAKED AO in the ORM red channel, multiplied into ambient only. Multiplying AO into direct
//     light is the classic mistake -- it darkens the lit side and reads as dirt, not occlusion.
//   * Wrapped diffuse for skin and cloth, a cheap stand-in for the subsurface term the Mobile
//     renderer does not have. Half-Lambert wrap softens the terminator without a second pass.
//
// The gameplay uniforms (hit_flash, dissolve, poise_break_glow) are unchanged -- Phase 2 combat
// drives them by name and must keep working.

global uniform vec4 ashfall_rim_color;

// INSTANCE uniforms, not plain ones. Every actor shares one ShaderMaterial so the whole roster
// batches into a small number of draw calls, but each still needs its own silhouette colour and its
// own hit flash. A plain uniform would flash every enemy on screen when one of them got hit, and
// duplicating the material per actor would multiply the draw calls instead. Godot allows 16 of
// these per shader; this uses four.
instance uniform vec4 albedo_color : source_color = vec4(0.62, 0.58, 0.54, 1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, hint_default_white;

// Packed Occlusion / Roughness / Metallic. One fetch instead of three, which matters on mobile
// bandwidth far more than it does on desktop.
uniform sampler2D orm_texture : filter_linear_mipmap_anisotropic, hint_default_white;
uniform bool use_orm = false;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.68;
uniform float metallic_value : hint_range(0.0, 1.0) = 0.0;
uniform float ao_strength : hint_range(0.0, 1.0) = 1.0;

uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic;
uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;

// Detail normal, tiled tight. This is the single cheapest realism win available.
uniform sampler2D detail_normal : hint_normal, filter_linear_mipmap_anisotropic;
uniform float detail_tiling : hint_range(1.0, 32.0) = 9.0;
uniform float detail_strength : hint_range(0.0, 2.0) = 0.45;

// Wrapped diffuse. 0 is Lambert; higher values push light around the terminator the way skin and
// thick cloth actually behave.
uniform float diffuse_wrap : hint_range(0.0, 0.6) = 0.18;
uniform vec4 wrap_tint : source_color = vec4(0.85, 0.42, 0.34, 1.0);

// Rim stays, but as a grounded specular-ish edge rather than a cartoon outline. MoodDirector writes
// the colour so characters keep reading against the biome fog.
uniform float rim_power : hint_range(0.5, 12.0) = 5.0;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.22;

instance uniform float hit_flash : hint_range(0.0, 1.0) = 0.0;
instance uniform float dissolve_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 dissolve_edge_color : source_color = vec4(1.0, 0.45, 0.12, 1.0);
uniform float dissolve_edge_width : hint_range(0.0, 0.3) = 0.06;
uniform sampler2D dissolve_noise : hint_default_white, filter_linear;
instance uniform float poise_break_glow : hint_range(0.0, 1.0) = 0.0;

varying float ao_term;

void fragment() {
	if (dissolve_amount > 0.0) {
		float noise = texture(dissolve_noise, UV * 3.0).r;
		if (noise < dissolve_amount) {
			discard;
		}
		float edge = smoothstep(dissolve_amount, dissolve_amount + dissolve_edge_width, noise);
		EMISSION += dissolve_edge_color.rgb * (1.0 - edge) * 4.0;
	}

	vec4 base = texture(albedo_texture, UV) * albedo_color;
	ALBEDO = mix(base.rgb, vec3(1.0), hit_flash);

	if (use_orm) {
		vec3 orm = texture(orm_texture, UV).rgb;
		ao_term = mix(1.0, orm.r, ao_strength);
		ROUGHNESS = orm.g * roughness_value;
		METALLIC = orm.b * metallic_value;
	} else {
		ao_term = 1.0;
		ROUGHNESS = roughness_value;
		METALLIC = metallic_value;
	}

	// Base normal plus a tight detail layer. Partial-derivative blending keeps the detail from
	// flattening the base map, which naive addition does.
	vec3 base_n = texture(normal_texture, UV).xyz * 2.0 - 1.0;
	base_n.xy *= normal_strength;
	vec3 detail_n = texture(detail_normal, UV * detail_tiling).xyz * 2.0 - 1.0;
	detail_n.xy *= detail_strength;
	vec3 blended = normalize(vec3(base_n.xy + detail_n.xy, base_n.z * detail_n.z));
	NORMAL_MAP = blended * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;

	// AO belongs on ambient only. Folding it into direct light darkens the lit side of a face and
	// reads as grime rather than as contact shadow.
	AO = ao_term;
	AO_LIGHT_AFFECT = 0.0;

	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), rim_power);
	EMISSION += ashfall_rim_color.rgb * fresnel * rim_strength;
	EMISSION += base.rgb * poise_break_glow * 1.5;
}

void light() {
	vec3 n = normalize(NORMAL);
	vec3 l = normalize(LIGHT);
	float n_dot_l = dot(n, l);

	// Wrapped diffuse: remap N.L from [-wrap, 1] to [0, 1] so the terminator softens instead of
	// hitting a hard line. Normalised so total energy does not climb with the wrap amount.
	float wrapped = clamp((n_dot_l + diffuse_wrap) / (1.0 + diffuse_wrap), 0.0, 1.0);
	float energy = 1.0 / (1.0 + diffuse_wrap);

	// The wrap band is tinted: light travelling a short distance through skin or cloth comes back
	// warm. Cheap, and it is most of what a subsurface term buys visually.
	float band = clamp(1.0 - abs(n_dot_l) * 3.0, 0.0, 1.0);
	vec3 warmth = wrap_tint.rgb * band * diffuse_wrap;

	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * wrapped * energy;
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * warmth;

	// GGX specular with Schlick Fresnel. Dielectrics keep a 4% base reflectance; metals take their
	// tint from albedo, which is what makes rusted steel read as metal rather than grey plastic.
	vec3 h = normalize(l + normalize(VIEW));
	float n_dot_h = clamp(dot(n, h), 0.0, 1.0);
	float n_dot_v = clamp(dot(n, normalize(VIEW)), 0.0, 1.0);
	float v_dot_h = clamp(dot(normalize(VIEW), h), 0.0, 1.0);

	float a = max(ROUGHNESS * ROUGHNESS, 0.002);
	float a2 = a * a;
	float d_denom = n_dot_h * n_dot_h * (a2 - 1.0) + 1.0;
	float ndf = a2 / (PI * d_denom * d_denom);

	float k = a * 0.5;
	float g = (n_dot_v / (n_dot_v * (1.0 - k) + k)) * (max(n_dot_l, 0.0) / (max(n_dot_l, 0.0) * (1.0 - k) + k));

	vec3 f0 = mix(vec3(0.04), ALBEDO, METALLIC);
	vec3 fresnel = f0 + (1.0 - f0) * pow(1.0 - v_dot_h, 5.0);

	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * ndf * g * fresnel * max(n_dot_l, 0.0) * 0.25;
}
