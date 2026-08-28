class_name ToiletMinigame
extends Node3D

## Ported from feat/game-character-hoang's minigames/toilet_minigame/
## toilet_minigame.gd (source of truth for this minigame's behavior), owned
## per-toilet (child of Toilet, like on that branch) rather than per-player.
## Adapted only where main's architecture differs:
## - bladder access goes through player.get_bladder()/reduce_bladder()/
##   reset_bladder() instead of reaching into player.bladder directly.
## - start(player, toilet)/is_running() are thin adapters so Player/Toilet
##   can drive this the same way they already drive DoorGhostMinigame,
##   without needing to know about MinigameViewPoint or MinigameState.
## - _process() also cancels safely if the toilet or player becomes invalid
##   mid-session (main's existing session-safety contract, tested by
##   tests/toilet_minigame_smoke.gd).
## Player.gd fields the source branch has and main doesn't (yaw_clamp_*,
## set_held_item_visibility, take_damage/current_health) are all already
## guarded with has_method()/"x" in player checks in the source itself, so
## they degrade gracefully here without any changes.

enum MinigameState { IDLE, PLAYING, SUCCESS, CANCELLED }

## Cancelling the toilet does not erase its ghost. The debt lives on the
## player (rather than on one Toilet node) so changing bathrooms cannot reset
## the encounter in maps with several toilets.
const GHOST_ADVANCE_META := &"toilet_ghost_advance"

var current_state: MinigameState = MinigameState.IDLE
var player: Node3D
var _toilet: Node

signal session_ended(success: bool)
signal minigame_state_changed(state: String)
signal minigame_effect_requested(effect: String)

# Asset Pipeline
@export var balance_asset: PackedScene = preload("res://toilet/assets/water_nozzle.tscn")
## Brief 3D "caught" reaction shown when the player fails to look at the
## Toilet Ghost in time. Gameplay consequence is the player's seven-second
## stun/slow; this scene is only its visual/audio impact beat.
@export var toilet_ghost_caught_scene: PackedScene = preload("res://minigames/toilet_ghost_caught.tscn")
var instantiated_asset: Node3D
var left_grip: Marker3D
var right_grip: Marker3D
var liquid_origin: Marker3D

# 3D Elements
@onready var asset_anchor: Node3D = $BalanceVisual/AssetAnchor
@onready var left_hand: MeshInstance3D = $LeftHand
@onready var right_hand: MeshInstance3D = $RightHand
@onready var stream: MeshInstance3D = $LiquidStream
@onready var toilet_target: Marker3D = $ToiletTarget
## Toilet-minigame-specific threat (minigames/toilet_ghost.gd), driven
## entirely from here (arm()/update()/reset()) - see those three call sites
## below. Duck-typed like every other cross-object call in this file so a
## missing/renamed node degrades to a no-op instead of an error.
@onready var toilet_ghost: Node = get_node_or_null("ToiletGhost")

# HUD Elements
@onready var bladder_bar: ProgressBar = $HUDLayer/MarginContainer/VBoxContainer/StatusArea/BladderContainer/ProgressBar
@onready var health_bar: ProgressBar = $HUDLayer/MarginContainer/VBoxContainer/StatusArea/HealthContainer/ProgressBar
@onready var feedback_label: Label = $HUDLayer/MarginContainer/VBoxContainer/FeedbackLabel
@onready var balance_indicator: ColorRect = $HUDLayer/MarginContainer/VBoxContainer/BalanceTrack/Indicator
@onready var safe_zone_rect: ColorRect = $HUDLayer/MarginContainer/VBoxContainer/BalanceTrack/SafeZone
@onready var warning_zone_rect: ColorRect = $HUDLayer/MarginContainer/VBoxContainer/BalanceTrack/WarningZone
@onready var danger_noise_bar: ProgressBar = $HUDLayer/MarginContainer/VBoxContainer/DangerNoiseBar
@onready var combo_label: Label = $HUDLayer/MarginContainer/VBoxContainer/ComboLabel
@onready var hud_layer: CanvasLayer = $HUDLayer

