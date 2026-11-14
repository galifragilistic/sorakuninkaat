shader_type spatial;
render_mode cull_disabled;

// World-space checker used by graybox surfaces so motion is readable
// under the orthographic camera.
uniform vec3 color_a : source_color = vec3(0.5);
uniform vec3 color_b : source_color = vec3(0.45);
uniform float cell_size = 4.0;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 cell = floor(world_position.xz / cell_size);
	float checker = mod(cell.x + cell.y, 2.0);
	ALBEDO = mix(color_a, color_b, checker);
	ROUGHNESS = 1.0;
}
