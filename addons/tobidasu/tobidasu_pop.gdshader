// Tobidasu pop-up shader: blends every vertex from its flat 2D position
// (VERTEX) to its 3D position (CUSTOM0.xyz) with a staggered, bouncy ease.
shader_type spatial;
render_mode cull_back, depth_draw_opaque, specular_disabled;

#include "res://addons/tobidasu/tobidasu_pop.gdshaderinc"

uniform sampler2D atlas : source_color, filter_nearest, repeat_disable;
// Same atlas with mipmaps (tile-clean box filter) for the stable-pixel filter.
uniform sampler2D atlas_mips : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 atlas_grid = vec4(0.0, 0.0, 16.0, 16.0);
// 0 = plain nearest sampling in 3D (shimmers in the distance), 1 = stable pixels.
uniform float stable_pixels : hint_range(0.0, 1.0) = 1.0;
// 0 = unlit (pixel-exact 2D look), 1 = lit by the scene.
uniform float shade : hint_range(0.0, 1.0) = 1.0;
uniform vec3 soil_color : source_color = vec3(0.45, 0.30, 0.20);
uniform vec3 doorway_color : source_color = vec3(0.12, 0.08, 0.08);
uniform float soil_depth = 0.6;
// Side walls show the outline pixel only as a thin rim, then the colour
// `side_inset` pixels further inside the shape (avoids dark "stalks").
uniform float side_rim = 0.045;
uniform float side_inset = 2.0;
uniform float side_darken = 0.88;
// Cliffs: rock strata tinted by the edge colour.
uniform vec3 rock_color : source_color = vec3(0.70, 0.58, 0.47);
uniform float cliff_rim = 0.1;
// Water beds get darker and bluer with depth once popped.
uniform vec3 deep_color : source_color = vec3(0.12, 0.30, 0.45);
uniform float pixels_per_unit = 16.0;

// --- 3D-only juice (all of it fades out before pop reaches 0) ---------------
// Wind bends trees around their root (CUSTOM2 = pivot + tree height).
uniform float wind_strength : hint_range(0.0, 3.0) = 1.0;
uniform float wind_speed : hint_range(0.0, 4.0) = 1.0;
uniform vec2 wind_direction = vec2(1.0, 0.35);
// Height-field ambient occlusion: mean height around each pixel ((h + 1) / 4).
uniform sampler2D ao_map : hint_default_black, filter_nearest, repeat_disable;
uniform vec2 map_cells = vec2(1.0);
uniform float ao_strength : hint_range(0.0, 1.0) = 0.55;
// Window panes (mask from TobidasuRule.glow_colors) and doorways light up at night.
uniform sampler2D glow_mask : hint_default_black, filter_nearest, repeat_disable;
uniform float night_lights : hint_range(0.0, 1.0) = 0.0;
// Windows light up from the ground to this height (3D units): animate it to
// switch a tall building on storey by storey. Default: everything.
uniform float glow_rise = 1000.0;
// 0..1: lit panes of standing things (TREE: stone lanterns, the pagoda) flicker
// like candles. Building windows stay steady.
uniform float glow_flicker : hint_range(0.0, 1.0) = 0.0;
// Brightness of those lit panes of standing things (1 = like the windows).
uniform float tree_glow = 1.0;
uniform vec3 window_color : source_color = vec3(1.0, 0.74, 0.38);
uniform float window_energy = 2.4;
// Soft cloud shadows drifting with the wind (sun light only).
uniform float cloud_shadows : hint_range(0.0, 1.0) = 0.0;
uniform float cloud_scale = 0.07;
// Brighter top pixel row on side faces (crisp voxel edges).
uniform float edge_highlight : hint_range(0.0, 0.5) = 0.1;
// Lights per map cell (R, 1 = on): window panes and doorways of a cell glow only
// where this is lit (Tobidasu3D.set_lights switches a shop off for the night).
uniform sampler2D light_map : hint_default_white, filter_nearest, repeat_disable;

