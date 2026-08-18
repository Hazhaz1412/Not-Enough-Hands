extends Node3D
class_name ToiletMinigame

enum MinigameState { IDLE, PLAYING, SUCCESS, CANCELLED }

var current_state: MinigameState = MinigameState.IDLE
var player: Node3D

signal session_ended(success: bool)
signal minigame_state_changed(state: String)
signal minigame_effect_requested(effect: String)

# Asset Pipeline
@export var balance_asset: PackedScene = preload("res://objects/toilet/assets/water_nozzle.tscn")
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

# HUD Elements
@onready var bladder_bar: ProgressBar = $HUDLayer/MarginContainer/VBoxContainer/StatusArea/BladderContainer/ProgressBar
@onready var health_bar: ProgressBar = $HUDLayer/MarginContainer/VBoxContainer/StatusArea/HealthContainer/ProgressBar
@onready var feedback_label: Label = $HUDLayer/MarginContainer/VBoxContainer/FeedbackLabel
@onready var hud_layer: CanvasLayer = $HUDLayer

# Configurable Parameters
@export var nozzle_control_speed: float = 1.5
@export var nozzle_max_offset: float = 0.5
@export var oscillation_speed: float = 5.0
@export var oscillation_amplitude: float = 0.08
@export var movement_smoothing: float = 8.0
@export var camera_transition_duration: float = 0.25

@export var min_camera_rotation_x: float = -90.0
@export var max_camera_rotation_x: float = 90.0

@export var min_camera_rotation_y: float = -90.0
@export var max_camera_rotation_y: float = 90.0

@export var min_camera_rotation_z: float = -90.0
@export var max_camera_rotation_z: float = 90.0

@export var bladder_drain_rate: float = 20.0
@export var damage_delay: float = 1.0
@export var damage_amount: float = 10.0

@export var safe_zone_width: float = 0.1
@export var warning_zone_width: float = 0.3

# Internal state
var damage_timer: float = 0.0
var time_passed: float = 0.0
var player_offset: float = 0.0
const TARGET_CENTER_X = 0.0

# Camera handling
var saved_player_position: Vector3
var saved_pitch: float
var original_camera: Camera3D
var camera_pivot: Node3D

func _ready() -> void:
	hud_layer.hide()
	left_hand.hide()
	right_hand.hide()
	stream.hide()
	hide()
	
	_load_asset()

func _load_asset() -> void:
	if not balance_asset: return
	
	if instantiated_asset:
		instantiated_asset.queue_free()
		
	instantiated_asset = balance_asset.instantiate()
	asset_anchor.add_child(instantiated_asset)
	
	left_grip = instantiated_asset.get_node_or_null("LeftGrip") as Marker3D
	right_grip = instantiated_asset.get_node_or_null("RightGrip") as Marker3D
	liquid_origin = instantiated_asset.get_node_or_null("LiquidOrigin") as Marker3D

func start_session(p_player: Node3D, minigame_viewpoint: Marker3D) -> void:
	if current_state != MinigameState.IDLE:
		return
		
	player = p_player
	current_state = MinigameState.PLAYING
	
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

func _process(delta: float) -> void:
	if current_state != MinigameState.PLAYING:
		return
		
	_handle_input(delta)
	_update_visuals(delta)
	_evaluate_balance(delta)
	_update_status_bars()

func _unhandled_input(event: InputEvent) -> void:
	if current_state != MinigameState.PLAYING:
		return
		
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		cancel()

func _handle_input(delta: float) -> void:
	var input_dir = Input.get_axis("move_left", "move_right")
	player_offset += input_dir * nozzle_control_speed * delta
	player_offset = clamp(player_offset, -nozzle_max_offset, nozzle_max_offset)

func _update_visuals(delta: float) -> void:
	time_passed += delta
	
	# Calculate total position
	var auto_offset = sin(time_passed * oscillation_speed) * oscillation_amplitude
	var target_x = TARGET_CENTER_X + auto_offset + player_offset
	
	var max_x = 0.37
	target_x = clamp(target_x, -max_x, max_x)
	
	# Move Anchor smoothly
	asset_anchor.position.x = lerp(asset_anchor.position.x, target_x, movement_smoothing * delta)
	
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
	
	if distance <= (safe_zone_width / 2.0):
		# CENTERED ZONE
		feedback_label.text = "CENTERED"
		feedback_label.add_theme_color_override("font_color", Color.GREEN)
		if stream.material_override:
			var mat = stream.material_override as StandardMaterial3D
			mat.albedo_color = Color(0.4, 0.7, 1.0, 0.8)
		stream.show()
		damage_timer = 0.0
		
		if player and player.get("bladder"):
			var bladder = player.bladder
			if bladder.get_value() <= 0:
				succeed()
			else:
				bladder.reduce(bladder_drain_rate * delta)
				if bladder.get_value() <= 0:
					succeed()
					
	elif distance <= (warning_zone_width / 2.0):
		# UNSTABLE ZONE
		feedback_label.text = "UNSTABLE"
		feedback_label.add_theme_color_override("font_color", Color.YELLOW)
		if stream.material_override:
			var mat = stream.material_override as StandardMaterial3D
			mat.albedo_color = Color(0.8, 0.8, 0.2, 0.4)
		stream.show()
		damage_timer = 0.0
	else:
		# DANGER ZONE
		feedback_label.text = "DANGER!"
		feedback_label.add_theme_color_override("font_color", Color.RED)
		stream.hide()
		
		damage_timer += delta
		if damage_timer >= damage_delay:
			damage_timer = 0.0
			if player and player.has_method("take_damage"):
				player.take_damage(damage_amount)
				minigame_effect_requested.emit("damage_taken")

func _update_status_bars() -> void:
	if not player: return
	
	if player.get("bladder"):
		bladder_bar.max_value = player.bladder.max_value
		bladder_bar.value = player.bladder.current_value
		
	if "current_health" in player and "max_health" in player:
		health_bar.max_value = player.max_health
		health_bar.value = player.current_health

func succeed() -> void:
	if current_state != MinigameState.PLAYING: return
	current_state = MinigameState.SUCCESS
	minigame_state_changed.emit("SUCCESS")
	
	feedback_label.text = "SUCCESS!"
	feedback_label.add_theme_color_override("font_color", Color.GREEN)
	stream.hide()
	await get_tree().create_timer(1.0).timeout
	
	_cleanup()

func cancel() -> void:
	if current_state != MinigameState.PLAYING: return
	current_state = MinigameState.CANCELLED
	minigame_state_changed.emit("CANCELLED")
	
	feedback_label.text = "CANCELLED!"
	feedback_label.add_theme_color_override("font_color", Color.GRAY)
	stream.hide()
	await get_tree().create_timer(0.5).timeout
	
	_cleanup()

func _cleanup() -> void:
	hud_layer.hide()
	left_hand.hide()
	right_hand.hide()
	stream.hide()
	hide()
	
	var was_success = (current_state == MinigameState.SUCCESS)
	
	if camera_pivot:
		if "yaw_clamp_active" in player:
			player.yaw_clamp_active = false
			player.pitch_clamp_min = -PI/2
			player.pitch_clamp_max = PI/2
			
		var tween = create_tween()
		tween.tween_property(player, "global_position", saved_player_position, camera_transition_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		await tween.finished
	
	# Unlock player
	if player:
		if player.has_method("set_physics_process"):
			player.set_physics_process(true)
		if player.has_method("set_held_item_visibility"):
			player.set_held_item_visibility(true)
	
	# Reset state
	current_state = MinigameState.IDLE
	player = null
	
	session_ended.emit(was_success)
