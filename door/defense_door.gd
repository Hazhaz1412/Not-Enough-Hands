class_name DefenseDoor
extends StaticBody3D

signal targeted(door: Node, will_attack: bool)
signal attack_phase_changed(door: Node, phase: AttackPhase)
signal durability_changed(door: Node, current: float, repair_cap: float)
signal ghost_driven_away(door: Node)
signal breached(door: Node)
signal rebuilt(door: Node)
signal exorcism_started(door: Node)
signal exorcism_failed(door: Node, repair_cap: float)
signal exorcism_completed(door: Node)

enum AttackPhase {
	IDLE,
	STALKING,
	WEAK_ATTACK,
	STRONG_ATTACK,
	BREACHED,
}

@export_category("Identity")
@export_range(1, 7, 1) var entrance_id: int = 1
@export var interaction_range: float = 3.0

@export_category("Durability")
@export var max_durability: float = 100.0
## Only this fraction of damage can ever be repaired. Ten points of damage
## therefore lowers the repair ceiling by three and leaves seven repairable.
@export_range(0.0, 1.0, 0.01) var repair_efficiency: float = 0.7
@export var repair_per_interaction: float = 7.0
@export var minigame_failure_penalty: float = 20.0
@export var minimum_repair_cap_after_failure: float = 10.0

@export_category("Ghost attack")
@export var stalking_wait_min: float = 3.0
@export var stalking_wait_max: float = 5.0
@export var weak_phase_duration: float = 8.0
@export var damage_tick_interval: float = 1.0
@export var weak_damage_min: float = 3.0
@export var weak_damage_max: float = 5.0
@export var strong_damage_min: float = 7.0
@export var strong_damage_max: float = 10.0

@export_category("Audio variation")
@export var warning_pitch_min: float = 0.88
@export var warning_pitch_max: float = 1.05
@export var strong_pitch_min: float = 0.82
@export var strong_pitch_max: float = 1.06

var current_durability: float
var repair_cap: float
var attack_phase: AttackPhase = AttackPhase.IDLE
var planned_attack: bool = false
var phase_time_remaining: float = 0.0
var damage_tick_remaining: float = 0.0
var minigame_active: bool = false
var repair_unlocked_after_breach: bool = false

var _rng := RandomNumberGenerator.new()
var _hit_tween: Tween

@onready var door_visual: Node3D = $DoorVisual
@onready var entrance_label_front: Label3D = $DoorVisual/EntranceLabelFront
@onready var entrance_label_back: Label3D = $DoorVisual/EntranceLabelBack
@onready var light_damage: Node3D = $DoorVisual/DamageLight
@onready var medium_damage: Node3D = $DoorVisual/DamageMedium
@onready var heavy_damage: Node3D = $DoorVisual/DamageHeavy
@onready var door_collision: CollisionShape3D = $DoorCollision
@onready var warning_audio: AudioStreamPlayer3D = $WarningAudio
@onready var strong_attack_audio: AudioStreamPlayer3D = $StrongAttackAudio


func _ready() -> void:
	_rng.randomize()
	add_to_group("defense_doors")
	if not strong_attack_audio.stream:
		strong_attack_audio.stream = _create_strong_impact_stream()
	entrance_label_front.text = "%02d" % entrance_id
	entrance_label_back.text = "%02d" % entrance_id
	reset_door()


func _physics_process(delta: float) -> void:
	# A client runs no attack of its own: its durability, phase and timers all
	# arrive through apply_network_state(). Without this every peer would chew
	# through its own copy of the door on its own schedule and disagree about
	# which entrances are still standing.
	if minigame_active or not WorldNet.is_world_authority():
		return
	match attack_phase:
		AttackPhase.STALKING:
			phase_time_remaining -= delta
			if phase_time_remaining <= 0.0:
				if planned_attack:
					_enter_weak_attack()
				else:
					_finish_false_alarm()
		AttackPhase.WEAK_ATTACK:
			phase_time_remaining -= delta
			_process_damage_ticks(delta, weak_damage_min, weak_damage_max, false)
			if attack_phase == AttackPhase.WEAK_ATTACK and phase_time_remaining <= 0.0:
				_enter_strong_attack()
		AttackPhase.STRONG_ATTACK:
			_process_damage_ticks(delta, strong_damage_min, strong_damage_max, true)


## Starts a suspicious-door event. A false event waits for the same amount of
## time and plays the same scratching sound, but leaves without damaging the
## door. Pass wait_override in tests or authored special events only.
func begin_targeting(will_attack: bool = true, wait_override: float = -1.0) -> bool:
	if attack_phase != AttackPhase.IDLE or current_durability <= 0.0:
		return false

	planned_attack = will_attack
	phase_time_remaining = (
		_rng.randf_range(stalking_wait_min, stalking_wait_max)
		if wait_override < 0.0
		else maxf(wait_override, 0.0)
	)
	_set_attack_phase(AttackPhase.STALKING)
	_play_warning_audio()
	targeted.emit(self, will_attack)
	return true


