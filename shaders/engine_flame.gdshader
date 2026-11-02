shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 color : source_color = vec3(0.3, 0.8, 1.0);
uniform float intensity = 1.8;

void fragment() {
	float t = UV.y; // 0 = ノズル側
	float flicker = 0.85 + 0.15 * sin(TIME * 60.0 + UV.x * 30.0);
	float fade = pow(1.0 - t, 1.6);
	vec3 core = mix(color, vec3(1.0), pow(1.0 - t, 6.0) * 0.8);
	ALBEDO = core * intensity * flicker;
	ALPHA = fade;
}