// --- moving parts (Tobidasu3D.follow: a train car, a cable car) -------------
// >= 0: every vertex uses this start delay (the part pops as one piece).
uniform float delay_override = -1.0;
// World x / z range (min x, min z, max x, max z) outside which the model is cut
// away: a train going into a tunnel, or off the edge of the map.
uniform vec4 clip_rect = vec4(-1e9, -1e9, 1e9, 1e9);
varying vec3 v_world;
// A moving part's place on the followed map (tiles; set by Tobidasu3D): cloud
// shadows, the climbing night lights and the flicker use map positions.
uniform vec3 part_offset = vec3(0.0);

varying float v_h3;
varying float v_fill;
varying float v_side;
varying float v_depth;
varying flat int v_kind;
varying vec3 v_p3;
varying float v_fx;
varying float v_ca;
// Atlas tile of the face (texels), constant over the face: fragment UVs are
// clamped into it. With MSAA, edge samples extrapolate UVs past the face, and a
// transparent texel of the neighbouring atlas tile would then read as a
// doorway (lit at night: dotted seams along building edges).
varying flat vec2 v_tile;

// Bend of a tree (pivot.xyz = root, pivot.w = height) at point p: leans along
// the wind with travelling gusts, sways, and the leaves flutter a little. A
// smooth function of p, so faces that share corners stay glued together.
vec3 wind_offset(vec3 p, vec4 pivot) {
	vec2 dir = normalize(wind_direction + vec2(1e-5));
	vec2 side = vec2(-dir.y, dir.x);
	float t = TIME * wind_speed;
	float h = clamp((p.y - pivot.y) / max(pivot.w, 0.05), 0.0, 1.5);
	float along = dot(pivot.xz, dir);
	float phase = pivot.x * 1.7 + pivot.z * 2.3;
	float gust = 0.5 + 0.5 * sin(along * 0.42 - t * 1.5) * (0.6 + 0.4 * sin(along * 0.13 + pivot.z * 0.21 - t * 0.6));
	float bend = (0.25 + 0.75 * gust) * (0.7 + 0.3 * sin(t * 2.4 + phase));
	float k = wind_strength * 0.07 * pivot.w * h * h;
	vec2 d = dir * k * bend + side * k * 0.25 * sin(t * 1.9 + phase * 1.3);
	vec3 o = vec3(d.x, -0.5 * dot(d, d) / max(pivot.w, 0.05), d.y);
	float fl = wind_strength * 0.006 * h * (0.4 + gust);
	o += fl * vec3(sin(t * 8.0 + p.y * 37.0 + p.x * 11.0), 0.0, sin(t * 7.0 + p.y * 29.0 + p.z * 13.0));
	return o;
}

// Well bucket: 0 = hanging up, 1 = down in the water. Waits, lowers, dips,
// then is hauled back up in a few pulls.
// Seconds, advanced by Tobidasu3D (so game code can sync sounds, see bucket_time()).
uniform float anim_clock = 0.0;
float bucket_drop(float phase) {
	float t = fract(anim_clock / 7.0 + phase) * 7.0;
	float down = smoothstep(1.0, 2.5, t);
	float up = t - 3.3;
	float pulls = clamp((up + 0.25 * sin(up * 6.2832 / 0.8)) / 2.4, 0.0, 1.0);
	return down * (1.0 - smoothstep(0.0, 1.0, pulls));
}

