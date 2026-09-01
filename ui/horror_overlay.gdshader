shader_type canvas_item;

// The game's single post-process pass. It sits on the player's HorrorOverlay
// CanvasLayer at layer 90, under every HUD layer, so it grades the 3D world and
// leaves the interaction prompt, status bars, blink and the door encounter's
// own overlay clean and readable on top of it.
//
// The look is early-2000s survival horror: a cheap digital camera with a dirty
// lens. Chromatic fringing at the edges, an aggressive sharpen rather than any
// kind of bloom, desaturated and contrasty, heavy grain that lives in the
// shadows, and a hard vignette. The flashlight is meant to be the only thing
// that buys clarity - everything this shader does makes the dark worse to look
// at, not better.
//
// `danger_intensity` is the one knob gameplay drives: 0 is the house as it
// normally plays, 1 is a ghost about to reach the player. Every strength below
// is a pair - the calm value and where it lands at full danger.

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;

// --- retro grade ------------------------------------------------------------
uniform float chromatic_aberration : hint_range(0.0, 0.05) = 0.003;
uniform float danger_aberration : hint_range(0.0, 0.05) = 0.025;
uniform float grain_strength : hint_range(0.0, 0.4) = 0.04;
uniform float danger_grain : hint_range(0.0, 0.4) = 0.20;
uniform float sharpen_strength : hint_range(0.0, 2.0) = 0.30;
uniform float danger_sharpen : hint_range(0.0, 2.0) = 0.80;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.20;
uniform float danger_vignette : hint_range(0.0, 1.0) = 0.60;
uniform float contrast : hint_range(0.5, 2.5) = 1.30;
// Contrast pivots here, not at mid-grey. Almost everything in this game sits
// between black and a quarter-lit, so pivoting at 0.5 crushes the whole image
// into the floor and takes the ghost with it.
uniform float contrast_pivot : hint_range(0.02, 0.8) = 0.22;
uniform float saturation : hint_range(0.0, 2.0) = 0.72;
uniform float danger_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float pulse_strength : hint_range(0.0, 0.2) = 0.018;

// --- gameplay signals, all pre-existing and still driven from player.gd ------
uniform float threat_strength : hint_range(0.0, 1.0) = 0.0;
uniform float stun_strength : hint_range(0.0, 1.0) = 0.0;
uniform float toilet_presence : hint_range(0.0, 1.0) = 0.0;
// Local-only signal from player.gd: one means the player's reticle is planted
// on an unobstructed, nearby Hunter. It deliberately does not share
// threat_strength; hearing something behind you should feel different from
// choosing to stare into its face.
uniform float hunter_gaze_strength : hint_range(0.0, 1.0) = 0.0;

