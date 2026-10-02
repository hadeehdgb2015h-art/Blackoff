// Low ground mist: two scrolling noise layers in world space, soft edges.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec4 color : source_color = vec4(0.55, 0.42, 0.78, 0.4);
uniform float scale = 0.06;
uniform float speed = 1.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz * scale;
	float t = TIME * speed;
	float n = texture(noise_tex, p + vec2(t * 0.011, t * 0.006)).r;
	n *= texture(noise_tex, p * 1.9 + vec2(-t * 0.008, t * 0.012)).r;
	float edge = smoothstep(0.0, 0.12, UV.x) * smoothstep(1.0, 0.88, UV.x) * smoothstep(0.0, 0.12, UV.y) * smoothstep(1.0, 0.88, UV.y);
	float near = smoothstep(0.6, 3.0, length(VERTEX));  // no flat sheet right in the eye
	ALBEDO = color.rgb;
	ALPHA = clamp(color.a * n * 2.2 * edge * near, 0.0, 1.0);
}
