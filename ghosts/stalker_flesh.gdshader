shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Procedural wet chitin / exposed bone for the Abyssal Stalker.
//
// Same world-space, texture-free approach as statue_stone.gdshader and
// crawler_flesh.gdshader, so all the ghosts stay in one art language. The
// huntsman used to be *worn* - tanned hide and coat wax, the one dressed thing
// in the house. It is not dressed any more. What replaced it is the opposite
// reading: nothing on it was ever made, every surface is the creature itself,
// and all of it is soaking.
//
// Two variants come out of this one shader:
//   bone_amount = 0.0  the body. Black, slick, dripping, faint copper sheen.
//   bone_amount = 1.0  spines, claws, ribs, skull. Drier, paler, harder edges.
// Keeping them on one shader means the flare-up when it charges reaches the
// whole silhouette at once instead of only the soft parts.

uniform vec3 flesh_color : source_color = vec3(0.038, 0.030, 0.026);
// Ridges and raised plate edges, where the copper key light in the concept art
// actually lands.
uniform vec3 ridge_color : source_color = vec3(0.150, 0.092, 0.055);
// Between the plates. Not dark grey - functionally a hole.
uniform vec3 deep_color : source_color = vec3(0.006, 0.005, 0.006);
// The dry bone variant: old ivory gone brown at the roots.
uniform vec3 bone_color : source_color = vec3(0.215, 0.172, 0.128);
// Slick that runs off it constantly. Tinted, never neutral.
uniform vec3 slime_color : source_color = vec3(0.055, 0.042, 0.030);
// What it glows with from inside when it commits.
uniform vec3 heat_color : source_color = vec3(0.42, 0.075, 0.045);
// The gaze light is part of its own head, so the body is always catching a
// little of its own glow. Cold, unlike the lantern this creature replaced.
uniform vec3 gaze_tint : source_color = vec3(0.55, 0.62, 0.72);

uniform float noise_scale : hint_range(0.5, 24.0) = 7.0;
// Segmented plate banding, sampled mostly along the body's own length.
uniform float plate_scale : hint_range(1.0, 90.0) = 26.0;
uniform float wetness : hint_range(0.0, 1.0) = 0.86;
uniform float drip_amount : hint_range(0.0, 1.0) = 0.7;
// Speed the slick crawls downward. Slow: it is viscous, not water.
uniform float drip_speed : hint_range(0.0, 2.0) = 0.28;
uniform float bone_amount : hint_range(0.0, 1.0) = 0.0;
uniform float bump_strength : hint_range(0.0, 3.0) = 1.25;
uniform float rim_power : hint_range(0.5, 8.0) = 2.6;
uniform float rim_strength : hint_range(0.0, 4.0) = 0.62;
// Driven from hunter_ghost.gd through stalker_rig.gd: 0.0 = quartering the
// house, 1.0 = charging.
uniform float agitation : hint_range(0.0, 1.0) = 0.0;
// How hard the crown is burning right now.
uniform float gaze_glow : hint_range(0.0, 2.0) = 0.55;

varying vec3 world_position;
varying vec3 world_normal;
varying vec3 local_position;

