shader_type spatial;
#include "res://shaders/noise.gdshaderinc"

// 0: 地球型 / 2: ガス惑星 / 3: 氷 / 4: 溶岩 / 5: 岩石(衛星)
uniform int planet_type = 0;
uniform vec3 color_a : source_color = vec3(0.05, 0.2, 0.45);
uniform vec3 color_b : source_color = vec3(0.2, 0.4, 0.15);
uniform vec3 color_c : source_color = vec3(0.55, 0.45, 0.35);
uniform float seed = 0.0;
uniform float noise_scale = 2.5;
uniform float sea_level = 0.5;
uniform bool clouds = true;

varying vec3 obj_pos;

void vertex() {
	obj_pos = normalize(VERTEX);
}

void fragment() {
	vec3 p = obj_pos * noise_scale + vec3(seed);
	vec3 col = vec3(0.5);
	float rough = 0.9;
	vec3 emit = vec3(0.0);

	if (planet_type == 0) {
		float h = fbm(p, 6);
		if (h < sea_level) {
			col = mix(color_a * 0.45, color_a, smoothstep(sea_level - 0.25, sea_level, h));
			rough = 0.3;
		} else {
			col = mix(color_b, color_c, smoothstep(sea_level, sea_level + 0.25, h));
		}
		float lat = abs(obj_pos.y) + (h - 0.5) * 0.2;
		col = mix(col, vec3(0.92, 0.95, 1.0), smoothstep(0.78, 0.86, lat));
		if (clouds) {
			vec3 q = obj_pos * noise_scale * 1.6 + vec3(seed * 2.0 + TIME * 0.004, 0.0, 0.0);
			float cl = fbm(q + fbm(q * 1.5, 3), 5);
			float c = smoothstep(0.5, 0.75, cl);
			col = mix(col, vec3(1.0), c * 0.85);
			rough = mix(rough, 0.95, c);
		}
	} else if (planet_type == 2) {
		float warp = fbm(p * vec3(1.0, 3.0, 1.0), 5);
		float y = obj_pos.y * 9.0 + warp * 3.0;
		float bands = sin(y) * 0.5 + 0.5;
		float bands2 = sin(y * 2.7 + 1.3) * 0.5 + 0.5;
		col = mix(color_a, color_b, bands);
		col = mix(col, color_c, bands2 * 0.5);
		// 大赤斑風の渦
		vec3 spot_c = normalize(vec3(0.8, -0.35, 0.5));
		float sd = length(obj_pos - spot_c);
		col = mix(col, color_b * 0.8 + vec3(0.15, 0.02, 0.0), smoothstep(0.18, 0.08, sd + warp * 0.05));
		rough = 1.0;
	} else if (planet_type == 3) {
		float h = fbm(p, 6);
		float ridge = 1.0 - abs(fbm(p * 2.0 + vec3(3.0), 5) * 2.0 - 1.0);
		col = mix(color_a, color_c, h);
		col = mix(col, color_b, smoothstep(0.88, 0.97, ridge));
		rough = 0.45;
	} else if (planet_type == 4) {
		float h = fbm(p, 6);
		float ridge = 1.0 - abs(fbm(p * 1.5 + vec3(7.0), 6) * 2.0 - 1.0);
		col = mix(color_a, color_b, h);
		float crack = smoothstep(0.86, 0.97, ridge);
		col = mix(col, color_c * 0.3, crack);
		float pulse = 0.8 + 0.2 * sin(TIME * 0.8 + h * 20.0);
		emit = color_c * crack * 4.0 * pulse;
	} else {
		float h = fbm(p, 6);
		float cr = fbm(p * 3.0, 4);
		col = mix(color_a, color_b, h);
		col *= 0.75 + 0.5 * smoothstep(0.35, 0.65, cr);
		col = mix(col, color_c, smoothstep(0.7, 0.8, fbm(p * 6.0, 3)) * 0.4);
	}

	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.3;
	EMISSION = emit;
}
