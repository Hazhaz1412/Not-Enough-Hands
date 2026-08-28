extends CharacterBody3D

signal eyes_closed_changed(closed: bool)
signal killed_by_ghost(ghost: Node3D)
signal door_minigame_started(door: Node)
signal door_minigame_finished()
signal fusebox_minigame_started(fusebox: Node)
signal hunter_trap_changed(trapped: bool)
signal toilet_ghost_stun_changed(active: bool)

@export var walk_speed: float = 4
@export var crouch_speed: float = 1.75
@export var sprint_speed_multiplier: float = 2.5
@export var jump_velocity: float = 4.2
@export var player_radius: float = 0.32
@export var crouch_height: float = 1.05
@export var standing_height: float = 1.75
@export var crouch_camera_height: float = 0.05
@export var standing_camera_height: float = 0.62
@export var crouch_transition_speed: float = 10.0
@export var max_step_height: float = 0.6
@export var step_floor_margin: float = 0.08
## Minimum forward reach used when probing for a landing on top of a step.
## A single frame's real motion (often just a few cm at walk speed) isn't
## enough to clear the riser's front edge, so the down-cast lands back on
## the riser's near-vertical face instead of the flat tread and the whole
## step-up silently fails every frame.
@export var step_probe_distance: float = 0.3

@export_category("Camera Feel")
@export var head_bob_frequency: float = 8.0
@export var head_bob_horizontal: float = 0.012
@export var head_bob_vertical: float = 0.018

@export_category("Movement Audio")
@export var walk_step_interval: float = 0.48
@export var sprint_step_interval: float = 0.34
@export var crouch_step_interval: float = 0.7
@export var footstep_slice_duration: float = 0.38

@export_category('Blink')
@export var automatic_blink_enabled: bool = true
@export var blink_interval: float = 7.0
@export var forced_blink_duration: float = 0.22
@export var eyelid_transition_speed: float = 16.0

var is_crouching: bool = false
@export var max_stamina: float = 100.0
@export var sprint_stamina_drain: float = 20.0
@export var stamina_regen_idle: float = 20.0
@export var stamina_regen_moving: float = 5.0

var current_stamina: float = max_stamina
var head_bob_time: float = 0.0
var eyes_closed: bool = false
var is_alive: bool = true
var blink_time_remaining: float = blink_interval
var forced_blink_remaining: float = 0.0
## Highest threat currently reported by any ghost - drives the horror overlay
## and the camera sway. Kept under its original name because the shader
## parameter and the camera code already read it.
var statue_threat: float = 0.0
var threat_sources: Dictionary = {}
var eyelid_closure: float = 0.0
@export var mouse_sensitivity: float = 0.002
@export var max_interaction_range: float = 10.0

@export_category("Toilet Ghost Stun")
## Getting caught by the Toilet Ghost is a severe scare, not a death. The
## player keeps control but moves at 20% speed while the vision effect runs.
@export var toilet_ghost_stun_duration: float = 7.0
@export_range(0.05, 1.0) var toilet_ghost_stun_speed_multiplier: float = 0.2
@export var toilet_ghost_stun_fade_duration: float = 0.75
## Keep enough center light to read the room; the shortened beam and vignette
## still make the ghost's arrival oppressive without making it pitch-black.
@export_range(0.0, 1.0) var toilet_ghost_flashlight_energy_multiplier: float = 0.5
@export_range(0.0, 1.0) var toilet_ghost_flashlight_range_multiplier: float = 0.55
var toilet_ghost_stun_remaining: float = 0.0
var _toilet_ghost_present: bool = false
var _flashlight_base_energy: float = 0.0
var _flashlight_base_range: float = 0.0

## Temporary look-around constraint a minigame can impose (currently only
## ToiletMinigame) - false/full-range outside any minigame, so normal
## mouse-look is unaffected. yaw is clamped via an accumulator (rotate_y()
## itself has no absolute angle to read back) while pitch is clamped
## directly on camera_pivot.rotation.x like the un-constrained case already
## does, just with configurable bounds instead of the hardcoded +-PI/2.
var yaw_clamp_active: bool = false
var yaw_clamp_min: float = 0.0
var yaw_clamp_max: float = 0.0
var accumulated_yaw: float = 0.0
var pitch_clamp_min: float = -PI / 2.0
var pitch_clamp_max: float = PI / 2.0

@export_category("Development")
@export var minigame_ghost_resume_grace: float = 1.5
@export var dev_speed_multiplier: float = 3.0

var dev_invincible: bool = false
var dev_fast_movement: bool = false
var dev_noclip: bool = false
var dev_clear_vision: bool = false
var _blink_before_clear_vision: bool = true
var _dev_vision_light: OmniLight3D
var hunter_trap_source: Node3D

