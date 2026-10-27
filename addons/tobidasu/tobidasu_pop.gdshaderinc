// Shared 2D -> 3D pop animation (see TobidasuBuilder for the vertex layout).

// 0 = flat 2D map, 1 = fully popped 3D model.
uniform float pop : hint_range(0.0, 1.0) = 1.0;
// Share of the timeline each piece spends growing (rest is stagger).
uniform float window : hint_range(0.05, 1.0) = 0.35;
uniform float overshoot : hint_range(0.0, 3.0) = 1.6;

float ease_out_back(float k) {
	float c1 = overshoot;
	float c3 = c1 + 1.0;
	float x = k - 1.0;
	return 1.0 + c3 * x * x * x + c1 * x * x;
}

// Linear progress of a piece that starts after `delay` (0..1).
float pop_progress(float delay) {
	return clamp((pop - delay * (1.0 - window)) / window, 0.0, 1.0);
}

// Wall that folds up around a hinge line on the ground (at z = p3.z, height
// `base`). A point `p3.z - p_flat.z` in front of the hinge ends up at height p3.y.
vec3 pop_hinge(vec3 p_flat, vec3 p3, float e, float base) {
	float a = e * 1.5707963;
	float r = mix(p3.z - p_flat.z, p3.y - base, clamp(e, 0.0, 1.0));
	return vec3(mix(p_flat.x, p3.x, e), mix(p_flat.y, base, clamp(e, 0.0, 1.0)) + r * sin(a), p3.z - r * cos(a));
}

// Lid (roof) riding on a folding facade of `rows` flat rows and `wall_h` height:
// linear blend plus the offset that keeps its front edge on the facade top.
vec3 pop_lid(vec3 p_flat, vec3 p3, float e, float rows, float wall_h) {
	float a = e * 1.5707963;
	float r = mix(rows, wall_h, clamp(e, 0.0, 1.0));
	vec3 fix = vec3(0.0, r * sin(a) - e * wall_h, -r * cos(a) + (1.0 - e) * rows);
	return mix(p_flat, p3, e) + fix;
}

// Stable pixels: crisp, non-shimmering texels under a perspective camera.
// Texels stay hard-edged up close with a one-screen-pixel blend at their
// borders (resolution-independent "uv anti-aliasing"), and are averaged from
// tile-clean mip levels when they get smaller than a screen pixel. The
// bilinear footprint is clamped inside the current atlas tile so neighbours in
// the atlas never bleed in. `grid` = atlas margin (xy) and tile step (zw) in
// texels, `tile` = tile size in texels. Call outside of branches (derivatives).
vec4 texel_stable_rect(sampler2D tex_lin, vec2 uv, vec2 lo, vec2 hi) {
	vec2 ts = vec2(textureSize(tex_lin, 0));
	vec2 p = uv * ts;
	vec2 dx = dFdx(p);
	vec2 dy = dFdy(p);
	vec2 dp = max(abs(dx) + abs(dy), vec2(1e-4));
	vec2 seam = floor(p + 0.5);
	vec2 q = seam + clamp((p - seam) / dp, -0.5, 0.5);
	vec2 size = hi - lo;
	float lod = clamp(log2(max(length(dx), length(dy))), 0.0, log2(min(size.x, size.y)));
	vec2 s = min(vec2(exp2(ceil(lod)) * 0.5), size * 0.5);
	q = clamp(q, lo + s, hi - s);
	return textureLod(tex_lin, q / ts, lod);
}

vec4 texel_stable(sampler2D tex_lin, vec2 uv, vec4 grid, float tile) {
	vec2 p = uv * vec2(textureSize(tex_lin, 0));
	vec2 o = grid.xy + floor((p - grid.xy) / grid.zw) * grid.zw;
	return texel_stable_rect(tex_lin, uv, o, o + tile);
}

// Screen x left of which the stable filter is off (before/after comparisons).
uniform float stable_split : hint_range(0.0, 1.0) = 0.0;

// How much of the stable filter to use: none while flat (pixel-exact 2D).
float stable_amount(float strength, float screen_x) {
	return strength * smoothstep(0.0, 0.15, pop) * step(stable_split, screen_x);
}
