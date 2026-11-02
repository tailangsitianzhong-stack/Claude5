shader_type sky;
#include "res://shaders/noise.gdshaderinc"

uniform vec3 nebula_a : source_color = vec3(0.35, 0.10, 0.45);
uniform vec3 nebula_b : source_color = vec3(0.05, 0.25, 0.45);
uniform vec3 band_normal = vec3(0.3, 1.0, 0.2);
uniform float nebula_strength = 0.12;

float star_layer(vec3 dir, float scale, float threshold, float size, out vec3 tint) {
	vec3 p = dir * scale;
	vec3 cell = floor(p);
	vec3 f = fract(p);
	float h = hash13(cell);
	tint = vec3(1.0);
	if (h < threshold) {
		return 0.0;
	}
	vec3 c = hash33(cell) * 0.6 + 0.2;
	float d = length(f - c);
	float b = (h - threshold) / (1.0 - threshold);
	float t = hash13(cell + 13.7);
	tint = mix(vec3(0.7, 0.8, 1.0), vec3(1.0, 0.85, 0.65), t);
	return smoothstep(size, 0.0, d) * (0.3 + b * 2.5);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec3 col = vec3(0.002, 0.003, 0.009);

	// 天の川っぽい帯
	float bd = dot(dir, normalize(band_normal));
	float band = exp(-bd * bd * 10.0);
	float n1 = fbm(dir * 3.0, 5);
	float n2 = fbm(dir * 6.0 + vec3(4.0), 4);
	vec3 neb = mix(nebula_a, nebula_b, smoothstep(0.3, 0.7, n2));
	col += neb * pow(n1, 3.0) * nebula_strength * (0.3 + band * 2.0);
	col += vec3(0.5, 0.45, 0.4) * band * smoothstep(0.35, 0.8, n2) * 0.03;

	// 星
	vec3 tint;
	float s1 = star_layer(dir, 160.0, 0.965 - band * 0.03, 0.16, tint);
	col += tint * s1;
	float s2 = star_layer(dir, 55.0, 0.992, 0.12, tint);
	col += tint * s2 * 1.6;

	COLOR = col;
}
