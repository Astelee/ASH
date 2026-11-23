shader_type canvas_item;

// The HIGH-tier variant of the fullscreen pass. Same quad, same node, different material.
//
// This one samples the screen, which is the whole point and also the whole cost: `hint_screen_texture`
// makes Godot allocate and resolve a back buffer, measured at +11.8 MB of texture memory on the
// Ashfall Village scene. That is affordable on a tier already running at full render scale and 4x
// MSAA; it is not affordable on the tier that defines the 60 MB budget.
//
// [QualityManager.allows_screen_texture] decides which material [ColorGrade] mounts. Everything
// below HIGH gets grade_and_grain.gdshader, which produces the same vignette, grain and pulse as a
// pure multiplier and cannot do chromatic aberration.
//
// Exposure, tonemapping, contrast, saturation and the LUT are NOT here -- Environment does all five
// in the tonemap resolve on every tier. This pass exists solely for the effects that need to read
// neighbouring pixels.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;

uniform float vignette_strength : hint_range(0.0, 1.0) = 0.18;
uniform float vignette_softness : hint_range(0.01, 1.0) = 0.55;
uniform float grain_amount : hint_range(0.0, 0.3) = 0.02;

// Lateral colour separation, scaled by distance from centre the way a real lens does it. This is
// the one effect in the chain that cannot be expressed as a per-pixel multiplier.
uniform float chromatic_aberration : hint_range(0.0, 1.0) = 0.0;

uniform float pulse_strength : hint_range(0.0, 1.0) = 0.0;
uniform float pulse_speed : hint_range(0.0, 8.0) = 1.5;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 from_centre = uv - vec2(0.5);

	vec3 color;
	if (chromatic_aberration > 0.0) {
		vec2 offset = from_centre * chromatic_aberration * 0.01;
		color.r = texture(screen_texture, uv + offset).r;
		color.g = texture(screen_texture, uv).g;
		color.b = texture(screen_texture, uv - offset).b;
	} else {
		color = texture(screen_texture, uv).rgb;
	}

	float vignette = 1.0 - smoothstep(vignette_softness, 1.0, length(from_centre) * 1.414);
	color *= mix(1.0, vignette, vignette_strength);

	if (pulse_strength > 0.0) {
		float scan = sin(uv.y * 620.0 + TIME * pulse_speed) * 0.5 + 0.5;
		color *= mix(1.0, 0.92 + scan * 0.08, pulse_strength);
	}

	// Multiplicative, matching the cheap variant exactly so the two tiers do not disagree about
	// how grainy the game is.
	if (grain_amount > 0.0) {
		float noise = hash(uv * vec2(1920.0, 1080.0) + fract(TIME) * 37.0) - 0.5;
		color *= 1.0 + noise * grain_amount * 2.0;
	}

	COLOR = vec4(color, 1.0);
}
