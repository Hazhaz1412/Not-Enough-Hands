extends CharacterBody3D

enum StatueState { DORMANT, HIDDEN, FROZEN, STALKING, ATTACK_WINDUP, COOLDOWN }

signal observation_changed(is_observed: bool)
signal attack_started(target: Node3D)
signal attack_cancelled()
signal hunt_started(target: Node3D, ambush_position: Vector3)
signal disappeared()
signal spotted_jumpscare_started()

@export_category('Behavior')
@export var active: bool = true
@export var base_speed: float = 6.55
@export var maximum_speed: float = 9.3
@export var speed_per_breached_door: float = 0.4
@export_range(0, 7) var breached_door_count: int = 0
@export_range(0.0, 1.0) var night_aggression: float = 0.2
@export var acceleration: float = 22.0
@export var turn_speed: float = 9.0
@export var unseen_grace_time: float = 0.32

@export_category('Hunt Cycle')
## The statue spends most of its time absent, then sometimes starts an ambush
## instead of pursuing continuously for the entire game.
@export var intermittent_hunts_enabled: bool = true
@export var start_hidden: bool = true
@export_range(0.0, 1.0) var hunt_activation_chance: float = 0.4
@export var initial_hidden_delay_min: float = 12.0
@export var initial_hidden_delay_max: float = 20.0
@export var hidden_hunt_delay_min: float = 20.0
@export var hidden_hunt_delay_max: float = 34.0
@export var no_hunt_retry_delay: float = 8.0
## Once any living player spots it, this countdown continues even if that
## player looks away. The statue vanishes when it expires.
@export var observed_disappear_delay: float = 10.0
## Hunt candidates must be moving and are ranked by how few teammates are
## within this radius. This naturally selects a lone moving player.
@export var moving_target_speed: float = 0.2
@export var isolation_radius: float = 7.0
## Never manifest close enough to give a player an unavoidable point-blank
## encounter. Distances are measured horizontally on the target's navigation
## floor, and the same radius is kept clear of *every* living player - see
## _is_position_clear_of_players().
@export var ambush_min_distance: float = 15.0
@export var ambush_max_distance: float = 22.0
@export_range(4, 32, 1) var ambush_candidate_count: int = 16

@export_category('Observation')
@export var observation_half_angle: float = 38.0
@export var observation_point_height: float = 1.55
@export var maximum_observation_distance: float = 32.0
@export_flags_3d_physics var sight_blocking_mask: int = 1

@export_category('Attack')
@export var attack_range: float = 1.15
@export var attack_windup: float = 0.48
## Pause after a swing before it may wind up again. Long enough that a survived
## attack is a real chance to break away rather than a one-second reprieve.
@export var attack_cooldown: float = 3.0
## Vertical separation beyond this immediately rules out an attack, cheaply,
## before paying for an occlusion raycast. Generous enough for normal
## stair/landing height variance, far short of a full floor-to-floor gap
## (~2.3m in this house) - stops the statue killing through a floor/ceiling.
@export var max_attack_height_difference: float = 1.5
## Height above each body's feet the attack occlusion ray is cast between -
## roughly torso height, keeps the ray off the floor mesh at close range.
@export var attack_ray_height: float = 1.1

@export_category('Movement Feel')
@export var movement_animation_speed: float = 13.0
@export var stuck_time_before_steering: float = 0.42
@export var steering_duration: float = 0.9
## How much the gait is quantised into stop-motion steps. 0 is a smooth walk.
@export_range(0.0, 1.0) var stop_motion_amount: float = 0.45
## The statue has no jump, so without an explicit step-up it cannot climb
## discrete stair risers at all - move_and_slide() only handles continuous
## slopes, not vertical steps. Mirrors player.gd's _try_step_up.
@export var max_step_height: float = 0.6
@export var step_floor_margin: float = 0.08
## Minimum forward reach used when probing for a landing on top of a step -
## see player.gd's step_probe_distance for why this can't just be the raw
## per-frame motion.
@export var step_probe_distance: float = 0.3
## Direct pursuit is safe only on roughly the same level. With a larger
## height gap the statue waits for a valid nav path instead of running to the
## point directly below a player on another floor.
@export var direct_chase_max_height_difference: float = 0.8

@export_category('Dread')
## Distance at which the statue starts visibly waking up: cracks glow, eyes burn.
@export var dread_radius: float = 10.0
## Re-pose the statue every time it is caught after moving unseen.
@export var pose_snap_on_freeze: bool = true
## Also snap to face the player when caught, so it is always staring at you.
@export var face_player_on_freeze: bool = true
@export var eye_calm_color: Color = Color(0.12, 0.17, 0.18)
@export var eye_hunt_color: Color = Color(0.95, 0.15, 0.05)

var state: StatueState = StatueState.DORMANT
var is_observed: bool = false
var current_target: CharacterBody3D
var unseen_time: float = 0.0
var attack_timer: float = 0.0
var cooldown_timer: float = 0.0
var dev_attack_suspended: bool = false
## The game director's own hold, kept apart from the flag above because that one
## is not a dev flag at all: player.gd refcounts it as the minigame safety lock.
## A director sharing it would release somebody's lock mid-encounter.
var director_attacks_suspended: bool = false
var attack_resume_grace_remaining: float = 0.0
var target_refresh_timer: float = 0.0
var hidden_timer: float = 0.0
## Set by request_hunt_soon(). The next hidden roll skips its dice and commits,
## so an ambush the director has already spent an event slot on cannot quietly
## evaporate into another no_hunt_retry_delay. Cleared the moment it is used.
var forced_hunt_pending: bool = false
var spotted_disappear_timer: float = -1.0
var movement_phase: float = 0.0
var stuck_timer: float = 0.0
var steering_timer: float = 0.0
var steering_sign: float = 1.0
var last_position: Vector3
var following_navigation_path: bool = false
var spotted_jumpscare_played: bool = false
var normal_collision_layer: int
var normal_collision_mask: int
var gravity: float = ProjectSettings.get_setting('physics/3d/default_gravity')

var agitation: float = 0.0
var jaw_open: float = 0.0
var pose_index: int = -1
var presentation_time: float = 0.0
var stone_material: ShaderMaterial
var eye_material: StandardMaterial3D
var model_skeleton: Skeleton3D
var model_bone_drivers: Array[Dictionary] = []