@onready var camera_pivot: Node3D = $CameraPivot
@onready var interact_ray: RayCast3D = $CameraPivot/Camera3D/InteractRay
@onready var flashlight: SpotLight3D = $CameraPivot/Camera3D/Flashlight
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var blink_overlay: ColorRect = $BlinkOverlay/Eyelids
@onready var blink_bar: ProgressBar = $BlinkUI/BlinkContainer/VBoxContainer/BlinkBar
@onready var horror_overlay_rect: ColorRect = $HorrorOverlay/VignetteAndGrain
@onready var death_ui: CanvasLayer = $DeathUI
@onready var footstep_players: Array[AudioStreamPlayer3D] = [$FootstepA, $FootstepB]
@onready var door_minigame: CanvasLayer = get_node_or_null("DoorGhostMinigame") as CanvasLayer
@onready var fusebox_minigame: CanvasLayer = get_node_or_null("FuseboxMinigame") as CanvasLayer
@onready var equipment: PlayerEquipment = $Equipment
@onready var bladder: PlayerBladder = $Bladder

## Set by start_toilet_minigame() for the duration of this player's session -
## ToiletMinigame lives per-toilet, not as a fixed child of Player like
## DoorGhostMinigame, since only one toilet can ever be occupied by this
## player at a time.
var _active_toilet_minigame: Node = null

var _minigame_ghost_safety_locks: int = 0
var _minigame_ghost_release_remaining: float = 0.0

# Transient starts extracted once from the source recording. Keeping these
# authored offsets avoids scanning several megabytes of PCM every time a player
# spawns (important once four network players are present).
var _footstep_offsets: Array[float] = [
	1.6143,
	6.6620,
	7.7615,
	9.4607,
	10.0604,
	11.1849,
	11.7097,
	12.3844,
	14.4834,
	15.2081,
	19.4062,
	28.4271,
	28.9019,
	29.4766,
	30.0264,
	31.1509,
	32.2504,
	33.3249,
]
var _footstep_stop_times: Array[float] = [0.0, 0.0]
var _footstep_time_remaining: float = 0.0
var _footstep_player_index: int = 0
var _last_footstep_offset_index: int = -1
var _was_walking_on_floor: bool = false
var _footstep_rng := RandomNumberGenerator.new()

# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready() -> void:
	_footstep_rng.randomize()
	current_stamina = max_stamina
	blink_time_remaining = blink_interval
	var shape := collision_shape.shape as CapsuleShape3D
	shape.radius = player_radius
	shape.height = standing_height
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if interact_ray:
		interact_ray.target_position = Vector3(0, 0, -max_interaction_range)
	if flashlight:
		_flashlight_base_energy = flashlight.light_energy
		_flashlight_base_range = flashlight.spot_range


## Status visuals keep ticking while a minigame temporarily disables this
## body's physics. That makes a seven-second Toilet Ghost stun seven seconds
## of real gameplay time, including the brief camera-release transition.
func _process(delta: float) -> void:
	_update_toilet_ghost_stun(delta)

func _unhandled_input(event: InputEvent) -> void:
	if not is_alive:
		return
	if _is_alt_toggle_event(event):
		toggle_mouse_capture()
		get_viewport().set_input_as_handled()
		return
	if is_door_minigame_active():
		return

	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		# Rotate player horizontally - clamped to a limited look-around
		# window while yaw_clamp_active (e.g. ToiletMinigame), full range
		# otherwise.
		var yaw_delta: float = -event.relative.x * mouse_sensitivity
		if yaw_clamp_active:
			var new_yaw: float = clamp(accumulated_yaw + yaw_delta, yaw_clamp_min, yaw_clamp_max)
			yaw_delta = new_yaw - accumulated_yaw
			accumulated_yaw = new_yaw
		rotate_y(yaw_delta)

		# Rotate camera vertically, clamped to pitch_clamp_min/max (+-90
		# degrees normally, narrower while a minigame constrains it).
		camera_pivot.rotate_x(-event.relative.y * mouse_sensitivity)
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, pitch_clamp_min, pitch_clamp_max)

	if is_any_minigame_active():
		return

	if event.is_action_pressed("interact"):
		_try_interact()
	if event.is_action_pressed("drop_item"):
		_drop_selected_item()
	if event.is_action_pressed("select_slot_1"):
		equipment.select_slot(0)
	if event.is_action_pressed("select_slot_2"):
		equipment.select_slot(1)
	if event is InputEventMouseButton and event.pressed:
		# Only 2 slots exist, so "next" and "previous" are both just "the
		# other slot" - same select_slot() the keyboard shortcuts use.
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			equipment.select_slot(1 - equipment.selected_slot)


func toggle_mouse_capture() -> void:
	Input.set_mouse_mode(get_toggled_mouse_mode(Input.get_mouse_mode()))


func get_toggled_mouse_mode(current_mode: Input.MouseMode) -> Input.MouseMode:
	return (
		Input.MOUSE_MODE_VISIBLE
		if current_mode == Input.MOUSE_MODE_CAPTURED
		else Input.MOUSE_MODE_CAPTURED
	)


