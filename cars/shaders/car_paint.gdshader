// Car paint with a layer of dirt and dust that climbs up from the sills as
// the car drives on loose ground (dirt_amount 0..1, set by CarModel).
// Works in the mesh's own space: y is height above the car's floor.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 paint_color : source_color = vec3(1.0);
uniform float paint_roughness = 0.6;
uniform vec3 dirt_color : source_color = vec3(0.45, 0.36, 0.26);
uniform float dirt_amount = 0.0;
// Dirt line height (local y) with no dirt and with full dirt.
uniform vec2 dirt_height = vec2(0.18, 0.75);
// Even a clean car has a little grime along the bottom.
uniform float base_dirt = 0.35;
uniform sampler2D dirt_noise : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float noise_scale = 1.6;

varying vec3 local_position;

void vertex() {
	local_position = VERTEX;
}

void fragment() {
	float noise = texture(dirt_noise, local_position.zy * noise_scale + local_position.x * 0.37).r;
	float line = mix(dirt_height.x, dirt_height.y, dirt_amount) + (noise - 0.5) * 0.18;
	float mask = 1.0 - smoothstep(line - 0.12, line + 0.05, local_position.y);
	mask *= mix(base_dirt, 0.9, dirt_amount) * (0.65 + 0.7 * noise);
	// A faint dusting over the whole body as the car gets really dirty.
	mask = max(mask, dirt_amount * 0.18 * noise);
	ALBEDO = mix(paint_color, dirt_color, clamp(mask, 0.0, 1.0));
	ROUGHNESS = mix(paint_roughness, 0.95, clamp(mask, 0.0, 1.0));
}