@onready var visual_root: Node3D = $VisualRoot
@onready var torso_pivot: Node3D = $VisualRoot/TorsoPivot
@onready var head_pivot: Node3D = $VisualRoot/TorsoPivot/HeadPivot
@onready var jaw_pivot: Node3D = $VisualRoot/TorsoPivot/HeadPivot/JawPivot
@onready var eye_light: OmniLight3D = $VisualRoot/TorsoPivot/HeadPivot/EyeLight
@onready var eye_glow_left: MeshInstance3D = $VisualRoot/TorsoPivot/HeadPivot/EyeGlowLeft
@onready var skull: MeshInstance3D = $VisualRoot/TorsoPivot/HeadPivot/Skull
@onready var left_arm_pivot: Node3D = $VisualRoot/TorsoPivot/LeftArmPivot
@onready var left_forearm_pivot: Node3D = $VisualRoot/TorsoPivot/LeftArmPivot/ForearmPivot
@onready var right_arm_pivot: Node3D = $VisualRoot/TorsoPivot/RightArmPivot
@onready var right_forearm_pivot: Node3D = $VisualRoot/TorsoPivot/RightArmPivot/ForearmPivot
@onready var left_leg_pivot: Node3D = $VisualRoot/LeftLegPivot
@onready var left_shin_pivot: Node3D = $VisualRoot/LeftLegPivot/ShinPivot
@onready var right_leg_pivot: Node3D = $VisualRoot/RightLegPivot
@onready var right_shin_pivot: Node3D = $VisualRoot/RightLegPivot/ShinPivot
@onready var dust: GPUParticles3D = $VisualRoot/Dust
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var teleport_audio: AudioStreamPlayer3D = $TeleportAudio
@onready var attack_audio: AudioStreamPlayer3D = $AttackAudio
@onready var spotted_jumpscare_audio: AudioStreamPlayer3D = $SpottedJumpscareAudio

## The imported model is bound in a T-pose while the pivot rotations below
## assume arms hanging at the sides, so its arm bones start from this drop.
const MODEL_ARM_DROP_DEGREES: float = 80.0

# Frozen silhouettes, in degrees. The statue snaps between these the instant it
# is caught, so it is never in the same shape twice when you look back at it.
const IDLE_POSES: Array[Dictionary] = [
	{ # Vigil - dead straight, arms at its sides, staring right through you.
		'torso': Vector3(-8.0, 0.0, 1.0),
		'head': Vector3(2.0, 0.0, -2.0),
		'jaw': 0.24,
		'left_arm': Vector3(-3.0, 0.0, -4.0), 'left_forearm': Vector3(6.0, 0.0, 0.0),
		'right_arm': Vector3(-5.0, 0.0, 5.0), 'right_forearm': Vector3(9.0, 0.0, 0.0),
		'left_leg': Vector3(1.0, 0.0, 0.0), 'left_shin': Vector3(-3.0, 0.0, 0.0),
		'right_leg': Vector3(-2.0, 0.0, 0.0), 'right_shin': Vector3(-2.0, 0.0, 0.0),
	},
	{ # Mourning - folded over, head bowed under its own weight.
		'torso': Vector3(-27.0, 3.0, -2.0),
		'head': Vector3(-33.0, -6.0, 5.0),
		'jaw': 0.1,
		'left_arm': Vector3(-24.0, 0.0, -8.0), 'left_forearm': Vector3(16.0, 0.0, 0.0),
		'right_arm': Vector3(-28.0, 0.0, 9.0), 'right_forearm': Vector3(11.0, 0.0, 0.0),
		'left_leg': Vector3(4.0, 0.0, 0.0), 'left_shin': Vector3(-9.0, 0.0, 0.0),
		'right_leg': Vector3(-3.0, 0.0, 0.0), 'right_shin': Vector3(-4.0, 0.0, 0.0),
	},
	{ # Reaching - one hand already out for your throat, caught mid-step.
		'torso': Vector3(-19.0, -10.0, 3.0),
		'head': Vector3(6.0, 12.0, -9.0),
		'jaw': 0.34,
		'left_arm': Vector3(-36.0, 0.0, -12.0), 'left_forearm': Vector3(28.0, 0.0, 0.0),
		'right_arm': Vector3(84.0, 14.0, 16.0), 'right_forearm': Vector3(10.0, 0.0, -6.0),
		'left_leg': Vector3(-11.0, 0.0, 0.0), 'left_shin': Vector3(-6.0, 0.0, 0.0),
		'right_leg': Vector3(13.0, 0.0, 0.0), 'right_shin': Vector3(-17.0, 0.0, 0.0),
	},
	{ # Listening - head cocked at an angle no neck should manage.
		'torso': Vector3(-12.0, 8.0, -4.0),
		'head': Vector3(-4.0, -21.0, 35.0),
		'jaw': 0.18,
		'left_arm': Vector3(46.0, -8.0, -22.0), 'left_forearm': Vector3(94.0, 0.0, 12.0),
		'right_arm': Vector3(-15.0, 0.0, 6.0), 'right_forearm': Vector3(8.0, 0.0, 0.0),
		'left_leg': Vector3(2.0, 0.0, 0.0), 'left_shin': Vector3(-5.0, 0.0, 0.0),
		'right_leg': Vector3(-6.0, 0.0, 0.0), 'right_shin': Vector3(-3.0, 0.0, 0.0),
	},
	{ # Silent scream - arched back, jaw torn open, arms flung behind it.
		'torso': Vector3(-31.0, 0.0, 0.0),
		'head': Vector3(27.0, 0.0, 2.0),
		'jaw': 1.0,
		'left_arm': Vector3(-48.0, -10.0, -16.0), 'left_forearm': Vector3(42.0, 0.0, 0.0),
		'right_arm': Vector3(-52.0, 10.0, 17.0), 'right_forearm': Vector3(38.0, 0.0, 0.0),
		'left_leg': Vector3(7.0, 0.0, 0.0), 'left_shin': Vector3(-15.0, 0.0, 0.0),
		'right_leg': Vector3(-8.0, 0.0, 0.0), 'right_shin': Vector3(-6.0, 0.0, 0.0),
	},
]


func _ready() -> void:
	add_to_group('hostile_ghosts')
	normal_collision_layer = collision_layer
	normal_collision_mask = collision_mask
	last_position = global_position
	_setup_model()
	_prepare_materials()
	_apply_idle_pose(randi() % IDLE_POSES.size())
	if active and intermittent_hunts_enabled and start_hidden:
		_enter_hidden(_random_delay(initial_hidden_delay_min, initial_hidden_delay_max), false)
	else:
		state = StatueState.FROZEN if active else StatueState.DORMANT
		_set_manifested(active)


