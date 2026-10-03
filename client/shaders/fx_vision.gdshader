// Sky visions (phase 21): a rendered scene shown beside the moon as a faint
// glowing mirage. Additive, so the scene's black is clear sky; a soft round
// edge and a slow ripple keep it a vision rather than a picture. One quad,
// one texture lookup per pixel.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform float fade = 0.0;     // 0 hidden .. 1 fully shown
uniform float energy = 1.5;
uniform vec4 tint : source_color = vec4(0.78, 0.9, 1.0, 1.0);

void vertex() {
	// face the camera (same as fx_billboard)
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz),
		INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz), INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	vec2 uv = UV;
	uv.x += sin(uv.y * 18.0 + TIME * 1.3) * 0.004;
	uv.y += sin(uv.x * 14.0 - TIME * 0.9) * 0.003;
	vec3 c = texture(tex, uv).rgb;
	c = max(c - vec3(0.085), vec3(0.0)) * 1.3;  // the scene's hazy sky fades into the real one
	float d = length(UV - 0.5) * 2.0;
	float edge = 1.0 - smoothstep(0.5, 0.98, d);
	float shimmer = 0.9 + 0.1 * sin(TIME * 2.1 + UV.y * 8.0);
	ALBEDO = c * tint.rgb * (energy * edge * fade * shimmer);
}
