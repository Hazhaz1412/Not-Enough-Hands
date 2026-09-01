class_name FuseboxMinigame
extends CanvasLayer

## Blackout repair minigame: seat every fuse by pressing "interact" the
## instant a sweeping needle crosses a randomised safe band. One input, so a
## panicking player can still act - the rest of the tension comes from the
## band narrowing and the needle speeding up each fuse, and from a nerve
## meter that drains on its own and takes a hit on every miss. Unlike the
## door minigame this deliberately does NOT suspend ghost attacks: a miss is
## loud enough to be heard, and standing at an open panel is the risk the
## mechanic is built around.

signal minigame_started(fusebox: Node)
signal minigame_completed(fusebox: Node)
signal minigame_failed(fusebox: Node)
signal minigame_closed()

enum Phase {
	INACTIVE,
	PLAYING,
	SUCCESS,
	FAIL,
}

@export_category("Rules")
## One entry per fuse. Array length is the fuse count.
@export var band_widths_deg: Array[float] = [26.0, 18.0, 12.0]
@export var needle_speeds_deg: Array[float] = [95.0, 120.0, 150.0]
@export var needle_span_deg: float = 88.0
@export var starting_nerve: float = 100.0
@export var shock_nerve_cost: float = 13.0
@export var nerve_drain_per_second: float = 2.6
@export_range(0.0, 1.0) var shock_noise_loudness: float = 0.85

@export_category("Presentation")
@export var success_duration: float = 0.9
@export var fail_duration: float = 1.1

const SLOT_COLOR_EMPTY := Color(0.1, 0.09, 0.13, 0.9)
const SLOT_COLOR_SET := Color(0.33, 0.5, 0.3, 0.95)

var active: bool = false
var phase: Phase = Phase.INACTIVE
var fuse_index: int = 0
var nerve: float = 100.0
var shocks: int = 0
var angle: float = 0.0
var direction: float = 1.0
var speed: float = 0.0
var band_lo: float = -10.0
var band_hi: float = 10.0
var phase_timer: float = 0.0
var current_fusebox: Node
var owning_player: Node

var _rng := RandomNumberGenerator.new()
var _slot_nodes: Array[ColorRect] = []

@onready var root: Control = $Root
@onready var black_background: ColorRect = $Root/BlackBackground
@onready var shock_flash: ColorRect = $Root/ShockFlash
@onready var nerve_label: Label = $Root/CenterPanel/Panel/Margin/Content/NerveLabel
@onready var nerve_bar: ProgressBar = $Root/CenterPanel/Panel/Margin/Content/NerveBar
@onready var gauge: FuseboxGauge = $Root/CenterPanel/Panel/Margin/Content/Gauge
@onready var slots_row: HBoxContainer = $Root/CenterPanel/Panel/Margin/Content/SlotsRow
@onready var status_label: RichTextLabel = $Root/CenterPanel/Panel/Margin/Content/Status
@onready var shock_audio: AudioStreamPlayer = $ShockAudio
@onready var success_audio: AudioStreamPlayer = $SuccessAudio


func _ready() -> void:
	_rng.randomize()
	visible = false
	_build_fuse_slots()
	if not shock_audio.stream:
		shock_audio.stream = _create_shock_stream()
	if not success_audio.stream:
		success_audio.stream = _create_success_stream()


func _exit_tree() -> void:
	if active:
		cancel()


func start(player: Node, fusebox: Node) -> bool:
	if active or not is_instance_valid(fusebox):
		return false
	if not fusebox.has_method("begin_repair") or not bool(fusebox.call("begin_repair")):
		return false

	active = true
	phase = Phase.PLAYING
	owning_player = player
	current_fusebox = fusebox
	fuse_index = 0
	nerve = starting_nerve
	shocks = 0
	angle = -needle_span_deg
	direction = 1.0
	speed = needle_speeds_deg[0]
	root.position = Vector2.ZERO
	shock_flash.color.a = 0.0
	visible = true
	_pick_band()
	_reset_slots()
	_update_nerve_bar()
	_set_status(
		"%d cầu chì cần lắp. Chờ kim vào vùng xanh." % band_widths_deg.size(),
		false
	)
	minigame_started.emit(fusebox)
	return true