func _is_alt_toggle_event(event: InputEvent) -> bool:
	return (
		event is InputEventKey
		and event.pressed
		and not event.echo
		and (event.keycode == KEY_ALT or event.physical_keycode == KEY_ALT)
	)


func get_interaction_target() -> Node:
	if not interact_ray or not interact_ray.is_colliding():
		return null

	var target := interact_ray.get_collider() as Node
	while target and target != get_tree().root:
		# Component-based interactables: a child node literally named
		# "Interactable" is the actual interaction target, not its parent -
		# the player calls interact()/can_interact() on the component itself.
		var component := target.get_node_or_null("Interactable")
		if component and component.has_method("interact"):
			return component
		if target.has_method("interact"):
			return target
		target = target.get_parent()

	return null


func can_interact_with(target: Node) -> bool:
	if not target or not interact_ray.is_colliding():
		return false

	if target.has_method("can_interact") and not target.can_interact():
		return false

	var allowed_range: float = target.interaction_range if "interaction_range" in target else 2.5
	var hit_distance := interact_ray.global_position.distance_to(interact_ray.get_collision_point())
	return hit_distance <= minf(allowed_range, max_interaction_range)


func _try_interact() -> void:
	interact_ray.force_raycast_update()
	var target := get_interaction_target()
	if target and can_interact_with(target):
		target.interact(self)


## Called by a PickupItem's own script when its Interactable fires - mirrors
## set_threat_from()/kill_by_ghost(): other systems call into the player's
## public API, the player never reaches into item internals. Returns false
## (leaving the item untouched in the world) when both equipment slots are
## already full.
func try_pick_up_item(item: Node3D) -> bool:
	if not equipment.try_add_item(item):
		return false
	if item.has_method("set_held"):
		item.set_held(true)
	item.reparent(self)
	return true


## Q drops whatever is in the currently selected equipment slot; does nothing
## if that slot is empty.
func _drop_selected_item() -> void:
	var item: Node3D = equipment.remove_selected()
	if item == null:
		return
	item.reparent(get_tree().root)
	item.global_position = (
		global_position
		+ Vector3(0, standing_camera_height, 0)
		+ (-global_transform.basis.z) * 1.2
	)
	item.global_rotation = Vector3.ZERO
	if item.has_method("set_held"):
		item.set_held(false)


func _physics_process(delta: float) -> void:
	_update_minigame_ghost_safety(delta)
	if is_any_minigame_active():
		_open_eyes_for_minigame()
		velocity = Vector3.ZERO
		_stop_footsteps()
		return

	_update_blink(delta)
	if not is_alive:
		velocity = Vector3.ZERO
		_stop_footsteps()
		return

	if dev_noclip:
		_fly(delta)
		return

	var was_on_floor := is_on_floor()
	if is_trapped_by_hunter():
		velocity.x = 0.0
		velocity.z = 0.0
		if not was_on_floor:
			velocity.y -= gravity * delta
		elif velocity.y < 0.0:
			velocity.y = 0.0
		move_and_slide()
		_stop_footsteps()
		return

	# Add the gravity.
	if not was_on_floor:
		velocity.y -= gravity * delta

	# Handle Jump
	if Input.is_action_just_pressed("jump") and is_on_floor():
		if is_crouching:
			if _can_stand():
				_stand_up()
				velocity.y = jump_velocity
		else:
			velocity.y = jump_velocity

	# Handle Crouch
	if Input.is_action_pressed("crouch"):
		if not is_crouching:
			_crouch()
	else:
		if is_crouching:
			if _can_stand():
				_stand_up()

	# Get the input direction and handle the movement/deceleration.
	# Input.get_vector automatically normalizes diagonal input
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	var is_sprinting = false
	if direction != Vector3.ZERO and Input.is_action_pressed("run") and current_stamina > 0.0 and not is_crouching:
		is_sprinting = true

	var current_speed = walk_speed
	
	if is_sprinting:
		current_speed = walk_speed * sprint_speed_multiplier
		current_stamina -= sprint_stamina_drain * delta
	else:
		if is_crouching:
			current_speed = crouch_speed
			
		if direction == Vector3.ZERO:
			current_stamina += stamina_regen_idle * delta
		else:
			current_stamina += stamina_regen_moving * delta

	if dev_fast_movement:
		current_speed *= maxf(dev_speed_multiplier, 1.0)
		current_stamina = max_stamina
	if is_toilet_ghost_stunned():
		current_speed *= get_toilet_ghost_speed_multiplier()
			
	current_stamina = clamp(current_stamina, 0.0, max_stamina)

	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)

	_update_camera_motion(delta)

	if was_on_floor and velocity.y <= 0.0:
		var horizontal_motion := Vector3(velocity.x, 0.0, velocity.z) * delta
		_try_step_up(horizontal_motion)

	move_and_slide()
	_update_footsteps(delta, is_sprinting)


