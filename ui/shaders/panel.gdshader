shader_type canvas_item;

// Panel with chamfered top-left and bottom-right corners, an inner border
// and an optional blurred backdrop (SPEC.md section 6).
uniform vec2 rect_size = vec2(100.0, 100.0);
uniform float chamfer = 14.0;
uniform float border_width = 2.0;
uniform vec4 fill_color : source_color = vec4(0.055, 0.071, 0.125, 0.86);
uniform vec4 border_color : source_color = vec4(0.18, 0.21, 0.33, 1.0);
// Mip level of the screen texture used behind translucent fills. 0 = no
// backdrop sampling: the fill is blended normally with whatever is below.
uniform float blur_amount = 2.5;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

varying vec2 local_position;

void vertex() {
	local_position = VERTEX;
}

// Distance in pixels from the panel edge; positive inside.
float edge_distance(vec2 point) {
	float distance_to_edge = min(min(point.x, point.y), min(rect_size.x - point.x, rect_size.y - point.y));
	distance_to_edge = min(distance_to_edge, (point.x + point.y - chamfer) * 0.70711);
	vec2 from_corner = rect_size - point;
	distance_to_edge = min(distance_to_edge, (from_corner.x + from_corner.y - chamfer) * 0.70711);
	return distance_to_edge;
}

void fragment() {
	float distance_to_edge = edge_distance(local_position);
	float coverage = clamp(distance_to_edge + 0.5, 0.0, 1.0);
	float interior = clamp(distance_to_edge - border_width + 0.5, 0.0, 1.0);
	vec4 fill = fill_color;
	if (blur_amount > 0.0) {
		vec3 backdrop = textureLod(screen_texture, SCREEN_UV, blur_amount).rgb;
		fill = vec4(mix(backdrop, fill_color.rgb, fill_color.a), 1.0);
	}
	vec4 color = border_width > 0.0 ? mix(border_color, fill, interior) : fill;
	COLOR = vec4(color.rgb, color.a * coverage);
}