func cancel() -> void:
	if not active:
		return
	if is_instance_valid(current_fusebox) and current_fusebox.has_method("cancel_repair"):
		current_fusebox.call("cancel_repair")
	_close()


func is_running() -> bool:
	return active


func set_random_seed(value: int) -> void:
	_rng.seed = value


func _input(event: InputEvent) -> void:
	if not active:
		return
	if phase == Phase.PLAYING and event.is_action_pressed("interact") and not event.is_echo():
		_attempt()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton or event is InputEventKey:
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not active:
		return
	if is_instance_valid(owning_player) \
		and "is_alive" in owning_player \
		and not bool(owning_player.get("is_alive")):
		cancel()
		return
	if not is_instance_valid(current_fusebox):
		cancel()
		return

	gauge.needle_angle_deg = angle
	gauge.band_lo_deg = band_lo
	gauge.band_hi_deg = band_hi
	gauge.span_deg = needle_span_deg
	gauge.queue_redraw()

	match phase:
		Phase.PLAYING:
			_update_playing(delta)
		Phase.SUCCESS, Phase.FAIL:
			phase_timer -= delta
			if phase_timer <= 0.0:
				_close()


func _update_playing(delta: float) -> void:
	angle += direction * speed * delta
	if angle >= needle_span_deg:
		angle = needle_span_deg
		direction = -1.0
	elif angle <= -needle_span_deg:
		angle = -needle_span_deg
		direction = 1.0

	nerve = maxf(nerve - nerve_drain_per_second * delta, 0.0)
	_update_nerve_bar()
	if nerve <= 0.0:
		_begin_fail()


func _attempt() -> void:
	if angle >= band_lo and angle <= band_hi:
		_seat_fuse()
	else:
		_shock()


func _seat_fuse() -> void:
	_set_slot_seated(fuse_index, true)
	fuse_index += 1
	if fuse_index >= band_widths_deg.size():
		_begin_success()
		return
	speed = needle_speeds_deg[fuse_index]
	_pick_band()
	_set_status(
		"Đã lắp! Cầu chì %d/%d — vùng an toàn hẹp hơn." % [fuse_index + 1, band_widths_deg.size()],
		false
	)


func _shock() -> void:
	shocks += 1
	nerve = maxf(nerve - shock_nerve_cost, 0.0)
	_update_nerve_bar()
	_pick_band()
	_play_shock_feedback()
	_report_noise()
	_set_status("Giật điện! Tiếng động đó không hề nhỏ.", true)
	if nerve <= 0.0:
		_begin_fail()


func _begin_success() -> void:
	phase = Phase.SUCCESS
	phase_timer = success_duration
	if is_instance_valid(current_fusebox) and current_fusebox.has_method("complete_repair"):
		current_fusebox.call("complete_repair")
	success_audio.play()
	_set_status("Điện đã khôi phục.", false)
	minigame_completed.emit(current_fusebox)


func _begin_fail() -> void:
	phase = Phase.FAIL
	phase_timer = fail_duration
	if is_instance_valid(current_fusebox) and current_fusebox.has_method("apply_repair_failure"):
		current_fusebox.call("apply_repair_failure")
	_play_shock_feedback()
	_set_status("Thần kinh không trụ nổi. Cầu chì vẫn hỏng.", true)
	minigame_failed.emit(current_fusebox)


func _close() -> void:
	active = false
	phase = Phase.INACTIVE
	visible = false
	current_fusebox = null
	owning_player = null
	minigame_closed.emit()


func _pick_band() -> void:
	var width: float = band_widths_deg[fuse_index]
	var half := width * 0.5
	var centre := (_rng.randf() * 2.0 - 1.0) * (needle_span_deg - half - 10.0)
	band_lo = centre - half
	band_hi = centre + half


func _report_noise() -> void:
	if not is_instance_valid(current_fusebox) or not (current_fusebox is Node3D):
		return
	get_tree().call_group(
		"crawler_ghosts",
		"report_noise",
		(current_fusebox as Node3D).global_position,
		shock_noise_loudness,
		current_fusebox
	)


