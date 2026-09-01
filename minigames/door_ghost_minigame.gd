class_name DoorGhostMinigame
extends Node3D

## First-person 3D encounter fought at the defense door that is under attack.
##
## The player is pinned to the door, the flashlight is forced on, and an actual
## 3D ghost stands somewhere in the exterior. Finding it and holding the beam on
## it pushes it back; ignoring it lets it walk up to the door. Five pushes drive
## it off for good, one lapse and it gets its hit in.
##
## This is only the encounter. Durability, breaching and the repair flow all
## stay in door/defense_door.gd and are reached through the same three calls the
## previous screenspace version used - begin_exorcism() (by Player),
## apply_exorcism_failure(), complete_exorcism() and cancel_exorcism(). Nothing
## here damages a door directly, so the 20-point failure hit is applied exactly
## once, by the door itself.

signal minigame_started(door: Node)
signal attempt_failed(door: Node, repair_cap: float)
signal minigame_completed(door: Node)
signal minigame_closed()
signal repel_landed(door: Node, phase_index: int, phase_hits: int)
signal encounter_phase_changed(phase_index: int)

## The encounter's state is (state, phase_index): the SEARCH -> RETREAT ->
## SEARCH loop is identical in all three phases, and the timeout path out of it
## (STARE -> JUMPSCARE) is shared, so the phase is a second axis rather than
## three copied sets of states. PHASE_1_SEARCH is (SEARCH, 0), PHASE_2_RETREAT
## is (RETREAT, 1), and so on.
enum State { INACTIVE, SEARCH, STARE, DODGE, RETREAT, JUMPSCARE, SUCCESS }

## Phases of the encounter: peephole, ajar, wide open. Every per-phase export
## below carries exactly this many entries.
const TOTAL_PHASES := 3

## Where the ghost may stand: Marker3Ds in this group. door/defense_door.tscn
## authors five per door, so both maps get them from the shared door scene and
## neither map is named here. The count is not fixed - a map may drop more into
## the group, and anything in it near the attacked door is a candidate.
const SPOT_GROUP := &"door_ghost_positions"

## Only for the DoorOutcome names. The outcome of an encounter goes out through
## the player rather than straight onto the door, because in a session the
## encounter is played on one machine and the door lives on another.
const PLAYER_SCRIPT := preload("res://player/player.gd")

@export_category("Rules")
## Successful flashlight hits needed to finish one phase. The counter is
## per-phase and resets to zero on every transition, so the whole encounter
## costs hits_per_phase * TOTAL_PHASES hits.
@export var hits_per_phase: int = 2
## Seconds the ghost needs to cross from its spot to the door. This is one
## search/hit cycle, not one phase: every landed hit resets it in full.
@export var threat_window: float = 3.0
## Remaining time at which the ghost stops closing and simply stares. It stays
## vulnerable here, giving a final short chance before the real deadline.
@export var stare_threshold: float = 0.8
## How long the beam has to stay on the ghost, unbroken, for the hit to count.
## Brushing past it does nothing; look away and the hold starts over.
@export var flashlight_confirm_time: float = 0.35
## Shape of the approach. The ghost is time-locked to arrive exactly as the
## window closes - so it can never idle short of the door, and a near position
## is not easier than a far one - and this is how that time is spent: above 1
## it creeps then rushes, below 1 it comes hard and eases in.
@export var approach_easing: float = 1.6
## Beat between a landed repel and the ghost reappearing somewhere else.
@export var retreat_duration: float = 0.3
## How much of that beat it spends recoiling in the beam before it vanishes.
@export var reaction_duration: float = 0.18

@export_category("Dodge")
## One roll per appearance, made once a continuous beam reaches this fraction
## of a completed repel. A dodge resets that hold but never counts as a hit.
@export_range(0.0, 1.0, 0.01) var dodge_chance: float = 0.3
@export_range(0.05, 0.95, 0.05) var dodge_trigger_fraction: float = 0.3
## Angular sidestep relative to the camera. It must clear the gameplay beam's
## 16.8-degree half-angle even at the far phase, where a fixed metre offset
## would still leave the ghost illuminated.
@export_range(18.0, 60.0, 1.0) var dodge_angle_degrees: float = 24.0
@export_range(0.1, 1.0, 0.05) var dodge_duration: float = 0.3

@export_category("Presentation text")
## Shown with the phase number and the per-phase hit counter.
@export var phase_names: PackedStringArray = PackedStringArray([
	"LỖ CHỐNG TRỘM", "MỞ HÉ CỬA", "MỞ TOANG CỬA",
])

@export_category("Camera")
## Metres the player is pushed out past the door leaf in each phase. Phase 0 is
## the peephole (still behind the leaf), the last phase steps into the opening.
@export var phase_view_offsets: PackedFloat32Array = PackedFloat32Array([0.28, 0.62, 1.05])
## Horizontal look limit per phase, in degrees either side of the door normal.
## 180 or more means the phase is free-look and the clamp is switched off.
@export var phase_yaw_limits: PackedFloat32Array = PackedFloat32Array([45.0, 60.0, 180.0])
@export var phase_pitch_limits: PackedFloat32Array = PackedFloat32Array([32.0, 45.0, 80.0])
## Keep the same tight darkness mask in every phase. Phase progression only
## loosens camera rotation; the mouse-driven flashlight remains the sole bright
## patch instead of the whole doorway becoming visible.
@export var phase_apertures: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0])
## Minigame-only flashlight reach and spread. Both are restored on exit.
@export_range(8.0, 30.0, 0.5) var encounter_flashlight_range: float = 16.5
@export_range(20.0, 55.0, 1.0) var encounter_flashlight_angle: float = 32.0
## The centre stays clear for the physical flashlight. Outside it, a small
## fraction of the world remains visible so silhouettes can guide the search
## without making the torch optional.
@export_range(0.15, 0.45, 0.01) var flashlight_focus_radius: float = 0.26
@export_range(0.0, 0.35, 0.01) var peripheral_visibility: float = 0.16
## How far the door leaf itself swings open per phase, in degrees.
@export var phase_leaf_swing: PackedFloat32Array = PackedFloat32Array([0.0, 26.0, 88.0])
## Hinge line the leaf swings around, in the door's own local space. Local, so
## the villa's scaled doors hinge on their own jamb without a second number.
@export var leaf_hinge_offset: Vector3 = Vector3(-1.1, 0.0, 0.0)
@export var eye_height: float = 1.5
@export var phase_transition_duration: float = 0.3
## Dramatic push-in while the beam is actually on the ghost: the camera FOV is
## squeezed to this fraction of the player camera's own FOV, so the ghost fills
## the frame for the length of the hold and through its recoil. Restored on exit.
@export_range(0.35, 1.0, 0.01) var lit_zoom_fraction: float = 0.58
## Seconds to reach the zoomed framing, and to fall back out of it. In fast, out
## slower, so the snap lands with the hit and the release is not a lurch.
@export_range(0.05, 1.0, 0.01) var zoom_in_duration: float = 0.14
@export_range(0.05, 1.5, 0.01) var zoom_out_duration: float = 0.32

