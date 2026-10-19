shader_type canvas_item;
uniform sampler2D portrait_mask : filter_linear;
uniform vec2 portrait_size = vec2(88.0, 92.0);
uniform vec2 source_size = vec2(88.0, 92.0);
varying vec4 vertex_tint;
void vertex() {
	vertex_tint = COLOR;
}
void fragment() {
	vec2 sample_uv = UV;
	float source_aspect = source_size.x / source_size.y;
	float target_aspect = portrait_size.x / portrait_size.y;
	if (source_aspect > target_aspect) {
		float fraction = target_aspect / source_aspect;
		sample_uv.x = (1.0 - fraction) * 0.5 + UV.x * fraction;
	} else {
		// Preserve the upper portrait focal point rather than cropping the eyes.
		sample_uv.y = UV.y * source_aspect / target_aspect;
	}
	COLOR = texture(TEXTURE, sample_uv) * vertex_tint;
	COLOR.a *= texture(portrait_mask, UV).a;
}
