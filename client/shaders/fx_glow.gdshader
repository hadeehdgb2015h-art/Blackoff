// Additive emissive sprite for runes, sigils and corruption veins.
// The texture is white + alpha; colour, spin and pulse are per instance.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 color : source_color = vec4(0.7, 0.35, 1.0, 1.0);
uniform float energy = 1.5;
uniform float spin = 0.0;          // rad/s
uniform float pulse = 0.25;        // 0 = steady
uniform float pulse_speed = 1.6;
uniform float phase = 0.0;
uniform vec4 atlas = vec4(0.0, 0.0, 1.0, 1.0);  // offset.xy, scale.zw

void fragment() {
	vec2 uv = UV - 0.5;
	float a = TIME * spin;
	uv = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * uv + 0.5;
	float m = texture(tex, atlas.xy + clamp(uv, 0.0, 1.0) * atlas.zw).a;
	float p = 1.0 - pulse + pulse * (0.5 + 0.5 * sin(TIME * pulse_speed + phase));
	ALBEDO = color.rgb * m * energy * p;
}
