// Tobidasu water surface: a see-through, pixel-snapped animated sheet that
// fades in as the map pops out (invisible in the flat 2D map).
shader_type spatial;
render_mode cull_back, depth_draw_opaque, blend_mix, specular_schlick_ggx;

#include "res://addons/tobidasu/tobidasu_pop.gdshaderinc"

uniform float shade : hint_range(0.0, 1.0) = 1.0;
uniform vec3 water_color : source_color = vec3(0.36, 0.72, 0.92);
uniform vec3 foam_color : source_color = vec3(0.92, 0.98, 1.0);
uniform float opacity : hint_range(0.0, 1.0) = 0.62;
uniform float pixels_per_unit = 16.0;
uniform float speed = 1.0;
uniform float stable_pixels : hint_range(0.0, 1.0) = 1.0;

varying float v_show;
varying vec3 v_p3;

void vertex() {
	float k = pop_progress(CUSTOM0.w);
	float e = ease_out_back(k);
	VERTEX = mix(VERTEX, CUSTOM0.xyz, e);
	// Gentle bob once fully popped.
	VERTEX.y += 0.012 * sin(TIME * 1.7 * speed + CUSTOM0.x * 1.3 + CUSTOM0.z * 0.9) * smoothstep(0.8, 1.0, pop);
	v_show = smoothstep(0.35, 0.9, k);
	v_p3 = CUSTOM0.xyz;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	// Water pixels smaller than a screen pixel fade to their average (no sparkle noise).
	vec2 wp = v_p3.xz * pixels_per_unit;
	float far = stable_pixels * step(stable_split, SCREEN_UV.x) * smoothstep(0.6, 1.6, max(fwidth(wp.x), fwidth(wp.y)));
	if (v_show <= 0.001) {
		discard;
	}
	vec2 q = floor(v_p3.xz * pixels_per_unit);
	float t = TIME * speed;
	// Slow diagonal ripple bands, snapped to the pixel grid.
	float wave = sin((q.x * 0.35 + q.y * 0.6) * 0.5 - t * 1.6) + 0.6 * sin((q.x * -0.5 + q.y * 0.3) * 0.45 + t * 1.1);
	float ripple = step(1.25, wave);
	// Twinkling glints that hop around every few frames.
	float tick = floor(t * 3.0);
	float ripple_avg = 0.2;
	ripple = mix(ripple, ripple_avg, far);
	float glint = step(0.985, hash12(q + vec2(tick * 7.0, tick * 3.0)));
	glint *= 1.0 - far;
	vec3 col = mix(water_color, foam_color, clamp(ripple * 0.45 + glint, 0.0, 1.0));
	ALBEDO = col * shade;
	EMISSION = col * (1.0 - shade) + foam_color * glint * 0.25;
	ROUGHNESS = 0.18;
	SPECULAR = 0.6;
	ALPHA = v_show * mix(opacity, 1.0, clamp(ripple * 0.3 + glint, 0.0, 1.0));
}
