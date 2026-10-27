// Tobidasu critters: butterflies, fireflies and falling leaves, all animated
// in the vertex shader from per-instance data (one MultiMesh per kind).
// Instance origin = home point; INSTANCE_CUSTOM = (phase, size, range, speed);
// INSTANCE_COLOR = colour. Everything shrinks to nothing while the map is flat.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, specular_disabled;

// 0 = butterfly, 1 = firefly, 2 = leaf, 3 = bee, 4 = grasshopper, 5 = koi,
// 6 = snowflake, 7 = smoke / steam puff.
uniform int kind = 0;
// 0..1: hidden .. fully there (pop, time of day and the user's switch combined).
uniform float amount : hint_range(0.0, 1.0) = 1.0;
uniform float pixels_per_unit = 16.0;
uniform vec2 wind_direction = vec2(1.0, 0.35);
uniform float wind_strength = 1.0;
uniform float glow_energy = 3.0;
// Smoke clock (seconds, advanced by TobidasuCritters together with the puffs' births).
uniform float smoke_clock = 0.0;

varying vec2 v_uv;
varying vec4 v_col;
varying float v_blink;
varying float v_seed;

// Butterfly wing (6 x 6 pixels, body side on the left): 0 empty, 1 colour, 2 dark edge.
// Rows go from the leading edge back: a big forewing, then a small hindwing.
const int WING[36] = int[](
	2, 2, 2, 2, 2, 0,
	2, 1, 1, 1, 1, 2,
	2, 1, 1, 1, 2, 0,
	2, 1, 1, 2, 0, 0,
	2, 1, 1, 2, 0, 0,
	0, 2, 2, 0, 0, 0);

// Grasshopper (5 x 3 pixels, side view, head on the right): 1 green, 2 dark.
const int HOPPER[15] = int[](
	0, 1, 1, 1, 0,
	1, 1, 1, 1, 2,
	2, 0, 2, 0, 2);

// Koi (7 x 3 pixels, seen from above, head on the right): 1 body colour,
// 2 patch (white on every second fish), 3 fins / tail.
const int KOI[21] = int[](
	3, 0, 1, 1, 2, 1, 0,
	3, 3, 1, 2, 1, 1, 1,
	3, 0, 1, 1, 1, 2, 0);

float hash11(float n) {
	return fract(sin(n * 12.9898 + 4.1414) * 43758.5453);
}

// Grasshopper spot after hop n: somewhere within `range` of its home.
vec2 hop_spot(float n, float seed, float range) {
	return (vec2(hash11(n + seed * 17.0), hash11(n * 1.7 + seed * 31.0 + 5.0)) - 0.5) * 2.0 * range;
}

// Bee (5 x 3 pixels, camera-facing, head on the right): 0 empty, 1 yellow,
// 2 dark stripe / head, 3 wing.
const int BEE[15] = int[](
	0, 3, 3, 0, 0,
	2, 1, 2, 1, 2,
	0, 1, 2, 1, 0);

vec3 butterfly_path(float t, float r) {
	return vec3(sin(t * 0.53) * r + sin(t * 1.31) * 0.35 * r,
		0.4 + 0.2 * sin(t * 1.7) + 0.07 * sin(t * 5.3),
		sin(t * 0.71 + 1.3) * r * 0.8 + cos(t * 1.13) * 0.3 * r);
}

vec3 cam_axis(int i, mat4 model, mat4 inv_view) {
	return normalize((inverse(model) * vec4(inv_view[i].xyz, 0.0)).xyz);
}

