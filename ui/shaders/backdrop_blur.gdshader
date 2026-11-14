shader_type canvas_item;

// Blurs and darkens everything drawn behind this rect (results and pause
// screens over the race view).
uniform float blur_amount : hint_range(0.0, 6.0) = 3.5;
uniform vec4 tint : source_color = vec4(0.055, 0.071, 0.125, 0.45);
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

void fragment() {
	vec3 backdrop = textureLod(screen_texture, SCREEN_UV, blur_amount).rgb;
	COLOR = vec4(mix(backdrop, tint.rgb, tint.a), 1.0);
}
