shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, shadows_disabled;
#include "res://shaders/noise.gdshaderinc"

uniform vec3 ring_color : source_color = vec3(0.85, 0.75, 0.6);
uniform float inner = 0.55; // 0.5 = 外周
uniform float outer = 1.0;

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	if (d < inner || d > outer) {
		discard;
	}
	float t = (d - inner) / (outer - inner);
	float bands = vnoise(vec3(t * 60.0, 0.0, 0.0)) * 0.6 + vnoise(vec3(t * 200.0, 3.0, 0.0)) * 0.4;
	float gap = smoothstep(0.02, 0.0, abs(t - 0.62)) ;
	float a = bands * smoothstep(0.0, 0.05, t) * smoothstep(1.0, 0.9, t) * (1.0 - gap);
	ALBEDO = ring_color * (0.6 + bands * 0.5);
	ALPHA = clamp(a * 0.85, 0.0, 1.0);
	ROUGHNESS = 1.0;
}
