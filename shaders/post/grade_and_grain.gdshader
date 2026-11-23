shader_type canvas_item;
render_mode blend_mul, unshaded;

// The default fullscreen pass: vignette, film grain, eerie pulse. One ColorRect on one CanvasLayer.
//
// THIS SHADER DELIBERATELY DOES NOT SAMPLE THE SCREEN. A `hint_screen_texture` forces Godot to
// allocate and resolve a full back buffer, measured at +11.8 MB of a 60 MB texture budget on the
// Ashfall Village scene. Every effect here is a per-pixel MULTIPLIER, so `blend_mul` applies it
// against whatever is already in the framebuffer for free.
//
// Multiplicative grain is not a compromise, it is the more correct model: film grain is a density
// variation, so it naturally scales with what is underneath it and leaves true black alone. The
// earlier additive version needed an explicit luminance term to fake exactly that behaviour.
//
// Exposure, tonemapping, contrast, saturation and the LUT are NOT here. Environment does all five
// inside the tonemap resolve, which costs no extra pass and no extra memory -- see MoodDirector.
// Chromatic aberration genuinely needs the screen copy, so it lives in grade_screen.gdshader and
// only runs on the tier whose budget can afford it.
//
// Do not add a second fullscreen quad for any reason. Anything new belongs in this chain.

uniform float vignette_strength : hint_range(0.0, 1.0) = 0.18;
uniform float vignette_softness : hint_range(0.01, 1.0) = 0.55;
uniform float grain_amount : hint_range(0.0, 0.3) = 0.02;

uniform float pulse_strength : hint_range(0.0, 1.0) = 0.0;
uniform float pulse_speed : hint_range(0.0, 8.0) = 1.5;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float multiplier = 1.0;

	float vignette = 1.0 - smoothstep(vignette_softness, 1.0, length(uv - vec2(0.5)) * 1.414);
	multiplier *= mix(1.0, vignette, vignette_strength);

	if (pulse_strength > 0.0) {
		float scan = sin(uv.y * 620.0 + TIME * pulse_speed) * 0.5 + 0.5;
		multiplier *= mix(1.0, 0.92 + scan * 0.08, pulse_strength);
	}

	if (grain_amount > 0.0) {
		float noise = hash(uv * vec2(1920.0, 1080.0) + fract(TIME) * 37.0) - 0.5;
		multiplier *= 1.0 + noise * grain_amount * 2.0;
	}

	COLOR = vec4(vec3(max(multiplier, 0.0)), 1.0);
}