@export_category("Ghost placement")
## Only markers this close to the attacked door are treated as its spots.
@export var spot_search_radius: float = 9.0
## A spot the door cannot actually see from is discarded below this distance.
@export var minimum_spot_distance: float = 1.8
## Minimum horizontal spawn distance from the phase viewpoint. Later phases
## open the door wider and deliberately put the ghost deeper into the exterior:
## close through the peephole, medium through the ajar door, far when open.
@export var phase_minimum_spot_distances: PackedFloat32Array = PackedFloat32Array([
	3.0, 4.8, 6.6,
])
## Fractions along the walk from a spot to the door that must also be in view.
## A spot the beam can reach is not enough on its own: the ghost has to stay
## hittable while it closes, or a doorway with something in the middle of its
## approach (House2's cellar areaway has a stair ramp there) hands the player a
## position they can only watch disappear.
@export var approach_samples: PackedFloat32Array = PackedFloat32Array([0.35, 0.7])
## How far short of whatever is behind it a spot is pulled back.
@export var spot_wall_margin: float = 0.4
## Closest the final stare brings the ghost to the player, in metres. The model
## is 1.70 m with its face at 1.58 m, just above the 1.50 m viewpoint, so this
## has to leave enough room for the head to still be in frame when it arrives.
@export var contact_distance: float = 1.45
## Height of the model's chest above its floor-anchored root - the point both
## the beam test and the occlusion ray target.
@export var ghost_chest_height: float = 1.2
@export_flags_3d_physics var sight_blocking_mask: int = 1
## The layer ghosts/door_ghost.tscn puts its own hit volume on (the same one
## the Huntsman's body uses). A beam only counts when the ray reaches *that*
## collider, so being roughly on screen is never enough.
@export_flags_3d_physics var ghost_hit_layer: int = 4
## Fraction of the flashlight's own cone that counts as a hit. Below 1.0 the
## player has to put the ghost near the middle of the beam, not just clip it.
@export_range(0.1, 1.0, 0.01) var flashlight_cone_fraction: float = 0.6

@export_category("Presentation")
@export var jumpscare_duration: float = 0.8
@export var success_duration: float = 0.75
@export var heartbeat_interval_far: float = 1.2
@export var heartbeat_interval_near: float = 0.3
@export var hint_duration: float = 2.5

@export_category("Ghost scene")
## Spawned into the running level - never parented to the player - so the ghost
## really is standing in the world rather than riding the camera rig.
@export var ghost_scene: PackedScene

@export_category("Lighting")
## Old-wiring wobble on the flashlight for the length of the encounter. Small
## on purpose: the beam is the only tool the player has, so it may look
## unreliable and must never actually be.
@export_range(0.0, 0.2, 0.005) var flashlight_flicker: float = 0.04
@export var flashlight_flicker_speed: float = 11.0
## Every artificial light in both maps is already in this group - house2.gd and
## house3/villa_electrical_setup.gd both register their fixtures there, and
## power_manager/light_flicker already drive it. The encounter borrows it to
## put the house out for the duration, so the flashlight is the only thing
## lighting the doorway.
@export var house_light_group: StringName = &"flickering_house_lights"
@export var blackout_house_lights: bool = true

@export_category("Development")
@export var dev_disable_other_ghost_attacks: bool = true

var active: bool = false
var state: State = State.INACTIVE
var phase_index: int = 0
## Hits landed in the current phase only - this is what the player is shown
## and what advances a phase. total_hits is kept for signals and tests.
var phase_hits: int = 0
var total_hits: int = 0
var threat_remaining: float = 0.0
var state_timer: float = 0.0
var lit_time: float = 0.0
var current_door: Node
var owning_player: Node3D

var spots: Array[Vector3] = []
var spot_index: int = -1
var ghost_origin: Vector3 = Vector3.ZERO
var outward: Vector3 = Vector3.FORWARD
var floor_height: float = 0.0

var ghost: DoorGhost

var _camera: Camera3D
var _camera_pivot: Node3D
var _flashlight: SpotLight3D
var _aperture: float = 0.0
var _flash: float = 0.0
var _heartbeat_timer: float = 0.0
var _hint_remaining: float = 0.0
var _progress_pulse: float = 0.0
var _rng := RandomNumberGenerator.new()
var _ghost_safety_acquired: bool = false
var _phase_tween: Tween
var _leaf_tween: Tween
var _current_leaf_swing: float = 0.0
var _spots_phase: int = -1
var _dodge_roll_checked: bool = false
var _dodge_from: Vector3 = Vector3.ZERO
var _dodge_to: Vector3 = Vector3.ZERO
var _dodge_return_state: State = State.SEARCH

var _saved_player_position: Vector3 = Vector3.ZERO
var _saved_player_yaw: float = 0.0
var _saved_pitch: float = 0.0
var _saved_yaw_clamp_active: bool = false
var _saved_flashlight_visible: bool = true
var _saved_flashlight_energy: float = 0.0
var _saved_flashlight_range: float = 0.0
var _saved_flashlight_angle: float = 0.0
var _saved_camera_fov: float = 0.0
var _zoom: float = 0.0
var _flicker_time: float = 0.0
## Lights this encounter switched off, and what they were before it did.
var _darkened_lights: Dictionary = {}
## The leaf assembly (everything on DoorVisual except the fixed frame) and its
## resting transforms, so the swing is undone exactly on the way out.
var _leaf_parts: Array[Node3D] = []
var _leaf_rest: Array[Transform3D] = []


@onready var overlay: CanvasLayer = $Overlay
@onready var mask: ColorRect = $Overlay/Mask
@onready var hint: Label = $Overlay/Hint
@onready var pips: HBoxContainer = $Overlay/Pips
@onready var progress: Label = $Overlay/Progress
@onready var music_audio: AudioStreamPlayer = $MusicAudio
@onready var drone_audio: AudioStreamPlayer = $DroneAudio
@onready var heartbeat_audio: AudioStreamPlayer = $HeartbeatAudio
@onready var relocate_audio: AudioStreamPlayer = $RelocateAudio
@onready var bone_audio: AudioStreamPlayer = $BoneAudio
@onready var flashlight_audio: AudioStreamPlayer = $FlashlightAudio
@onready var success_audio: AudioStreamPlayer = $SuccessAudio
@onready var jumpscare_audio: AudioStreamPlayer = $JumpscareAudio