func _physics_process(delta: float) -> void:
	# See hunter_ghost.gd: on a client this body is placed and animated by
	# WorldReplicator, never simulated here.
	if not WorldNet.is_world_authority():
		return
	attack_resume_grace_remaining = maxf(attack_resume_grace_remaining - delta, 0.0)
	if not active:
		state = StatueState.DORMANT
		velocity = Vector3.ZERO
		return
	if state == StatueState.HIDDEN:
		_update_hidden_hunt(delta)
		_update_player_threat()
		return

	if intermittent_hunts_enabled:
		if not is_instance_valid(current_target) or (
			'is_alive' in current_target and not current_target.is_alive
		):
			_disappear()
			return
	else:
		target_refresh_timer -= delta
		if target_refresh_timer <= 0.0 or not is_instance_valid(current_target):
			current_target = _find_closest_living_player()
			target_refresh_timer = 0.2

	var observed_now := _is_observed_by_any_player()
	if observed_now != is_observed:
		is_observed = observed_now
		if is_observed:
			_play_spotted_jumpscare_once()
			_on_caught_in_the_open()
			if spotted_disappear_timer < 0.0:
				spotted_disappear_timer = observed_disappear_delay
		observation_changed.emit(is_observed)

	if spotted_disappear_timer >= 0.0:
		spotted_disappear_timer -= delta
		if spotted_disappear_timer <= 0.0:
			_disappear()
			return

	if is_observed:
		_freeze_statue(delta)
	else:
		_update_unseen_behavior(delta)

	var was_on_floor := is_on_floor()
	if not was_on_floor:
		velocity.y -= gravity * delta
	else:
		velocity.y = -0.15

	if was_on_floor and velocity.y <= 0.0:
		var horizontal_motion := Vector3(velocity.x, 0.0, velocity.z) * delta
		_try_step_up(horizontal_motion)

	move_and_slide()
	_update_stuck_state(delta)
	_update_player_threat()
	_update_presentation(delta)


func set_dev_attack_suspended(suspended: bool) -> void:
	_set_attack_suspension(suspended, director_attacks_suspended)


## The director's hold on this ghost's attacks. Held separately from the lock
## above so the two cannot overwrite each other: either one alone blocks, and
## attacks only resume once both have let go.
func set_director_attacks_suspended(suspended: bool) -> void:
	_set_attack_suspension(dev_attack_suspended, suspended)


## True while this ghost is a live threat the director has to count against its
## concurrency budget. FROZEN counts: it is standing in the room, and the only
## thing holding it there is somebody spending their eyes on it.
func is_engaged() -> bool:
	return state in [
		StatueState.FROZEN,
		StatueState.STALKING,
		StatueState.ATTACK_WINDUP,
	]


## Director hook: brings the next ambush forward without starting one. It only
## shortens a wait that is already running, so a hunt already underway is left
## alone - the director changes the schedule, never a live encounter. The roll
## is forced as well, or the director would spend an event slot on a coin flip.
func request_hunt_soon(within_seconds: float) -> bool:
	if not active or not intermittent_hunts_enabled or state != StatueState.HIDDEN:
		return false
	hidden_timer = minf(hidden_timer, maxf(within_seconds, 0.0))
	forced_hunt_pending = true
	return true


func _set_attack_suspension(dev_held: bool, director_held: bool) -> void:
	var was_blocked := dev_attack_suspended or director_attacks_suspended
	dev_attack_suspended = dev_held
	director_attacks_suspended = director_held
	var is_blocked := dev_held or director_held
	if is_blocked == was_blocked:
		return
	if is_blocked:
		attack_resume_grace_remaining = 0.0
		if state == StatueState.ATTACK_WINDUP:
			attack_cancelled.emit()
			WorldNet.stop_shared(attack_audio)
			attack_timer = 0.0
			state = StatueState.COOLDOWN
			cooldown_timer = maxf(cooldown_timer, attack_cooldown)
	else:
		attack_resume_grace_remaining = maxf(attack_resume_grace_remaining, attack_cooldown)
	_update_player_threat()


func _attacks_blocked() -> bool:
	return dev_attack_suspended \
		or director_attacks_suspended \
		or attack_resume_grace_remaining > 0.0


## Forces the existing statue instance to manifest for development testing,
## bypassing its hidden timer and random hunt roll.
func dev_force_spawn(target: CharacterBody3D = null) -> bool:
	active = true
	if not is_instance_valid(target):
		target = _find_closest_living_player()
	if not is_instance_valid(target):
		return false

	var ambush_position := _find_ambush_position(target)
	if ambush_position == Vector3.INF:
		var fallback := target.global_position \
			+ target.global_basis.z * maxf(ambush_min_distance, 4.0)
		var map_rid := nav_agent.get_navigation_map()
		if map_rid.is_valid() and NavigationServer3D.map_get_iteration_id(map_rid) > 0:
			fallback = NavigationServer3D.map_get_closest_point(map_rid, fallback)
		ambush_position = fallback + Vector3.UP * 0.02

	_begin_hunt(target, ambush_position)
	return true


# --- Hunt lifecycle ----------------------------------------------------------


func _update_hidden_hunt(delta: float) -> void:
	velocity = Vector3.ZERO
	if not intermittent_hunts_enabled:
		current_target = _find_closest_living_player()
		state = StatueState.FROZEN
		_set_manifested(true)
		return

	hidden_timer -= delta
	if hidden_timer > 0.0:
		return

	# A failed roll creates a real quiet interval instead of checking every
	# frame until success, which would make the probability meaningless. A hunt
	# the director asked for skips the dice entirely - it already decided this
	# is the moment, and paid an event slot for it.
	var forced := forced_hunt_pending
	forced_hunt_pending = false
	if not forced and (hunt_activation_chance <= 0.0 or (
		hunt_activation_chance < 1.0 and randf() > hunt_activation_chance
	)):
		hidden_timer = no_hunt_retry_delay
		return

	var target := _find_most_isolated_moving_player()
	if not target:
		hidden_timer = no_hunt_retry_delay
		return

	var ambush_position := _find_ambush_position(target)
	if ambush_position == Vector3.INF:
		hidden_timer = no_hunt_retry_delay
		return

	_begin_hunt(target, ambush_position)


