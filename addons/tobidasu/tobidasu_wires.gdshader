// Tobidasu wires: thin camera-facing ribbons along a sagging line.
// VERTEX = point on the wire, CUSTOM0.xyz = its direction, CUSTOM0.w = signed
// half width (tiles). `amount` shrinks them to nothing while the map is flat.
shader_type spatial;
render_mode cull_disabled, specular_disabled;

uniform float amount : hint_range(0.0, 1.0) = 1.0;

varying vec4 v_col;

void vertex() {
	vec3 cam = (inverse(MODEL_MATRIX) * vec4(INV_VIEW_MATRIX[3].xyz, 1.0)).xyz;
	vec3 side = normalize(cross(CUSTOM0.xyz, cam - VERTEX) + vec3(1e-6));
	// at least about one screen pixel wide, so a far wire does not break up
	float d = length(cam - VERTEX);
	float w = max(abs(CUSTOM0.w), d * 0.0011) * sign(CUSTOM0.w);
	VERTEX += side * w * amount;
	v_col = COLOR;
	NORMAL = vec3(0.0, 1.0, 0.0);   // lit like the ground: dark at night
}

void fragment() {
	ALBEDO = v_col.rgb;
	ROUGHNESS = 1.0;
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);   // (either side faces up)
}
