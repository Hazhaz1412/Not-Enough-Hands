shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_schlick_ggx;

// One eye, whole. Sclera, iris, pupil and the wet highlight are all one sphere
// resolved from the surface normal in object space, so an eye costs a single
// draw and a single node - which is the only reason the creature can afford to
// wear twenty-six of them.
//
// -Z is the direction the eye is looking, matching the rest of the rig. Point
// the parent pivot and the pupil follows; nothing else has to move.

uniform vec3 sclera_color : source_color = vec3(0.055, 0.048, 0.042);
uniform vec3 iris_color : source_color = vec3(0.52, 0.30, 0.11);
uniform vec3 vein_color : source_color = vec3(0.20, 0.055, 0.040);
// The pupil is not a dark colour, it is an absence, and it has to stay that way
// under the creature's own gaze light.
uniform vec3 pupil_color : source_color = vec3(0.002, 0.002, 0.003);
uniform float iris_size : hint_range(0.05, 1.0) = 0.42;
// Drops toward 0 when it has locked on to something: the pupil snaps to a pin.
uniform float pupil_size : hint_range(0.02, 0.9) = 0.20;
uniform float iris_glow : hint_range(0.0, 6.0) = 1.1;
uniform float wetness : hint_range(0.0, 1.0) = 0.95;
uniform float agitation : hint_range(0.0, 1.0) = 0.0;

varying vec3 object_normal;
varying vec3 object_position;

float hash12(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * vec3(0.1031, 0.11369, 0.13787));
	q += dot(q, q.yzx + 19.19);
	return fract((q.x + q.y) * q.z);
}

void vertex() {
	object_normal = normalize(NORMAL);
	object_position = VERTEX;
}

void fragment() {
	vec3 n = normalize(object_normal);
	// 0 at the pupil, 1 at the back of the eyeball.
	float aim = clamp(-n.z * 0.5 + 0.5, 0.0, 1.0);
	float from_axis = 1.0 - clamp(-n.z, 0.0, 1.0);

	float iris_mask = 1.0 - smoothstep(iris_size * 0.72, iris_size, from_axis);
	float pupil_mask = 1.0 - smoothstep(pupil_size * 0.6, pupil_size, from_axis);

	// Radial fibres, so the iris has structure instead of reading as a decal.
	float angle = atan(n.y, n.x);
	float fibre = hash12(vec2(floor(angle * 9.0), 1.0));
	vec3 iris = mix(iris_color * 0.55, iris_color, fibre);
	iris = mix(iris, iris_color * 1.6, smoothstep(0.55, 1.0, iris_mask));

	// Bloodshot toward the rim, worse the closer it is to charging.
	float veins = smoothstep(0.62, 1.0, from_axis)
		* hash12(vec2(floor(angle * 14.0), 3.0));
	vec3 sclera = mix(sclera_color, vein_color, veins * (0.35 + agitation * 0.65));

	vec3 base = mix(sclera, iris, iris_mask);
	base = mix(base, pupil_color, pupil_mask);
	ALBEDO = base;

	METALLIC = 0.0;
	ROUGHNESS = mix(0.42, 0.04, wetness);
	SPECULAR = mix(0.4, 1.0, wetness);
	AO = 1.0;

	// A cornea bulge over the iris. Cheap, and it is what makes a sphere read
	// as an eye at two metres in the dark.
	vec3 bulged = normalize(n + vec3(0.0, 0.0, -1.0) * iris_mask * 0.55 * wetness);
	NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(bulged, 0.0)).xyz);

	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	// The iris carries its own light. Only the iris - a glowing sclera would
	// make it a lamp, and it has to stay an eye.
	vec3 emit = iris_color * iris_mask * (1.0 - pupil_mask) * iris_glow
		* (0.75 + 0.25 * sin(TIME * (1.6 + 5.0 * agitation) + object_position.x * 30.0));
	emit += vec3(0.6, 0.66, 0.74) * fresnel * 0.16 * wetness;
	EMISSION = emit * aim;
}