func _begin_hunt(target: CharacterBody3D, ambush_position: Vector3) -> void:
	current_target = target
	global_position = ambush_position
	last_position = ambush_position
	velocity = Vector3.ZERO
	unseen_time = unseen_grace_time
	spotted_disappear_timer = -1.0
	spotted_jumpscare_played = false
	WorldNet.stop_shared(spotted_jumpscare_audio)
	is_observed = false
	state = StatueState.STALKING
	_set_manifested(true)

	var flat_target := target.global_position - global_position
	flat_target.y = 0.0
	if not flat_target.is_zero_approx():
		rotation.y = atan2(-flat_target.x, -flat_target.z)
	_apply_idle_pose(_pick_new_pose_index())
	WorldNet.play_shared(teleport_audio)
	hunt_started.emit(target, ambush_position)


func _disappear() -> void:
	var was_observed := is_observed
	if state == StatueState.ATTACK_WINDUP:
		attack_cancelled.emit()
	WorldNet.stop_shared(attack_audio)
	WorldNet.stop_shared(spotted_jumpscare_audio)
	if state != StatueState.HIDDEN:
		WorldNet.play_shared(teleport_audio)

	state = StatueState.HIDDEN
	velocity = Vector3.ZERO
	unseen_time = 0.0
	attack_timer = 0.0
	stuck_timer = 0.0
	steering_timer = 0.0
	spotted_disappear_timer = -1.0
	spotted_jumpscare_played = false
	is_observed = false
	current_target = null
	hidden_timer = _random_delay(hidden_hunt_delay_min, hidden_hunt_delay_max)
	_set_manifested(false)
	if was_observed:
		observation_changed.emit(false)
	disappeared.emit()


func _enter_hidden(delay: float, play_sound: bool = true) -> void:
	state = StatueState.HIDDEN
	hidden_timer = maxf(delay, 0.0)
	spotted_disappear_timer = -1.0
	spotted_jumpscare_played = false
	WorldNet.stop_shared(spotted_jumpscare_audio)
	current_target = null
	velocity = Vector3.ZERO
	if play_sound:
		WorldNet.play_shared(teleport_audio)
	_set_manifested(false)


func _set_manifested(manifested: bool) -> void:
	visual_root.visible = manifested
	dust.emitting = manifested
	collision_layer = normal_collision_layer if manifested else 0
	collision_mask = normal_collision_mask if manifested else 0


func _random_delay(minimum: float, maximum: float) -> float:
	var low := minf(minimum, maximum)
	var high := maxf(minimum, maximum)
	return randf_range(maxf(low, 0.0), maxf(high, 0.0))


## Hops the statue up onto a stair riser that's blocking its horizontal
## motion, exactly like player.gd's _try_step_up: probe forward, probe
## straight up, probe forward again from the raised height, then probe down
## to find a walkable landing - only commits if that landing is a small,
## climbable step, not a wall or a big drop.
func _try_step_up(horizontal_motion: Vector3) -> void:
	if horizontal_motion.is_zero_approx():
		return
	if is_on_floor() and get_floor_normal().dot(up_direction) < 0.98:
		return

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

	# Use whatever headroom is actually available, up to max_step_height. The
	# stairwell ceiling can block a full-height probe while still leaving ample
	# room to climb the current 20 cm riser.
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


func _freeze_statue(delta: float) -> void:
	if state == StatueState.ATTACK_WINDUP:
		attack_cancelled.emit()
		WorldNet.stop_shared(attack_audio)
	state = StatueState.FROZEN
	unseen_time = 0.0
	attack_timer = 0.0
	velocity.x = move_toward(velocity.x, 0.0, acceleration * delta * 2.0)
	velocity.z = move_toward(velocity.z, 0.0, acceleration * delta * 2.0)


func _update_unseen_behavior(delta: float) -> void:
	unseen_time += delta

	if state == StatueState.COOLDOWN:
		cooldown_timer -= delta
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
		_animate_motion(delta, 0.22)
		if cooldown_timer <= 0.0:
			state = StatueState.STALKING
		return

	if state == StatueState.ATTACK_WINDUP:
		_update_attack_windup(delta)
		return

	if unseen_time < unseen_grace_time or not is_instance_valid(current_target):
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
		return

	var raw_offset := current_target.global_position - global_position
	if absf(raw_offset.y) <= max_attack_height_difference:
		var horizontal_offset := raw_offset
		horizontal_offset.y = 0.0
		if horizontal_offset.length() <= attack_range and _has_attack_line_of_sight(current_target):
			_begin_attack()
			return

	state = StatueState.STALKING
	var flat_offset := raw_offset
	flat_offset.y = 0.0
	_stalk_target(delta, flat_offset)


## Mirrors _camera_can_see_point's occlusion-ray idiom, but for whether the
## statue's own reach to the player is blocked by a wall/floor/ceiling -
## nothing equivalent existed before this fix, which is how the statue used
## to be able to kill through a floor.
func _has_attack_line_of_sight(target: CharacterBody3D) -> bool:
	var origin := global_position + Vector3.UP * attack_ray_height
	var target_point := target.global_position + Vector3.UP * attack_ray_height
	var query := PhysicsRayQueryParameters3D.create(
		origin,
		target_point,
		sight_blocking_mask,
		[get_rid(), target.get_rid()]
	)
	query.hit_from_inside = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty()


func _stalk_target(delta: float, target_offset: Vector3) -> void:
	var direction := _navigation_direction(target_offset)
	if direction.is_zero_approx():
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
		return

	# The navigation corridor already steers around walls and through the
	# stairwell. The old sideways stuck nudge can push the body off a narrow
	# tread, so reserve it for nav-less test/open scenes that chase directly.
	if steering_timer > 0.0 and not following_navigation_path:
		steering_timer -= delta
		var sideways := Vector3(-direction.z, 0.0, direction.x) * steering_sign
		direction = (direction + sideways * 0.82).normalized()

	var target_yaw := atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, minf(turn_speed * delta, 1.0))

	var speed := base_speed + speed_per_breached_door * breached_door_count
	speed += lerpf(0.0, 1.5, night_aggression)
	speed = minf(speed, maximum_speed)
	var movement_acceleration := acceleration
	var burst := lerpf(0.82, 1.18, sin(movement_phase * 0.63) * 0.5 + 0.5)
	var desired_velocity := direction * speed * burst
	velocity.x = move_toward(velocity.x, desired_velocity.x, movement_acceleration * delta)
	velocity.z = move_toward(velocity.z, desired_velocity.z, movement_acceleration * delta)
	_animate_motion(delta, speed / maxf(base_speed, 0.1))


