shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.48;
uniform float grain_strength : hint_range(0.0, 0.15) = 0.025;
uniform float pulse_strength : hint_range(0.0, 0.2) = 0.018;
uniform float threat_strength : hint_range(0.0, 1.0) = 0.0;
uniform float stun_strength : hint_range(0.0, 1.0) = 0.0;
uniform float toilet_presence : hint_range(0.0, 1.0) = 0.0;

float random_noise(vec2 position) {
	return fract(sin(dot(position, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 centered_uv = UV - vec2(0.5);
	centered_uv.x *= 0.72;
	float edge = smoothstep(0.24, 0.58, length(centered_uv));
	float pulse = sin(TIME * 0.72) * 0.5 + 0.5;
	float grain = random_noise(floor(UV * vec2(640.0, 360.0)) + floor(TIME * 18.0));
	float darkness = edge * (vignette_strength + pulse * pulse_strength);
	darkness += grain * grain_strength;
	darkness += threat_strength * (0.05 + pulse * 0.08);
	// A manifested Toilet Ghost narrows the player's usable view even before
	// it moves. The real flashlight is dimmed in Player too; this is the
	// peripheral tunnel vision layered over it.
	darkness += toilet_presence * (0.20 + edge * 0.42 + pulse * 0.06);
	vec3 threat_tint = vec3(0.035, 0.0, 0.0) * threat_strength * pulse;

	// Toilet Ghost concussion: warp and blur the already-rendered world, then
	// drive irregular dark pulses at two incommensurate frequencies so the
	// flicker never reads like a clean metronome.
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
	float stunned_brightness = mix(0.62, 0.16, dark_flash);
	vec3 stunned_color = blurred * stunned_brightness;
	stunned_color = mix(stunned_color, vec3(0.018, 0.022, 0.04), 0.18);
	float stun_alpha = stun_strength * mix(0.82, 0.97, dark_flash);

	COLOR = vec4(
		mix(threat_tint, stunned_color, stun_strength),
		max(clamp(darkness, 0.0, 0.88), stun_alpha)
	);
}