void vertex() {
	float phase = INSTANCE_CUSTOM.x * 100.0;
	float size = INSTANCE_CUSTOM.y * amount;
	float range = INSTANCE_CUSTOM.z;
	float speed = INSTANCE_CUSTOM.w;
	v_uv = UV;
	v_col = COLOR;
	v_blink = 1.0;
	v_seed = 0.0;
	vec3 v = VERTEX;
	if (kind == 0) {
		// Wings are the mesh's two quads (x < 0 left, x > 0 right), body along z.
		float t = TIME * speed + phase;
		vec3 p = butterfly_path(t, range);
		vec3 vel = butterfly_path(t + 0.05, range) - p;
		float yaw = atan(vel.x, vel.z);
		float flap = 0.5 + 0.5 * sin(TIME * 17.0 + phase * 3.0);
		float a = mix(0.3, 1.4, flap * flap);
		vec3 w = vec3(sign(v.x) * abs(v.x) * cos(a), abs(v.x) * sin(a), v.z) * size;
		w = vec3(w.x * cos(yaw) + w.z * sin(yaw), w.y, -w.x * sin(yaw) + w.z * cos(yaw));
		VERTEX = p + w + vec3(0.0, 0.04 * flap, 0.0) * amount;
	} else if (kind == 1) {
		// Firefly: a camera-facing square drifting around its home, blinking.
		float t = TIME * 0.45 * speed + phase;
		vec3 p = vec3(sin(t * 0.7) * range + sin(t * 1.9) * 0.25, 0.25 + 0.55 * (0.5 + 0.5 * sin(t * 0.43 + 1.0)),
			cos(t * 0.61) * range + cos(t * 1.7) * 0.25);
		float b = smoothstep(-0.1, 0.9, sin(TIME * (0.9 + 0.5 * speed) + phase * 1.7));
		v_blink = b;
		vec3 r = cam_axis(0, MODEL_MATRIX, INV_VIEW_MATRIX);
		vec3 u = cam_axis(1, MODEL_MATRIX, INV_VIEW_MATRIX);
		VERTEX = p + (r * v.x + u * v.y) * size * (0.6 + 0.4 * b);
	} else if (kind == 4) {
		// Grasshopper: sits, then jumps in a quick arc to a new spot nearby.
		float period = 2.6 / speed;
		float t = TIME / period + INSTANCE_CUSTOM.x * 7.0;
		float n = floor(t);
		float u = fract(t);
		float a = clamp(u / 0.22, 0.0, 1.0);
		vec2 from = hop_spot(n, INSTANCE_CUSTOM.x, range);
		vec2 to = hop_spot(n + 1.0, INSTANCE_CUSTOM.x, range);
		vec2 xz = mix(from, to, smoothstep(0.0, 1.0, a));
		float y = 0.03 + 4.0 * 0.32 * a * (1.0 - a);
		vec3 p = vec3(xz.x, y, xz.y);
		vec3 r = cam_axis(0, MODEL_MATRIX, INV_VIEW_MATRIX);
		vec3 up = cam_axis(1, MODEL_MATRIX, INV_VIEW_MATRIX);
		float face = dot(vec3(to.x - from.x, 0.0, to.y - from.y), r) < 0.0 ? -1.0 : 1.0;
		// Legs stretch out while in the air.
		v_blink = a > 0.0 && a < 1.0 ? 1.0 : 0.0;
		VERTEX = p + (r * v.x * face * 5.0 / 3.0 + up * (v.y + 0.5)) * size;
	} else if (kind == 5) {
		// Koi: a slow loop around its spot (speed sign = direction), lying
		// flat under the water, body along the way it swims, tail wagging.
		float t = TIME * 0.35 * speed + phase;
		vec3 p = vec3(cos(t) * range, 0.0, sin(t) * range * 0.6);
		vec2 dir = normalize(vec2(-sin(t) * range, cos(t) * range * 0.6) * sign(speed) + vec2(1e-5));
		vec2 side = vec2(-dir.y, dir.x);
		float wag = v.x < -0.2 ? sin(TIME * 6.0 + phase) * 0.12 * (-v.x) : 0.0;
		vec2 q = dir * v.x + side * (v.y + wag);
		VERTEX = p + vec3(q.x, 0.0, q.y) * size;
		NORMAL = vec3(0.0, 1.0, 0.0);   // lying flat
	} else if (kind == 6) {
		// Snowflake: falls from `range` (snow height) to the base in a loop,
		// drifting with the wind and swaying a little.
		float u = fract(TIME * 0.45 * speed / max(range, 0.5) + INSTANCE_CUSTOM.x);
		vec2 dir = normalize(wind_direction + vec2(1e-5));
		vec2 side = vec2(-dir.y, dir.x);
		vec2 xz = dir * (u - 0.5) * range * 0.5 * wind_strength + side * sin(TIME * 1.1 * speed + phase) * 0.18;
		vec3 p = vec3(xz.x, range * (1.0 - u), xz.y);
		vec3 r = cam_axis(0, MODEL_MATRIX, INV_VIEW_MATRIX);
		vec3 up = cam_axis(1, MODEL_MATRIX, INV_VIEW_MATRIX);
		// flakes right in front of the lens would be big white squares
		vec3 wp = (MODEL_MATRIX * vec4(p, 1.0)).xyz;
		float near = smoothstep(2.0, 5.0, length(wp - INV_VIEW_MATRIX[3].xyz));
		// lighter snow = fewer flakes (not smaller ones, they would flicker)
		float keep = step(hash11(INSTANCE_CUSTOM.x * 311.0), amount);
		// never bigger than about two screen pixels at 1080p (close flakes)
		float s = min(INSTANCE_CUSTOM.y, length(wp - INV_VIEW_MATRIX[3].xyz) * 0.004);
		VERTEX = p + (r * v.x + up * v.y) * s * keep * near;
	} else if (kind == 7) {
		// Smoke / steam puff: born at its source (the instance origin, set as it
		// is born), it rises, slows, swells and drifts off with the wind.
		float life = max(INSTANCE_CUSTOM.w, 0.1);
		float k = smoke_clock / life + INSTANCE_CUSTOM.x;
		float a = fract(k);
		v_seed = hash11(floor(k) * 7.13 + INSTANCE_CUSTOM.x * 91.0);
		vec2 dir = normalize(wind_direction + vec2(1e-5));
		vec2 side = vec2(-dir.y, dir.x);
		float rise = range * (1.0 - (1.0 - a) * (1.0 - a));
		vec2 xz = dir * wind_strength * 0.45 * life * a * a + side * (v_seed - 0.5) * 0.3 * a;
		vec3 p = vec3(xz.x, rise, xz.y);
		v_blink = a;
		vec3 r = cam_axis(0, MODEL_MATRIX, INV_VIEW_MATRIX);
		vec3 up = cam_axis(1, MODEL_MATRIX, INV_VIEW_MATRIX);
		VERTEX = p + (r * v.x + up * v.y) * INSTANCE_CUSTOM.y * amount * (0.55 + 1.5 * a);
	} else if (kind == 3) {
		// Bee: quick loops around its hive with a nervous buzz on top.
		float t = TIME * 1.6 * speed + phase;
		vec3 p = vec3(sin(t) * range + 0.12 * sin(TIME * 11.0 + phase),
			0.22 + 0.16 * sin(t * 1.7 + 0.5) + 0.04 * sin(TIME * 17.0 + phase * 2.0),
			sin(t * 2.0 + 1.0) * range * 0.6 + 0.12 * cos(TIME * 13.0 + phase));
		v_blink = step(0.0, sin(TIME * 60.0 + phase));   // wings flicker
		vec3 r = cam_axis(0, MODEL_MATRIX, INV_VIEW_MATRIX);
		vec3 u = cam_axis(1, MODEL_MATRIX, INV_VIEW_MATRIX);
		// Face the way it flies (mirror the sprite when moving left on screen).
		float vx = dot(vec3(cos(t) * range, 0.0, cos(t * 2.0 + 1.0) * range * 1.2), r);
		VERTEX = p + (r * v.x * (vx < 0.0 ? -1.0 : 1.0) * 5.0 / 3.0 + u * v.y) * size;
	} else {
		// Leaf: drops from the canopy (home) to the ground (range = fall height),
		// swinging and tumbling, drifting with the wind; then starts over.
		float period = 7.0 / speed;
		float u = fract(TIME / period + INSTANCE_CUSTOM.x);
		vec2 dir = normalize(wind_direction + vec2(1e-5));
		float sw = sin(u * 13.0 + phase) * 0.22;
		vec3 p = vec3(dir.x, 0.0, dir.y) * u * 1.4 * wind_strength + vec3(-dir.y, 0.0, dir.x) * sw;
		p.y = -u * range + 0.03 * cos(u * 13.0 + phase);
		float s = size * smoothstep(0.0, 0.06, u) * (1.0 - smoothstep(0.88, 1.0, u));
		float spin = u * 9.0 + phase;
		vec3 w = vec3(v.x * cos(spin), v.x * sin(spin) * 0.6 + v.z * 0.5, v.z * cos(spin * 0.7)) * s;
		VERTEX = p + w;
	}
}

