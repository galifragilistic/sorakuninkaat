shader_type canvas_item;

// Full-screen vignette drawn over the 3D view and under the HUD.
uniform float strength : hint_range(0.0, 1.0) = 0.45;
uniform vec3 tint : source_color = vec3(0.03, 0.04, 0.09);
// Distance from the centre (0..1) where darkening starts.
uniform float inner_radius : hint_range(0.0, 1.0) = 0.5;
uniform float softness : hint_range(0.01, 1.0) = 0.6;

void fragment() {
	// 1.0 at the corners.
	float distance_to_center = length(UV - vec2(0.5)) * 1.41421;
	float amount = smoothstep(inner_radius, inner_radius + softness, distance_to_center);
	COLOR = vec4(tint, amount * strength);
}
