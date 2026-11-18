// The small 3D picture of the retro style, scaled up with sharp pixels (the
// TextureRect filters it with nearest). Colours are cut down to a few levels
// per channel with 4x4 ordered (Bayer) dithering, like 15-bit consoles.
shader_type canvas_item;

// Highest level per channel: 2^bits - 1 (31 for 5-bit colour).
uniform float levels = 31.0;
uniform float dither_strength = 1.0;

const float BAYER[16] = float[16](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0
);

void fragment() {
	vec4 colour = texture(TEXTURE, UV);
	// The dither pattern follows the rendered pixels, not the screen pixels.
	ivec2 pixel = ivec2(floor(UV * vec2(textureSize(TEXTURE, 0))));
	int index = (pixel.y % 4) * 4 + (pixel.x % 4);
	float threshold = (BAYER[index] + 0.5) / 16.0 - 0.5;
	vec3 quantised = floor(colour.rgb * levels + 0.5 + threshold * dither_strength) / levels;
	COLOR = vec4(clamp(quantised, 0.0, 1.0), colour.a);
}
