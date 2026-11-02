shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

uniform vec3 atmo_color : source_color = vec3(0.4, 0.7, 1.0);
uniform float strength = 1.0;
uniform vec3 sun_position = vec3(0.0);

varying vec3 world_normal;
varying vec3 world_pos;

void vertex() {
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 n = normalize(world_normal);
	vec3 v = normalize(CAMERA_POSITION_WORLD - world_pos);
	vec3 l = normalize(sun_position - world_pos);
	float rim = 1.0 - clamp(dot(n, v), 0.0, 1.0);
	float lit = smoothstep(-0.35, 0.5, dot(n, l));
	float a = pow(rim, 2.2) * lit * strength;
	ALBEDO = atmo_color * 1.5;
	ALPHA = clamp(a, 0.0, 1.0);
}
