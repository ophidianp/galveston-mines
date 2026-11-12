// Full-screen post-process for the mines: bloom around bright lights,
// per-level colour grading, vignette and a little film grain.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform vec4 tint : source_color = vec4(1.0);
uniform float saturation = 0.9;
uniform float contrast = 1.08;
uniform float bloom = 0.55;
uniform float bloom_threshold = 0.42;
uniform float vignette = 0.55;
uniform float grain = 0.035;

vec3 bright(vec2 uv) {
	vec3 c = texture(screen_tex, uv).rgb;
	return max(c - bloom_threshold, vec3(0.0));
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = SCREEN_PIXEL_SIZE;
	vec3 col = texture(screen_tex, uv).rgb;

	// Cheap two-ring bloom: soft glow around lanterns, lamps and crystals.
	vec3 glow = vec3(0.0);
	for (int i = 0; i < 12; i++) {
		float a = float(i) * 0.5235988;
		vec2 dir = vec2(cos(a), sin(a));
		glow += bright(uv + dir * px * 7.0);
		glow += bright(uv + dir * px * 18.0) * 0.6;
	}
	col += glow / 19.2 * bloom;

	// Grade.
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(luma), col, saturation);
	col = (col - 0.5) * contrast + 0.5;
	col *= tint.rgb;

	// Vignette.
	vec2 d = uv - 0.5;
	d.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x * 0.5625;
	col *= clamp(1.0 - dot(d, d) * vignette * 2.2, 0.0, 1.0);

	// Film grain.
	float n = fract(sin(dot(uv * 913.0 + fract(TIME * 7.3), vec2(12.9898, 78.233))) * 43758.5453);
	col += (n - 0.5) * grain;

	COLOR = vec4(max(col, vec3(0.0)), 1.0);
}
