// Grille: a dark mesh of diagonal openings between thin bars.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 bar_color : source_color = vec3(0.12, 0.12, 0.14);
uniform vec3 hole_color : source_color = vec3(0.01, 0.01, 0.012);
uniform float holes_per_metre = 30.0;
uniform float bar_share = 0.28;

varying vec3 local_position;

void vertex() {
	local_position = VERTEX;
}

void fragment() {
	// Grilles face forward or back (xy) or up (xz): use whichever plane the face lies in.
	vec2 p = abs(NORMAL.y) > 0.5 ? local_position.xz : local_position.xy;
	p *= holes_per_metre;
	vec2 diamond = vec2(p.x + p.y, p.x - p.y) * 0.7071;
	vec2 cell = abs(fract(diamond) - 0.5);
	float bar = 1.0 - step(bar_share * 0.5, min(cell.x, cell.y));
	ALBEDO = mix(hole_color, bar_color, bar);
	ROUGHNESS = 0.7;
	METALLIC = bar * 0.3;
}