## Called by a future ward/tool/ghost system. Keeping this as a door API means
## the attack timing does not need to know what kind of item repelled the ghost.
func drive_ghost_away() -> bool:
	if attack_phase not in [
		AttackPhase.STALKING,
		AttackPhase.WEAK_ATTACK,
		AttackPhase.STRONG_ATTACK,
	]:
		return false

	_stop_attack_audio()
	planned_attack = false
	phase_time_remaining = 0.0
	damage_tick_remaining = 0.0
	_set_attack_phase(AttackPhase.IDLE)
	ghost_driven_away.emit(self)
	return true


func take_damage(amount: float, strong_hit: bool = false) -> float:
	if minigame_active or amount <= 0.0 or current_durability <= 0.0:
		return 0.0

	var applied_damage := minf(amount, current_durability)
	current_durability -= applied_damage
	repair_cap = maxf(
		current_durability,
		repair_cap - applied_damage * (1.0 - repair_efficiency)
	)
	_play_hit_reaction(strong_hit)
	_update_damage_visuals()
	durability_changed.emit(self, current_durability, repair_cap)

	if current_durability <= 0.0:
		current_durability = 0.0
		minigame_active = false
		repair_unlocked_after_breach = false
		_stop_attack_audio()
		_set_breached_visual(true)
		_set_attack_phase(AttackPhase.BREACHED)
		breached.emit(self)

	return applied_damage


func repair(amount: float) -> float:
	if attack_phase == AttackPhase.BREACHED and not repair_unlocked_after_breach:
		return 0.0
	if amount <= 0.0 or current_durability >= repair_cap:
		return 0.0

	var was_breached := attack_phase == AttackPhase.BREACHED
	var restored := minf(amount, repair_cap - current_durability)
	current_durability += restored
	if was_breached and current_durability > 0.0:
		repair_unlocked_after_breach = false
		_set_breached_visual(false)
		_set_attack_phase(AttackPhase.IDLE)
		rebuilt.emit(self)
	_update_damage_visuals()
	durability_changed.emit(self, current_durability, repair_cap)
	return restored


func interact(player: Node3D = null) -> void:
	if _can_start_exorcism():
		if player and player.has_method("start_door_minigame"):
			player.call("start_door_minigame", self)
		return
	repair(repair_per_interaction)


func get_interaction_prompt(interact_key_name: String) -> String:
	if minigame_active:
		return "[center][color=#b9d7e8]ĐANG ĐUỔI THỨ BÊN NGOÀI...[/color][/center]"
	if attack_phase == AttackPhase.BREACHED:
		if not repair_unlocked_after_breach:
			return "[center][b]%s[/b]  CHIẾU ĐÈN ĐUỔI MA — CỬA NGOÀI %02d[/center]" % [
				interact_key_name,
				entrance_id,
			]
	var door_name := "CỬA NGOÀI %02d" % entrance_id
	match attack_phase:
		AttackPhase.STALKING:
			return "[center][b]%s[/b]  CHIẾU ĐÈN ĐUỔI MA — %s[/center]" % [
				interact_key_name,
				door_name,
			]
		AttackPhase.WEAK_ATTACK:
			return "[center][b]%s[/b]  VÀO MINIGAME ĐUỔI MA — %s[/center]" % [
				interact_key_name,
				door_name,
			]
		AttackPhase.STRONG_ATTACK:
			return "[center][color=#e05b4f][b]%s[/b]  CHIẾU ĐÈN NGAY — %s SẮP VỠ![/color][/center]" % [
				interact_key_name,
				door_name,
			]
		AttackPhase.BREACHED:
			return "[center][b]%s[/b]  DỰNG LẠI %s  0/%.0f[/center]" % [
				interact_key_name,
				door_name,
				repair_cap,
			]

	if current_durability < repair_cap:
		return "[center][b]%s[/b]  SỬA %s  %.0f/%.0f[/center]" % [
			interact_key_name,
			door_name,
			current_durability,
			repair_cap,
		]
	return "[center]%s — %.0f/%.0f[/center]" % [
		door_name,
		current_durability,
		repair_cap,
	]


func reset_door() -> void:
	_stop_attack_audio()
	current_durability = max_durability
	repair_cap = max_durability
	planned_attack = false
	phase_time_remaining = 0.0
	damage_tick_remaining = 0.0
	minigame_active = false
	repair_unlocked_after_breach = false
	_set_breached_visual(false)
	_set_attack_phase(AttackPhase.IDLE)
	_update_damage_visuals()
	durability_changed.emit(self, current_durability, repair_cap)