# Configurable Parameters
@export_category("Aim Control")
@export var keyboard_control_acceleration: float = 2.4
@export var mouse_velocity_impulse: float = 0.01
@export var nozzle_max_offset: float = 0.5
@export var oscillation_speed: float = 1.2
@export var oscillation_amplitude: float = 0.14
@export var oscillation_amplitude_end: float = 0.24
@export var drift_pull: float = 6.0
@export var velocity_damping: float = 3.0
@export var max_nozzle_velocity: float = 0.9
@export_range(0.0, 1.0) var boundary_bounce: float = 0.18
@export var movement_smoothing: float = 8.0
@export var camera_transition_duration: float = 0.25

@export var min_camera_rotation_x: float = -90.0
@export var max_camera_rotation_x: float = 90.0

## The direction faced the instant the toilet minigame starts is treated as
## 0 degrees; the player can turn fully around to check either rear shoulder.
## The toilet Ghost's rear-diagonal spawn arc stays slightly inside this
## limit, so every appearance remains catchable and never unwinnable.
@export var min_camera_rotation_y: float = -180.0
@export var max_camera_rotation_y: float = 180.0

@export var min_camera_rotation_z: float = -90.0
@export var max_camera_rotation_z: float = 90.0

## A full bladder takes 13.5 seconds of controlled full-speed flow to empty:
## five times faster than filling. Every entry needs 1.5 seconds to build
## pressure again, so repeatedly entering and cancelling gains almost nothing.
@export var bladder_drain_rate: float = 100.0 / 13.5
@export_range(0.0, 1.0) var warning_drain_multiplier: float = 0.35
@export var pee_ramp_duration: float = 1.5
@export var pee_ramp_power: float = 4.0
@export var center_lock_delay: float = 0.3
@export var combo_ramp_duration: float = 2.5
@export var max_combo_bonus: float = 0.3

@export_category("Difficulty")
@export var safe_zone_width: float = 0.16
@export var safe_zone_width_end: float = 0.1
@export var warning_zone_width: float = 0.34
@export var warning_zone_width_end: float = 0.26
@export var tremor_interval_start: float = 3.8
@export var tremor_interval_end: float = 2.4
@export var tremor_warning_duration: float = 0.35
@export var tremor_force: float = 0.28

@export_category("Danger Consequence")
@export var danger_noise_delay: float = 0.9
@export var danger_noise_repeat_interval: float = 1.1
@export_range(0.0, 1.0) var danger_noise_loudness: float = 0.85
## Each voluntary exit moves the next Toilet Ghost one ordinary lurch closer.
## It stops just short of contact so cancelling is dangerous, not an off-screen
## instant death; the player always gets one final reaction window.
@export_range(0.0, 1.0) var cancel_ghost_advance_cap: float = 0.95

# Internal state
var damage_timer: float = 0.0
var time_passed: float = 0.0
var player_offset: float = 0.0
var nozzle_velocity: float = 0.0
var pending_mouse_motion: float = 0.0
var safe_streak_time: float = 0.0
var session_start_bladder: float = 0.0
var noise_cooldown: float = 0.0
var next_tremor_time: float = 0.0
var tremor_warning_remaining: float = 0.0
var tremor_direction: float = 1.0
var _flow_ramp_elapsed: float = 0.0
## The E press that starts the toilet session is still travelling through the
## input tree. Ignore it until released so it cannot immediately cancel itself.
var _wait_for_interact_release: bool = false
var _rng := RandomNumberGenerator.new()
const TARGET_CENTER_X = 0.0
const VISUAL_MAX_X = 0.37

# Camera handling
var saved_player_position: Vector3
var saved_pitch: float
var saved_yaw: float
var original_camera: Camera3D
var camera_pivot: Node3D

func _ready() -> void:
	_rng.randomize()
	hud_layer.hide()
	left_hand.hide()
	right_hand.hide()
	stream.hide()
	hide()

	if toilet_ghost and toilet_ghost.has_signal("ghost_timed_out"):
		toilet_ghost.ghost_timed_out.connect(_on_toilet_ghost_caught)

	_load_asset()