float hash13(vec3 p) {
	p = fract(p * vec3(0.1031, 0.11369, 0.13787));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

float value_noise(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(cell);
	float n100 = hash13(cell + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(cell + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(cell + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(cell + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(cell + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(cell + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(cell + vec3(1.0, 1.0, 1.0));
	return mix(
		mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y),
		f.z);
}

// Two octaves, not four. Every octave is eight hashed corners, and this shader
// runs on ~300 parts of a creature that fills a lot of screen when it is on top
// of you - the four-octave version cost about a hundred and fifty hashes per
// fragment and was the single most expensive thing in the frame. Two octaves
// look near-identical at the distances anyone ever sees this from.
float fbm(vec3 p) {
	return value_noise(p) * 0.64 + value_noise(p * 2.03 + vec3(5.7, 13.1, 9.3)) * 0.3;
}

// Hard-edged carapace banding. Sampled in *local* space so the rings follow
// each limb down its own length instead of slicing the creature into world
// slabs - the tail has to read as vertebrae no matter which way it is whipping.
float plate_field(vec3 local_p) {
	// One octave is plenty to break up a sine wave.
	float band = sin(local_p.y * plate_scale + value_noise(local_p * 3.0) * 2.2);
	float ridge = 1.0 - abs(band);
	return pow(clamp(ridge, 0.0, 1.0), 3.5);
}

// Viscous slick crawling downward in world space, so a limb that lifts still
// drains toward the floor.
float drip_field(vec3 p) {
	vec3 flow = vec3(p.x * 9.0, p.y * 1.35 - TIME * drip_speed, p.z * 9.0);
	float streak = fbm(flow);
	return smoothstep(0.46, 0.82, streak) * drip_amount;
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	local_position = VERTEX;
}

void fragment() {
	vec3 surface_normal = normalize(world_normal);
	vec3 sample_position = world_position * noise_scale;

	float grain = fbm(sample_position);
	float plates = plate_field(local_position);
	float slick = drip_field(world_position);
	// Pooling: the underside of everything stays wetter than the top.
	float underside = clamp(-surface_normal.y * 0.5 + 0.5, 0.0, 1.0);
	slick = clamp(slick + underside * 0.28 * drip_amount, 0.0, 1.0);

	vec3 base = mix(deep_color, flesh_color, smoothstep(0.28, 0.70, grain));
	base = mix(base, ridge_color, plates * 0.34);
	// The dry variant keeps the plate ridges but loses the black.
	vec3 dry = mix(bone_color * 0.40, bone_color, smoothstep(0.35, 0.85, grain));
	dry = mix(dry, bone_color * 1.22, plates * 0.30);
	dry = mix(dry, deep_color, smoothstep(0.46, 0.04, grain) * 0.82);
	base = mix(base, dry, bone_amount);
	// Slick darkens what it runs over rather than lightening it - it is the
	// specular that sells the wet, never the albedo.
	base = mix(base, slime_color * 0.35, slick * (0.72 - bone_amount * 0.30));
	ALBEDO = base;

	METALLIC = 0.0;
	float wet = clamp(wetness * (0.35 + slick * 0.9) * (1.0 - bone_amount * 0.55), 0.0, 1.0);
	ROUGHNESS = mix(mix(0.86, 0.68, bone_amount), 0.14, wet);
	SPECULAR = mix(0.24, 0.80, wet);
	AO = clamp(1.0 - (1.0 - plates) * 0.22 - (1.0 - grain) * 0.24, 0.0, 1.0);
	AO_LIGHT_AFFECT = 0.75;

	// The bump gradient is taken at a single octave - four noise lookups where it
	// used to take eight. It needs its own centre sample rather than reusing
	// `grain`: mixing a one-octave neighbour against a two-octave centre leaves a
	// constant bias in the difference, which tilts every normal on the body.
	float eps = 0.6;
	float height = value_noise(sample_position);
	vec3 gradient = vec3(
		value_noise(sample_position + vec3(eps, 0.0, 0.0)) - height,
		value_noise(sample_position + vec3(0.0, eps, 0.0)) - height,
		value_noise(sample_position + vec3(0.0, 0.0, eps)) - height) / eps;
	gradient -= surface_normal * dot(gradient, surface_normal);
	// Plates stand proud, the seams between them cut in.
	vec3 bumped = normalize(surface_normal
		- (gradient - surface_normal * plates * 0.5) * bump_strength);
	NORMAL = normalize((VIEW_MATRIX * vec4(bumped, 0.0)).xyz);

	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), rim_power);

	// The concept art is lit almost entirely by a cold key raking one edge. In
	// a black corridor that edge is the only thing the player gets: not a shape,
	// a wet outline moving.
	vec3 sheen = mix(ridge_color, gaze_tint, 0.55) * fresnel * rim_strength
		* (0.10 + wet * 0.38);
	vec3 bounce = gaze_tint * gaze_glow * (0.025 + fresnel * 0.14)
		* (0.86 + 0.14 * sin(TIME * 2.1));
	// Something under the plates lights up a beat before it moves.
	float pulse = 0.5 + 0.5 * sin(TIME * (2.2 + 7.0 * agitation) + world_position.y * 3.1);
	vec3 heat = heat_color * agitation * (1.0 - plates) * (0.25 + 0.75 * pulse) * 0.30;

	EMISSION = sheen + bounce + heat;
}