## Takes the server's door wholesale, and re-derives everything visible from it.
##
## The breach and the rebuild are driven off the durability rather than off the
## phase, because those two are what a client can get visibly wrong: a hole it
## cannot walk through, or a door it can walk through that still looks solid.
## Everything else - the timers, the RNG, the audio - stays the server's alone
## and is never sent.
func apply_network_state(
	durability: float,
	cap: float,
	phase: AttackPhase,
	exorcism_running: bool,
	repair_unlocked: bool
) -> void:
	var was_down := current_durability <= 0.0
	var previous_phase := attack_phase
	var lost := current_durability - maxf(durability, 0.0)
	current_durability = maxf(durability, 0.0)
	repair_cap = cap
	minigame_active = exorcism_running
	repair_unlocked_after_breach = repair_unlocked
	_set_attack_phase(phase)

	# The scratching and the impacts are fired by the calls a client never
	# makes, so they are re-derived here: the phase turning to STALKING is the
	# warning, and durability having dropped since the last packet is a hit.
	# Damage arrives as a level rather than as events, so several ticks inside
	# one 5 Hz packet are one reaction - close enough to hear and see.
	if previous_phase != AttackPhase.STALKING and phase == AttackPhase.STALKING:
		_play_warning_audio()
	if lost > 0.0:
		_play_hit_reaction(phase == AttackPhase.STRONG_ATTACK)

	var is_down := current_durability <= 0.0
	if is_down and not was_down:
		_stop_attack_audio()
		_set_breached_visual(true)
		breached.emit(self)
	elif was_down and not is_down:
		_set_breached_visual(false)
		rebuilt.emit(self)

	_update_damage_visuals()
	durability_changed.emit(self, current_durability, repair_cap)


func begin_exorcism() -> bool:
	if not _can_start_exorcism():
		return false
	minigame_active = true
	exorcism_started.emit(self)
	return true


func apply_exorcism_failure() -> float:
	if not minigame_active:
		return repair_cap

	if attack_phase == AttackPhase.BREACHED:
		var floor_cap := clampf(minimum_repair_cap_after_failure, 0.0, max_durability)
		repair_cap = maxf(repair_cap - minigame_failure_penalty, floor_cap)
		repair_cap = maxf(repair_cap, current_durability)
		durability_changed.emit(self, current_durability, repair_cap)
	elif attack_phase in [
		AttackPhase.STALKING,
		AttackPhase.WEAK_ATTACK,
		AttackPhase.STRONG_ATTACK,
	]:
		# A failed early repel attempt gives the attacker one heavy hit. Temporarily
		# release the damage guard, then immediately keep ownership of the door so
		# the minigame can perform its built-in retry. Repeated failures can breach
		# the door and seamlessly continue the same minigame in breached mode.
		minigame_active = false
		take_damage(minigame_failure_penalty, true)
		minigame_active = true
	else:
		return repair_cap

	exorcism_failed.emit(self, repair_cap)
	return repair_cap


func complete_exorcism() -> bool:
	if not minigame_active:
		return false

	var was_breached := attack_phase == AttackPhase.BREACHED
	var was_active_attack := attack_phase in [
		AttackPhase.STALKING,
		AttackPhase.WEAK_ATTACK,
		AttackPhase.STRONG_ATTACK,
	]
	if not was_breached and not was_active_attack:
		return false

	minigame_active = false
	if was_breached:
		repair_unlocked_after_breach = true
	else:
		_stop_attack_audio()
		planned_attack = false
		phase_time_remaining = 0.0
		damage_tick_remaining = 0.0
		_set_attack_phase(AttackPhase.IDLE)
		ghost_driven_away.emit(self)
	exorcism_completed.emit(self)
	return true


func cancel_exorcism() -> void:
	minigame_active = false


func _can_start_exorcism() -> bool:
	if minigame_active:
		return false
	if attack_phase == AttackPhase.BREACHED:
		return not repair_unlocked_after_breach
	return attack_phase in [
		AttackPhase.STALKING,
		AttackPhase.WEAK_ATTACK,
		AttackPhase.STRONG_ATTACK,
	]


func set_random_seed(value: int) -> void:
	_rng.seed = value


func _enter_weak_attack() -> void:
	phase_time_remaining = weak_phase_duration
	damage_tick_remaining = damage_tick_interval
	_set_attack_phase(AttackPhase.WEAK_ATTACK)


func _enter_strong_attack() -> void:
	phase_time_remaining = 0.0
	damage_tick_remaining = damage_tick_interval
	_set_attack_phase(AttackPhase.STRONG_ATTACK)


