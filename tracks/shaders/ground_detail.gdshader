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

// Hill shading, as on relief maps: a fixed light in view space (from the top
// left of the screen) lightens slopes facing it and darkens slopes facing
// away, whatever the sun does. Flat ground keeps its colour.
uniform vec3 hill_light = vec3(-0.5, 0.6, 0.6);
uniform float hill_shade_strength = 0.0;
// Darkest and lightest the hill shading may make a slope (colour multiplier).
uniform vec2 hill_shade_range = vec2(0.6, 1.2);
// Shading never lifts a colour above this, so bright snow does not bloom.
uniform float max_albedo = 0.92;
// Higher ground a little lighter, hollows a little darker: colour change per
// metre above or below height_reference, and its largest amount either way.
uniform float height_tint = 0.0;
uniform float height_tint_limit = 0.2;
uniform float height_reference = 0.0;
// Contour lines on the ground every contour_interval metres of height, about
// contour_width pixels wide, darkening the ground by contour_strength.
uniform float contour_strength = 0.0;
uniform float contour_interval = 1.0;
uniform float contour_width = 1.0;

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

	vec3 unshaded = albedo;
	if (hill_shade_strength > 0.0) {
		vec3 light = normalize(hill_light);
		vec3 up = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
		float shade = 1.0 + (dot(NORMAL, light) - dot(up, light)) * hill_shade_strength;
		albedo *= clamp(shade, hill_shade_range.x, hill_shade_range.y);
	}
	if (height_tint > 0.0) {
		float tint = clamp((world_position.y - height_reference) * height_tint, -height_tint_limit, height_tint_limit);
		albedo *= 1.0 + tint;
	}
	albedo = min(albedo, max(unshaded, vec3(max_albedo)));

	if (contour_strength > 0.0) {
		float level = (world_position.y - height_reference) / contour_interval;
		// Distance to the nearest contour in screen pixels, so lines keep their width.
		float pixels = abs(fract(level + 0.5) - 0.5) / max(fwidth(level), 1e-4);
		albedo *= 1.0 - contour_strength * (1.0 - smoothstep(0.0, contour_width, pixels));
	}

	ALBEDO = albedo;
	ROUGHNESS = roughness_value;
}