## Reached when the ghost completes its last lurch. The toilet session ends,
## control is returned, and the player survives with a seven-second stun.
func _on_toilet_ghost_caught() -> void:
	cancel(false)
	if is_instance_valid(player) and player.has_method("apply_toilet_ghost_stun"):
		player.call("apply_toilet_ghost_stun")
	if toilet_ghost_caught_scene:
		var caught := toilet_ghost_caught_scene.instantiate()
		# The caught scene owns a transparent 3D viewport, so it remains visible
		# above the normal HUD while still using the real Toilet Ghost model.
		add_child(caught)

func _load_asset() -> void:
	if not balance_asset: return

	if instantiated_asset:
		instantiated_asset.queue_free()

	instantiated_asset = balance_asset.instantiate()
	asset_anchor.add_child(instantiated_asset)

	left_grip = instantiated_asset.get_node_or_null("LeftGrip") as Marker3D
	right_grip = instantiated_asset.get_node_or_null("RightGrip") as Marker3D
	liquid_origin = instantiated_asset.get_node_or_null("LiquidOrigin") as Marker3D


## Adapter matching the calling convention Player/Toilet already use for
## DoorGhostMinigame - resolves the viewpoint from `toilet` and delegates to
## the ported start_session() unchanged.
func start(p_player: Node3D, toilet: Node) -> bool:
	if current_state != MinigameState.IDLE or not is_instance_valid(toilet):
		return false
	var viewpoint := toilet.get_node_or_null("MinigameViewPoint") as Marker3D
	if not viewpoint:
		return false
	_toilet = toilet
	start_session(p_player, viewpoint)
	return true


func is_running() -> bool:
	return current_state == MinigameState.PLAYING