void vertex() {
	float k = pop_progress(delay_override >= 0.0 ? delay_override : CUSTOM0.w);
	float e = ease_out_back(k);
	int kind = int(round(COLOR.b * 8.0));
	if (kind == 4) {
		VERTEX = pop_hinge(VERTEX, CUSTOM0.xyz, e, CUSTOM1.w);
	} else if (kind == 6) {
		VERTEX = pop_lid(VERTEX, CUSTOM0.xyz, e, COLOR.a * 8.0, CUSTOM1.w);
	} else {
		vec3 p3 = CUSTOM0.xyz;
		if (CUSTOM2.w > 0.0) {
			p3 += wind_offset(p3, CUSTOM2) * smoothstep(0.6, 1.0, k);
		} else if (CUSTOM2.w < 0.0 && p3.y < CUSTOM2.y) {
			p3.y -= bucket_drop(CUSTOM2.x) * CUSTOM2.z * smoothstep(0.6, 1.0, k);
		}
		VERTEX = mix(VERTEX, p3, e);
	}
	NORMAL = normalize(mix(vec3(0.0, 1.0, 0.0), CUSTOM1.xyz, clamp(k * 1.5, 0.0, 1.0)));
	v_h3 = CUSTOM0.y;
	v_fill = COLOR.r;
	v_side = COLOR.g;
	v_depth = kind == 6 ? 0.0 : CUSTOM1.w;
	v_kind = kind;
	v_p3 = CUSTOM0.xyz;
	v_fx = smoothstep(0.5, 1.0, pop);
	v_ca = COLOR.a;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 ts_v = vec2(textureSize(atlas, 0));
	v_tile = atlas_grid.xy + floor((UV * ts_v - atlas_grid.xy) / atlas_grid.zw) * atlas_grid.zw;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}

// 1 = sunlit, lower under a cloud (pixel-snapped edges).
float cloud_light(vec3 p) {
	vec2 q = floor(p.xz * pixels_per_unit) / pixels_per_unit;
	vec2 drift = normalize(wind_direction + vec2(1e-5)) * TIME * 0.35 * max(wind_speed, 0.2);
	vec2 u = (q - drift) * cloud_scale;
	float n = vnoise(u) * 0.65 + vnoise(u * 2.3 + 7.1) * 0.35;
	return 1.0 - cloud_shadows * v_fx * smoothstep(0.56, 0.7, n) * 0.4;
}