func _update_nerve_bar() -> void:
	if nerve_bar:
		nerve_bar.value = nerve
	if nerve_label:
		nerve_label.text = "THẦN KINH: %d" % int(round(nerve))


func _set_status(text: String, bad: bool) -> void:
	if not status_label:
		return
	var color := "#e6a79c" if bad else "#c8d6cf"
	status_label.text = "[center][color=%s]%s[/color][/center]" % [color, text]


func _build_fuse_slots() -> void:
	for child: Node in slots_row.get_children():
		child.queue_free()
	_slot_nodes.clear()
	for _index: int in band_widths_deg.size():
		var slot := ColorRect.new()
		slot.custom_minimum_size = Vector2(30.0, 40.0)
		slot.color = SLOT_COLOR_EMPTY
		slots_row.add_child(slot)
		_slot_nodes.append(slot)


func _reset_slots() -> void:
	if _slot_nodes.size() != band_widths_deg.size():
		_build_fuse_slots()
	for slot: ColorRect in _slot_nodes:
		slot.color = SLOT_COLOR_EMPTY


func _set_slot_seated(index: int, seated: bool) -> void:
	if index >= 0 and index < _slot_nodes.size():
		_slot_nodes[index].color = SLOT_COLOR_SET if seated else SLOT_COLOR_EMPTY


func _play_shock_feedback() -> void:
	shock_audio.pitch_scale = _rng.randf_range(0.9, 1.15)
	shock_audio.play()

	shock_flash.color.a = 0.0
	var flash_tween := create_tween()
	flash_tween.tween_property(shock_flash, "color:a", 0.85, 0.02)
	flash_tween.tween_property(shock_flash, "color:a", 0.0, 0.3)

	var shake_tween := create_tween()
	for _index: int in 4:
		shake_tween.tween_property(
			root, "position",
			Vector2(_rng.randf_range(-7.0, 7.0), _rng.randf_range(-4.0, 4.0)),
			0.03
		)
	shake_tween.tween_property(root, "position", Vector2.ZERO, 0.03)


## Short crack-and-zap burst. Generated once and reused, same reasoning as
## the house light flicker's electric snap: no external audio asset needed.
func _create_shock_stream() -> AudioStreamWAV:
	const SAMPLE_RATE := 22050
	const DURATION := 0.22
	var sample_count := int(SAMPLE_RATE * DURATION)
	var audio_data := PackedByteArray()
	audio_data.resize(sample_count * 2)

	for sample_index: int in sample_count:
		var time := float(sample_index) / SAMPLE_RATE
		var crack_envelope := exp(-time * 40.0)
		var noise := _rng.randf_range(-1.0, 1.0) * crack_envelope
		var zap := sin(TAU * 2600.0 * time) * exp(-time * 55.0) * 0.6
		var sample := clampf(noise * 0.75 + zap, -1.0, 1.0)
		audio_data.encode_s16(sample_index * 2, int(sample * 32767.0))

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = audio_data
	return stream


## Short rising two-tone chime for a completed repair.
func _create_success_stream() -> AudioStreamWAV:
	const SAMPLE_RATE := 22050
	const DURATION := 0.5
	var sample_count := int(SAMPLE_RATE * DURATION)
	var audio_data := PackedByteArray()
	audio_data.resize(sample_count * 2)

	for sample_index: int in sample_count:
		var time := float(sample_index) / SAMPLE_RATE
		var envelope := exp(-time * 4.5) * clampf(time / 0.02, 0.0, 1.0)
		var sweep := clampf(time / DURATION, 0.0, 1.0)
		var tone := sin(TAU * lerpf(420.0, 720.0, sweep) * time) * 0.55
		var harmonic := sin(TAU * lerpf(630.0, 1080.0, sweep) * time) * 0.22
		var sample := clampf((tone + harmonic) * envelope, -1.0, 1.0)
		audio_data.encode_s16(sample_index * 2, int(sample * 32767.0))

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = audio_data
	return stream