## Direction to steer this frame, sourced from the baked navmesh path. A
## straight-line fallback is allowed only when there is no navmesh at all
## (small isolated test scenes) or the player is on roughly the same level.
## This is important when the map is still syncing or a destination is
## disconnected: charging toward the player's X/Z coordinate from the floor
## below can never catch them and makes the statue look oblivious to stairs.
func _navigation_direction(fallback_offset: Vector3) -> Vector3:
	following_navigation_path = false
	# Reassigning the same target every frame forces a fresh path from the
	# statue's current ramp polygon. On an off-mesh stair link that repeatedly
	# sends it back to the lower endpoint instead of allowing link traversal.
	if nav_agent.target_position.distance_squared_to(current_target.global_position) > 0.04:
		nav_agent.target_position = current_target.global_position
	var next_point := nav_agent.get_next_path_position()
	var to_next := next_point - global_position
	to_next.y = 0.0
	var current_path := nav_agent.get_current_navigation_path()
	if current_path.size() > 1 and to_next.length_squared() > 0.0001:
		following_navigation_path = true
		return to_next.normalized()

	var map_rid := nav_agent.get_navigation_map()
	var has_navigation := map_rid.is_valid() \
		and NavigationServer3D.map_get_iteration_id(map_rid) > 0 \
		and not NavigationServer3D.map_get_regions(map_rid).is_empty()
	var height_difference := absf(current_target.global_position.y - global_position.y)
	if (not has_navigation or height_difference <= direct_chase_max_height_difference) \
		and fallback_offset.length_squared() > 0.0001:
		return fallback_offset.normalized()
	return Vector3.ZERO


func _begin_attack() -> void:
	if _attacks_blocked():
		return
	state = StatueState.ATTACK_WINDUP
	attack_timer = attack_windup
	velocity.x = 0.0
	velocity.z = 0.0
	WorldNet.play_shared(attack_audio)
	attack_started.emit(current_target)


func _update_attack_windup(delta: float) -> void:
	if _attacks_blocked():
		attack_cancelled.emit()
		WorldNet.stop_shared(attack_audio)
		attack_timer = 0.0
		state = StatueState.COOLDOWN
		cooldown_timer = maxf(cooldown_timer, attack_cooldown)
		return
	attack_timer -= delta
	var progress := 1.0 - clampf(attack_timer / maxf(attack_windup, 0.01), 0.0, 1.0)
	_apply_attack_pose(progress)
	velocity.x = 0.0
	velocity.z = 0.0

	if attack_timer > 0.0:
		return

	if not _attacks_blocked() \
		and is_instance_valid(current_target) \
		and current_target.has_method('kill_by_ghost'):
		current_target.kill_by_ghost(self)

	state = StatueState.COOLDOWN
	cooldown_timer = attack_cooldown


func _find_most_isolated_moving_player() -> CharacterBody3D:
	var living_players := _living_players()
	var best_player: CharacterBody3D
	var fewest_neighbors := INF
	var largest_nearest_neighbor_distance := -INF

	for candidate: CharacterBody3D in living_players:
		var horizontal_speed := Vector2(candidate.velocity.x, candidate.velocity.z).length()
		if horizontal_speed < moving_target_speed:
			continue

		var nearby_players := 0
		var nearest_neighbor_distance := INF
		for other: CharacterBody3D in living_players:
			if other == candidate:
				continue
			var distance := candidate.global_position.distance_to(other.global_position)
			nearest_neighbor_distance = minf(nearest_neighbor_distance, distance)
			if distance <= isolation_radius:
				nearby_players += 1

		if nearby_players < fewest_neighbors or (
			nearby_players == fewest_neighbors
			and nearest_neighbor_distance > largest_nearest_neighbor_distance
		):
			fewest_neighbors = nearby_players
			largest_nearest_neighbor_distance = nearest_neighbor_distance
			best_player = candidate

	return best_player


func _living_players() -> Array[CharacterBody3D]:
	var players: Array[CharacterBody3D] = []
	for node: Node in get_tree().get_nodes_in_group('players'):
		var player := node as CharacterBody3D
		if not player:
			continue
		if 'is_alive' in player and not player.is_alive:
			continue
		if player.has_method('can_be_targeted_by_ghosts') \
			and not bool(player.call('can_be_targeted_by_ghosts')):
			continue
		players.append(player)
	return players


func _find_ambush_position(target: CharacterBody3D) -> Vector3:
	var map_rid := nav_agent.get_navigation_map()
	var has_navigation := map_rid.is_valid() \
		and NavigationServer3D.map_get_iteration_id(map_rid) > 0 \
		and not NavigationServer3D.map_get_regions(map_rid).is_empty()
	if has_navigation:
		var target_nav_point := NavigationServer3D.map_get_closest_point(
			map_rid,
			target.global_position
		)
		for sample_index: int in ambush_candidate_count:
			var angle := randf() * TAU
			var distance := randf_range(ambush_min_distance, ambush_max_distance)
			var radial_offset := Vector3(cos(angle), 0.0, sin(angle)) * distance
			var nav_point := NavigationServer3D.map_get_closest_point(
				map_rid,
				target_nav_point + radial_offset
			)
			var flat_distance := Vector2(
				nav_point.x - target_nav_point.x,
				nav_point.z - target_nav_point.z
			).length()
			if flat_distance < ambush_min_distance or flat_distance > ambush_max_distance:
				continue
			if absf(nav_point.y - target_nav_point.y) > direct_chase_max_height_difference:
				continue

			var route := NavigationServer3D.map_get_path(
				map_rid,
				nav_point,
				target_nav_point,
				true
			)
			if route.is_empty() or route[route.size() - 1].distance_to(target_nav_point) > 0.75:
				continue

			var spawn_position := nav_point + Vector3.UP * 0.02
			if not _is_position_clear_of_players(spawn_position):
				continue
			if not _is_position_observed_by_any_player(spawn_position):
				return spawn_position
		return Vector3.INF

	# Small standalone test scenes have no NavigationRegion3D. They still get
	# the same distance/visibility rules on their flat floor.
	var floor_y := _player_foot_y(target)
	for sample_index: int in ambush_candidate_count:
		var angle := randf() * TAU
		var distance := randf_range(ambush_min_distance, ambush_max_distance)
		var candidate := Vector3(
			target.global_position.x + cos(angle) * distance,
			floor_y + 0.02,
			target.global_position.z + sin(angle) * distance
		)
		if not _is_position_clear_of_players(candidate):
			continue
		if not _is_position_observed_by_any_player(candidate):
			return candidate
	return Vector3.INF


