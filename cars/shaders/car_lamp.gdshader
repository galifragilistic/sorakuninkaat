// Glowing lamp lens with a reflector pattern of small hexagon-like cells.
// The lenses face forward or back, so the pattern uses the local x and y.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 lamp_color : source_color = vec3(1.0, 0.9, 0.6);
uniform float energy = 4.0;
uniform float cells_per_metre = 38.0;
// How much darker the cell borders are.
uniform float pattern_strength = 0.45;

varying vec3 local_position;

void vertex() {
	local_position = VERTEX;
}

void fragment() {
	vec2 p = local_position.xy * cells_per_metre;
	// Offset every other row: a honeycomb-like grid of rounded cells.
	p.x += mod(floor(p.y), 2.0) * 0.5;
	vec2 cell = fract(p) - 0.5;
	float edge = smoothstep(0.32, 0.5, length(cell));
	float shade = 1.0 - edge * pattern_strength;
	ALBEDO = lamp_color * shade;
	EMISSION = lamp_color * energy * shade;
	ROUGHNESS = 0.2;
}