func _update_blink(delta: float) -> void:
	var was_closed := eyes_closed
	var manual_close := Input.is_action_pressed('blink') and is_alive

	if manual_close:
		eyes_closed = true
		blink_time_remaining = blink_interval
	elif forced_blink_remaining > 0.0:
		eyes_closed = true
		forced_blink_remaining = maxf(forced_blink_remaining - delta, 0.0)
	else:
		eyes_closed = false
		if automatic_blink_enabled and is_alive:
			blink_time_remaining -= delta
			if blink_time_remaining <= 0.0:
				forced_blink_remaining = forced_blink_duration
				blink_time_remaining = blink_interval
				eyes_closed = true

	var target_closure := 1.0 if eyes_closed else 0.0
	eyelid_closure = move_toward(
		eyelid_closure,
		target_closure,
		eyelid_transition_speed * delta
	)
	var eyelid_material := blink_overlay.material as ShaderMaterial
	if eyelid_material:
		eyelid_material.set_shader_parameter('closure', eyelid_closure)

	if blink_bar:
		blink_bar.value = clampf(blink_time_remaining / maxf(blink_interval, 0.01), 0.0, 1.0) * 100.0

	if was_closed != eyes_closed:
		eyes_closed_changed.emit(eyes_closed)


func force_blink(duration: float = -1.0) -> void:
	# Ghosts force blinks to blind the player. That is exactly the kind of
	# thing clear vision exists to switch off.
	if dev_clear_vision:
		return
	forced_blink_remaining = forced_blink_duration if duration < 0.0 else duration
	blink_time_remaining = blink_interval
	if not eyes_closed and is_alive:
		eyes_closed = true
		eyes_closed_changed.emit(true)


## Minigame-safe variant of force_blink(): the eyelid animation and
## forced_blink_remaining's own countdown are both driven by _update_blink(),
## which only runs from _physics_process() - and minigames such as the
## toilet's disable physics processing for their whole duration to lock the
## player. Plain force_blink() would therefore set the logical state but
## never actually animate, and would only resolve once physics processing
## resumes after the minigame already ended (a blink playing out of
## context). This sets the eyelid shader parameter directly instead -
## mirroring _open_eyes_for_minigame()'s existing "set it directly" pattern
## for the opposite case - so the close reads immediately regardless of
## whether physics processing is running. The caller owns reopening (see
## end_forced_blink()) since there is no running update loop left to expire
## forced_blink_remaining on its own.
func force_blink_now() -> void:
	if dev_clear_vision or not is_alive:
		return
	forced_blink_remaining = forced_blink_duration
	eyelid_closure = 1.0
	var eyelid_material := blink_overlay.material as ShaderMaterial
	if eyelid_material:
		eyelid_material.set_shader_parameter('closure', 1.0)
	if not eyes_closed:
		eyes_closed = true
		eyes_closed_changed.emit(true)


## Reopens eyes closed by force_blink_now(), independent of _physics_process -
## see that method's doc comment for why this is needed. Safe to call even
## if force_blink_now() was never actually called (e.g. cleanup running
## unconditionally).
func end_forced_blink() -> void:
	if not eyes_closed and forced_blink_remaining <= 0.0 and eyelid_closure <= 0.0:
		return
	forced_blink_remaining = 0.0
	eyelid_closure = 0.0
	eyes_closed = false
	var eyelid_material := blink_overlay.material as ShaderMaterial
	if eyelid_material:
		eyelid_material.set_shader_parameter('closure', 0.0)
	eyes_closed_changed.emit(false)


func set_statue_threat(amount: float) -> void:
	set_threat_from('statue', amount)


## Threat is tracked per source and the overlay shows the worst of them. Two
## ghosts both writing a single shared value every physics frame would fight
## over it, and whichever ran second would win - so a crawler two rooms away
## could silently erase the dread of a statue standing behind you.
func set_threat_from(source: StringName, amount: float) -> void:
	if is_protected_from_ghost_attacks():
		amount = 0.0
	var clamped := clampf(amount, 0.0, 1.0)
	if clamped <= 0.0:
		threat_sources.erase(source)
	else:
		threat_sources[source] = clamped

	statue_threat = 0.0
	for value: float in threat_sources.values():
		statue_threat = maxf(statue_threat, value)

	var overlay_material := horror_overlay_rect.material as ShaderMaterial
	if overlay_material:
		overlay_material.set_shader_parameter('threat_strength', statue_threat)


func kill_by_ghost(ghost: Node3D) -> void:
	if not is_alive or is_protected_from_ghost_attacks():
		return
	is_alive = false
	forced_blink_remaining = 0.0
	eyes_closed = false
	velocity = Vector3.ZERO
	_stop_footsteps()
	if death_ui.has_method("show_jumpscare"):
		death_ui.call("show_jumpscare", ghost)
	else:
		death_ui.visible = true
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	killed_by_ghost.emit(ghost)


