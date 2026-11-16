// Ground and road: the low-poly vertex colours with a small detail texture
// laid over them in world space, rock on steep slopes and tyre ruts on roads.
// Vertex colours are authored in sRGB (like LowPoly.vertex_color_material).
// On roads the vertex alpha holds the position across the road (0 = left
// edge, 1 = right edge), which places the ruts.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D detail_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
// Texture repeats per metre, and how strongly it lightens and darkens the colour.
uniform float detail_scale = 0.25;
uniform float detail_strength = 0.3;
uniform float roughness_value = 1.0;

uniform sampler2D slope_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float slope_scale = 0.15;
uniform vec3 slope_color : source_color = vec3(0.42, 0.38, 0.33);
// Steepness (1 - |normal.y|) where rock starts showing and where it covers the ground.
uniform vec2 slope_range = vec2(0.3, 0.55);
uniform float slope_strength = 0.0;

uniform float road_width = 10.0;
// Distance of the ruts from the road's centre line and their half width (m).
uniform float rut_offset = 0.8;
uniform float rut_width = 0.45;
uniform float rut_strength = 0.0;
// The ruts come and go along the road with this second, larger pattern.
uniform float rut_break_scale = 0.37;

varying vec3 world_position;
varying vec3 world_normal;

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 albedo = srgb_to_linear(COLOR.rgb);
	float detail = texture(detail_texture, world_position.xz * detail_scale).r;
	albedo *= 1.0 + (detail - 0.5) * 2.0 * detail_strength;

	if (slope_strength > 0.0) {
		float steep = smoothstep(slope_range.x, slope_range.y, 1.0 - abs(world_normal.y));
		// Triplanar: no stretching on near-vertical faces.
		vec3 weights = abs(world_normal);
		weights /= weights.x + weights.y + weights.z;
		float rock = texture(slope_texture, world_position.zy * slope_scale).r * weights.x
			+ texture(slope_texture, world_position.xz * slope_scale).r * weights.y
			+ texture(slope_texture, world_position.xy * slope_scale).r * weights.z;
		albedo = mix(albedo, slope_color * (0.6 + 0.8 * rock), steep * slope_strength);
	}

	if (rut_strength > 0.0) {
		float lateral = abs((COLOR.a - 0.5) * road_width);
		float rut = 1.0 - smoothstep(0.0, rut_width, abs(lateral - rut_offset));
		rut *= 0.5 + 0.5 * texture(detail_texture, world_position.xz * detail_scale * rut_break_scale).r;
		albedo *= 1.0 - rut * rut_strength;
	}

	ALBEDO = albedo;
	ROUGHNESS = roughness_value;
}