func _player_foot_y(player: CharacterBody3D) -> float:
	var shape_node := player.get_node_or_null('CollisionShape3D') as CollisionShape3D
	if shape_node:
		var capsule := shape_node.shape as CapsuleShape3D
		if capsule:
			return shape_node.global_position.y - capsule.height * 0.5
	return player.global_position.y


## The ambush radius above is measured against the hunted player only, and the
## candidate merely has to be unseen. Neither says anything about the rest of
## the team: a point 18 m behind the target can be a metre behind somebody else
## who happens not to be looking that way, and that teammate then has a statue
## in their face with no warning at all. Measured against real player positions
## rather than their navmesh projections, because a player on a stair tread or
## on top of furniture projects several metres from where they actually stand -
## which is the same way a candidate could land next to the target itself.
func _is_position_clear_of_players(position: Vector3) -> bool:
	for player: CharacterBody3D in _living_players():
		var flat_offset := Vector2(
			player.global_position.x - position.x,
			player.global_position.z - position.z
		)
		if flat_offset.length() < ambush_min_distance:
			return false
	return true


func _is_position_observed_by_any_player(position: Vector3) -> bool:
	var observation_point := position + Vector3.UP * observation_point_height
	for player: CharacterBody3D in _living_players():
		var camera := player.get_node_or_null('CameraPivot/Camera3D') as Camera3D
		if camera and _camera_can_see_point(camera, player, observation_point):
			return true
	return false