func _ready() -> void:
	_rng.randomize()
	overlay.visible = false
	_ensure_audio_bus()
	# The bed has to outlast one encounter; the ghost loops its own whispers.
	var music_stream: Resource = music_audio.stream
	if music_stream and "loop" in music_stream:
		music_stream.set("loop", true)


func _exit_tree() -> void:
	if active:
		_report_outcome(PLAYER_SCRIPT.DoorOutcome.CANCELLED)
	_free_ghost()
	_restore_house()
	_release_ghost_safety()


## Called by Player.start_door_minigame() after the door has already granted
## the session through begin_exorcism().
func start(player: Node, door: Node) -> bool:
	if active or not is_instance_valid(door) or not door is Node3D:
		return false
	var player_body := player as Node3D
	if not is_instance_valid(player_body):
		return false
	_camera_pivot = player_body.get_node_or_null("CameraPivot") as Node3D
	_camera = player_body.get_node_or_null("CameraPivot/Camera3D") as Camera3D
	_flashlight = player_body.get_node_or_null("CameraPivot/Camera3D/Flashlight") as SpotLight3D
	if not _camera_pivot or not _camera:
		return false

	active = true
	current_door = door
	owning_player = player_body
	phase_hits = 0
	total_hits = 0
	lit_time = 0.0
	_flash = 0.0
	_heartbeat_timer = 0.0
	_hint_remaining = hint_duration

	var door_body := door as Node3D
	outward = _measure_outward(door_body)
	floor_height = _measure_floor(door_body.global_position)

	if not _spawn_ghost():
		active = false
		current_door = null
		owning_player = null
		return false
	_capture_player_state()
	_darken_house()
	_acquire_ghost_safety()
	spots.clear()
	spot_index = -1
	_spots_phase = -1
	_apply_phase(0, false)
	_aperture = phase_apertures[0]
	overlay.visible = true
	_update_progress()
	hint.modulate.a = 1.0
	_begin_search(true)
	music_audio.play()
	drone_audio.play()
	flashlight_audio.play()
	minigame_started.emit(door)
	return true


## The ghost lives in the level for exactly as long as the encounter does. It
## is parented to the running scene rather than to this node, because this node
## is a child of the player - anything under there is swung around by mouse-look
## instead of standing still in the world.
func _spawn_ghost() -> bool:
	if not ghost_scene:
		return false
	ghost = ghost_scene.instantiate() as DoorGhost
	if not ghost:
		return false
	var host: Node = get_tree().current_scene
	if not is_instance_valid(host):
		host = get_tree().root
	host.add_child(ghost)
	ghost.set_audio_bus(&"DoorMinigame")
	return true


func _free_ghost() -> void:
	if is_instance_valid(ghost):
		ghost.queue_free()
	ghost = null


func cancel() -> void:
	if not active:
		return
	_report_outcome(PLAYER_SCRIPT.DoorOutcome.CANCELLED)
	_close()


## The door is never touched directly. On a client this encounter is being
## played here while the door itself is the server's, so every outcome leaves
## through the player that owns this minigame - which is the node that knows
## whether it is the authority. On the authority that call lands straight on
## the door, exactly as it used to.
func _report_outcome(outcome: int) -> float:
	if not is_instance_valid(current_door):
		return 0.0
	if not is_instance_valid(owning_player) \
		or not owning_player.has_method("report_door_outcome"):
		return 0.0
	return float(owning_player.call("report_door_outcome", current_door, outcome))


func is_running() -> bool:
	return active


func get_phase_hits() -> int:
	return phase_hits


func get_total_hits() -> int:
	return total_hits


func get_hits_required() -> int:
	return maxi(hits_per_phase, 1) * TOTAL_PHASES


func get_threat_remaining() -> float:
	return threat_remaining


func get_phase_index() -> int:
	return phase_index


func set_random_seed(value: int) -> void:
	_rng.seed = value


func _process(delta: float) -> void:
	if not active:
		return
	if not is_instance_valid(current_door) \
		or not is_instance_valid(owning_player) \
		or not is_instance_valid(ghost):
		_close()
		return

	match state:
		State.SEARCH, State.STARE:
			_update_threat(delta)
		State.DODGE:
			_update_dodge(delta)
		State.RETREAT:
			state_timer -= delta
			if ghost.visible and state_timer <= retreat_duration - reaction_duration:
				_vanish_ghost()
			if state_timer <= 0.0:
				_begin_search(false)
		State.JUMPSCARE:
			_update_jumpscare(delta)
		State.SUCCESS:
			state_timer -= delta
			# The last hit reads like all the others - recoil, then gone.
			if ghost.visible and state_timer <= success_duration - reaction_duration:
				_vanish_ghost()
			if state_timer <= 0.0:
				_close()
	if active:
		_update_presentation(delta)


# ---------------------------------------------------------------- gameplay ---

func _update_threat(delta: float) -> void:
	threat_remaining -= delta
	if threat_remaining <= 0.0:
		_begin_failure()
		return

	var stare_at := stare_threshold
	if threat_remaining <= stare_at:
		if state != State.STARE:
			state = State.STARE
			relocate_audio.pitch_scale = _rng.randf_range(0.72, 0.86)
			relocate_audio.play()
			# It has arrived and stops walking, but remains vulnerable. A visible
			# ghost becoming immune in the centre of the flashlight reads as a
			# broken hitbox, not as a deadline.
			ghost.set_pose(DoorGhost.Pose.IDLE)
			_place_ghost(_stare_position())
		_check_flashlight(delta)
		return

	var travel := 1.0 - (threat_remaining - stare_at) / maxf(threat_window - stare_at, 0.01)
	if lit_time <= 0.0:
		ghost.set_pose(DoorGhost.Pose.APPROACH)
	_place_ghost(ghost_origin.lerp(
		_stare_position(), ease(clampf(travel, 0.0, 1.0), approach_easing)
	))
	_check_flashlight(delta)


func _check_flashlight(delta: float) -> void:
	if _flashlight_illuminates_ghost():
		if lit_time <= 0.0:
			flashlight_audio.play()
		lit_time += delta
		if not _dodge_roll_checked \
			and lit_time >= flashlight_confirm_time * dodge_trigger_fraction:
			_dodge_roll_checked = true
			if _rng.randf() < dodge_chance and _begin_dodge():
				return
		# Caught in the beam it stops walking and holds still, so the player can
		# tell a hit is landing before it completes.
		ghost.set_pose(DoorGhost.Pose.IDLE)
		if lit_time >= flashlight_confirm_time:
			_land_repel()
	else:
		lit_time = 0.0


