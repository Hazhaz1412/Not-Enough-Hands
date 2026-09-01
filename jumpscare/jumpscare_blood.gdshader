shader_type spatial;
render_mode cull_disabled, diffuse_burley;

// The Midnight Grin body, wearing blood that runs down its face.
//
// This is ghosts/midnight_grin_body.tres with one thing added: streaks that
// grow downward from the hairline as `blood_amount` rises. It is fed to
// GhostVisual through its exported `body_material`, so nothing about the
// gameplay ghosts changes - only the jumpscare's own copy of the body wears it.
//
// The streaks are placed in *model* space, not UV space, because the imported
// atlas layout is not something this effect should depend on. VERTEX here is
// the skinned position in the skeleton's own space, which this import measures
// in centimetres: y runs 0 (soles) to 170 (crown), the head is 142 to 170, and
// +z is the direction the face points. Every default below is in those units
// and every one of them was measured off the GLB by slicing the mesh - so the
// streaks land on the face rather than wherever a guess would put them.

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform float blood_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec3 blood_color : source_color = vec3(0.30, 0.012, 0.016);
// Where the streaks are born and how far down they can reach. The hairline of
// this model sits at 165.5, the chin at 142, so a full-strength streak runs off
// the jaw and onto the throat.
uniform float blood_origin_height = 165.5;
uniform float blood_reach = 42.0;
// Streaks only on the face side (+z) - the back of the skull stays clean.
uniform float face_side_fade_near = -6.0;
uniform float face_side_fade_far = 2.0;
// Roughly eleven rivulets across the 26 cm head.
uniform float streak_width = 2.4;

varying vec3 model_position;

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

void vertex() {
	model_position = VERTEX;
}

void fragment() {
	vec4 albedo = texture(albedo_texture, UV);
	ALBEDO = albedo.rgb;
	METALLIC = 0.0;

	// One rivulet per lane, each with its own start height and length, so they
	// do not read as a comb.
	// The meander is what stops eleven parallel bands reading as a barcode.
	float meander = sin(model_position.y * 0.34) * 0.7;
	float lane = (model_position.x + meander) / max(streak_width, 0.001);
	float lane_id = floor(lane);
	float lane_offset = hash11(lane_id);

	float start = blood_origin_height - lane_offset * 5.0;
	float length_here = blood_reach * blood_amount * (0.45 + 0.9 * hash11(lane_id + 13.0));
	float depth = start - model_position.y;
	float run = step(0.0, depth) * smoothstep(length_here, length_here - 3.5, depth);

	// Each rivulet is its own width and narrows as it runs, which is the
	// difference between blood running down a face and stripes painted on one.
	float taper = (0.55 + 0.85 * hash11(lane_id + 3.0))
		* (1.0 - 0.5 * clamp(depth / max(length_here, 1.0), 0.0, 1.0));
	float band = smoothstep(0.30 * taper, 0.14 * taper, abs(fract(lane) - 0.5));
	// The leading drop is darker and wetter than the trail behind it.
	float tip = smoothstep(length_here - 5.0, length_here - 0.5, depth) * run;

	float front = smoothstep(face_side_fade_near, face_side_fade_far, model_position.z);
	// The hair hangs down the face at the same heights the streaks run, and
	// blood on it reads as red hair rather than as blood. Its albedo is the one
	// thing that tells it apart from the skin, so the streaks are held to the
	// pale parts and the strands stay dark.
	float skin = smoothstep(0.22, 0.55, dot(albedo.rgb, vec3(0.299, 0.587, 0.114)));
	float blood = clamp(band * run * front * skin, 0.0, 1.0);

	// Capped below 1 on purpose: even at its heaviest the blood is a wash over
	// the face rather than a coat of paint hiding it.
	ALBEDO = mix(ALBEDO, blood_color, blood * 0.9);
	ALBEDO = mix(ALBEDO, blood_color * 0.55, tip * 0.6);
	// Only slightly glossier than the skin. Wet-looking blood on a face this
	// brightly lit turns into white specular bands and stops reading as blood
	// at all, which is the opposite of the point.
	ROUGHNESS = mix(0.9, 0.55, blood);
}
