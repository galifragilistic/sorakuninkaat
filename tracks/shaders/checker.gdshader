shader_type spatial;
render_mode cull_disabled;

// UV-space checkerboard for the start/finish line.
uniform vec3 color_a : source_color = vec3(0.95);
uniform vec3 color_b : source_color = vec3(0.06);
uniform vec2 cells = vec2(8.0, 2.0);

void fragment() {
	vec2 cell = floor(UV * cells);
	float checker = mod(cell.x + cell.y, 2.0);
	ALBEDO = mix(color_a, color_b, checker);
	ROUGHNESS = 0.9;
}