func start_session(p_player: Node3D, minigame_viewpoint: Marker3D) -> void:
	if current_state != MinigameState.IDLE:
		return

	player = p_player
	current_state = MinigameState.PLAYING
	_wait_for_interact_release = true

	# Lock player
	if player.has_method("set_physics_process"):
		player.set_physics_process(false)

	# Setup Camera Hijack
	original_camera = player.get_node_or_null("CameraPivot/Camera3D") as Camera3D
	camera_pivot = player.get_node_or_null("CameraPivot")

	if player and player.has_method("set_held_item_visibility"):
		player.set_held_item_visibility(false)

	if original_camera and camera_pivot and minigame_viewpoint:
		# Fix any existing distortion
		original_camera.transform = Transform3D.IDENTITY
		camera_pivot.rotation.y = 0
		camera_pivot.rotation.z = 0
		player.rotation.x = 0
		player.rotation.z = 0

		saved_player_position = player.global_position
		saved_pitch = camera_pivot.rotation.x
		saved_yaw = player.rotation.y

		var target_yaw = minigame_viewpoint.global_rotation.y
		var target_pitch = minigame_viewpoint.global_rotation.x
		var target_pos = minigame_viewpoint.global_position - Vector3(0, camera_pivot.position.y, 0)

		if "yaw_clamp_active" in player:
			player.yaw_clamp_active = true
			player.yaw_clamp_min = deg_to_rad(min_camera_rotation_y)
			player.yaw_clamp_max = deg_to_rad(max_camera_rotation_y)
			player.accumulated_yaw = 0.0
			player.pitch_clamp_min = deg_to_rad(min_camera_rotation_x)
			player.pitch_clamp_max = deg_to_rad(max_camera_rotation_x)

		var tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(player, "global_position", target_pos, camera_transition_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(player, "rotation:y", target_yaw, camera_transition_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(camera_pivot, "rotation:x", target_pitch, camera_transition_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# Reset minigame state
	damage_timer = 0.0
	time_passed = 0.0
	player_offset = 0.0
	nozzle_velocity = 0.0
	pending_mouse_motion = 0.0
	safe_streak_time = 0.0
	noise_cooldown = 0.0
	tremor_warning_remaining = 0.0
	_flow_ramp_elapsed = 0.0
	session_start_bladder = (
		maxf(float(player.call("get_bladder")), 0.01)
		if player and player.has_method("get_bladder")
		else 100.0
	)
	next_tremor_time = _rng.randf_range(
		maxf(tremor_interval_start * 0.85, 0.1),
		maxf(tremor_interval_start * 1.15, 0.11)
	)
	asset_anchor.position.x = 0
	asset_anchor.rotation.z = 0

	# Snap hands to starting position
	if left_grip:
		left_hand.global_position = left_grip.global_position
		left_hand.global_transform.basis = left_grip.global_transform.basis
	if right_grip:
		right_hand.global_position = right_grip.global_position
		right_hand.global_transform.basis = right_grip.global_transform.basis

	_update_visuals(0.0)
	_update_status_bars()

	left_hand.show()
	right_hand.show()
	hud_layer.show()
	show()

	if toilet_ghost and toilet_ghost.has_method("arm"):
		var saved_advance := _get_saved_ghost_advance()
		toilet_ghost.call(
			"arm",
			saved_advance,
			saved_advance > 0.0
		)

func _process(delta: float) -> void:
	if current_state != MinigameState.PLAYING:
		return
	# Session safety: a toilet removed/freed mid-session, or a player who
	# stopped being valid, must exit like a cancel - never as a success.
	if not is_instance_valid(_toilet) or not _toilet.is_inside_tree():
		cancel(false)
		return
	if not is_instance_valid(player) or not bool(player.get("is_alive")):
		cancel(false)
		return

	_handle_input(delta)
	_update_visuals(delta)
	_evaluate_balance(delta)
	_update_status_bars()

	if toilet_ghost and toilet_ghost.has_method("update"):
		toilet_ghost.update(delta, player, original_camera)

func _unhandled_input(event: InputEvent) -> void:
	if current_state != MinigameState.PLAYING:
		return

	if event.is_action_released("interact"):
		_wait_for_interact_release = false
		return

	if event.is_action_pressed("interact"):
		if _wait_for_interact_release:
			get_viewport().set_input_as_handled()
			return
		get_viewport().set_input_as_handled()
		cancel()
		return

	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		cancel()


## Mouse motion drives the nozzle here, then continues to Player.gd's camera
## look code. The player can therefore aim the stream and scan left, right, or
## behind at the same time. A/D remains an accessibility fallback and helps
## headless tests.
func _input(event: InputEvent) -> void:
	if current_state != MinigameState.PLAYING:
		return
	if event is InputEventMouseMotion \
		and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		apply_mouse_motion(event.relative.x)


func apply_mouse_motion(relative_x: float) -> void:
	if current_state == MinigameState.PLAYING:
		pending_mouse_motion += relative_x


func _advance_flow_ramp(delta: float) -> float:
	_flow_ramp_elapsed += maxf(delta, 0.0)
	var ramp_progress := clampf(
		_flow_ramp_elapsed / maxf(pee_ramp_duration, 0.001),
		0.0,
		1.0
	)
	return pow(ramp_progress, maxf(pee_ramp_power, 1.0))


func _handle_input(delta: float) -> void:
	time_passed += delta
	var progress := _get_completion_progress()
	var input_dir := Input.get_axis("move_left", "move_right")
	var drift_amplitude := lerpf(
		oscillation_amplitude,
		oscillation_amplitude_end,
		progress
	)
	# Two readable waves keep the hand from settling into a perfectly repeating
	# left/right rhythm. The player is counter-steering a moving equilibrium,
	# not chasing a teleported random target.
	var drift_target := (
		sin(time_passed * oscillation_speed) * drift_amplitude
		+ sin(time_passed * oscillation_speed * 0.43 + 1.7) * drift_amplitude * 0.28
	)
	var acceleration := (drift_target - player_offset) * drift_pull
	acceleration += input_dir * keyboard_control_acceleration
	nozzle_velocity += acceleration * delta
	nozzle_velocity += pending_mouse_motion * mouse_velocity_impulse
	pending_mouse_motion = 0.0

	_update_tremor(delta, progress)
	nozzle_velocity *= exp(-velocity_damping * delta)
	nozzle_velocity = clampf(nozzle_velocity, -max_nozzle_velocity, max_nozzle_velocity)
	player_offset += nozzle_velocity * delta
	if absf(player_offset) > nozzle_max_offset:
		player_offset = clampf(player_offset, -nozzle_max_offset, nozzle_max_offset)
		if signf(nozzle_velocity) == signf(player_offset):
			nozzle_velocity *= -boundary_bounce


func _update_tremor(delta: float, progress: float) -> void:
	if tremor_force <= 0.0:
		return
	if tremor_warning_remaining > 0.0:
		tremor_warning_remaining = maxf(tremor_warning_remaining - delta, 0.0)
		if tremor_warning_remaining <= 0.0:
			nozzle_velocity += tremor_direction * tremor_force * lerpf(0.8, 1.25, progress)
			var interval := lerpf(tremor_interval_start, tremor_interval_end, progress)
			next_tremor_time = time_passed + _rng.randf_range(
				maxf(interval * 0.85, 0.1),
				maxf(interval * 1.15, 0.11)
			)
		return
	if time_passed >= next_tremor_time:
		tremor_direction = -1.0 if _rng.randf() < 0.5 else 1.0
		tremor_warning_remaining = maxf(tremor_warning_duration, 0.001)

func _update_visuals(delta: float) -> void:
	var target_x := clampf(TARGET_CENTER_X + player_offset, -VISUAL_MAX_X, VISUAL_MAX_X)

	# Move Anchor smoothly
	var visual_blend := 1.0 - exp(-movement_smoothing * delta)
	asset_anchor.position.x = lerpf(asset_anchor.position.x, target_x, visual_blend)

	# Update Hands and Forearms
	if left_grip:
		left_hand.global_position = left_hand.global_position.lerp(left_grip.global_position, 15.0 * delta)
		left_hand.global_transform.basis = Basis(left_hand.global_transform.basis.get_rotation_quaternion().slerp(left_grip.global_transform.basis.get_rotation_quaternion(), 15.0 * delta))
	if right_grip:
		right_hand.global_position = right_hand.global_position.lerp(right_grip.global_position, 15.0 * delta)
		right_hand.global_transform.basis = Basis(right_hand.global_transform.basis.get_rotation_quaternion().slerp(right_grip.global_transform.basis.get_rotation_quaternion(), 15.0 * delta))

	# Update Liquid
	if liquid_origin and stream.visible:
		var stream_start = liquid_origin.global_position
		var stream_end = toilet_target.global_position

		stream.global_position = (stream_start + stream_end) / 2.0
		var dist = stream_start.distance_to(stream_end)
		var m = stream.mesh as CylinderMesh
		m.height = dist

		stream.look_at(stream_end, Vector3.UP, true)
		stream.rotate_object_local(Vector3.RIGHT, PI/2.0)

func _evaluate_balance(delta: float) -> void:
	var distance = abs(asset_anchor.position.x - TARGET_CENTER_X)
	var progress := _get_completion_progress()
	var current_safe_width := lerpf(safe_zone_width, safe_zone_width_end, progress)
	var current_warning_width := lerpf(warning_zone_width, warning_zone_width_end, progress)
	var flow_multiplier := _advance_flow_ramp(delta)

	if distance <= (current_safe_width / 2.0):
		# CENTERED ZONE
		safe_streak_time += delta
		damage_timer = 0.0
		noise_cooldown = maxf(noise_cooldown - delta, 0.0)
		var combo := _get_combo_multiplier()
		feedback_label.text = (
			"HOLD CENTER"
			if safe_streak_time < center_lock_delay
			else "CENTERED  x%.1f" % combo
		)
		feedback_label.add_theme_color_override("font_color", Color.GREEN)
		if stream.material_override:
			var mat = stream.material_override as StandardMaterial3D
			mat.albedo_color = Color(0.4, 0.7, 1.0, 0.8)
		stream.show()
		if flow_multiplier < 1.0:
			feedback_label.text = "BUILDING PRESSURE  %d%%" % roundi(flow_multiplier * 100.0)
		if safe_streak_time >= center_lock_delay \
			and player and player.has_method("get_bladder"):
			if player.get_bladder() <= 0:
				succeed()
			else:
				player.reduce_bladder(bladder_drain_rate * combo * flow_multiplier * delta)
				if player.get_bladder() <= 0:
					succeed()

	elif distance <= (current_warning_width / 2.0):
		# UNSTABLE ZONE
		safe_streak_time = maxf(safe_streak_time - delta * 2.0, 0.0)
		damage_timer = 0.0
		feedback_label.text = "UNSTABLE — SLOW FLOW"
		feedback_label.add_theme_color_override("font_color", Color.YELLOW)
		if stream.material_override:
			var mat = stream.material_override as StandardMaterial3D
			mat.albedo_color = Color(0.8, 0.8, 0.2, 0.4)
		stream.show()
		if flow_multiplier < 1.0:
			feedback_label.text = "UNSTABLE — BUILDING PRESSURE  %d%%" % roundi(flow_multiplier * 100.0)
		if player and player.has_method("get_bladder"):
			player.reduce_bladder(bladder_drain_rate * warning_drain_multiplier * flow_multiplier * delta)
			if player.get_bladder() <= 0:
				succeed()
	else:
		# DANGER ZONE
		safe_streak_time = 0.0
		feedback_label.text = "DANGER — TOO LOUD!"
		feedback_label.add_theme_color_override("font_color", Color.RED)
		stream.hide()

		damage_timer += delta
		noise_cooldown = maxf(noise_cooldown - delta, 0.0)
		if damage_timer >= danger_noise_delay and noise_cooldown <= 0.0:
			_emit_danger_noise()
			noise_cooldown = danger_noise_repeat_interval

	if tremor_warning_remaining > 0.0:
		feedback_label.text = "HAND SHAKING — PREPARE!"
		feedback_label.add_theme_color_override("font_color", Color.ORANGE)


func _get_completion_progress() -> float:
	if not player or not player.has_method("get_bladder") or session_start_bladder <= 0.0:
		return 0.0
	return clampf(1.0 - float(player.call("get_bladder")) / session_start_bladder, 0.0, 1.0)


func _get_combo_multiplier() -> float:
	var combo_time := maxf(safe_streak_time - center_lock_delay, 0.0)
	var combo_ratio := clampf(combo_time / maxf(combo_ramp_duration, 0.01), 0.0, 1.0)
	return 1.0 + combo_ratio * max_combo_bonus


func _emit_danger_noise() -> void:
	if not is_instance_valid(player):
		return
	var noise_position := global_position
	if is_instance_valid(_toilet) and _toilet is Node3D:
		noise_position = (_toilet as Node3D).global_position
	# The toilet's own ghost hears this too: a danger-zone burst is the player
	# audibly losing the aim half of the minigame, and it advances the stalk
	# (minigames/toilet_ghost.gd report_noise()). That is what makes the two
	# halves one system - bad aim brings it closer, and pushing it back costs
	# a look, which costs aim.
	for ghost_group: StringName in [&"crawler_ghosts", &"hunter_ghosts", &"toilet_ghosts"]:
		get_tree().call_group(
			ghost_group,
			"report_noise",
			noise_position,
			danger_noise_loudness,
			player
		)
	minigame_effect_requested.emit("noise_created")

func _update_status_bars() -> void:
	if not player: return

	if player.has_method("get_bladder_ratio"):
		bladder_bar.max_value = 1.0
		bladder_bar.value = player.get_bladder_ratio()

	if "current_health" in player and "max_health" in player:
		health_bar.max_value = player.max_health
		health_bar.value = player.current_health

	var normalized_x := clampf(
		(asset_anchor.position.x + VISUAL_MAX_X) / (VISUAL_MAX_X * 2.0),
		0.0,
		1.0
	)
	balance_indicator.anchor_left = normalized_x
	balance_indicator.anchor_right = normalized_x
	var progress := _get_completion_progress()
	var current_safe_width := lerpf(safe_zone_width, safe_zone_width_end, progress)
	var current_warning_width := lerpf(warning_zone_width, warning_zone_width_end, progress)
	_set_zone_anchors(warning_zone_rect, current_warning_width)
	_set_zone_anchors(safe_zone_rect, current_safe_width)
	danger_noise_bar.value = clampf(
		damage_timer / maxf(danger_noise_delay, 0.01),
		0.0,
		1.0
	)
	combo_label.text = (
		"LOCKING  %d%%" % int(clampf(safe_streak_time / maxf(center_lock_delay, 0.01), 0.0, 1.0) * 100.0)
		if safe_streak_time < center_lock_delay
		else "FLOW COMBO  x%.1f" % _get_combo_multiplier()
	)


func _set_zone_anchors(zone: ColorRect, world_width: float) -> void:
	if not zone:
		return
	var half_anchor_width := clampf(world_width / (VISUAL_MAX_X * 4.0), 0.0, 0.5)
	zone.anchor_left = 0.5 - half_anchor_width
	zone.anchor_right = 0.5 + half_anchor_width

func succeed() -> void:
	if current_state != MinigameState.PLAYING: return
	current_state = MinigameState.SUCCESS
	minigame_state_changed.emit("SUCCESS")
	_clear_saved_ghost_advance()

	# Belt-and-suspenders: the drain above already brings bladder to exactly
	# 0, but an explicit reset through the same Player API makes success
	# unconditionally end at 0 regardless of how it was reached.
	if is_instance_valid(player) and player.has_method("reset_bladder"):
		player.reset_bladder()

	feedback_label.text = "SUCCESS!"
	feedback_label.add_theme_color_override("font_color", Color.GREEN)
	stream.hide()
	await get_tree().create_timer(1.0).timeout

	_cleanup()

func cancel(apply_ghost_penalty: bool = true) -> void:
	if current_state != MinigameState.PLAYING: return
	if apply_ghost_penalty:
		_bank_cancelled_ghost_advance()
	current_state = MinigameState.CANCELLED
	minigame_state_changed.emit("CANCELLED")

	feedback_label.text = "CANCELLED!"
	feedback_label.add_theme_color_override("font_color", Color.GRAY)
	stream.hide()
	await get_tree().create_timer(0.5).timeout

	_cleanup()


func _get_saved_ghost_advance() -> float:
	if not is_instance_valid(player):
		return 0.0
	return clampf(float(player.get_meta(GHOST_ADVANCE_META, 0.0)), 0.0, 1.0)


func _bank_cancelled_ghost_advance() -> void:
	if not is_instance_valid(player):
		return
	var current_advance := _get_saved_ghost_advance()
	if toilet_ghost and "advance" in toilet_ghost:
		current_advance = maxf(current_advance, float(toilet_ghost.advance))
	var steps := 5
	if toilet_ghost and "steps_to_reach" in toilet_ghost:
		steps = maxi(int(toilet_ghost.steps_to_reach), 1)
	var cap := clampf(cancel_ghost_advance_cap, 0.0, 1.0)
	player.set_meta(
		GHOST_ADVANCE_META,
		minf(current_advance + 1.0 / float(steps), cap)
	)


func _clear_saved_ghost_advance() -> void:
	if is_instance_valid(player) and player.has_meta(GHOST_ADVANCE_META):
		player.remove_meta(GHOST_ADVANCE_META)

func _cleanup() -> void:
	hud_layer.hide()
	left_hand.hide()
	right_hand.hide()
	stream.hide()
	hide()

	if toilet_ghost and toilet_ghost.has_method("reset"):
		toilet_ghost.reset()

	var was_success = (current_state == MinigameState.SUCCESS)

	if camera_pivot:
		if "yaw_clamp_active" in player:
			player.yaw_clamp_active = false
			player.pitch_clamp_min = -PI/2
			player.pitch_clamp_max = PI/2

		var tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(player, "global_position", saved_player_position, camera_transition_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(player, "rotation:y", saved_yaw, camera_transition_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(camera_pivot, "rotation:x", saved_pitch, camera_transition_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

		# We need to wait for the tween to finish, but since it's parallel, waiting for the last property is sufficient, or chaining a callback.
		tween.chain().tween_callback(func(): pass)
		await tween.finished

	# Unlock player
	if player:
		if player.has_method("set_physics_process"):
			player.set_physics_process(true)
		if player.has_method("set_held_item_visibility"):
			player.set_held_item_visibility(true)

	# Release the toilet's occupancy gate - main's Toilet expects this call
	# (it doesn't listen for session_ended; it's driven directly).
	if is_instance_valid(_toilet) and _toilet.has_method("end_session"):
		_toilet.call("end_session")

	# Reset state
	current_state = MinigameState.IDLE
	_wait_for_interact_release = false
	player = null
	_toilet = null

	session_ended.emit(was_success)
