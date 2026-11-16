// Tyre rubber with lettering-like ridges on the sidewall and a block tread.
// The wheel mesh has its axle along local y.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 rubber_color : source_color = vec3(0.045, 0.045, 0.05);
uniform float tread_blocks = 22.0;
// Grooves across the tread width, and the dark share of each block.
uniform float tread_rows = 3.0;
uniform float groove_share = 0.22;
uniform float sidewall_ribs = 64.0;
uniform vec2 sidewall_band = vec2(0.24, 0.29);

varying vec3 local_position;

void vertex() {
	local_position = VERTEX;
}

void fragment() {
	float angle = atan(local_position.z, local_position.x) / TAU + 0.5;
	float radius = length(local_position.xz);
	float shade = 1.0;
	// World-space normal hint is enough: faces whose normal runs along the axle are sidewalls.
	vec3 local_normal = normalize((inverse(MODEL_MATRIX) * vec4((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz, 0.0)).xyz);
	if (abs(local_normal.y) > 0.6) {
		// Sidewall: a ring of short raised ribs, like moulded lettering.
		float in_band = step(sidewall_band.x, radius) * step(radius, sidewall_band.y);
		float rib = step(0.5, fract(angle * sidewall_ribs));
		shade = 1.0 + in_band * rib * 1.6;
	} else {
		// Tread: staggered blocks with grooves between them.
		float row = local_position.y * tread_rows * 4.0;
		float along = angle * tread_blocks + mod(floor(row), 2.0) * 0.5;
		float groove = step(1.0 - groove_share, fract(along)) + step(1.0 - groove_share, fract(row));
		shade = 1.0 - clamp(groove, 0.0, 1.0) * 0.75;
	}
	ALBEDO = rubber_color * shade;
	ROUGHNESS = 0.92;
}
