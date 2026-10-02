// Fake volumetric light cone under a lamp: additive, fades with height,
// at grazing angles and when the camera is inside it.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.85, 0.6, 1.0);
uniform float energy = 0.18;

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float fall = pow(1.0 - UV.y, 1.6);
	float near = smoothstep(0.8, 2.5, length(VERTEX));
	ALBEDO = color.rgb * energy * facing * facing * fall * near;
}