func _find_closest_living_player() -> CharacterBody3D:
	var closest_player: CharacterBody3D
	var closest_distance := INF
	for node: Node in get_tree().get_nodes_in_group('players'):
		var player := node as CharacterBody3D
		if not player:
			continue
		if 'is_alive' in player and not player.is_alive:
			continue
		if player.has_method('can_be_targeted_by_ghosts') \
			and not bool(player.call('can_be_targeted_by_ghosts')):
			continue
		var distance := global_position.distance_squared_to(player.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_player = player
	return closest_player


func _is_observed_by_any_player() -> bool:
	var observation_point := global_position + Vector3.UP * observation_point_height
	for node: Node in get_tree().get_nodes_in_group('players'):
		var player := node as CharacterBody3D
		if not player:
			continue
		if 'is_alive' in player and not player.is_alive:
			continue
		var camera := player.get_node_or_null('CameraPivot/Camera3D') as Camera3D
		if camera and _camera_can_see_point(camera, player, observation_point):
			return true
	return false


func _camera_can_see_point(camera: Camera3D, player: CharacterBody3D, point: Vector3) -> bool:
	var offset := point - camera.global_position
	var distance := offset.length()
	if distance <= 0.01 or distance > maximum_observation_distance:
		return false

	var look_dot := (-camera.global_basis.z).dot(offset / distance)
	if look_dot < cos(deg_to_rad(observation_half_angle)):
		return false
	if not camera.is_position_in_frustum(point):
		return false

	var query := PhysicsRayQueryParameters3D.create(
		camera.global_position,
		point,
		sight_blocking_mask,
		[player.get_rid()]
	)
	query.hit_from_inside = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty()


func _update_stuck_state(delta: float) -> void:
	var moved_distance := Vector2(
		global_position.x - last_position.x,
		global_position.z - last_position.z
	).length()
	last_position = global_position

	if state != StatueState.STALKING:
		stuck_timer = 0.0
		return

	if moved_distance < 0.006:
		stuck_timer += delta
	else:
		stuck_timer = maxf(stuck_timer - delta * 2.0, 0.0)

	if stuck_timer >= stuck_time_before_steering:
		stuck_timer = 0.0
		steering_timer = steering_duration
		steering_sign *= -1.0


func _update_player_threat() -> void:
	for node: Node in get_tree().get_nodes_in_group('players'):
		var player := node as CharacterBody3D
		if not player or not player.has_method('set_statue_threat'):
			continue
		var amount := 0.0
		if not _attacks_blocked() \
			and state != StatueState.HIDDEN \
			and state != StatueState.DORMANT:
			var distance := global_position.distance_to(player.global_position)
			amount = clampf(1.0 - distance / 12.0, 0.0, 1.0)
			if is_observed:
				amount *= 0.45
		player.set_statue_threat(amount)


# --- Presentation -------------------------------------------------------------


## Give this statue its own copy of the stone and eye materials so several
## statues can glow independently instead of sharing one scene sub-resource.
func _prepare_materials() -> void:
	var stone_source: Material = _primitive_material(skull)
	var eye_source: Material = _primitive_material(eye_glow_left)
	if stone_source is ShaderMaterial:
		stone_material = (stone_source as ShaderMaterial).duplicate()
	if eye_source is StandardMaterial3D:
		eye_material = (eye_source as StandardMaterial3D).duplicate()

	for node: Node in visual_root.find_children('*', 'MeshInstance3D', true, false):
		var mesh_instance := node as MeshInstance3D
		var material := _primitive_material(mesh_instance)
		if material == null:
			continue
		if material == stone_source and stone_material:
			mesh_instance.material_override = stone_material
		elif material == eye_source and eye_material:
			mesh_instance.material_override = eye_material


func _primitive_material(mesh_instance: MeshInstance3D) -> Material:
	var primitive := mesh_instance.mesh as PrimitiveMesh
	return primitive.material if primitive else null


## Swaps the procedural stone body for the imported statue model. The pivots,
## socket light and dust stay: they are what poses the model, which ships
## without a single animation clip.
func _setup_model() -> void:
	var model := visual_root.get_node_or_null('Model')
	if model == null:
		return
	for node: Node in visual_root.find_children('*', 'MeshInstance3D', true, false):
		if not model.is_ancestor_of(node):
			(node as MeshInstance3D).visible = false

	model_skeleton = model.find_child('Skeleton3D', true, false) as Skeleton3D
	if model_skeleton == null:
		push_warning('Statue model has no Skeleton3D: it will stay in its bind pose.')
		return

	var to_visual := visual_root.global_transform.affine_inverse() \
		* model_skeleton.global_transform
	var left_drop := Basis(Vector3.BACK, deg_to_rad(MODEL_ARM_DROP_DEGREES))
	var right_drop := Basis(Vector3.BACK, deg_to_rad(-MODEL_ARM_DROP_DEGREES))
	_add_bone_driver(torso_pivot, &'mixamorig_Spine_02', Basis(), to_visual)
	_add_bone_driver(head_pivot, &'mixamorig_Neck_013', Basis(), to_visual)
	_add_bone_driver(left_arm_pivot, &'mixamorig_LeftArm_017', left_drop, to_visual)
	_add_bone_driver(left_forearm_pivot, &'mixamorig_LeftForeArm_018', Basis(), to_visual)
	_add_bone_driver(right_arm_pivot, &'mixamorig_RightArm_06', right_drop, to_visual)
	_add_bone_driver(right_forearm_pivot, &'mixamorig_RightForeArm_07', Basis(), to_visual)
	_add_bone_driver(left_leg_pivot, &'mixamorig_LeftUpLeg_024', Basis(), to_visual)
	_add_bone_driver(left_shin_pivot, &'mixamorig_LeftLeg_025', Basis(), to_visual)
	_add_bone_driver(right_leg_pivot, &'mixamorig_RightUpLeg_028', Basis(), to_visual)
	_add_bone_driver(right_shin_pivot, &'mixamorig_RightLeg_029', Basis(), to_visual)

	# The model's head sits lower than the stone skull the light was placed for,
	# so the socket glow rides down with it instead of hanging above the model.
	var head_bone := model_skeleton.find_bone(&'mixamorig_Head_014')
	if head_bone >= 0:
		var head_height: float = (
			to_visual * model_skeleton.get_bone_global_rest(head_bone).origin
		).y
		eye_light.position.y = head_height + 0.07 \
			- torso_pivot.position.y - head_pivot.position.y


## Pivot rotations are written in the body's axes, while a bone pose is relative
## to that bone's own rest orientation inside the skeleton, so every rotation is
## re-expressed through the basis that maps skeleton space onto the body.
func _add_bone_driver(
	pivot: Node3D, bone_name: StringName, base: Basis, to_visual: Transform3D
) -> void:
	var bone := model_skeleton.find_bone(bone_name)
	if bone < 0:
		push_warning('Statue model is missing bone %s.' % bone_name)
		return
	var to_bone := to_visual.basis * model_skeleton.get_bone_global_rest(bone).basis
	model_bone_drivers.append({
		'pivot': pivot,
		'bone': bone,
		'base': base,
		'rest': model_skeleton.get_bone_rest(bone).basis,
		'to_bone': to_bone,
		'from_bone': to_bone.inverse(),
	})


## Copies the current pivot pose onto the model's skeleton. Every idle pose,
## gait step and attack lunge already written for the stone body drives the
## model instead, so it never stands there in its bind pose.
func _sync_model_pose() -> void:
	if model_skeleton == null:
		return
	for driver: Dictionary in model_bone_drivers:
		var pivot: Node3D = driver['pivot']
		var in_body: Basis = pivot.basis * (driver['base'] as Basis)
		var in_bone: Basis = (driver['rest'] as Basis) \
			* (driver['from_bone'] as Basis) * in_body * (driver['to_bone'] as Basis)
		model_skeleton.set_bone_pose_rotation(driver['bone'], in_bone.get_rotation_quaternion())


## Caught in the open: snap into a brand new shape, facing whoever spotted it.
## The player never sees the transition, only that it is different now.
func _play_spotted_jumpscare_once() -> void:
	if spotted_jumpscare_played:
		return
	spotted_jumpscare_played = true
	WorldNet.play_shared(spotted_jumpscare_audio)
	spotted_jumpscare_started.emit()


func _on_caught_in_the_open() -> void:
	if unseen_time < 0.25:
		return
	if pose_snap_on_freeze:
		_apply_idle_pose(_pick_new_pose_index())
	if face_player_on_freeze:
		_crane_head_toward_target()


## Only the head turns, never the body. Snapping the body would also hand the
## statue a free turn and make it reach the player sooner, so the neck does the
## work instead - which looks worse anyway.
func _crane_head_toward_target() -> void:
	if not is_instance_valid(current_target):
		return
	var local_target := to_local(current_target.global_position)
	local_target.y = 0.0
	if local_target.length_squared() < 0.0001:
		return
	var yaw := atan2(-local_target.x, -local_target.z) - torso_pivot.rotation.y
	head_pivot.rotation.y = clampf(wrapf(yaw, -PI, PI), deg_to_rad(-78.0), deg_to_rad(78.0))


func _pick_new_pose_index() -> int:
	if IDLE_POSES.size() <= 1:
		return 0
	var next_index := randi() % IDLE_POSES.size()
	if next_index == pose_index:
		next_index = (next_index + 1) % IDLE_POSES.size()
	return next_index


func _apply_idle_pose(index: int) -> void:
	pose_index = clampi(index, 0, IDLE_POSES.size() - 1)
	var pose: Dictionary = IDLE_POSES[pose_index]
	visual_root.position = Vector3.ZERO
	visual_root.rotation = Vector3.ZERO
	torso_pivot.rotation = _degrees(pose['torso'])
	head_pivot.rotation = _degrees(pose['head'])
	left_arm_pivot.rotation = _degrees(pose['left_arm'])
	left_forearm_pivot.rotation = _degrees(pose['left_forearm'])
	right_arm_pivot.rotation = _degrees(pose['right_arm'])
	right_forearm_pivot.rotation = _degrees(pose['right_forearm'])
	left_leg_pivot.rotation = _degrees(pose['left_leg'])
	left_shin_pivot.rotation = _degrees(pose['left_shin'])
	right_leg_pivot.rotation = _degrees(pose['right_leg'])
	right_shin_pivot.rotation = _degrees(pose['right_shin'])
	jaw_open = pose['jaw']
	_apply_jaw()
	_sync_model_pose()
	# Deliberately does NOT touch movement_phase: _stalk_target derives its
	# speed burst from it, so resetting it here would make re-posing change
	# how fast the statue moves.


func _degrees(angles: Vector3) -> Vector3:
	return Vector3(deg_to_rad(angles.x), deg_to_rad(angles.y), deg_to_rad(angles.z))


func _apply_jaw() -> void:
	# Negative pitch drops the front of the jaw, so the mouth tears open.
	jaw_pivot.rotation.x = deg_to_rad(-jaw_open * 36.0)


func _animate_motion(delta: float, speed_scale: float) -> void:
	movement_phase += delta * movement_animation_speed * speed_scale

	# Quantising the phase turns the walk into stop-motion: it arrives in
	# stutters rather than gliding, which reads as wrong long before you can
	# say why.
	var quantised := floorf(movement_phase / (PI / 5.0)) * (PI / 5.0)
	var phase := lerpf(movement_phase, quantised, stop_motion_amount)

	var stride := sin(phase)
	var counter_stride := sin(phase + PI)
	var twitch := sin(phase * 2.73) * 0.06

	visual_root.position.y = absf(sin(phase * 2.0)) * 0.05
	visual_root.position.z = 0.0
	visual_root.rotation.z = sin(phase * 0.47) * 0.1

	# Hunched low and shoulder-first, like something too tall for the house.
	torso_pivot.rotation.x = deg_to_rad(-32.0) + absf(stride) * 0.1
	torso_pivot.rotation.y = sin(phase * 0.41) * 0.09
	torso_pivot.rotation.z = twitch

	head_pivot.rotation.x = deg_to_rad(26.0) - absf(counter_stride) * 0.14
	head_pivot.rotation.y = sin(phase * 0.31) * 0.24
	head_pivot.rotation.z = sin(phase * 1.9) * 0.07
	jaw_open = lerpf(jaw_open, 0.55 + absf(stride) * 0.25, minf(delta * 6.0, 1.0))
	_apply_jaw()

	left_arm_pivot.rotation.x = deg_to_rad(-16.0) + stride * 0.72
	left_arm_pivot.rotation.z = deg_to_rad(-16.0) + counter_stride * 0.2
	left_forearm_pivot.rotation.x = deg_to_rad(24.0) + maxf(stride, 0.0) * 0.55
	right_arm_pivot.rotation.x = deg_to_rad(-16.0) + counter_stride * 0.72
	right_arm_pivot.rotation.z = deg_to_rad(16.0) + stride * 0.2
	right_forearm_pivot.rotation.x = deg_to_rad(24.0) + maxf(counter_stride, 0.0) * 0.55

	left_leg_pivot.rotation.x = stride * 0.46
	left_shin_pivot.rotation.x = deg_to_rad(-10.0) - maxf(stride, 0.0) * 0.7
	right_leg_pivot.rotation.x = counter_stride * 0.46
	right_shin_pivot.rotation.x = deg_to_rad(-10.0) - maxf(counter_stride, 0.0) * 0.7


func _apply_attack_pose(progress: float) -> void:
	var reach := ease(progress, -1.6)
	# Rear back, then throw both arms forward with the jaw already open.
	visual_root.position.z = lerpf(visual_root.position.z, -0.14, reach)
	torso_pivot.rotation.x = lerpf(torso_pivot.rotation.x, deg_to_rad(-42.0), reach)
	torso_pivot.rotation.z = lerpf(torso_pivot.rotation.z, 0.0, reach)
	head_pivot.rotation.x = lerpf(head_pivot.rotation.x, deg_to_rad(24.0), reach)
	head_pivot.rotation.y = lerpf(head_pivot.rotation.y, 0.0, reach)
	head_pivot.rotation.z = lerpf(head_pivot.rotation.z, deg_to_rad(9.0), reach)
	left_arm_pivot.rotation.x = lerpf(left_arm_pivot.rotation.x, deg_to_rad(98.0), reach)
	right_arm_pivot.rotation.x = lerpf(right_arm_pivot.rotation.x, deg_to_rad(98.0), reach)
	left_arm_pivot.rotation.z = lerpf(left_arm_pivot.rotation.z, deg_to_rad(-22.0), reach)
	right_arm_pivot.rotation.z = lerpf(right_arm_pivot.rotation.z, deg_to_rad(22.0), reach)
	left_forearm_pivot.rotation.x = lerpf(left_forearm_pivot.rotation.x, deg_to_rad(14.0), reach)
	right_forearm_pivot.rotation.x = lerpf(right_forearm_pivot.rotation.x, deg_to_rad(14.0), reach)
	jaw_open = maxf(jaw_open, reach)
	_apply_jaw()


## Drives everything that makes the statue feel awake: glowing fractures,
## burning sockets and the dust shaking loose off its shoulders.
func _update_presentation(delta: float) -> void:
	presentation_time += delta

	var proximity := 0.0
	if is_instance_valid(current_target):
		var distance := global_position.distance_to(current_target.global_position)
		proximity = clampf(1.0 - distance / maxf(dread_radius, 0.01), 0.0, 1.0)

	var target_agitation := proximity * 0.6
	match state:
		StatueState.STALKING:
			target_agitation = maxf(proximity, 0.5)
		StatueState.ATTACK_WINDUP:
			target_agitation = 1.0
		StatueState.COOLDOWN:
			target_agitation = maxf(proximity, 0.7)
		StatueState.HIDDEN, StatueState.DORMANT:
			target_agitation = 0.0
	agitation = move_toward(agitation, target_agitation, delta * 2.6)

	if stone_material:
		stone_material.set_shader_parameter('agitation', agitation)

	# Never a steady glow - the sockets breathe, and now and then they simply
	# stop being lit for a moment.
	var flicker := 1.0 + sin(presentation_time * 17.3) * 0.06 + sin(presentation_time * 3.1) * 0.11
	if fmod(presentation_time, 4.7) < 0.06:
		flicker *= 0.12
	var eye_color := eye_calm_color.lerp(eye_hunt_color, agitation)
	if eye_material:
		eye_material.albedo_color = eye_color
		eye_material.emission = eye_color
		eye_material.emission_energy_multiplier = lerpf(1.1, 7.5, agitation) * flicker
	eye_light.light_color = eye_color
	eye_light.light_energy = lerpf(0.16, 1.35, agitation) * flicker

	var shedding := 0.24
	if state == StatueState.STALKING or state == StatueState.COOLDOWN:
		shedding = 0.85
	elif state == StatueState.ATTACK_WINDUP:
		shedding = 1.0
	dust.amount_ratio = lerpf(dust.amount_ratio, shedding, minf(delta * 4.0, 1.0))
	_sync_model_pose()