## Public status-effect API used by the Toilet Ghost minigame. Reapplying the
## scare refreshes (never stacks) the duration, so the speed multiplier cannot
## be compounded into an accidental immobilize.
func apply_toilet_ghost_stun(duration: float = -1.0) -> bool:
	if not is_alive or dev_invincible:
		return false
	var resolved_duration := (
		toilet_ghost_stun_duration
		if duration < 0.0
		else duration
	)
	if resolved_duration <= 0.0:
		return false
	var was_active := is_toilet_ghost_stunned()
	toilet_ghost_stun_remaining = maxf(toilet_ghost_stun_remaining, resolved_duration)
	velocity.x *= get_toilet_ghost_speed_multiplier()
	velocity.z *= get_toilet_ghost_speed_multiplier()
	_set_toilet_ghost_stun_visual(1.0)
	if not was_active:
		toilet_ghost_stun_changed.emit(true)
	return true


func is_toilet_ghost_stunned() -> bool:
	return toilet_ghost_stun_remaining > 0.0


func get_toilet_ghost_speed_multiplier() -> float:
	return clampf(toilet_ghost_stun_speed_multiplier, 0.05, 1.0)


func _update_toilet_ghost_stun(delta: float) -> void:
	if toilet_ghost_stun_remaining <= 0.0:
		return
	toilet_ghost_stun_remaining = maxf(toilet_ghost_stun_remaining - delta, 0.0)
	var visual_strength := clampf(
		toilet_ghost_stun_remaining / maxf(toilet_ghost_stun_fade_duration, 0.01),
		0.0,
		1.0
	)
	_set_toilet_ghost_stun_visual(visual_strength)
	if toilet_ghost_stun_remaining <= 0.0:
		toilet_ghost_stun_changed.emit(false)


func _set_toilet_ghost_stun_visual(strength: float) -> void:
	var overlay_material := horror_overlay_rect.material as ShaderMaterial
	if overlay_material:
		overlay_material.set_shader_parameter("stun_strength", clampf(strength, 0.0, 1.0))


## Called by the Toilet Ghost only while its body is actually visible. The
## narrowed, dim flashlight makes finding it a visual task; it does not reveal
## a lurch through an audio cue.
func set_toilet_ghost_presence(present: bool) -> void:
	_toilet_ghost_present = present
	if flashlight:
		flashlight.light_energy = (
			_flashlight_base_energy * toilet_ghost_flashlight_energy_multiplier
			if present
			else _flashlight_base_energy
		)
		flashlight.spot_range = (
			_flashlight_base_range * toilet_ghost_flashlight_range_multiplier
			if present
			else _flashlight_base_range
		)
	var overlay_material := horror_overlay_rect.material as ShaderMaterial
	if overlay_material:
		overlay_material.set_shader_parameter("toilet_presence", 1.0 if present else 0.0)


func start_door_minigame(door: Node) -> bool:
	if not is_alive \
		or not door_minigame \
		or is_any_minigame_active() \
		or not is_instance_valid(door):
		return false
	if not door.has_method("begin_exorcism") or not bool(door.call("begin_exorcism")):
		return false
	if not door_minigame.has_method("start") or not bool(door_minigame.call("start", self, door)):
		door.call("cancel_exorcism")
		return false
	door_minigame_started.emit(door)
	return true


func is_door_minigame_active() -> bool:
	return door_minigame != null \
		and door_minigame.has_method("is_running") \
		and bool(door_minigame.call("is_running"))


func start_fusebox_minigame(fusebox: Node) -> bool:
	if not is_alive \
		or not fusebox_minigame \
		or is_any_minigame_active() \
		or not is_instance_valid(fusebox):
		return false
	if not fusebox_minigame.has_method("start") or not bool(fusebox_minigame.call("start", self, fusebox)):
		return false
	fusebox_minigame_started.emit(fusebox)
	return true


func is_fusebox_minigame_active() -> bool:
	return fusebox_minigame != null \
		and fusebox_minigame.has_method("is_running") \
		and bool(fusebox_minigame.call("is_running"))


## Called by a Toilet's own script when interacted with - mirrors
## start_door_minigame(): the toilet never reaches into player internals,
## it just calls this public API the same way PickupItem/LightSwitch do.
## Unlike DoorGhostMinigame, ToiletMinigame is owned per-toilet (a child of
## the Toilet, matching feat/game-character-hoang's node structure) rather
## than pre-instantiated per-player, so it's resolved from `toilet` here and
## the reference kept only for as long as this player's session lasts.
func start_toilet_minigame(toilet: Node) -> bool:
	if not is_alive or is_any_minigame_active() or not is_instance_valid(toilet):
		return false
	var minigame: Node = toilet.get_node_or_null("ToiletMinigame")
	if not minigame or not minigame.has_method("start"):
		return false
	if not bool(minigame.call("start", self, toilet)):
		return false
	_active_toilet_minigame = minigame
	return true