func _finish_false_alarm() -> void:
	_stop_attack_audio()
	planned_attack = false
	phase_time_remaining = 0.0
	_set_attack_phase(AttackPhase.IDLE)


func _process_damage_ticks(
	delta: float,
	minimum_damage: float,
	maximum_damage: float,
	strong_hit: bool
) -> void:
	damage_tick_remaining -= delta
	while damage_tick_remaining <= 0.0 and current_durability > 0.0:
		take_damage(_rng.randf_range(minimum_damage, maximum_damage), strong_hit)
		damage_tick_remaining += maxf(damage_tick_interval, 0.01)


func _set_attack_phase(new_phase: AttackPhase) -> void:
	if attack_phase == new_phase:
		return
	attack_phase = new_phase
	attack_phase_changed.emit(self, attack_phase)


func _play_warning_audio() -> void:
	if not warning_audio.stream:
		return
	warning_audio.pitch_scale = _rng.randf_range(warning_pitch_min, warning_pitch_max)
	warning_audio.play()


func _play_strong_audio() -> void:
	if not strong_attack_audio.stream:
		return
	strong_attack_audio.pitch_scale = _rng.randf_range(strong_pitch_min, strong_pitch_max)
	var stream_length := strong_attack_audio.stream.get_length()
	var random_offset := 0.0
	if stream_length > 2.0:
		random_offset = _rng.randf_range(0.0, stream_length - 2.0)
	strong_attack_audio.play(random_offset)


## Provides a low wooden thud until a recorded strong-impact asset is assigned
## in the scene. It is generated once per door and remains fully positional.
func _create_strong_impact_stream() -> AudioStreamWAV:
	const SAMPLE_RATE := 22050
	const DURATION := 0.42
	var sample_count := int(SAMPLE_RATE * DURATION)
	var audio_data := PackedByteArray()
	audio_data.resize(sample_count * 2)

	for sample_index: int in sample_count:
		var time := float(sample_index) / SAMPLE_RATE
		var envelope := exp(-time * 9.5)
		var low_body := sin(TAU * 54.0 * time) * 0.72
		var wood_body := sin(TAU * 91.0 * time) * 0.23
		var impact_noise := _rng.randf_range(-0.16, 0.16) * exp(-time * 24.0)
		var sample := clampf((low_body + wood_body) * envelope + impact_noise, -1.0, 1.0)
		audio_data.encode_s16(sample_index * 2, int(sample * 32767.0))

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = audio_data
	return stream


func _stop_attack_audio() -> void:
	if warning_audio:
		warning_audio.stop()
	if strong_attack_audio:
		strong_attack_audio.stop()


func _play_hit_reaction(strong_hit: bool) -> void:
	if strong_hit:
		_play_strong_audio()
	if not door_visual:
		return
	if _hit_tween and _hit_tween.is_running():
		_hit_tween.kill()
	door_visual.position = Vector3.ZERO
	door_visual.rotation = Vector3.ZERO
	var kick_distance := 0.13 if strong_hit else 0.045
	var kick_rotation := deg_to_rad(1.5 if strong_hit else 0.45)
	_hit_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_hit_tween.tween_property(
		door_visual,
		"position:z",
		kick_distance,
		0.055 if strong_hit else 0.035
	)
	_hit_tween.parallel().tween_property(
		door_visual,
		"rotation:z",
		_rng.randf_range(-kick_rotation, kick_rotation),
		0.055 if strong_hit else 0.035
	)
	_hit_tween.tween_property(door_visual, "position:z", 0.0, 0.12)
	_hit_tween.parallel().tween_property(door_visual, "rotation:z", 0.0, 0.12)


func _update_damage_visuals() -> void:
	if not is_node_ready():
		return
	var durability_ratio := current_durability / maxf(max_durability, 0.01)
	light_damage.visible = durability_ratio <= 0.75
	medium_damage.visible = durability_ratio <= 0.45
	heavy_damage.visible = durability_ratio <= 0.2


func _set_breached_visual(is_breached: bool) -> void:
	if not is_node_ready():
		return
	door_collision.set_deferred("disabled", is_breached)
	for node_path: NodePath in [
		^"DoorVisual/DoorLeaf",
		^"DoorVisual/BraceFrontTop",
		^"DoorVisual/BraceFrontBottom",
		^"DoorVisual/BraceBackTop",
		^"DoorVisual/BraceBackBottom",
		^"DoorVisual/BoltFrontLeftTop",
		^"DoorVisual/BoltFrontRightTop",
		^"DoorVisual/BoltFrontLeftBottom",
		^"DoorVisual/BoltFrontRightBottom",
	]:
		get_node(node_path).visible = not is_breached
	if is_breached:
		light_damage.visible = false
		medium_damage.visible = false
		heavy_damage.visible = false