void fragment() {
	vec2 ts_f = vec2(textureSize(atlas, 0));
	vec2 uv = clamp(UV * ts_f, v_tile + 0.5, v_tile + pixels_per_unit - 0.5) / ts_f;
	vec4 c = texture(atlas, uv);
	vec4 cs = texel_stable(atlas_mips, uv, atlas_grid, pixels_per_unit);
	c = mix(c, cs, stable_amount(stable_pixels, SCREEN_UV.x));
	if (v_world.x < clip_rect.x || v_world.z < clip_rect.y || v_world.x > clip_rect.z || v_world.z > clip_rect.w) {
		discard;
	}
	float door = 0.0;
	if (c.a < 0.5) {
		if (v_fill < 0.5) {
			discard;
		}
		c = vec4(doorway_color, 1.0);
		door = 1.0;
	}
	vec3 col = c.rgb;
	if (v_side > 0.1 && v_depth > side_rim) {
		vec2 px = 1.0 / vec2(textureSize(atlas, 0));
		vec2 dir = v_side < 0.375 ? vec2(1.0, 0.0) : (v_side < 0.625 ? vec2(-1.0, 0.0) : (v_side < 0.875 ? vec2(0.0, 1.0) : vec2(0.0, -1.0)));
		vec4 inner = texture(atlas, uv + dir * px * side_inset);
		vec4 inner1 = texture(atlas, uv + dir * px);
		if (inner.a >= 0.5 && dot(inner.rgb, vec3(0.333)) > dot(c.rgb, vec3(0.333))) {
			col = inner.rgb;
		} else if (inner1.a >= 0.5 && dot(inner1.rgb, vec3(0.333)) > dot(c.rgb, vec3(0.333))) {
			col = inner1.rgb;
		}
		col *= side_darken;
	}
	// The faces are only seen once popped, so the 3D-only looks below use the
	// interpolated 3D position (pixel-snapped so they stay pixel art).
	if ((v_kind == 2 || (v_kind == 3 && v_h3 > 0.0)) && v_depth > cliff_rim) {
		// Cliff: horizontal rock strata in pixel-sized blocks.
		vec3 q = floor(v_p3 * pixels_per_unit + 0.001);
		float along = q.x + q.z;
		float yb = -q.y + floor(hash12(vec2(floor(along / 7.0), 5.0)) * 2.0);
		float band = floor(yb / 3.0);
		float n = hash12(vec2(floor((along + band * 3.0) / 4.0), band));
		vec3 rock = mix(rock_color, col, 0.12) * (0.84 + 0.2 * n);
		rock *= mod(yb, 3.0) < 0.5 ? 0.78 : 1.0;
		col = rock;
	}
	if (v_kind == 1 || v_kind == 3) {
		// Diorama base: below ground level the side walls turn into layered soil.
		float band = step(0.5, fract(-v_h3 * 7.0));
		vec3 soil = soil_color * (0.9 + 0.1 * band) * mix(1.0, 0.7, clamp(-v_h3 / soil_depth, 0.0, 1.0));
		col = mix(col, soil, smoothstep(0.02, 0.06, -v_h3));
	}
	if (v_kind == 8) {
		col = mix(col, deep_color, 0.45 * shade);
	}
	// 3D-only looks: exactly neutral while v_fx = 0 (the flat 2D map).
	vec3 glow = vec3(0.0);
	if (v_fx > 0.0) {
		// Flowers lifted off the ground (bloom mask G): the ground under them
		// takes the nearest non-flower colour of the tile. The heads themselves
		// carry COLOR.a = 0.5 and keep their pixels.
		if (v_ca > 0.75 && v_kind != 6 && texture(glow_mask, uv).g > 0.5) {
			vec2 px = 1.0 / vec2(textureSize(atlas, 0));
			vec3 fill = col;
			for (int r = 1; r <= 3; r++) {
				bool found = false;
				for (int k = 0; k < 4; k++) {
					vec2 d = k == 0 ? vec2(1.0, 0.0) : (k == 1 ? vec2(-1.0, 0.0) : (k == 2 ? vec2(0.0, 1.0) : vec2(0.0, -1.0)));
					vec2 q = uv + d * px * float(r);
					if (texture(glow_mask, q).g < 0.5 && texture(atlas, q).a > 0.5) {
						fill = texture(atlas, q).rgb;
						found = true;
						break;
					}
				}
				if (found) {
					break;
				}
			}
			col = mix(col, fill, v_fx);
		}
		if (v_side > 0.1 && v_depth < 1.0 / pixels_per_unit) {
			col *= 1.0 + edge_highlight * v_fx;
		}
		vec2 auv = (floor(v_p3.xz * pixels_per_unit) + 0.5) / (map_cells * pixels_per_unit);
		float mean_h = texture(ao_map, auv).r * 4.0 - 1.0;
		float occl = clamp((mean_h - v_p3.y) * 1.5, 0.0, 1.0);
		col *= 1.0 - ao_strength * v_fx * occl;
		vec3 pm = v_p3 + part_offset;
		float lit = night_lights * v_fx * clamp((glow_rise - pm.y) * 6.0, 0.0, 1.0);
		lit *= texture(light_map, (floor(v_p3.xz - vec2(0.0, 0.01)) + 0.5) / map_cells).r;   // (a facade sits on its south edge)
		if (glow_flicker > 0.0 && v_kind != 4 && v_kind != 6) {
			float ph = hash12(floor(v_p3.xz)) * 6.2832;   // one phase per tile (a lantern; a moving part keeps its own)
			float f = 0.5 + 0.5 * sin(TIME * 7.3 + ph);
			f = f * 0.6 + 0.4 * (0.5 + 0.5 * sin(TIME * 13.1 + ph * 2.1));
			lit *= 1.0 - glow_flicker * 0.45 * f;
		}
		if (v_kind != 4 && v_kind != 6) {
			lit *= tree_glow;
		}
		float pane = texture(glow_mask, uv).r * lit;
		pane = max(pane, door * lit * 0.55);   // doorway: warm room light
		col = mix(col, window_color, pane * 0.8);
		glow = window_color * window_energy * pane;
	}
	ALBEDO = col * shade;
	EMISSION = col * (1.0 - shade) + glow;
	ROUGHNESS = 1.0;
}

void light() {
	float k = clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION;
	if (LIGHT_IS_DIRECTIONAL && cloud_shadows > 0.0) {
		k *= cloud_light(v_p3 + part_offset);
	}
	DIFFUSE_LIGHT += k * LIGHT_COLOR / PI;
}
