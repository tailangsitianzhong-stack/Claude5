shader_type spatial;
render_mode unshaded, shadows_disabled;
#include "res://shaders/noise.gdshaderinc"

uniform vec3 color_hot : source_color = vec3(1.0, 0.95, 0.75);
uniform vec3 color_cool : source_color = vec3(1.0, 0.45, 0.1);
uniform float energy = 6.0;

varying vec3 obj_pos;

void vertex() {
	obj_pos = normalize(VERTEX);
}

void fragment() {
	float n = fbm(obj_pos * 6.0 + vec3(TIME * 0.03), 5);
	float g = fbm(obj_pos * 20.0 - vec3(TIME * 0.05), 3);
	vec3 col = mix(color_cool, color_hot, smoothstep(0.3, 0.7, n * 0.7 + g * 0.3));
	ALBEDO = col * energy;
}
