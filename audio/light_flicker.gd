class_name HouseLightFlicker
extends Node3D

## Occasional, localised electrical failures. Only one authored house light is
## disturbed at a time, and the 3D snap follows that exact bulb so the player
## can hear which room just went dark.

enum FlickerState {
	WAITING,
	OFF,
	ON,
}

@export_category("Schedule")
@export var initial_delay_min: float = 7.0
@export var initial_delay_max: float = 15.0
@export var event_delay_min: float = 14.0
@export var event_delay_max: float = 32.0
@export_range(1, 8, 1) var pulse_count_min: int = 2
@export_range(1, 8, 1) var pulse_count_max: int = 5

@export_category("Flicker rhythm")
@export var off_duration_min: float = 0.035
@export var off_duration_max: float = 0.13
@export var on_duration_min: float = 0.045
@export var on_duration_max: float = 0.19
@export_range(0.0, 0.15, 0.005) var off_energy_ratio_max: float = 0.025

@export_category("Player focus")
## Prefer a light near the player so an uncommon event is actually seen/heard.
## If none is in range, the closest house light is used.
@export var preferred_player_radius: float = 11.0

var state: FlickerState = FlickerState.WAITING
var state_time: float = 0.0
var _lights: Array[Light3D] = []
var _base_energy: Dictionary = {}
var _active_light: Light3D
var _active_base_energy: float = 0.0
var _pulses_remaining: int = 0
var _last_light: Light3D
var _audio_players: Array[AudioStreamPlayer3D] = []
var _audio_index: int = 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	if Engine.is_editor_hint():
		set_process(false)
		return
	_create_audio_players()
	# House2 builds its generated lights in the parent's _ready(), after this
	# child has entered the tree. Deferred collection sees the completed house.
	_initialize.call_deferred()


func _exit_tree() -> void:
	_restore_all_lights()


func _initialize() -> void:
	_collect_lights()
	_schedule_next(true)


func _process(delta: float) -> void:
	if _lights.is_empty():
		return
	state_time -= delta
	if state_time > 0.0:
		return

	match state:
		FlickerState.WAITING:
			_begin_random_flicker()
		FlickerState.OFF:
			_turn_active_light_on()
		FlickerState.ON:
			if _pulses_remaining > 0:
				_pulses_remaining -= 1
				_turn_active_light_off()
			else:
				_finish_flicker()


func _collect_lights() -> void:
	_lights.clear()
	_base_energy.clear()
	var house := get_parent()
	for node: Node in get_tree().get_nodes_in_group("flickering_house_lights"):
		var light := node as Light3D
		if not light or not house.is_ancestor_of(light):
			continue
		_lights.append(light)
		_base_energy[light] = light.light_energy


func _begin_random_flicker() -> void:
	var light := _choose_light_near_player()
	if not light:
		_schedule_next(false)
		return
	var low := mini(pulse_count_min, pulse_count_max)
	var high := maxi(pulse_count_min, pulse_count_max)
	_start_flicker(light, _rng.randi_range(low, high))


func _choose_light_near_player() -> Light3D:
	var valid_lights: Array[Light3D] = []
	for light: Light3D in _lights:
		if is_instance_valid(light) and light.visible:
			valid_lights.append(light)
	if valid_lights.is_empty():
		return null

	var player := get_tree().get_first_node_in_group("players") as Node3D
	var candidates: Array[Light3D] = []
	var closest_light: Light3D
	var closest_distance := INF
	if player:
		for light: Light3D in valid_lights:
			var distance := light.global_position.distance_to(player.global_position)
			if distance <= preferred_player_radius:
				candidates.append(light)
			if distance < closest_distance:
				closest_distance = distance
				closest_light = light
	if candidates.is_empty():
		if closest_light:
			candidates.append(closest_light)
		else:
			candidates = valid_lights

	var selected := candidates[_rng.randi_range(0, candidates.size() - 1)]
	if candidates.size() > 1 and selected == _last_light:
		var current_index := candidates.find(selected)
		selected = candidates[(current_index + _rng.randi_range(1, candidates.size() - 1)) % candidates.size()]
	return selected


func _start_flicker(light: Light3D, pulse_count: int) -> bool:
	if not is_instance_valid(light):
		return false
	if state != FlickerState.WAITING:
		_finish_flicker()

	_active_light = light
	_active_base_energy = float(_base_energy.get(light, light.light_energy))
	_pulses_remaining = maxi(pulse_count - 1, 0)
	_last_light = light
	_turn_active_light_off()
	return true


