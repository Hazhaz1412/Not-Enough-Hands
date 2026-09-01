shader_type canvas_item;
render_mode unshaded;

// Presentation layer of the 3D door encounter. `aperture` controls only how
// much darkness is masked away; the minigame deliberately keeps it at zero in
// every phase so camera freedom does not turn into ambient visibility.
// `pressure` is how close the attacker is to reaching the player, and `flash`
// is the one-frame repel confirmation. Nothing here is gameplay - every
// decision is made in 3D by door_ghost_minigame.gd.
uniform float aperture : hint_range(0.0, 1.0) = 0.0;
uniform float pressure : hint_range(0.0, 1.0) = 0.0;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform float focus_radius : hint_range(0.15, 0.45) = 0.26;
uniform float peripheral_visibility : hint_range(0.0, 0.35) = 0.16;
uniform float viewport_aspect = 1.7777778;

float random_noise(vec2 point) {
	return fract(sin(dot(point, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	// Tight central flashlight window; aperture can widen it for variants.
	vec2 centered = UV - vec2(0.5);
	centered.x *= viewport_aspect;
	float radius = mix(focus_radius, 1.9, aperture * aperture);
	float peephole = smoothstep(radius * 0.72, radius * 1.06, length(centered));

	// Teeth closing in from the screen edges. The nearest edge decides which
	// axis the spikes run along, so all four borders bite inwards.
	float to_left_right = min(UV.x, 1.0 - UV.x);
	float to_top_bottom = min(UV.y, 1.0 - UV.y);
	float edge_distance = min(to_left_right, to_top_bottom);
	float along = to_left_right < to_top_bottom ? UV.y : UV.x;
	float saw = abs(fract(along * 21.0) - 0.5) * 2.0;
	float breath = sin(TIME * (5.0 + pressure * 16.0)) * 0.5 + 0.5;
	float tooth_length = pressure * pressure * (0.10 + breath * 0.045);
	float bite = 1.0 - smoothstep(0.0, tooth_length * saw + 0.002, edge_distance);

	float grain = random_noise(FRAGCOORD.xy + vec2(TIME * 91.0, TIME * 37.0)) - 0.5;
	// Peripheral shapes remain barely readable, while the focus window leaves
	// the real SpotLight3D unobstructed and therefore dramatically brighter.
	float ambient_darkness = 1.0 - peripheral_visibility;
	float darkness = max(peephole * ambient_darkness, bite);
	darkness = clamp(darkness + grain * (0.012 + pressure * 0.05), 0.0, 1.0);

	vec3 tint = mix(vec3(0.0), vec3(0.22, 0.012, 0.012), bite);
	tint = mix(tint, vec3(0.92, 0.95, 1.0), flash);
	COLOR = vec4(tint, max(darkness, flash * 0.85));
}
