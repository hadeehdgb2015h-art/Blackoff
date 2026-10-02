// Screen vignette with a dark violet tint; keeps the centre fully clear.
shader_type canvas_item;

uniform vec4 tint : source_color = vec4(0.09, 0.03, 0.14, 1.0);
uniform float strength = 0.6;

void fragment() {
	vec2 q = UV - 0.5;
	q.x *= 1.6;
	float v = smoothstep(0.42, 1.0, length(q));
	COLOR = vec4(tint.rgb, v * strength);
}
