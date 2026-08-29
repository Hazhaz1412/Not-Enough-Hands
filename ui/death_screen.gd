extends CanvasLayer

signal restart_requested()

enum Phase {
	IDLE,
	IMPACT,
	JUMPSCARE,
	BLACKOUT,
	GAME_OVER,
}

const STATUE_STING = preload("res://assets/audio/statue_spotted_jumpscare.mp3")
const CRAWLER_STING = preload("res://assets/audio/crawler_scream.ogg")
const HUNTER_STING = preload("res://assets/audio/creature_reveal.mp3")
const DARKNESS_STING = preload("res://assets/audio/minigame/door_minigame_jumpscare.mp3")
## No dedicated toilet-ghost jumpscare sting exists yet (Sprint 10) - reusing
## its own established appearance cue rather than leaving it silently
## mislabeled as the statue (see _identify_killer()).
const TOILET_STING = preload("res://assets/audio/statue_teleport.wav")

@export_category("Timing")
@export var impact_duration: float = 0.12
@export var jumpscare_duration: float = 1.28
@export var blackout_duration: float = 0.46
@export var game_over_fade_duration: float = 0.38

var phase: Phase = Phase.IDLE
var phase_elapsed: float = 0.0
var killer_variant: StringName = &"statue"
var restarting: bool = false

@onready var backdrop: ColorRect = $Backdrop
@onready var impact_flash: ColorRect = $ImpactFlash
@onready var visage: Control = $Visage
@onready var game_over: Control = $GameOver
@onready var card: Control = $GameOver/Card
@onready var cause_label: Label = $GameOver/Card/Content/Cause
@onready var tip_label: Label = $GameOver/Card/Content/Tip
@onready var restart_button: Button = $GameOver/Card/Content/RestartButton
@onready var scare_audio: AudioStreamPlayer = $ScareAudio


func _ready() -> void:
	# The world is paused on death so the attacking ghost cannot continue moving,
	# but this CanvasLayer still needs to animate and receive the restart click.
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	restart_button.pressed.connect(_on_restart_pressed)


func show_jumpscare(ghost: Node3D) -> void:
	if phase != Phase.IDLE:
		return

	killer_variant = _identify_killer(ghost)
	phase = Phase.IMPACT
	phase_elapsed = 0.0
	restarting = false
	visible = true
	backdrop.color = Color(0.025, 0.0, 0.0, 1.0)
	impact_flash.color = Color(1.0, 0.88, 0.8, 1.0)
	visage.visible = false
	game_over.visible = false
	game_over.modulate.a = 0.0
	card.scale = Vector2(0.94, 0.94)
	visage.call("configure", killer_variant)
	_configure_copy()

	match killer_variant:
		&"crawler":
			scare_audio.stream = CRAWLER_STING
			scare_audio.pitch_scale = 0.92
		&"hunter":
			scare_audio.stream = HUNTER_STING
			scare_audio.pitch_scale = 0.76
			impact_flash.color = Color(0.92, 0.72, 0.48, 1.0)
			backdrop.color = Color(0.07, 0.012, 0.0, 1.0)
		&"darkness":
			scare_audio.stream = DARKNESS_STING
			scare_audio.pitch_scale = 0.58
			impact_flash.color = Color(0.34, 0.56, 0.82, 1.0)
			backdrop.color = Color(0.0, 0.004, 0.018, 1.0)
		&"toilet":
			scare_audio.stream = TOILET_STING
			scare_audio.pitch_scale = 0.85
		_:
			scare_audio.stream = STATUE_STING
			scare_audio.pitch_scale = 0.97
	scare_audio.play()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	# Only own the global pause when this player belongs to the active gameplay
	# scene. Isolated component tests and editor previews may instance Player
	# directly under SceneTree.root without a current scene.
	var active_scene := get_tree().current_scene
	if active_scene and active_scene.is_ancestor_of(self):
		get_tree().paused = true


func _process(delta: float) -> void:
	if phase == Phase.IDLE:
		return

	phase_elapsed += delta
	match phase:
		Phase.IMPACT:
			_update_impact()
		Phase.JUMPSCARE:
			_update_jumpscare()
		Phase.BLACKOUT:
			_update_blackout()
		Phase.GAME_OVER:
			_update_game_over()


func _update_impact() -> void:
	var progress := clampf(phase_elapsed / maxf(impact_duration, 0.01), 0.0, 1.0)
	impact_flash.color.a = 1.0 - progress
	backdrop.color = Color(0.5 * (1.0 - progress), 0.0, 0.0, 1.0)
	if phase_elapsed >= impact_duration:
		phase = Phase.JUMPSCARE
		phase_elapsed = 0.0
		visage.visible = true
		impact_flash.color = Color(0.75, 0.0, 0.0, 0.0)


