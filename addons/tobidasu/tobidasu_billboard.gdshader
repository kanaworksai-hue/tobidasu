// Tobidasu sprite card: lies flat exactly where the 2D sprite is drawn, then
// stands up on its feet and turns to face the camera (Y-axis billboard).
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, specular_disabled;

#include "res://addons/tobidasu/tobidasu_pop.gdshaderinc"

uniform sampler2D sprite : source_color, filter_nearest, repeat_disable;
uniform sampler2D sprite_mips : source_color, filter_linear_mipmap, repeat_disable;
uniform float stable_pixels : hint_range(0.0, 1.0) = 1.0;
uniform float shade : hint_range(0.0, 1.0) = 1.0;
// Texture region of the current frame (u0, v0, u1, v1); u0 > u1 flips.
uniform vec4 uv_rect = vec4(0.0, 0.0, 1.0, 1.0);
// Sprite rectangle on the flat map (x, z, width, height) in tiles.
uniform vec4 flat_rect = vec4(0.0, 0.0, 1.0, 1.0);
// Height of the card above the flat map, and of the ground under its feet in 3D.
uniform float flat_y = 0.01;
uniform float ground_y = 0.0;
uniform float delay = 0.5;
// How much the card must always face the camera (sin of the angle), 0 = no limit.
uniform float min_facing : hint_range(0.0, 1.0) = 0.6;

void vertex() {
	float k = pop_progress(delay);
	float e = ease_out_back(k);
	vec3 cam_right = (inverse(MODEL_MATRIX) * vec4(INV_VIEW_MATRIX[0].xyz, 0.0)).xyz;
	cam_right.y = 0.0;
	cam_right = length(cam_right) > 1e-4 ? normalize(cam_right) : vec3(1.0, 0.0, 0.0);
	vec3 right = normalize(mix(vec3(1.0, 0.0, 0.0), cam_right, clamp(e, 0.0, 1.0)) + vec3(1e-5, 0.0, 0.0));
	vec3 back = cross(vec3(0.0, 1.0, 0.0), right);
	vec2 feet = vec2(flat_rect.x + flat_rect.z * 0.5, flat_rect.y + flat_rect.w);
	vec3 base = vec3(feet.x, mix(flat_y, ground_y, clamp(e, 0.0, 1.0)), feet.y);
	// Standing up by angle a while the camera sits at elevation t (seen from the
	// feet), the card faces the camera by sin(a + t): it would turn edge-on if it
	// stood up while the camera still looks straight down. Never lean further
	// than min_facing allows, so the character stays visible the whole way.
	vec3 cam = (inverse(MODEL_MATRIX) * vec4(INV_VIEW_MATRIX[3].xyz, 1.0)).xyz;
	float t = asin(clamp(normalize(cam - base).y, -1.0, 1.0));
	float a = max(min(e * 1.5707963, 3.14159265 - asin(min_facing) - t), 0.0);
	vec3 card_up = vec3(0.0, 1.0, 0.0) * sin(a) + back * cos(a);
	VERTEX = base + right * (UV.x - 0.5) * flat_rect.z + card_up * (1.0 - UV.y) * flat_rect.w;
	NORMAL = normalize(cross(right, card_up));
}

void fragment() {
	vec2 uv = mix(uv_rect.xy, uv_rect.zw, UV);
	vec4 c = texture(sprite, uv);
	vec2 ts = vec2(textureSize(sprite_mips, 0));
	vec4 cs = texel_stable_rect(sprite_mips, uv, min(uv_rect.xy, uv_rect.zw) * ts, max(uv_rect.xy, uv_rect.zw) * ts);
	c = mix(c, cs, stable_amount(stable_pixels, SCREEN_UV.x));
	if (c.a < 0.5) {
		discard;
	}
	ALBEDO = c.rgb * shade;
	EMISSION = c.rgb * (1.0 - shade);
	ROUGHNESS = 1.0;
}