func is_toilet_minigame_active() -> bool:
	return is_instance_valid(_active_toilet_minigame) \
		and _active_toilet_minigame.has_method("is_running") \
		and bool(_active_toilet_minigame.call("is_running"))


## Shared "freeze movement/look, don't fight the minigame for input" gate.
## Covers every minigame that can own the screen: door, fusebox, and toilet.
## The fusebox minigame deliberately never calls acquire_minigame_ghost_safety
## - a miss there is meant to be heard - so ghost suspension stays keyed off
## the door minigame alone; this only covers input/movement ownership.
func is_any_minigame_active() -> bool:
	return is_door_minigame_active() or is_fusebox_minigame_active() or is_toilet_minigame_active()


## Thin delegation to this player's own Bladder component - other systems
## (the toilet minigame, its HUD) call these instead of touching bladder
## internals directly, the same way try_pick_up_item()/equipment work.
func get_bladder() -> float:
	return bladder.get_bladder()


func get_bladder_ratio() -> float:
	return bladder.get_bladder_ratio()


func add_bladder(amount: float) -> void:
	bladder.add_bladder(amount)


func reduce_bladder(amount: float) -> void:
	bladder.reduce_bladder(amount)


func set_bladder(value: float) -> void:
	bladder.set_bladder(value)


## Called by ToiletMinigame on success - the only bladder ever touched is
## this player's own, and only because this player is the one who reached
## the toilet minigame's success state.
func reset_bladder() -> void:
	bladder.reset_bladder()


func acquire_minigame_ghost_safety() -> void:
	_minigame_ghost_safety_locks += 1
	_minigame_ghost_release_remaining = 0.0
	if _minigame_ghost_safety_locks == 1:
		get_tree().call_group("hostile_ghosts", "set_dev_attack_suspended", true)
	_clear_all_ghost_threat()


func release_minigame_ghost_safety() -> void:
	_minigame_ghost_safety_locks = maxi(_minigame_ghost_safety_locks - 1, 0)
	if _minigame_ghost_safety_locks == 0:
		_minigame_ghost_release_remaining = maxf(minigame_ghost_resume_grace, 0.0)
		if _minigame_ghost_release_remaining <= 0.0:
			get_tree().call_group("hostile_ghosts", "set_dev_attack_suspended", false)
			door_minigame_finished.emit()


func is_protected_from_ghost_attacks() -> bool:
	return dev_invincible \
		or _minigame_ghost_safety_locks > 0 \
		or _minigame_ghost_release_remaining > 0.0


func can_be_targeted_by_ghosts() -> bool:
	return is_alive and not is_protected_from_ghost_attacks()


func apply_hunter_trap(source: Node3D) -> bool:
	if not is_alive or is_protected_from_ghost_attacks() or is_trapped_by_hunter():
		return false
	hunter_trap_source = source
	velocity.x = 0.0
	velocity.z = 0.0
	_stop_footsteps()
	hunter_trap_changed.emit(true)
	return true


func release_from_hunter_trap(source: Node3D = null) -> void:
	if not is_instance_valid(hunter_trap_source):
		hunter_trap_source = null
		return
	if is_instance_valid(source) and hunter_trap_source != source:
		return
	hunter_trap_source = null
	hunter_trap_changed.emit(false)


func is_trapped_by_hunter() -> bool:
	if is_instance_valid(hunter_trap_source) and hunter_trap_source.is_inside_tree():
		return true
	if hunter_trap_source != null:
		hunter_trap_source = null
		hunter_trap_changed.emit(false)
	return false


func set_dev_invincible(enabled: bool) -> void:
	dev_invincible = enabled
	if enabled:
		_clear_all_ghost_threat()


func set_dev_fast_movement(enabled: bool) -> void:
	dev_fast_movement = enabled
	if enabled:
		current_stamina = max_stamina


## Free flight with collision switched off, for inspecting a map from inside
## it. The capsule's shape is disabled rather than its layers, so nothing can
## push the player around while they are clipping through walls.
func set_dev_noclip(enabled: bool) -> void:
	dev_noclip = enabled
	collision_shape.disabled = enabled
	if enabled:
		velocity = Vector3.ZERO
		_stop_footsteps()