func _begin_dodge() -> bool:
	var eye := _camera.global_position
	var eye_ground := Vector3(eye.x, floor_height, eye.z)
	var radial := ghost.global_position - eye_ground
	radial.y = 0.0
	if radial.length_squared() < 0.01:
		return false
	var first_side := -1.0 if _rng.randf() < 0.5 else 1.0
	for side: float in [first_side, -first_side]:
		var dodge_direction := radial.normalized().rotated(
			Vector3.UP, deg_to_rad(dodge_angle_degrees) * side
		)
		var candidate := eye_ground + dodge_direction * radial.length()
		candidate.y = _measure_floor(candidate)
		if not _inside_phase_yaw(candidate, eye) \
			or not _first_blocker(eye, candidate).is_empty():
			continue
		# Refund the incomplete hold and pause the deadline for the actual dodge.
		# The player must reacquire the ghost, but is never punished for the time
		# in which the game itself moved it out of the beam.
		threat_remaining = minf(threat_window, threat_remaining + lit_time)
		lit_time = 0.0
		_dodge_return_state = state
		state = State.DODGE
		state_timer = dodge_duration
		_dodge_from = ghost.global_position
		_dodge_to = candidate
		ghost.set_pose(DoorGhost.Pose.REACT)
		relocate_audio.pitch_scale = _rng.randf_range(1.08, 1.22)
		relocate_audio.play()
		return true
	return false


func _update_dodge(delta: float) -> void:
	state_timer = maxf(state_timer - delta, 0.0)
	var completion := 1.0 - state_timer / maxf(dodge_duration, 0.01)
	_place_ghost(_dodge_from.lerp(_dodge_to, ease(completion, -1.7)))
	if state_timer > 0.0:
		return
	ghost_origin = _dodge_to
	state = _dodge_return_state
	ghost.set_pose(
		DoorGhost.Pose.IDLE if state == State.STARE else DoorGhost.Pose.APPROACH
	)


## Real 3D test against the player's own SpotLight3D: inside its range, inside
## its cone, and the beam actually arriving at the ghost's own collider. Screen
## position is never consulted, and a ray that stops on a wall first is not a
## hit no matter how well the ghost lines up behind it.
func _flashlight_illuminates_ghost() -> bool:
	if not is_instance_valid(_flashlight) or not ghost.visible:
		return false
	var target := ghost.get_chest_point()
	var offset := target - _flashlight.global_position
	var distance := offset.length()
	if distance <= 0.05 or distance > _flashlight.spot_range:
		return false
	var half_angle := deg_to_rad(_flashlight.spot_angle) * flashlight_cone_fraction
	if (-_flashlight.global_transform.basis.z).dot(offset / distance) < cos(half_angle):
		return false

	# One ray answers both questions at once: did anything get in the way, and
	# is what the beam landed on the ghost itself.
	var query := PhysicsRayQueryParameters3D.create(
		_flashlight.global_position,
		target,
		sight_blocking_mask | ghost_hit_layer,
		_sight_exclusions()
	)
	query.collide_with_areas = true
	query.hit_from_inside = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and ghost.owns_collider(hit["collider"])


## One landed hit: it retreats, the phase counter moves, and the approach
## window starts over from full - _begin_search() is the only place that
## re-arms it, so the reset and the reposition can never come apart.
func _land_repel() -> void:
	phase_hits += 1
	total_hits += 1
	lit_time = 0.0
	_flash = 1.0
	# It recoils in the beam first and only then goes - see the RETREAT branch
	# in _process(), which is what actually takes it off the map.
	ghost.set_pose(DoorGhost.Pose.REACT)
	bone_audio.pitch_scale = _rng.randf_range(0.86, 1.14)
	bone_audio.play()
	repel_landed.emit(current_door, phase_index, phase_hits)

	if phase_hits < maxi(hits_per_phase, 1):
		_update_progress()
		state = State.RETREAT
		state_timer = retreat_duration
		return

	# Phase cleared.
	if phase_index >= TOTAL_PHASES - 1:
		_begin_success()
		return
	phase_hits = 0
	state = State.RETREAT
	state_timer = retreat_duration
	_apply_phase(phase_index + 1, true)
	_update_progress()


func _begin_search(is_first: bool) -> void:
	state = State.SEARCH
	threat_remaining = threat_window
	lit_time = 0.0
	_dodge_roll_checked = false
	if _spots_phase != phase_index:
		spots = _collect_spots()
		spot_index = -1
		_spots_phase = phase_index
	ghost_origin = _pick_spot()
	ghost.appear(ghost_origin)
	_place_ghost(ghost_origin)
	if not is_first:
		relocate_audio.pitch_scale = _rng.randf_range(0.9, 1.1)
		relocate_audio.play()
	ghost.start_whisper()


func _begin_success() -> void:
	state = State.SUCCESS
	state_timer = success_duration
	ghost.stop_whisper()
	drone_audio.stop()
	heartbeat_audio.stop()
	success_audio.play()
	ghost.set_pose(DoorGhost.Pose.REACT)
	_report_outcome(PLAYER_SCRIPT.DoorOutcome.CLEARED)
	minigame_completed.emit(current_door)


## Time ran out. The door itself owns the consequence: apply_exorcism_failure()
## is the same call the screenspace version made, so the ~20-point hit (or the
## repair-cap loss on an already breached door) happens once, in one place.
func _begin_failure() -> void:
	state = State.JUMPSCARE
	state_timer = jumpscare_duration
	ghost.stop_whisper()
	music_audio.stop()
	drone_audio.stop()
	heartbeat_audio.stop()
	jumpscare_audio.pitch_scale = _rng.randf_range(0.94, 1.04)
	jumpscare_audio.play()
	ghost.visible = true
	ghost.set_pose(DoorGhost.Pose.LUNGE)
	_place_ghost(_stare_position())

	var cap := _report_outcome(PLAYER_SCRIPT.DoorOutcome.FAILED)
	attempt_failed.emit(current_door, cap)


