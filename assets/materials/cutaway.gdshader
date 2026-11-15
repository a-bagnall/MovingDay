shader_type spatial;

// Cargo bay shell. Cuts a soft screen-space hole around each player standing inside.
// reveals[i].xy = player in screen UV, reveals[i].z = 0..1 strength.

uniform vec4 albedo : source_color = vec4(0.92, 0.93, 0.97, 1.0);
uniform vec3 reveals[2];
uniform float inner_radius = 0.07;
uniform float outer_radius = 0.17;

void fragment() {
	ALBEDO = albedo.rgb;
	float aspect = VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
	float alpha = 1.0;
	for (int i = 0; i < 2; i++) {
		float dist = length((SCREEN_UV - reveals[i].xy) * vec2(aspect, 1.0));
		float hole = 1.0 - smoothstep(inner_radius, outer_radius, dist);
		alpha = min(alpha, 1.0 - hole * reveals[i].z);
	}
	ALPHA = alpha;
	ALPHA_HASH_SCALE = 1.0;
}