func _update_jumpscare() -> void:
	var progress := clampf(phase_elapsed / maxf(jumpscare_duration, 0.01), 0.0, 1.0)
	visage.call("set_scare_progress", progress)

	# Each killer interrupts the rush in its own rhythm. The Hunter closes in
	# with hard, regular cuts; the Darkness Ghost seems to vanish inside the
	# blackout and reappear closer on irregular frames.
	var frame := int(phase_elapsed * 30.0)
	var cut_to_black := false
	match killer_variant:
		&"hunter":
			cut_to_black = frame in [3, 4, 10, 17, 25]
		&"darkness":
			cut_to_black = frame in [2, 6, 7, 14, 15, 23, 29]
		_:
			cut_to_black = frame in [4, 11, 24]
	visage.visible = not cut_to_black
	if killer_variant == &"darkness":
		var cold_flicker := (sin(phase_elapsed * 53.0) * 0.5 + 0.5) * 0.022
		backdrop.color = Color(0.0, cold_flicker * 0.55, cold_flicker, 1.0)
	elif killer_variant == &"hunter":
		var hunter_flicker := 0.018 + (sin(phase_elapsed * 67.0) * 0.5 + 0.5) * 0.045
		backdrop.color = Color(hunter_flicker, hunter_flicker * 0.22, 0.0, 1.0)
	else:
		var red_flicker := 0.025 + (sin(phase_elapsed * 73.0) * 0.5 + 0.5) * 0.055
		backdrop.color = Color(red_flicker, 0.0, 0.002, 1.0)
	impact_flash.color.a = maxf(sin(phase_elapsed * 91.0), 0.0) * progress * 0.12

	if phase_elapsed >= jumpscare_duration:
		phase = Phase.BLACKOUT
		phase_elapsed = 0.0
		visage.visible = false
		impact_flash.color = Color.BLACK
		backdrop.color = Color.BLACK


func _update_blackout() -> void:
	if phase_elapsed >= blackout_duration:
		phase = Phase.GAME_OVER
		phase_elapsed = 0.0
		game_over.visible = true
		game_over.modulate.a = 0.0
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		restart_button.grab_focus()


func _update_game_over() -> void:
	var progress := clampf(
		phase_elapsed / maxf(game_over_fade_duration, 0.01),
		0.0,
		1.0
	)
	game_over.modulate.a = progress
	card.scale = Vector2.ONE * lerpf(0.94, 1.0, ease(progress, -1.8))


func _identify_killer(ghost: Node3D) -> StringName:
	if is_instance_valid(ghost):
		if ghost.is_in_group("darkness_ghosts") \
			or "darkness" in ghost.name.to_lower():
			return &"darkness"
		if ghost.is_in_group("crawler_ghosts") \
			or "crawler" in ghost.name.to_lower():
			return &"crawler"
		if ghost.is_in_group("hunter_ghosts") \
			or "hunter" in ghost.name.to_lower():
			return &"hunter"
		if "toilet" in ghost.name.to_lower():
			return &"toilet"
	return &"statue"


func _configure_copy() -> void:
	match killer_variant:
		&"crawler":
			cause_label.text = "BẠN ĐÃ BỊ KẺ BÒ TRÊN TRẦN BẮT"
			tip_label.text = "Nó không cần nhìn thấy bạn. Đứng im và đừng gây tiếng động."
		&"hunter":
			cause_label.text = "THỢ SĂN ĐÃ TÓM ĐƯỢC BẠN"
			tip_label.text = "Nó lần theo dấu chân bạn để lại. Đừng quay về lối cũ, và đừng bao giờ đứng yên trong vệt đèn của nó."
		&"darkness":
			cause_label.text = "MA BÓNG TỐI ĐÃ NUỐT CHỬNG BẠN"
			tip_label.text = "Khôi phục điện cho từng khu vực. Trong bóng tối, nó luôn biết bạn đang ở đâu."
		&"toilet":
			cause_label.text = "CON MA NHÀ VỆ SINH ĐÃ BẮT ĐƯỢC BẠN"
			tip_label.text = "Nó xuất hiện bất ngờ quanh bạn. Hãy quay lại nhìn thẳng vào nó trước khi hết thời gian."
		_:
			cause_label.text = "BẠN ĐÃ BỊ TƯỢNG ĐÁ BẮT"
			tip_label.text = "Đừng quay lưng. Đừng nhắm mắt khi nó đang ở gần."


func _on_restart_pressed() -> void:
	if restarting or phase != Phase.GAME_OVER:
		return
	restarting = true
	restart_button.disabled = true
	restart_requested.emit()
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	var error := get_tree().reload_current_scene()
	if error != OK:
		restarting = false
		restart_button.disabled = false
		get_tree().paused = true
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		push_error("Could not restart the current scene (error %d)." % error)


## Test hooks keep the sequence verifiable without waiting through presentation
## timing in a headless smoke test.
func debug_finish_jumpscare() -> void:
	if phase == Phase.IDLE:
		return
	phase = Phase.GAME_OVER
	phase_elapsed = game_over_fade_duration
	visage.visible = false
	impact_flash.color = Color.BLACK
	backdrop.color = Color.BLACK
	game_over.visible = true
	game_over.modulate.a = 1.0
	card.scale = Vector2.ONE
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func is_showing_game_over() -> bool:
	return phase == Phase.GAME_OVER and game_over.visible
