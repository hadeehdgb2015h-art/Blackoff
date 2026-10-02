// Tall beacon beam over the supply cache: additive, fades towards the top and
// at grazing angles, soft pulse. Visible from anywhere on the map.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(0.35, 1.0, 0.45, 1.0);
uniform float energy = 0.55;

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float fall = pow(1.0 - UV.y, 1.3);               // UV.y = 0 at the top of the cylinder
	float pulse = 0.85 + 0.15 * sin(TIME * 2.0);
	ALBEDO = color.rgb * energy * facing * fall * pulse;
}
