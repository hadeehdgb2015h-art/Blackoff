// Camera-facing sprite for far sky objects (moon face, lightning bolts).
// RGBA texture; `energy` above 1 lets it bloom. Fog never applies.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 color : source_color = vec4(1.0);
uniform float energy = 1.0;
uniform float alpha_scale = 1.0;
uniform bool white_alpha = false;  // texture is white + alpha (bolts)

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz),
		INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz), INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	vec4 t = texture(tex, UV);
	ALBEDO = (white_alpha ? vec3(1.0) : t.rgb) * color.rgb * energy;
	ALPHA = t.a * alpha_scale;
}