func _turn_active_light_off() -> void:
	if not is_instance_valid(_active_light):
		_finish_flicker()
		return
	state = FlickerState.OFF
	_active_light.light_energy = _active_base_energy * _rng.randf_range(
		0.0,
		off_energy_ratio_max
	)
	state_time = _random_range(off_duration_min, off_duration_max)
	_play_electric_snap(false)


func _turn_active_light_on() -> void:
	if not is_instance_valid(_active_light):
		_finish_flicker()
		return
	state = FlickerState.ON
	# Intermediate recoveries are slightly unstable; the final state is restored
	# to the exact authored energy in _finish_flicker().
	_active_light.light_energy = _active_base_energy * _rng.randf_range(0.86, 1.08)
	state_time = _random_range(on_duration_min, on_duration_max)
	_play_electric_snap(true)


func _finish_flicker() -> void:
	if is_instance_valid(_active_light):
		_active_light.light_energy = _active_base_energy
	_active_light = null
	_active_base_energy = 0.0
	_pulses_remaining = 0
	_schedule_next(false)


func _schedule_next(initial: bool) -> void:
	state = FlickerState.WAITING
	state_time = (
		_random_range(initial_delay_min, initial_delay_max)
		if initial
		else _random_range(event_delay_min, event_delay_max)
	)


func _random_range(minimum: float, maximum: float) -> float:
	var low := minf(minimum, maximum)
	var high := maxf(minimum, maximum)
	return _rng.randf_range(maxf(low, 0.01), maxf(high, 0.01))


func _create_audio_players() -> void:
	var stream := _create_electric_snap_stream()
	for index: int in 2:
		var audio := AudioStreamPlayer3D.new()
		audio.name = "ElectricSnap%d" % (index + 1)
		audio.stream = stream
		audio.volume_db = -7.0
		audio.unit_size = 2.5
		audio.max_distance = 18.0
		audio.panning_strength = 1.35
		add_child(audio)
		_audio_players.append(audio)


func _play_electric_snap(turning_on: bool) -> void:
	if not is_instance_valid(_active_light) or _audio_players.is_empty():
		return
	var audio := _audio_players[_audio_index]
	_audio_index = (_audio_index + 1) % _audio_players.size()
	audio.global_position = _active_light.global_position
	audio.pitch_scale = _rng.randf_range(0.91, 1.12) * (1.04 if turning_on else 0.96)
	audio.volume_db = _rng.randf_range(-9.0, -5.5) - (1.5 if turning_on else 0.0)
	audio.play()


## Short mechanical click plus decaying mains buzz/crackle. Generated once and
## reused by the two positional players, so no external audio asset is needed.
func _create_electric_snap_stream() -> AudioStreamWAV:
	const SAMPLE_RATE := 22050
	const DURATION := 0.13
	var sample_count := int(SAMPLE_RATE * DURATION)
	var audio_data := PackedByteArray()
	audio_data.resize(sample_count * 2)

	for sample_index: int in sample_count:
		var time := float(sample_index) / SAMPLE_RATE
		var click_envelope := exp(-time * 95.0)
		var buzz_envelope := exp(-time * 24.0)
		var mechanical_click := _rng.randf_range(-1.0, 1.0) * click_envelope
		var mains_buzz := (
			sin(TAU * 120.0 * time) * 0.24
			+ sin(TAU * 2140.0 * time) * 0.08
		) * buzz_envelope
		var crackle_gate := 1.0 if _rng.randf() > 0.91 else 0.0
		var crackle := _rng.randf_range(-0.32, 0.32) * crackle_gate * buzz_envelope
		var sample := clampf(mechanical_click * 0.7 + mains_buzz + crackle, -1.0, 1.0)
		audio_data.encode_s16(sample_index * 2, int(sample * 32767.0))

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = audio_data
	return stream


func _restore_all_lights() -> void:
	for light: Light3D in _lights:
		if is_instance_valid(light) and _base_energy.has(light):
			light.light_energy = float(_base_energy[light])


## Deterministic hooks for the headless presentation test.
func set_random_seed(value: int) -> void:
	_rng.seed = value


func debug_start_flicker(light: Light3D, pulse_count: int = 2) -> bool:
	return _start_flicker(light, pulse_count)


func get_light_count() -> int:
	return _lights.size()


func get_active_light() -> Light3D:
	return _active_light


func is_flickering() -> bool:
	return state != FlickerState.WAITING