float random_noise(vec2 position) {
	return fract(sin(dot(position, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 centered_uv = UV - vec2(0.5);
	centered_uv.x *= 0.72;
	float edge = smoothstep(0.24, 0.58, length(centered_uv));
	float pulse = sin(TIME * 0.72) * 0.5 + 0.5;

	float aberration = mix(chromatic_aberration, danger_aberration, danger_intensity);
	float grain_amount = mix(grain_strength, danger_grain, danger_intensity);
	float sharpen = mix(sharpen_strength, danger_sharpen, danger_intensity);
	float vignette = mix(vignette_strength, danger_vignette, danger_intensity);
	float gaze_frame = floor(TIME * 30.0);
	float gaze_noise = random_noise(vec2(gaze_frame, floor(SCREEN_UV.y * 96.0)));
	float tear_gate = smoothstep(0.78, 0.98, gaze_noise) * hunter_gaze_strength;
	float frame_jitter = (random_noise(vec2(gaze_frame, 19.71)) - 0.5)
		* SCREEN_PIXEL_SIZE.x * 9.0 * hunter_gaze_strength;
	float horizontal_tear = (gaze_noise - 0.5) * 0.035 * tear_gate;
	float vertical_jitter = (random_noise(vec2(gaze_frame, 47.13)) - 0.5)
		* SCREEN_PIXEL_SIZE.y * 4.0 * hunter_gaze_strength;
	vec2 gaze_uv = clamp(
		SCREEN_UV + vec2(horizontal_tear + frame_jitter, vertical_jitter),
		SCREEN_PIXEL_SIZE,
		vec2(1.0) - SCREEN_PIXEL_SIZE
	);

	// Chromatic aberration. Zero at the centre so whatever the player is aiming
	// at stays honest during calm play, opening up towards the corners. Looking
	// at the Hunter adds a full-frame horizontal split, including at the centre,
	// so its silhouette gets the red/cyan doubled edge from the reference look.
	vec2 from_centre = gaze_uv - vec2(0.5);
	vec2 split = from_centre * aberration * length(from_centre) * 2.0;
	vec2 gaze_split = vec2(
		(0.003 + tear_gate * 0.006) * hunter_gaze_strength,
		0.0
	);
	vec3 color;
	color.r = texture(screen_texture, gaze_uv + split + gaze_split).r;
	color.g = texture(screen_texture, gaze_uv).g;
	color.b = texture(screen_texture, gaze_uv - split - gaze_split).b;

	// Unsharp mask off a four-tap box. Cheap, and it reads as an old video
	// sharpening filter rather than an outline.
	vec2 texel = SCREEN_PIXEL_SIZE;
	vec3 neighbours = texture(screen_texture, SCREEN_UV + vec2(texel.x, 0.0)).rgb;
	neighbours += texture(screen_texture, SCREEN_UV - vec2(texel.x, 0.0)).rgb;
	neighbours += texture(screen_texture, SCREEN_UV + vec2(0.0, texel.y)).rgb;
	neighbours += texture(screen_texture, SCREEN_UV - vec2(0.0, texel.y)).rgb;
	color += (color - neighbours * 0.25) * sharpen;
	color = max(color, vec3(0.0));

	// Grade: pull the colour out, push the contrast up, keep the blacks black.
	float luma = dot(color, vec3(0.299, 0.587, 0.114));
	color = mix(vec3(luma), color, saturation);
	color = (color - vec3(contrast_pivot)) * contrast + vec3(contrast_pivot);
	color = max(color, vec3(0.0));

	// Grain, biased into the shadows - looking into the dark is what should
	// look degraded, not the surface the flashlight is on.
	float grain = random_noise(floor(FRAGCOORD.xy) + floor(TIME * 24.0)) - 0.5;
	color += vec3(grain) * grain_amount * mix(1.7, 0.30, smoothstep(0.0, 0.55, luma));

	// Hunter interference: hard monochrome sensor grit, fine scanlines and
	// irregular brightness loss. This remains one screen pass and adds no extra
	// texture, which keeps it cheap enough to flare every time the gaze crosses
	// the creature.
	if (hunter_gaze_strength > 0.001) {
		float static_noise = random_noise(
			floor(FRAGCOORD.xy * 1.7) + vec2(gaze_frame * 13.0, gaze_frame * 7.0)
		) - 0.5;
		float scanline = sin(FRAGCOORD.y * 2.15 + TIME * 24.0) * 0.5 + 0.5;
		float signal_drop = smoothstep(
			0.82,
			0.99,
			random_noise(vec2(gaze_frame * 0.37, floor(SCREEN_UV.y * 32.0)))
		);
		color += vec3(static_noise) * (0.12 + tear_gate * 0.20) * hunter_gaze_strength;
		color *= 1.0 - scanline * 0.11 * hunter_gaze_strength;
		color *= 1.0 - signal_drop * 0.38 * hunter_gaze_strength;
		float gaze_luma = dot(color, vec3(0.299, 0.587, 0.114));
		color = mix(color, mix(vec3(gaze_luma), color, 0.55), hunter_gaze_strength * 0.42);
	}

	// Vignette, plus the two pre-existing darkening signals. A manifested Toilet
	// Ghost narrows the usable view; a live threat breathes at the edges.
	float darkness = edge * (vignette + pulse * pulse_strength);
	darkness += threat_strength * (0.05 + pulse * 0.08);
	darkness += toilet_presence * (0.20 + edge * 0.42 + pulse * 0.06);
	color *= 1.0 - clamp(darkness, 0.0, 0.94);
	color += vec3(0.035, 0.0, 0.0) * threat_strength * pulse;

	// Toilet Ghost concussion. Branching keeps its nine extra taps off every
	// frame that is not actually stunned.
	if (stun_strength > 0.001) {
		float wobble = sin(SCREEN_UV.y * 24.0 + TIME * 8.5) * stun_strength;
		vec2 stunned_uv = SCREEN_UV + vec2(wobble * SCREEN_PIXEL_SIZE.x * 5.0, 0.0);
		vec2 blur_step = SCREEN_PIXEL_SIZE * (2.0 + stun_strength * 5.0);
		vec3 blurred = texture(screen_texture, stunned_uv).rgb * 0.28;
		blurred += texture(screen_texture, stunned_uv + vec2(blur_step.x, 0.0)).rgb * 0.12;
		blurred += texture(screen_texture, stunned_uv - vec2(blur_step.x, 0.0)).rgb * 0.12;
		blurred += texture(screen_texture, stunned_uv + vec2(0.0, blur_step.y)).rgb * 0.12;
		blurred += texture(screen_texture, stunned_uv - vec2(0.0, blur_step.y)).rgb * 0.12;
		blurred += texture(screen_texture, stunned_uv + blur_step).rgb * 0.06;
		blurred += texture(screen_texture, stunned_uv - blur_step).rgb * 0.06;
		blurred += texture(screen_texture, stunned_uv + vec2(blur_step.x, -blur_step.y)).rgb * 0.06;
		blurred += texture(screen_texture, stunned_uv + vec2(-blur_step.x, blur_step.y)).rgb * 0.06;
		float uneven_flicker = sin(TIME * 11.7) * sin(TIME * 17.3) * 0.5 + 0.5;
		float dark_flash = smoothstep(0.62, 0.94, uneven_flicker);
		vec3 stunned_color = blurred * mix(0.62, 0.16, dark_flash);
		stunned_color = mix(stunned_color, vec3(0.018, 0.022, 0.04), 0.18);
		color = mix(color, stunned_color, stun_strength * mix(0.82, 0.97, dark_flash));
	}

	COLOR = vec4(color, 1.0);
}