void fragment() {
	if (kind == 0) {
		// Pixel-art wing: u from the body to the tip, v front to back.
		vec2 q = floor(clamp(v_uv, 0.0, 0.999) * 6.0);
		int c = WING[int(q.y) * 6 + int(q.x)];
		if (c == 0) {
			discard;
		}
		vec3 col = c == 2 ? vec3(0.247, 0.149, 0.192) : v_col.rgb;
		ALBEDO = col;
		EMISSION = col * 0.15;
	} else if (kind == 1) {
		// Bright core pixel with a dimmer rim, well above 1 so it blooms.
		// 3 x 3 pixels around a 1 pixel core: the rim only shows while the light is up.
		vec2 q = abs(v_uv - 0.5);
		float core = step(max(q.x, q.y), 0.1667);
		if (core < 0.5 && v_blink < 0.4) {
			discard;
		}
		ALBEDO = vec3(0.0);
		EMISSION = v_col.rgb * glow_energy * mix(0.25, 1.0, v_blink) * mix(0.3, 1.0, core) * amount;
	} else if (kind == 4) {
		vec2 q = floor(clamp(v_uv, 0.0, 0.999) * vec2(5.0, 3.0));
		int c = HOPPER[int(q.y) * 5 + int(q.x)];
		if (c == 0 && !(v_blink > 0.5 && q.y > 1.5)) {
			discard;
		}
		vec3 col = c == 1 ? vec3(0.5, 0.82, 0.32) : vec3(0.16, 0.26, 0.12);
		ALBEDO = col * 0.5;
		EMISSION = col * 0.45;
	} else if (kind == 5) {
		vec2 q = floor(clamp(v_uv, 0.0, 0.999) * vec2(7.0, 3.0));
		int c = KOI[int(q.y) * 7 + int(q.x)];
		if (c == 0) {
			discard;
		}
		vec3 col = v_col.rgb;
		if (c == 2 && v_col.a < 0.75) {
			col = vec3(0.97, 0.95, 0.9);
		} else if (c == 3) {
			col = mix(v_col.rgb, vec3(1.0), 0.35);
		}
		// Seen through the tinted water: mostly self-lit so the colours stay vivid.
		ALBEDO = col * 0.5;
		EMISSION = col * 0.75;
	} else if (kind == 6) {
		ALBEDO = v_col.rgb * 0.75;
		EMISSION = v_col.rgb * 0.3;
	} else if (kind == 7) {
		// A lumpy pixel disc that thins out into single pixels as it fades.
		vec2 q = floor(clamp(v_uv, 0.0, 0.999) * 8.0);
		vec2 d = q + 0.5 - 4.0;
		float lump = 3.1 + 0.9 * hash11(dot(q, vec2(1.0, 8.0)) + v_seed * 31.0);
		if (length(d) > lump) {
			discard;
		}
		float alpha = v_col.a * (1.0 - smoothstep(0.25, 1.0, v_blink)) * smoothstep(0.0, 0.06, v_blink);
		if (hash11(dot(q, vec2(1.0, 8.0)) * 1.7 + v_seed * 13.0 + 0.5) > alpha) {
			discard;
		}
		float shade = 0.88 + 0.12 * step(d.x + d.y, 0.0);   // lighter on the upper left
		ALBEDO = v_col.rgb * 0.7 * shade;
		EMISSION = v_col.rgb * 0.22 * shade;
	} else if (kind == 3) {
		vec2 q = floor(clamp(v_uv, 0.0, 0.999) * vec2(5.0, 3.0));
		int c = BEE[int(q.y) * 5 + int(q.x)];
		if (c == 0 || (c == 3 && v_blink < 0.5)) {
			discard;
		}
		vec3 col = c == 1 ? vec3(1.0, 0.8, 0.2) : (c == 2 ? vec3(0.2, 0.12, 0.15) : vec3(0.95, 0.97, 1.0));
		// The card faces the camera, not the sun: mostly self-lit so it stays bright.
		ALBEDO = col * 0.5;
		EMISSION = col * 0.6;
	} else {
		ALBEDO = v_col.rgb;
	}
	ROUGHNESS = 1.0;
}