## Strips every effect that makes the house hard to read: the vignette and
## grain, the threat distortion, the involuntary blinking, and the darkness
## itself. The environment side of it (fog, ambient) belongs to the scene, so
## DevTools handles that; this covers everything the player owns.
func set_dev_clear_vision(enabled: bool) -> void:
	dev_clear_vision = enabled
	horror_overlay_rect.visible = not enabled

	if enabled:
		_blink_before_clear_vision = automatic_blink_enabled
		automatic_blink_enabled = false
		forced_blink_remaining = 0.0
		blink_time_remaining = blink_interval
		eyes_closed = false
		eyelid_closure = 0.0
		var eyelid_material := blink_overlay.material as ShaderMaterial
		if eyelid_material:
			eyelid_material.set_shader_parameter("closure", 0.0)
		var overlay_material := horror_overlay_rect.material as ShaderMaterial
		if overlay_material:
			overlay_material.set_shader_parameter("threat_strength", 0.0)
	else:
		automatic_blink_enabled = _blink_before_clear_vision

	if not _dev_vision_light:
		_dev_vision_light = OmniLight3D.new()
		_dev_vision_light.name = "DevVisionLight"
		# Wide and soft rather than bright and tight: the point is to read the
		# room you are standing in, not to cast a second flashlight beam.
		_dev_vision_light.light_energy = 1.1
		_dev_vision_light.omni_range = 18.0
		_dev_vision_light.omni_attenuation = 1.2
		_dev_vision_light.light_color = Color(0.92, 0.95, 1.0)
		camera_pivot.add_child(_dev_vision_light)
	_dev_vision_light.visible = enabled


## Camera-relative flight: WASD follows where you are looking, Space and Ctrl
## are straight up and down. Position is written directly, so no collision,
## gravity or step-up logic gets a say.
func _fly(delta: float) -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var camera_basis := camera_pivot.global_basis
	var motion := (
		camera_basis * Vector3(input_dir.x, 0.0, input_dir.y)
		+ Vector3.UP * (
			(1.0 if Input.is_action_pressed("jump") else 0.0)
			- (1.0 if Input.is_action_pressed("crouch") else 0.0)
		)
	)
	var speed := walk_speed * 3.0
	if Input.is_action_pressed("run"):
		speed *= 3.0
	if dev_fast_movement:
		speed *= maxf(dev_speed_multiplier, 1.0)

	velocity = motion.normalized() * speed if motion.length_squared() > 0.0 else Vector3.ZERO
	global_position += velocity * delta
	current_stamina = max_stamina
	_update_camera_motion(delta)
	_stop_footsteps()


func _update_minigame_ghost_safety(delta: float) -> void:
	if _minigame_ghost_safety_locks > 0 or _minigame_ghost_release_remaining <= 0.0:
		return
	_minigame_ghost_release_remaining = maxf(_minigame_ghost_release_remaining - delta, 0.0)
	if _minigame_ghost_release_remaining <= 0.0:
		get_tree().call_group("hostile_ghosts", "set_dev_attack_suspended", false)
		door_minigame_finished.emit()


func _clear_all_ghost_threat() -> void:
	threat_sources.clear()
	statue_threat = 0.0
	var overlay_material := horror_overlay_rect.material as ShaderMaterial
	if overlay_material:
		overlay_material.set_shader_parameter("threat_strength", 0.0)


func _open_eyes_for_minigame() -> void:
	var was_closed := eyes_closed
	forced_blink_remaining = 0.0
	eyes_closed = false
	eyelid_closure = 0.0
	var eyelid_material := blink_overlay.material as ShaderMaterial
	if eyelid_material:
		eyelid_material.set_shader_parameter("closure", 0.0)
	if was_closed:
		eyes_closed_changed.emit(false)


func _update_footsteps(delta: float, is_sprinting: bool) -> void:
	for index: int in _footstep_stop_times.size():
		if _footstep_stop_times[index] <= 0.0:
			continue
		_footstep_stop_times[index] -= delta
		if _footstep_stop_times[index] <= 0.0:
			footstep_players[index].stop()

	var real_velocity := get_real_velocity()
	var horizontal_speed := Vector2(real_velocity.x, real_velocity.z).length()
	var walking_on_floor := is_on_floor() and horizontal_speed > 0.25
	if not walking_on_floor:
		_was_walking_on_floor = false
		_footstep_time_remaining = 0.0
		return

	var interval := walk_step_interval
	if is_crouching:
		interval = crouch_step_interval
	elif is_sprinting:
		interval = sprint_step_interval

	if not _was_walking_on_floor:
		_play_wood_footstep(is_sprinting)
		_footstep_time_remaining = interval
	else:
		_footstep_time_remaining -= delta
		if _footstep_time_remaining <= 0.0:
			_play_wood_footstep(is_sprinting)
			_footstep_time_remaining += interval
	_was_walking_on_floor = true


func _play_wood_footstep(is_sprinting: bool) -> void:
	if footstep_players.is_empty() or _footstep_offsets.is_empty():
		return
	var offset_index := _footstep_rng.randi_range(0, _footstep_offsets.size() - 1)
	if offset_index == _last_footstep_offset_index and _footstep_offsets.size() > 1:
		offset_index = (offset_index + 1) % _footstep_offsets.size()
	_last_footstep_offset_index = offset_index

	var player_index := _footstep_player_index
	_footstep_player_index = (_footstep_player_index + 1) % footstep_players.size()
	var audio_player := footstep_players[player_index]
	var movement_pitch := 0.93 if is_crouching else (1.035 if is_sprinting else 1.0)
	audio_player.pitch_scale = movement_pitch * _footstep_rng.randf_range(0.965, 1.035)
	audio_player.volume_db = (
		_footstep_rng.randf_range(-12.5, -10.0)
		if is_crouching
		else _footstep_rng.randf_range(-7.5, -4.5) + (1.2 if is_sprinting else 0.0)
	)
	audio_player.play(_footstep_offsets[offset_index])
	_footstep_stop_times[player_index] = footstep_slice_duration


