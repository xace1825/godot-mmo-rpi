shader_type canvas_item;

uniform float time_scale : hint_range(0.0, 5.0) = 1.0;
uniform float wave_amp : hint_range(0.0, 8.0) = 2.0;

void fragment() {
	vec2 uv = UV;
	float t = TIME * time_scale;
	uv.x += sin(t + uv.y * 12.0) * wave_amp * 0.003;
	uv.y += cos(t + uv.x * 12.0) * wave_amp * 0.003;
	COLOR = texture(TEXTURE, uv);
}