func _update_jumpscare(delta: float) -> void:
	state_timer -= delta
	var completion := 1.0 - clampf(state_timer / maxf(jumpscare_duration, 0.01), 0.0, 1.0)
	var lunge := _stare_position().lerp(_camera_ground_position(), ease(completion, -1.8))
	_place_ghost(lunge + Vector3(
		_rng.randf_range(-0.04, 0.04),
		0.0,
		_rng.randf_range(-0.04, 0.04)
	))
	if state_timer <= 0.0:
		# The attack is resolved; hand the door back to its normal attack flow.
		_report_outcome(PLAYER_SCRIPT.DoorOutcome.CANCELLED)
		_close()


# ------------------------------------------------------------- positioning ---

func _pick_spot() -> Vector3:
	if spots.is_empty():
		return _fallback_spot()
	if spots.size() == 1:
		spot_index = 0
		return spots[0]
	var next_index := spot_index
	while next_index == spot_index:
		next_index = _rng.randi_range(0, spots.size() - 1)
	spot_index = next_index
	return spots[spot_index]


func _place_ghost(position: Vector3) -> void:
	ghost.global_position = position
	if is_instance_valid(_camera):
		ghost.face_point(_camera.global_position)
	ghost.sync_collider()


## The vanish beat: the glitch that used to fire on the hit itself now fires
## here, so the sound is the ghost leaving rather than the ghost being struck.
func _vanish_ghost() -> void:
	ghost.vanish()
	relocate_audio.pitch_scale = _rng.randf_range(0.94, 1.14)
	relocate_audio.play()


## Where the ghost ends up when it stops and stares: floor level, directly in
## front of whatever viewpoint the current phase put the player at.
func _stare_position() -> Vector3:
	return _camera_ground_position() + outward * contact_distance


func _camera_ground_position() -> Vector3:
	var eye := (
		_camera.global_position
		if is_instance_valid(_camera)
		else (current_door as Node3D).global_position
	)
	return Vector3(eye.x, floor_height, eye.z)


## The direction the encounter faces, always horizontal. A door that is not
## standing upright - the villa tips entrance 07 onto its back to make a roof
## hatch - has no usable normal, so its own up axis stands in; either way the
## player ends up looking along the wall's outside, not into the floor.
func _measure_outward(door_body: Node3D) -> Vector3:
	var basis := door_body.global_transform.basis
	# Maps that rotate the shared defense-door asset independently of its
	# authored House2 convention can state the real exterior normal explicitly.
	# Falling back to local -Z preserves every existing House2 entrance.
	var direction: Vector3 = door_body.get_meta("exterior_outward", -basis.z)
	if absf(direction.normalized().y) > 0.7:
		direction = -basis.y
	direction.y = 0.0
	return direction.normalized() if direction.length_squared() > 0.001 else Vector3.FORWARD


## The door's own origin is on its floor in both maps, but the ground just
## outside it need not be (House2's cellar areaway, the villa's terraces), so
## the ghost's feet follow whatever is actually under the doorway.
func _measure_floor(near: Vector3) -> float:
	var query := PhysicsRayQueryParameters3D.create(
		near + Vector3.UP * 1.5,
		near + Vector3.DOWN * 3.0,
		sight_blocking_mask,
		_sight_exclusions()
	)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return float(hit["position"].y) if hit else near.y


## Used when no authored position survives - a doorway too cramped or too
## cluttered to host the arc. Backs straight out along the axis the ghost walks
## in on, which is clear by construction, and takes the furthest point on it
## the beam can still reach. Better a short straight approach than a position
## the player cannot win against.
func _fallback_spot() -> Vector3:
	var door_body := current_door as Node3D
	var eye := _view_position(phase_view_offsets[phase_index]) + Vector3.UP * (
		_camera_pivot.position.y if is_instance_valid(_camera_pivot) else 0.0
	)
	var ground := Vector3(eye.x, floor_height, eye.z)
	var phase_distance := _phase_minimum_spot_distance()
	var best := ground + outward * phase_distance
	for step: int in 8:
		var candidate := ground + outward * (phase_distance + float(step) * 0.45)
		candidate.y = _measure_floor(candidate)
		if not _first_blocker(eye, candidate).is_empty():
			break
		best = candidate
	return best


## Markers first, geometry second: every candidate comes from the SPOT_GROUP,
## then gets rebuilt on the encounter's own upright plane, floor-snapped, and
## pulled back out of anything standing in front of it. That is what lets one
## authored set of markers in defense_door.tscn work for the hand-built House2
## doors, the villa's scaled ones, and its tipped roof hatch alike.
##
## A spot only survives if the beam can actually reach it from the doorway, so
## the encounter can never hide the ghost somewhere it cannot be repelled.
func _collect_spots() -> Array[Vector3]:
	var resolved: Array[Vector3] = []
	var scored: Array[Dictionary] = []
	var door_body := current_door as Node3D
	var eye := _view_position(phase_view_offsets[phase_index]) + Vector3.UP * (
		_camera_pivot.position.y if is_instance_valid(_camera_pivot) else 0.0
	)
	for node: Node in get_tree().get_nodes_in_group(SPOT_GROUP):
		var marker := node as Node3D
		if not marker or not marker.is_inside_tree():
			continue
		if marker.global_position.distance_to(door_body.global_position) > spot_search_radius:
			continue
		if not _owns_spot(marker):
			continue
		var candidate := _spot_origin(marker, door_body)
		candidate = _apply_phase_minimum_distance(candidate, eye)
		if not _inside_phase_yaw(candidate, eye):
			continue
		candidate = _resolve_spot(candidate, eye)
		if candidate.is_finite():
			scored.append({"spot": candidate, "clearance": _approach_clearance(eye, candidate)})

	# Positions the ghost stays hittable from all the way in are the ones worth
	# using. Where a doorway has none - House2's cellar areaway is a stair well
	# with a ramp across the approach - take the best the geometry allows
	# rather than none at all, so the door stays winnable instead of handing
	# the player a ghost they can only watch vanish.
	var best := 0.0
	for entry: Dictionary in scored:
		best = maxf(best, float(entry["clearance"]))
	for entry: Dictionary in scored:
		if is_equal_approx(float(entry["clearance"]), best):
			resolved.append(entry["spot"] as Vector3)
	return resolved