func _stop_footsteps() -> void:
	for audio_player: AudioStreamPlayer3D in footstep_players:
		audio_player.stop()
	_footstep_stop_times.fill(0.0)
	_was_walking_on_floor = false


func _update_camera_motion(delta: float) -> void:
	var target_height := crouch_camera_height if is_crouching else standing_camera_height
	var bob_offset := Vector2.ZERO
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()

	if is_on_floor() and horizontal_speed > 0.1:
		var speed_ratio := horizontal_speed / maxf(walk_speed, 0.1)
		head_bob_time += delta * head_bob_frequency * speed_ratio
		bob_offset.x = cos(head_bob_time * 0.5) * head_bob_horizontal
		bob_offset.y = sin(head_bob_time) * head_bob_vertical

	var target_position := Vector3(bob_offset.x, target_height + bob_offset.y, 0.0)
	var threat_wave := sin(Time.get_ticks_msec() * 0.019) * statue_threat
	target_position.x += threat_wave * 0.008
	var blend := minf(crouch_transition_speed * delta, 1.0)
	camera_pivot.position = camera_pivot.position.lerp(target_position, blend)
	camera_pivot.rotation.z = lerpf(camera_pivot.rotation.z, threat_wave * 0.006, blend)


func _try_step_up(horizontal_motion: Vector3) -> void:
	if horizontal_motion.is_zero_approx():
		return
	# A slope already supplies continuous vertical motion. Treating that plane
	# as a blocked horizontal step repeatedly teleports the capsule upward and
	# is exactly what made the old stair camera judder.
	if is_on_floor() and get_floor_normal().dot(up_direction) < 0.98:
		return

	# Only step when the normal movement is blocked by a near-vertical riser.
	# At the first frame of a ramp the previous floor normal is still flat, so
	# inspect the forward hit too and let move_and_slide() handle walkable slopes.
	var forward_collision := KinematicCollision3D.new()
	if not test_move(
		global_transform,
		horizontal_motion,
		forward_collision,
		safe_margin,
		false
	):
		return
	if forward_collision.get_normal().dot(up_direction) >= cos(floor_max_angle):
		return

	# Raise as far as the available headroom permits, up to max_step_height.
	# Requiring the full maximum clearance makes a perfectly climbable 20 cm
	# stair fail beneath a low ceiling if only (for example) 26 cm is free.
	var available_step_height := max_step_height
	var up_collision := KinematicCollision3D.new()
	var requested_step_up := Vector3.UP * max_step_height
	if test_move(global_transform, requested_step_up, up_collision, safe_margin, false):
		available_step_height = up_collision.get_travel().y
	if available_step_height <= 0.02:
		return
	var step_up := Vector3.UP * available_step_height

	# The landing search needs to clear the riser's front edge, which a
	# single frame's real motion is often too small to do - probe forward
	# by at least step_probe_distance in the same direction instead.
	var probe_motion := horizontal_motion
	if probe_motion.length() < step_probe_distance:
		probe_motion = probe_motion.normalized() * step_probe_distance

	var raised_transform := global_transform
	raised_transform.origin += step_up
	if test_move(raised_transform, probe_motion):
		return

	# Find a walkable landing below the raised, forward position.
	var forward_transform := raised_transform
	forward_transform.origin += probe_motion
	var down_collision := KinematicCollision3D.new()
	var down_motion := Vector3.DOWN * (available_step_height + step_floor_margin)
	if not test_move(forward_transform, down_motion, down_collision):
		return
	if down_collision.get_normal().dot(up_direction) < 0.65:
		return

	var landing_y := forward_transform.origin.y + down_collision.get_travel().y
	var step_height := landing_y - global_position.y
	if step_height > 0.02 and step_height <= available_step_height + step_floor_margin:
		global_position.y += step_height


func _crouch() -> void:
	is_crouching = true
	var shape = collision_shape.shape as CapsuleShape3D
	shape.height = crouch_height
	collision_shape.position.y = (standing_height - crouch_height) / -2.0

func _stand_up() -> void:
	is_crouching = false
	var shape = collision_shape.shape as CapsuleShape3D
	shape.height = standing_height
	collision_shape.position.y = 0.0

func _can_stand() -> bool:
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsShapeQueryParameters3D.new()
	
	var shape = CapsuleShape3D.new()
	shape.radius = (collision_shape.shape as CapsuleShape3D).radius
	shape.height = standing_height
	
	query.shape = shape
	query.transform = global_transform
	query.exclude = [get_rid()]
	query.collision_mask = collision_mask
	
	var result = space_state.intersect_shape(query)
	return result.is_empty()