## A marker parented under a defense door belongs to that door; a free-standing
## one a map author drops into the group belongs to the nearest door. Without
## this a door would borrow its neighbour's spots whenever two entrances are
## within spot_search_radius of each other.
func _owns_spot(marker: Node3D) -> bool:
	var ancestor := marker.get_parent()
	while ancestor:
		if ancestor.is_in_group("defense_doors"):
			return ancestor == current_door
		ancestor = ancestor.get_parent()
	var nearest: Node = current_door
	var nearest_distance := marker.global_position.distance_to((current_door as Node3D).global_position)
	for node: Node in get_tree().get_nodes_in_group("defense_doors"):
		var door_body := node as Node3D
		if not door_body:
			continue
		var distance := marker.global_position.distance_to(door_body.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = node
	return nearest == current_door


## A door-owned marker is authored in the door's own space, so it is re-read
## there and rebuilt on the upright encounter plane - that keeps the arc flat
## and outside even for a door lying on its back. Free-standing markers are
## already world-authored and are taken as they stand.
func _spot_origin(marker: Node3D, door_body: Node3D) -> Vector3:
	if not door_body.is_ancestor_of(marker):
		return marker.global_position
	var local := door_body.to_local(marker.global_position)
	var right := outward.cross(Vector3.UP).normalized()
	return (
		Vector3(door_body.global_position.x, floor_height, door_body.global_position.z)
		+ right * local.x
		+ outward * -local.z
	)


func _resolve_spot(candidate: Vector3, eye: Vector3) -> Vector3:
	var ground := Vector3(eye.x, floor_height, eye.z)
	var direction := candidate - ground
	direction.y = 0.0
	var distance := direction.length()
	if distance < 0.01:
		return Vector3.INF
	direction /= distance

	# Two passes: place it, and if something is in the way place it just short
	# of that instead. Whatever comes out has to pass the same visibility test
	# the flashlight will use, or it is dropped.
	for _pass: int in 2:
		if distance < _phase_minimum_spot_distance():
			return Vector3.INF
		candidate = ground + direction * distance
		candidate.y = _measure_floor(candidate)
		var blocker := _first_blocker(eye, candidate)
		if blocker.is_empty():
			return candidate
		# Horizontal, like the distance it replaces: eye is a metre and a half up,
		# so a straight 3D length here reads as further out than the spot is and
		# can slip a candidate under the phase minimum.
		var blocked: Vector3 = blocker["position"]
		distance = ground.distance_to(Vector3(blocked.x, floor_height, blocked.z)) - spot_wall_margin
	return Vector3.INF


func _phase_minimum_spot_distance() -> float:
	if phase_minimum_spot_distances.is_empty():
		return minimum_spot_distance
	return maxf(
		minimum_spot_distance,
		phase_minimum_spot_distances[clampi(
			phase_index, 0, phase_minimum_spot_distances.size() - 1
		)]
	)


func _apply_phase_minimum_distance(candidate: Vector3, eye: Vector3) -> Vector3:
	var ground := Vector3(eye.x, floor_height, eye.z)
	var direction := candidate - ground
	direction.y = 0.0
	var distance := direction.length()
	if distance < 0.01:
		direction = outward
		distance = 0.0
	if distance >= _phase_minimum_spot_distance():
		return candidate
	var result := ground + direction.normalized() * _phase_minimum_spot_distance()
	result.y = candidate.y
	return result


func _inside_phase_yaw(candidate: Vector3, eye: Vector3) -> bool:
	var yaw_limit := phase_yaw_limits[clampi(phase_index, 0, phase_yaw_limits.size() - 1)]
	if yaw_limit >= 179.0:
		return true
	var direction := candidate - Vector3(eye.x, floor_height, eye.z)
	direction.y = 0.0
	if direction.length_squared() < 0.001:
		return false
	var angle := rad_to_deg(acos(clampf(outward.dot(direction.normalized()), -1.0, 1.0)))
	# Keep a small input margin so a legal spawn is not exactly on the clamp.
	return angle <= maxf(yaw_limit - 2.0, 0.0)


## Fraction of the walk from `spot` to the door that the beam can still reach.
## 1.0 means the ghost stays hittable the whole way in.
func _approach_clearance(eye: Vector3, spot: Vector3) -> float:
	if approach_samples.is_empty():
		return 1.0
	var arrival := Vector3(eye.x, spot.y, eye.z) + outward * contact_distance
	var clear := 0
	for fraction: float in approach_samples:
		if _first_blocker(eye, spot.lerp(arrival, fraction)).is_empty():
			clear += 1
	return float(clear) / float(approach_samples.size())


func _first_blocker(eye: Vector3, spot: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(
		eye,
		spot + Vector3.UP * ghost_chest_height,
		sight_blocking_mask,
		_sight_exclusions()
	)
	query.hit_from_inside = true
	return get_world_3d().direct_space_state.intersect_ray(query)


func _sight_exclusions() -> Array[RID]:
	var exclusions: Array[RID] = []
	if is_instance_valid(owning_player) and owning_player.has_method("get_rid"):
		exclusions.append(owning_player.get_rid())
	if is_instance_valid(current_door) and current_door.has_method("get_rid"):
		exclusions.append(current_door.get_rid())
	return exclusions


# ------------------------------------------------------------------ phases ---

func _apply_phase(index: int, animate: bool) -> void:
	phase_index = clampi(index, 0, TOTAL_PHASES - 1)
	var target := _view_position(phase_view_offsets[phase_index])
	if _phase_tween and _phase_tween.is_running():
		_phase_tween.kill()
	if animate:
		_phase_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_phase_tween.tween_property(
			owning_player, "global_position", target, phase_transition_duration
		)
	else:
		owning_player.global_position = target
		_orient_camera_to_exterior()
	_apply_look_limits()
	_swing_leaf(phase_leaf_swing[phase_index], animate)
	encounter_phase_changed.emit(phase_index)


func _apply_look_limits() -> void:
	if not "yaw_clamp_active" in owning_player:
		return
	var yaw_limit := phase_yaw_limits[phase_index]
	owning_player.set("yaw_clamp_active", yaw_limit < 180.0)
	owning_player.set("yaw_clamp_min", -deg_to_rad(yaw_limit))
	owning_player.set("yaw_clamp_max", deg_to_rad(yaw_limit))
	owning_player.set("pitch_clamp_min", -deg_to_rad(phase_pitch_limits[phase_index]))
	owning_player.set("pitch_clamp_max", deg_to_rad(phase_pitch_limits[phase_index]))


func _view_position(offset: float) -> Vector3:
	var door_body := current_door as Node3D
	var pivot_height := _camera_pivot.position.y if is_instance_valid(_camera_pivot) else 0.0
	return (
		Vector3(door_body.global_position.x, floor_height, door_body.global_position.z)
		+ outward * offset
		+ Vector3.UP * (eye_height - pivot_height)
	)


## The encounter renders through the player's real camera, not a flat overlay.
## Lock its initial forward vector to the outside normal so the camera sees the
## level's exterior (garden, road, fog and props) beyond this door in both maps.
## Subsequent mouse movement is still constrained by the phase look limits.
func _orient_camera_to_exterior() -> void:
	if not is_instance_valid(owning_player):
		return
	var exterior_yaw := atan2(-outward.x, -outward.z)
	owning_player.rotation = Vector3(0.0, exterior_yaw, 0.0)
	if is_instance_valid(_camera_pivot):
		_camera_pivot.rotation = Vector3.ZERO
	if "accumulated_yaw" in owning_player:
		owning_player.set("accumulated_yaw", 0.0)


## Cosmetic only: the leaf assembly's transforms, never its collider, its
## durability or DoorVisual itself - defense_door.gd owns DoorVisual and resets
## it on every hit, so staying one level below it keeps the two from fighting.
func _swing_leaf(degrees: float, animate: bool) -> void:
	if _leaf_parts.is_empty():
		return
	if _leaf_tween and _leaf_tween.is_running():
		_leaf_tween.kill()
	if animate:
		_leaf_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_leaf_tween.tween_method(
			_set_leaf_swing, _current_leaf_swing, degrees, phase_transition_duration
		)
		bone_audio.pitch_scale = 0.6
		bone_audio.play()
	else:
		_set_leaf_swing(degrees)


func _set_leaf_swing(degrees: float) -> void:
	_current_leaf_swing = degrees
	var to_hinge := Transform3D(Basis.IDENTITY, -leaf_hinge_offset)
	var from_hinge := Transform3D(Basis.IDENTITY, leaf_hinge_offset)
	var swing := Transform3D(Basis(Vector3.UP, deg_to_rad(degrees)), Vector3.ZERO)
	var hinged := from_hinge * swing * to_hinge
	for index: int in _leaf_parts.size():
		if is_instance_valid(_leaf_parts[index]):
			_leaf_parts[index].transform = hinged * _leaf_rest[index]


func _capture_leaf_parts() -> void:
	_leaf_parts.clear()
	_leaf_rest.clear()
	_current_leaf_swing = 0.0
	var visual := (current_door as Node3D).get_node_or_null("DoorVisual") as Node3D
	if not visual:
		return
	for child: Node in visual.get_children():
		var part := child as Node3D
		# The frame stays in the wall; everything else is the leaf that swings.
		if part and not part.name.begins_with("Frame"):
			_leaf_parts.append(part)
			_leaf_rest.append(part.transform)


func _restore_leaf() -> void:
	for index: int in _leaf_parts.size():
		if is_instance_valid(_leaf_parts[index]):
			_leaf_parts[index].transform = _leaf_rest[index]
	_leaf_parts.clear()
	_leaf_rest.clear()
	_current_leaf_swing = 0.0


# ------------------------------------------------------------ presentation ---

func _update_presentation(delta: float) -> void:
	var pressure := 0.0
	match state:
		State.SEARCH:
			pressure = 1.0 - clampf(threat_remaining / maxf(threat_window, 0.01), 0.0, 1.0)
		State.DODGE:
			pressure = 1.0 - clampf(threat_remaining / maxf(threat_window, 0.01), 0.0, 1.0)
		State.STARE, State.JUMPSCARE:
			# It is on the doorstep. This is as bad as the picture gets.
			pressure = 1.0

	_aperture = move_toward(_aperture, phase_apertures[phase_index], delta * 2.2)
	_flash = maxf(_flash - delta * 4.0, 0.0)
	_update_zoom(delta)
	var material := mask.material as ShaderMaterial
	if material:
		var viewport_size := get_viewport().get_visible_rect().size
		material.set_shader_parameter("aperture", _aperture)
		material.set_shader_parameter("pressure", pressure)
		material.set_shader_parameter("flash", _flash)
		material.set_shader_parameter("focus_radius", flashlight_focus_radius)
		material.set_shader_parameter("peripheral_visibility", peripheral_visibility)
		if viewport_size.y > 0.0:
			material.set_shader_parameter("viewport_aspect", viewport_size.x / viewport_size.y)

	ghost.set_agitation(pressure)
	# The retro grade rides the same pressure the heartbeat and the teeth do:
	# more grain, wider colour fringing and a tighter vignette as it closes.
	if owning_player.has_method("set_danger_intensity"):
		owning_player.call("set_danger_intensity", pressure)
	_flicker_time += delta * flashlight_flicker_speed
	if is_instance_valid(_flashlight) and _saved_flashlight_energy > 0.0:
		var wobble := sin(_flicker_time) * sin(_flicker_time * 2.7) * flashlight_flicker
		_flashlight.light_energy = _saved_flashlight_energy * (1.0 + wobble)
	drone_audio.pitch_scale = lerpf(0.92, 1.12, pressure)
	drone_audio.volume_db = lerpf(-16.0, -6.0, pressure)
	ghost.set_whisper_pitch(lerpf(0.9, 1.15, pressure))
	music_audio.pitch_scale = lerpf(0.96, 1.08, pressure)

	_heartbeat_timer -= delta
	if _heartbeat_timer <= 0.0 and state in [State.SEARCH, State.STARE]:
		heartbeat_audio.pitch_scale = lerpf(0.88, 1.45, pressure)
		heartbeat_audio.volume_db = lerpf(-16.0, -4.0, pressure)
		heartbeat_audio.play()
		_heartbeat_timer = lerpf(heartbeat_interval_far, heartbeat_interval_near, pressure)

	_progress_pulse = maxf(_progress_pulse - delta * 2.0, 0.0)
	progress.modulate = Color(1.0, 1.0, 1.0, lerpf(0.72, 1.0, _progress_pulse))
	if _hint_remaining > 0.0:
		_hint_remaining -= delta
		hint.modulate.a = clampf(_hint_remaining, 0.0, 1.0)

## The camera pushes in on the ghost the moment the beam actually lands on it,
## and holds through the recoil that follows a repel. It is framing only - the
## hit test is the 3D beam ray in _flashlight_illuminates_ghost(), which a
## narrower FOV neither helps nor hinders.
func _update_zoom(delta: float) -> void:
	var want_zoom := lit_time > 0.0 or (state in [State.RETREAT, State.SUCCESS] and ghost.visible)
	var duration := zoom_in_duration if want_zoom else zoom_out_duration
	_zoom = move_toward(_zoom, 1.0 if want_zoom else 0.0, delta / maxf(duration, 0.01))
	if is_instance_valid(_camera) and _saved_camera_fov > 0.0:
		_camera.fov = lerpf(
			_saved_camera_fov, _saved_camera_fov * lit_zoom_fraction, ease(_zoom, 0.6)
		)


## The player is only ever shown where they are in the phase they are in.
func _update_progress() -> void:
	var required := maxi(hits_per_phase, 1)
	progress.text = "PHASE %d · %s\nSOI MA: %d / %d" % [
		phase_index + 1,
		phase_names[phase_index] if phase_index < phase_names.size() else "",
		phase_hits,
		required,
	]
	_progress_pulse = 1.0
	for index: int in pips.get_child_count():
		var pip := pips.get_child(index) as CanvasItem
		pip.visible = index < required
		pip.modulate = (
			Color(0.86, 0.94, 1.0, 0.95) if index < phase_hits else Color(1, 1, 1, 0.18)
		)


# ---------------------------------------------------------------- lifecycle ---

## Puts the house out for the length of the encounter, so the flashlight is the
## only thing lighting the doorway and the ghost is genuinely something the
## player has to find. Uses `visible`, which is the same switch power_manager
## already throws for a blackout, so light_flicker skips these lights instead
## of fighting for them (it only ever picks a light that is visible).
func _darken_house() -> void:
	if not blackout_house_lights:
		return
	for node: Node in get_tree().get_nodes_in_group(house_light_group):
		var light := node as Light3D
		if not light:
			continue
		_darkened_lights[light] = light.visible
		light.visible = false


## Only this encounter's own lights go back on, and only if the house is not
## already in a real outage - otherwise ending an encounter during a blackout
## would switch the lights on for the power manager.
func _restore_house() -> void:
	var blackout := false
	for node: Node in get_tree().get_nodes_in_group(&"power_manager"):
		if bool(node.get("is_blackout")):
			blackout = true
			break
	if not blackout:
		for entry: Variant in _darkened_lights:
			var light := entry as Light3D
			if is_instance_valid(light):
				light.visible = bool(_darkened_lights[entry])
	_darkened_lights.clear()


func _capture_player_state() -> void:
	_saved_player_position = owning_player.global_position
	_saved_camera_fov = _camera.fov
	_zoom = 0.0
	_saved_player_yaw = owning_player.rotation.y
	_saved_pitch = _camera_pivot.rotation.x
	_saved_yaw_clamp_active = bool(owning_player.get("yaw_clamp_active"))
	_capture_leaf_parts()
	if is_instance_valid(_flashlight):
		_saved_flashlight_visible = _flashlight.visible
		_saved_flashlight_energy = _flashlight.light_energy
		_saved_flashlight_range = _flashlight.spot_range
		_saved_flashlight_angle = _flashlight.spot_angle
		_flashlight.visible = true
		_flashlight.spot_range = encounter_flashlight_range
		_flashlight.spot_angle = encounter_flashlight_angle


func _close() -> void:
	for audio: Node in [
		music_audio, drone_audio, heartbeat_audio,
		relocate_audio, bone_audio, success_audio,
	]:
		audio.call("stop")
	if _phase_tween and _phase_tween.is_running():
		_phase_tween.kill()
	if _leaf_tween and _leaf_tween.is_running():
		_leaf_tween.kill()

	active = false
	state = State.INACTIVE
	overlay.visible = false
	_free_ghost()
	_restore_house()
	_restore_player_state()
	_release_ghost_safety()
	current_door = null
	owning_player = null
	minigame_closed.emit()


func _restore_player_state() -> void:
	_restore_leaf()
	if is_instance_valid(_camera) and _saved_camera_fov > 0.0:
		_camera.fov = _saved_camera_fov
	_zoom = 0.0
	if is_instance_valid(_flashlight):
		_flashlight.visible = _saved_flashlight_visible
		if _saved_flashlight_energy > 0.0:
			_flashlight.light_energy = _saved_flashlight_energy
		_flashlight.spot_range = _saved_flashlight_range
		_flashlight.spot_angle = _saved_flashlight_angle
	if is_instance_valid(owning_player) and owning_player.has_method("set_danger_intensity"):
		owning_player.call("set_danger_intensity", 0.0)
	if not is_instance_valid(owning_player):
		return
	owning_player.global_position = _saved_player_position
	owning_player.rotation = Vector3(0.0, _saved_player_yaw, 0.0)
	if is_instance_valid(_camera_pivot):
		_camera_pivot.rotation = Vector3(_saved_pitch, 0.0, 0.0)
	if "yaw_clamp_active" in owning_player:
		owning_player.set("yaw_clamp_active", _saved_yaw_clamp_active)
		owning_player.set("pitch_clamp_min", -PI / 2.0)
		owning_player.set("pitch_clamp_max", PI / 2.0)


func _acquire_ghost_safety() -> void:
	if _ghost_safety_acquired or not dev_disable_other_ghost_attacks:
		return
	_ghost_safety_acquired = true
	if is_instance_valid(owning_player) and owning_player.has_method("acquire_minigame_ghost_safety"):
		owning_player.call("acquire_minigame_ghost_safety")


func _release_ghost_safety() -> void:
	if not _ghost_safety_acquired:
		return
	_ghost_safety_acquired = false
	if is_instance_valid(owning_player) and owning_player.has_method("release_minigame_ghost_safety"):
		owning_player.call("release_minigame_ghost_safety")


func _ensure_audio_bus() -> void:
	var bus_index := AudioServer.get_bus_index("DoorMinigame")
	if bus_index < 0:
		AudioServer.add_bus()
		bus_index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus_index, "DoorMinigame")
		AudioServer.set_bus_send(bus_index, "Master")
		var compressor := AudioEffectCompressor.new()
		compressor.threshold = -13.0
		compressor.ratio = 4.0
		AudioServer.add_bus_effect(bus_index, compressor)
		var limiter := AudioEffectLimiter.new()
		limiter.ceiling_db = -1.0
		AudioServer.add_bus_effect(bus_index, limiter)
	for audio: Node in [
		music_audio, drone_audio, heartbeat_audio, relocate_audio,
		bone_audio, flashlight_audio, success_audio, jumpscare_audio,
	]:
		audio.set("bus", "DoorMinigame")


## Test hooks. The encounter is driven by real 3D geometry, so the headless
## smoke test aims the real flashlight instead of faking a hit.
func debug_step(delta: float) -> void:
	if active:
		_process(delta)


func debug_aim_at_ghost() -> void:
	if not active or not is_instance_valid(_camera_pivot):
		return
	var offset := ghost.global_position + Vector3.UP * ghost_chest_height - _camera.global_position
	if offset.length_squared() < 0.0001:
		return
	owning_player.rotation.y = atan2(-offset.x, -offset.z)
	_camera_pivot.rotation.x = asin(clampf(offset.normalized().y, -1.0, 1.0))


func debug_look_away() -> void:
	if active and is_instance_valid(owning_player):
		owning_player.rotation.y += PI
