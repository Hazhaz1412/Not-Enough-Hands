extends CharacterBody3D

signal killed_by_ghost(ghost: Node3D)
signal downed_changed(downed: bool)
signal became_spectator()
signal door_minigame_started(door: Node)
signal door_minigame_finished()
signal hunter_trap_changed(trapped: bool)
signal toilet_ghost_stun_changed(active: bool)

@export_category("Multiplayer")
@export var owner_peer_id: int = 0
@export var display_name: String = "Player"

@export var walk_speed: float = 7.5
@export var crouch_speed: float = 3.45
@export var sprint_speed_multiplier: float = 2.3
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

@export_category("Downed & Revive")
## Total time this player may ever spend on the floor. It is a run-long budget,
## not a per-death timer: it never refills, so each rescue costs the team from
## the same pool and a third trip down is normally the last one.
@export var downed_time_budget: float = 180.0
## Flat charge taken from the budget the moment a ghost puts this player down.
@export var downed_death_cost: float = 60.0
## Uninterrupted seconds a teammate must hold the interact key to lift them up.
@export var revive_duration: float = 10.0
@export var revive_range: float = 2.4
## How fast an abandoned rescue unwinds, as a multiple of real time.
@export var revive_decay_multiplier: float = 2.0
@export var downed_camera_height: float = -0.6
@export var downed_camera_roll_degrees: float = 18.0

@export_category("Camera Feel")
@export var head_bob_frequency: float = 8.0
@export var head_bob_horizontal: float = 0.012
@export var head_bob_vertical: float = 0.018

@export_category("Hunter Gaze Interference")
## Looking deliberately at a manifested Hunter corrupts the camera feed. The
## inner angle is fully affected; the outer angle is a soft shoulder so a tiny
## mouse movement does not make the post-process pop on and off.
@export var hunter_gaze_range: float = 28.0
@export_range(0.5, 15.0, 0.5) var hunter_gaze_full_angle: float = 3.5
@export_range(1.0, 25.0, 0.5) var hunter_gaze_outer_angle: float = 11.0
## A nearby wall muffles the signal instead of cutting it perfectly. This range
## is intentionally short so the leak reads as "right on the other side" and
## never turns into a general-purpose Hunter detector.
@export var hunter_gaze_through_wall_range: float = 5.0
@export_range(0.0, 0.5, 0.01) var hunter_gaze_through_wall_strength: float = 0.2
@export var hunter_gaze_fade_in_speed: float = 7.5
@export var hunter_gaze_fade_out_speed: float = 5.0
@export_flags_3d_physics var hunter_gaze_blocking_mask: int = 1

@export_category("Movement Audio")
@export var walk_step_interval: float = 0.48
@export var sprint_step_interval: float = 0.34
@export var crouch_step_interval: float = 0.7
@export var footstep_slice_duration: float = 0.38

var is_crouching: bool = false
@export var max_stamina: float = 125.0
@export var sprint_stamina_drain: float = 20.0
@export var stamina_regen_idle: float = 23.0
@export var stamina_regen_moving: float = 5.75

var current_stamina: float = max_stamina
var head_bob_time: float = 0.0
var is_alive: bool = true
## Downed players are deliberately not alive: every ghost's target scan already
## skips `is_alive == false`, so going down removes this player from all three
## of them without adding a fourth condition to each ghost.
var is_downed: bool = false
var is_spectator: bool = false
var downed_time_remaining: float = 180.0
var revive_progress: float = 0.0
## Highest threat currently reported by any ghost - drives the horror overlay
## and the camera sway. Kept under its original name because the shader
## parameter and the camera code already read it.
var statue_threat: float = 0.0
var threat_sources: Dictionary = {}
var hunter_gaze_strength: float = 0.0
@export var mouse_sensitivity: float = 0.002
@export var max_interaction_range: float = 10.0

@export_category("Peek")
## Holding Q/E leans the head out sideways without moving the body, so a corner
## can be checked before it is walked around. It is aimed squarely at the
## Huntsman: it hunts by line of sight from any angle, so the corner you walk
## blindly into is the one that kills you, and this is the way to spend a second
## instead of a life on it.
@export_range(0.0, 45.0, 0.5) var lean_max_angle: float = 18.0
## How far the eye slides sideways. Far enough to clear a doorframe, short
## enough that the body it belongs to is still behind cover.
@export_range(0.0, 1.5, 0.01) var lean_side_offset: float = 0.42
@export_range(0.5, 20.0, 0.1) var lean_speed: float = 7.0
## Fraction of the way to an obstruction the head is allowed to travel. Without
## it a lean pushes the camera through the very wall it is peeking around.
@export_range(0.1, 1.0, 0.05) var lean_wall_margin: float = 0.75
var _lean: float = 0.0
var _lean_reach: float = 0.0
var _network_lean: float = 0.0
var _camera_pivot_base_x: float = 0.0

@export_category("Flashlight")
## The torch is the one light a player carries, and it is now the one light
## they can run out of. A full battery is 215 seconds of ordinary beam against
## a 605-second night, so the switch (F) is a real decision rather than a
## formality, and the house's own lighting is the only free light there is.
##
## One unit is one second of ordinary beam, because the ordinary drain below is
## 1.0/s. That is the whole reason it is 1.0: these numbers get retuned every
## playtest, and a tank measured in seconds can be read straight off the design
## conversation instead of being divided out of it every time.
@export var flashlight_battery_max: float = 215.0
@export_range(0.0, 20.0, 0.05) var flashlight_drain_per_second: float = 1.0
## Holding the focus (right mouse) narrows the beam into something that can
## actually kill the Darkness Ghost, and burns just over six times the charge
## doing it: 35 seconds of focus out of a full tank, against 215 of plain light.
## The kill is paid for out of the same tank as seeing where you are, which is
## the point - but it is one third of the tank for a three-torch kill, not the
## whole evening.
@export_range(0.0, 40.0, 0.05) var flashlight_focus_drain_per_second: float = 6.15
@export_range(1.0, 60.0, 0.5) var flashlight_focus_angle: float = 12.0
@export_range(1.0, 6.0, 0.05) var flashlight_focus_energy_scale: float = 2.2
@export_range(1.0, 4.0, 0.05) var flashlight_focus_range_scale: float = 1.4
## Degrees of field of view the focus closes in. The beam narrowing on its own
## reads as the torch changing; the view narrowing with it is what reads as the
## player leaning into the thing they are burning, and it costs peripheral
## vision at exactly the moment something is walking at them.
@export_range(0.0, 40.0, 0.5) var flashlight_focus_fov_loss: float = 16.0
## How fast the zoom eases in and out. Instant would be a flinch, not a focus.
@export_range(0.5, 20.0, 0.1) var flashlight_focus_zoom_speed: float = 6.0
var _focus_zoom: float = 0.0
var flashlight_battery: float = 0.0
var _flashlight_on: bool = true
var _flashlight_focus_held: bool = false

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
var _flashlight_base_angle: float = 0.0

@export_category("Bladder Pressure")
## Where needing to go stops being a bar and starts costing something. Below
## this the penalties are exactly zero.
@export_range(0.0, 1.0, 0.05) var bladder_debuff_threshold: float = 0.75
## Degrees of field of view lost at a completely full bladder. Tunnel vision,
## not blindness - the room stays readable, there is just less of it.
@export_range(0.0, 40.0, 1.0) var bladder_debuff_fov_loss: float = 14.0
## Added to the overlay's own vignette at a full bladder, on top of whatever the
## rest of the night is already doing to it.
@export_range(0.0, 0.8, 0.05) var bladder_debuff_vignette: float = 0.35
## How much faster a sprint burns stamina at a full bladder. At 0.6 a full
## bladder costs 60% more per second, so the 6.25-second full reserve falls to
## just under four seconds.
@export_range(0.0, 3.0, 0.1) var bladder_debuff_stamina_scale: float = 0.6

## Mirrors `vignette_strength`'s default in ui/horror_overlay.gdshader, used when
## the scene never assigned one. Keep the two in step.
const OVERLAY_DEFAULT_VIGNETTE := 0.20

@export_subgroup("Losing control")
## An accident is not the tail of the pressure curve, it is its own state, and
## these are flat for the whole of it. Scaling them off the bladder level the
## way the pressure debuff does made the punishment evaporate: the level falls
## as it drains, so the penalty was gone under seven seconds into a
## twenty-seven-second accident and the rest was free.
@export_range(0.0, 60.0, 1.0) var wetting_fov_loss: float = 28.0
@export_range(0.0, 1.0, 0.05) var wetting_vignette: float = 0.6
## Walking pace while it happens. There is no sprint at all, but no hard lock
## either - twenty-seven seconds rooted to the floor in a house with a huntsman
## that never leaves is not a debuff, it is a death sentence.
@export_range(0.1, 1.0, 0.05) var wetting_speed_multiplier: float = 0.35
## Captured on first use rather than exported, so the debuff always releases
## back to whatever the scene actually authored.
var _camera_base_fov: float = 0.0
var _overlay_base_vignette: float = -1.0
## Set on a client between a toilet session ending and the server acknowledging
## the drain, so a snapshot from before the report cannot refill the bar.
var _bladder_report_pending: bool = false
## How long that latch will wait for the acknowledgement before deciding it is
## never coming. It only ever has to cover one report -> apply -> next snapshot
## round trip: a reliable packet up, and at most `NETWORK_STATE_INTERVAL` back.
## Three seconds is an order of magnitude past that even on a connection this
## game is already unplayable on, so it can only fire when the ack genuinely
## will not arrive.
const TOILET_REPORT_ACK_TIMEOUT := 3.0
## Seconds `_bladder_report_pending` has been waiting, counted only while it is
## set - see `_update_toilet_report_timeout()`.
var _bladder_report_wait: float = 0.0
## Incremented on the client each time a toilet report is sent, and echoed
## back by the server as server_toilet_ack in every snapshot (see
## _last_applied_toilet_report below). Reconciliation used to compare the
## reported bladder *value* against the server's broadcast value with a
## fixed +-0.01 tolerance - but the server keeps filling passively the whole
## round trip, and even just the 50ms gap to the next 20Hz broadcast (let
## alone real ping) routinely drifts past 0.01. Once it did, the server's
## value never dips back below the client's frozen one again until a full
## fill/wetting cycle, so the client's bar simply stopped updating - the
## "sometimes still full after peeing" bug. Comparing sequence numbers
## instead of values is exact regardless of latency or fill rate.
var _toilet_report_sequence: int = 0

## Temporary look-around constraint a minigame can impose (ToiletMinigame and
## DoorGhostMinigame) - false/full-range outside any minigame, so normal
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
var _dev_vision_light: OmniLight3D
var hunter_trap_source: Node3D

@onready var camera_pivot: Node3D = $CameraPivot
@onready var interact_ray: RayCast3D = $CameraPivot/Camera3D/InteractRay
@onready var flashlight: SpotLight3D = $CameraPivot/Camera3D/Flashlight
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var horror_overlay_rect: ColorRect = $HorrorOverlay/VignetteAndGrain
@onready var death_ui: CanvasLayer = $DeathUI
@onready var jumpscare: JumpscareController = $Jumpscare
@onready var footstep_players: Array[AudioStreamPlayer3D] = [$FootstepA, $FootstepB]
@onready var door_minigame: Node3D = get_node_or_null("DoorGhostMinigame") as Node3D
@onready var equipment: PlayerEquipment = $Equipment
@onready var bladder: PlayerBladder = $Bladder

## Set by start_toilet_minigame() for the duration of this player's session -
## ToiletMinigame lives per-toilet, not as a fixed child of Player like
## DoorGhostMinigame, since only one toilet can ever be occupied by this
## player at a time.
var _active_toilet_minigame: Node = null

## Same arrangement for BreakerMinigame, which lives per-breaker.
var _active_breaker_minigame: Node = null
## Server-side only: the highest _toilet_report_sequence this player's own
## client has had applied, echoed back to it so it can tell a stale snapshot
## from one that actually reflects its last report.
var _last_applied_toilet_report: int = 0
var _pending_jumpscare_killer: Node3D = null

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

const NETWORK_STATE_INTERVAL := 1.0 / 20.0
const NETWORK_SERVER_PEER_ID := 1
const PREDICTION_HISTORY_LIMIT := 180
## Measured in metres, but what it really is is "more frames of movement than a
## prediction error can plausibly be". It scales with sprint speed: at 17.25 m/s
## a 20 Hz snapshot is 0.86 m, so this stays a few packets clear of ordinary lag
## and only a genuine divergence snaps the body.
const PREDICTION_HARD_SNAP_DISTANCE := 2.3
const PREDICTION_CORRECTION_DEAD_ZONE := 0.03
const PREDICTION_RECONCILIATION_SPEED := 10.0

## What an encounter played on somebody's own machine reports back to the door.
enum DoorOutcome {
	CLEARED,
	FAILED,
	CANCELLED,
}

## The only three methods a handed-over encounter may re-enter on the owner's
## machine. The RPC that carries one is authority-only, but naming them here
## keeps it a fixed list rather than "whatever the server asks for".
const REMOTE_ENCOUNTER_STARTERS: Array[StringName] = [
	&"start_door_minigame",
	&"start_breaker_minigame",
	&"start_toilet_minigame",
]

## What this player is away at while the encounter is played on their own
## machine. Set only on the peer holding the *replica* - which is the server -
## and null everywhere the encounter is actually being played.
var _remote_encounter_target: Node = null
var _remote_encounter_starter: StringName = &""

var _network_move := Vector2.ZERO
var _network_jump: bool = false
var _network_crouch: bool = false
var _network_run: bool = false
## Held rather than pressed: reviving a teammate is the one interaction that
## needs the key's continuous state on the server, not a single edge.
var _network_interact: bool = false
var _network_flashlight_on: bool = true
var _network_flashlight_focus: bool = false
var _previous_network_jump: bool = false
var _network_yaw: float = 0.0
var _network_pitch: float = 0.0
var _state_sync_remaining: float = 0.0
var _snapshot_position := Vector3.ZERO
var _snapshot_yaw: float = 0.0
var _snapshot_pitch: float = 0.0
var _snapshot_velocity := Vector3.ZERO
var _has_network_snapshot: bool = false
var _snapshot_age: float = 0.0
var _local_input_sequence: int = 0
var _last_processed_input_sequence: int = -1
var _prediction_history: Dictionary = {}
var _pending_reconciliation := Vector3.ZERO
## Life-cycle changes use a reliable side channel in addition to the regular
## 20 Hz snapshot. The revision keeps a late, pre-death unreliable packet from
## briefly putting a player back on their feet after the reliable update.
var _life_state_revision: int = 0
var _last_received_life_state_revision: int = -1

func _ready() -> void:
	# Interior doors query this group for a light physical push. Keeping the
	# lookup on the door means player movement needs no door-specific branches.
	add_to_group(&"players")
	_footstep_rng.randomize()
	current_stamina = max_stamina
	downed_time_remaining = downed_time_budget
	var shape := collision_shape.shape as CapsuleShape3D
	shape.radius = player_radius
	shape.height = standing_height
	_network_yaw = rotation.y
	_network_pitch = camera_pivot.rotation.x
	_configure_player_presentation()
	if is_local_player() and DisplayServer.get_name() != "headless":
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if interact_ray:
		interact_ray.target_position = Vector3(0, 0, -max_interaction_range)
	flashlight_battery = flashlight_battery_max
	_camera_pivot_base_x = camera_pivot.position.x
	if flashlight:
		_flashlight_base_energy = flashlight.light_energy
		_flashlight_base_range = flashlight.spot_range
		_flashlight_base_angle = flashlight.spot_angle
		_apply_flashlight_state()
	if jumpscare:
		jumpscare.jumpscare_finished.connect(_on_ghost_jumpscare_finished)


func _exit_tree() -> void:
	if WorldNet.is_world_authority():
		_release_remote_encounter_target()


## Status visuals keep ticking while a minigame temporarily disables this
## body's physics. That makes a seven-second Toilet Ghost stun seven seconds
## of real gameplay time, including the brief camera-release transition.
func _process(delta: float) -> void:
	if not _is_network_session() or multiplayer.is_server() or is_local_player():
		_update_toilet_ghost_stun(delta)
	if is_local_player():
		_update_hunter_gaze_interference(delta)
		_update_bladder_pressure(delta)
		_update_toilet_report_timeout(delta)


## Needing to go is a real cost above `bladder_debuff_threshold` and not just a
## bar going orange: the view closes in and running burns stamina faster, so a
## player who ignores it is measurably worse at escaping the thing chasing them.
## Scaled from the threshold to full rather than switched on at it, so the
## penalty arrives as pressure rather than as a cliff.
##
## Local-only, exactly like the hunter-gaze vignette above: this is one player's
## own camera and their own stamina drain is applied where the movement is.
func _update_bladder_pressure(delta: float) -> void:
	# Two states, not one curve. Approaching full scales with how full it is;
	# an accident is flat and much worse, for the whole of its duration.
	var fov_loss := bladder_debuff_fov_loss * get_bladder_pressure()
	var vignette := bladder_debuff_vignette * get_bladder_pressure()
	if is_wetting():
		fov_loss = wetting_fov_loss
		vignette = wetting_vignette

	# The focus zoom is added here rather than written to the camera on its own,
	# because this is the only line in the game that owns camera.fov: a second
	# writer would mean the zoom and an accident's tunnel vision each erasing
	# the other, whichever ran last. Added, not maxed - focusing a torch while
	# wetting yourself should be the worst view in the game, not the same one.
	_focus_zoom = move_toward(
		_focus_zoom,
		1.0 if is_flashlight_focused() else 0.0,
		flashlight_focus_zoom_speed * delta
	)
	fov_loss += flashlight_focus_fov_loss * _focus_zoom

	var camera := camera_pivot.get_node_or_null("Camera3D") as Camera3D
	if camera:
		if _camera_base_fov <= 0.0:
			_camera_base_fov = camera.fov
		camera.fov = _camera_base_fov - fov_loss
	var overlay_material := horror_overlay_rect.material as ShaderMaterial
	if overlay_material == null:
		return
	if _overlay_base_vignette < 0.0:
		# A uniform the scene never overrode reads back as null rather than as
		# the shader's own default, and float(null) is a hard error - so the
		# default is mirrored here instead of assumed to be readable.
		var authored: Variant = overlay_material.get_shader_parameter("vignette_strength")
		_overlay_base_vignette = (
			float(authored) if authored != null else OVERLAY_DEFAULT_VIGNETTE
		)
	overlay_material.set_shader_parameter(
		"vignette_strength",
		clampf(_overlay_base_vignette + vignette, 0.0, 1.0)
	)


## 0 below the threshold, 1 at a full bladder. Everything that punishes a full
## bladder reads this one number so they cannot disagree about when it starts.
func get_bladder_pressure() -> float:
	if bladder == null or not is_alive:
		return 0.0
	var ratio := bladder.get_bladder_ratio()
	var span := maxf(1.0 - bladder_debuff_threshold, 0.001)
	return clampf((ratio - bladder_debuff_threshold) / span, 0.0, 1.0)


## The one release the toilet-report latch would otherwise not have.
##
## While `_bladder_report_pending` is set the client refuses every bladder
## snapshot, and only an acknowledgement clears it - which the authority is
## free to never send. `_report_remote_encounter_finished()` drops a report
## whose encounter the server has already let go (the toilet resolved to null
## on a peer mid-map-swap, the body left the tree with the run) without ever
## advancing the ack, and it is right to: that ownership check is what stops a
## client asserting an arbitrary bladder without the server having granted it a
## session. So the latch is released from this end instead. Left unbounded it
## froze the bar for the rest of the run, deaf to the authority - the same
## class of bug as the refill it exists to prevent, just pointing the other
## way. Taking the server's word one snapshot late beats never taking it again.
func _update_toilet_report_timeout(delta: float) -> void:
	if not _bladder_report_pending:
		_bladder_report_wait = 0.0
		return
	_bladder_report_wait += delta
	if _bladder_report_wait >= TOILET_REPORT_ACK_TIMEOUT:
		_bladder_report_pending = false
		_bladder_report_wait = 0.0


## This is intentionally a local camera check rather than part of the Hunter's
## server-side AI. Each player can be looking in a different direction, and the
## replicated Hunter body already gives every client all the geometry needed to
## decide what their own camera can see.
func _update_hunter_gaze_interference(delta: float) -> void:
	var target_strength := _hunter_gaze_target_strength()
	var speed := hunter_gaze_fade_in_speed \
		if target_strength > hunter_gaze_strength else hunter_gaze_fade_out_speed
	hunter_gaze_strength = move_toward(
		hunter_gaze_strength,
		target_strength,
		maxf(speed, 0.0) * delta
	)
	var overlay_material := horror_overlay_rect.material as ShaderMaterial
	if overlay_material:
		overlay_material.set_shader_parameter("hunter_gaze_strength", hunter_gaze_strength)


func _hunter_gaze_target_strength() -> float:
	if dev_clear_vision or not is_alive or hunter_gaze_range <= 0.0:
		return 0.0
	var camera := camera_pivot.get_node_or_null("Camera3D") as Camera3D
	if not camera or not camera.current:
		return 0.0

	var forward := -camera.global_basis.z.normalized()
	var full_angle := deg_to_rad(minf(hunter_gaze_full_angle, hunter_gaze_outer_angle))
	var outer_angle := deg_to_rad(maxf(hunter_gaze_full_angle, hunter_gaze_outer_angle))
	outer_angle = maxf(outer_angle, full_angle + 0.0001)
	var strongest := 0.0
	for node: Node in get_tree().get_nodes_in_group(&"hunter_ghosts"):
		var hunter := node as Node3D
		if not _is_visible_hunter(hunter):
			continue
		# Aim at the torso instead of the feet: it matches both the collision
		# capsule and the part of the silhouette the player naturally centres.
		var target_point := hunter.global_position + Vector3.UP * 1.05
		var offset := target_point - camera.global_position
		var distance := offset.length()
		if distance <= 0.001 or distance > hunter_gaze_range:
			continue
		if _hunter_gaze_is_blocked(camera.global_position, target_point):
			if hunter_gaze_through_wall_range <= 0.0 \
				or distance > hunter_gaze_through_wall_range:
				continue
			var wall_proximity := 1.0 - smoothstep(
				hunter_gaze_through_wall_range * 0.35,
				hunter_gaze_through_wall_range,
				distance
			)
			strongest = maxf(
				strongest,
				wall_proximity * hunter_gaze_through_wall_strength
			)
			continue

		var angle := acos(clampf(forward.dot(offset / distance), -1.0, 1.0))
		if angle >= outer_angle or not camera.is_position_in_frustum(target_point):
			continue
		var angle_strength := 1.0 - smoothstep(full_angle, outer_angle, angle)
		# Full strength through the close half of the range, then taper out so a
		# tiny far-away silhouette whispers static rather than flooding the frame.
		var distance_strength := 1.0 - smoothstep(
			hunter_gaze_range * 0.5,
			hunter_gaze_range,
			distance
		)
		strongest = maxf(strongest, angle_strength * distance_strength)
	return clampf(strongest, 0.0, 1.0)


func _is_visible_hunter(hunter: Node3D) -> bool:
	if not is_instance_valid(hunter) or not hunter.visible:
		return false
	if "manifested" in hunter and not bool(hunter.get("manifested")):
		return false
	var body := hunter.get_node_or_null("VisualRoot") as Node3D
	return body == null or body.visible


func _hunter_gaze_is_blocked(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(
		from,
		to,
		hunter_gaze_blocking_mask,
		[get_rid()]
	)
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _unhandled_input(event: InputEvent) -> void:
	if not is_local_player():
		return
	# Being down or spectating is not the same as being finished: both still
	# get to look around, they just lose everything below the look block.
	if not is_alive and not is_downed and not is_spectator:
		return
	if _is_alt_toggle_event(event):
		toggle_mouse_capture()
		get_viewport().set_input_as_handled()
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

	# A body on the floor cannot reach a door handle, and a spectator has no
	# body at all - looking is where their input stops.
	if is_downed or is_spectator:
		return

	if _is_any_minigame_active():
		return

	if event.is_action_pressed("interact"):
		if _is_network_client():
			_request_interact.rpc_id(NETWORK_SERVER_PEER_ID)
		else:
			_try_interact()
	if event.is_action_pressed("drop_item"):
		if _is_network_client():
			_request_drop_item.rpc_id(NETWORK_SERVER_PEER_ID)
		else:
			_drop_selected_item()
	# No RPC of its own: the switch rides the input stream every peer already
	# sends, so a press is felt locally on the frame it happens and reaches the
	# authority on the next tick like movement does.
	if event.is_action_pressed("flashlight_toggle"):
		_flashlight_on = not _flashlight_on
		_apply_flashlight_state()
	if event.is_action_pressed("select_slot_1"):
		_request_or_select_slot(0)
	if event.is_action_pressed("select_slot_2"):
		_request_or_select_slot(1)
	if event is InputEventMouseButton and event.pressed:
		# Only 2 slots exist, so "next" and "previous" are both just "the
		# other slot" - same select_slot() the keyboard shortcuts use.
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_request_or_select_slot(1 - equipment.selected_slot)


func is_local_player() -> bool:
	if not _is_network_session() or owner_peer_id <= 0:
		return true
	return multiplayer.get_unique_id() == owner_peer_id


func _configure_player_presentation() -> void:
	var local := is_local_player()
	var camera := camera_pivot.get_node_or_null("Camera3D") as Camera3D
	if camera:
		# Player scenes are instantiated once per peer. Their cameras deliberately
		# start non-current in player.tscn so a remote replica cannot steal the
		# viewport while its parent is still entering the tree.
		if local:
			camera.make_current()
		else:
			camera.current = false
	# The server keeps InteractRay active for authoritative range checks; remote
	# clients need neither the ray nor any of this player's full-screen UI.
	if interact_ray:
		interact_ray.enabled = local or multiplayer.is_server()
	for node_name: StringName in [
		&"HorrorOverlay",
		&"InteractionUI",
		&"StatusUI",
		&"EquipmentUI",
		&"DoorGhostMinigame",
		&"DownedUI",
		&"DeathUI",
	]:
		var presentation_node := get_node_or_null(NodePath(node_name))
		# Local UI nodes own their initial visibility (DeathUI and minigames
		# deliberately start hidden). Only remote players need a forced hide.
		if presentation_node and not local:
			if presentation_node is CanvasLayer or presentation_node is CanvasItem \
				or presentation_node is Node3D:
				presentation_node.set("visible", false)
			presentation_node.process_mode = Node.PROCESS_MODE_DISABLED
	if bladder:
		# The server owns every player's passive fill. ToiletMinigame drains through
		# explicit methods, so a client copy needs no second physics simulation.
		bladder.set_physics_process(not _is_network_session() or multiplayer.is_server())
	set_process_unhandled_input(local)


func _is_network_session() -> bool:
	var manager := get_node_or_null("/root/NetworkManager")
	return manager != null and bool(manager.get("session_active"))


## True while this body can still be asked a network question at all.
##
## An RPC is not delivered where it was sent from. It lands a frame or two
## later, and the end of a run spends exactly those frames swapping the villa
## for the lobby - while every peer goes on streaming input at its own rate,
## because none of them has heard yet. So the packet arrives at a body that has
## already left the tree with the map, and `Node.multiplayer` is null outside
## the tree: `multiplayer.is_server()` is then not the guard, it *is* the crash.
##
## A debug build reports "Cannot call method 'is_server' on a null value" and
## carries on, which is why this was invisible in every headless test. A release
## build dereferences null instead, and that is what took the Edgegap server
## down with a SIGSEGV every single time a wiped team was handed back to the
## lobby. Every RPC entry point below opens with this.
func _network_is_reachable() -> bool:
	return is_inside_tree() and multiplayer != null


## The server-side half of an RPC guard, safe to ask on a detached body.
func _rpc_reached_authority() -> bool:
	return _network_is_reachable() and multiplayer.is_server()


func _is_network_client() -> bool:
	return _is_network_session() and not multiplayer.is_server()


## True on a headless process that owns peer 1 without being a player.
func _is_dedicated_server() -> bool:
	var manager := get_node_or_null("/root/NetworkManager")
	return manager != null and bool(manager.get("dedicated_server"))


func _capture_and_send_network_input() -> void:
	var move := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var jump := Input.is_action_pressed("jump")
	var crouch := Input.is_action_pressed("crouch")
	var run_pressed := Input.is_action_pressed("run")
	var interact_held := Input.is_action_pressed("interact")
	var focus_held := Input.is_action_pressed("flashlight_focus")
	var yaw := rotation.y
	var pitch := camera_pivot.rotation.x
	_local_input_sequence += 1
	if multiplayer.is_server():
		_apply_network_input(
			move,
			jump,
			crouch,
			run_pressed,
			interact_held,
			yaw,
			pitch,
			_local_input_sequence,
			_flashlight_on,
			focus_held,
			_lean
		)
	else:
		_submit_network_input.rpc_id(
			NETWORK_SERVER_PEER_ID,
			move,
			jump,
			crouch,
			run_pressed,
			interact_held,
			yaw,
			pitch,
			_local_input_sequence,
			_flashlight_on,
			focus_held,
			_lean
		)


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _submit_network_input(
	move: Vector2,
	jump: bool,
	crouch: bool,
	run_pressed: bool,
	interact_held: bool,
	yaw: float,
	pitch: float,
	input_sequence: int,
	flashlight_on: bool,
	flashlight_focus: bool,
	lean: float
) -> void:
	if not _rpc_reached_authority() or not _rpc_sender_owns_player():
		return
	if not is_finite(move.x) or not is_finite(move.y) \
		or not is_finite(yaw) or not is_finite(pitch) or not is_finite(lean):
		return
	if input_sequence <= _last_processed_input_sequence:
		return
	_apply_network_input(
		move,
		jump,
		crouch,
		run_pressed,
		interact_held,
		yaw,
		pitch,
		input_sequence,
		flashlight_on,
		flashlight_focus,
		lean
	)


func _apply_network_input(
	move: Vector2,
	jump: bool,
	crouch: bool,
	run_pressed: bool,
	interact_held: bool,
	yaw: float,
	pitch: float,
	input_sequence: int = -1,
	flashlight_on: bool = true,
	flashlight_focus: bool = false,
	lean: float = 0.0
) -> void:
	_network_move = move.limit_length(1.0)
	_network_jump = jump
	_network_crouch = crouch
	_network_run = run_pressed
	_network_interact = interact_held
	_network_flashlight_on = flashlight_on
	_network_flashlight_focus = flashlight_focus
	_network_lean = clampf(lean, -1.0, 1.0)
	_network_yaw = wrapf(yaw, -PI, PI)
	_network_pitch = clampf(pitch, -PI * 0.5, PI * 0.5)
	if input_sequence >= 0:
		_last_processed_input_sequence = input_sequence


func _movement_input() -> Vector2:
	if _is_network_session() and multiplayer.is_server():
		return _network_move
	return Input.get_vector("move_left", "move_right", "move_forward", "move_backward")


func _input_action_pressed(action: StringName) -> bool:
	if _is_network_session() and multiplayer.is_server():
		match action:
			&"jump":
				return _network_jump
			&"crouch":
				return _network_crouch
			&"run":
				return _network_run
			&"interact":
				return _network_interact
	return Input.is_action_pressed(action)


func _input_action_just_pressed(action: StringName) -> bool:
	if _is_network_session() and multiplayer.is_server() and action == &"jump":
		return _network_jump and not _previous_network_jump
	return Input.is_action_just_pressed(action)


func _finish_network_tick(delta: float) -> void:
	if not _is_network_session() or not multiplayer.is_server():
		return
	_previous_network_jump = _network_jump
	_state_sync_remaining -= delta
	if _state_sync_remaining > 0.0:
		return
	_state_sync_remaining += NETWORK_STATE_INTERVAL
	# Reached through the tree rather than by name: an autoload's identifier
	# only resolves once the project's main loop is running, and this script is
	# compiled as a dependency by the `--script` smoke tests, which have none.
	var manager := get_node_or_null("/root/NetworkManager")
	if manager == null:
		return
	for ready_peer: int in manager.get("replication_ready_peers"):
		if ready_peer == NETWORK_SERVER_PEER_ID:
			continue
		_send_network_state(ready_peer)


func _finish_player_tick(delta: float) -> void:
	if _is_network_client() and is_local_player():
		if _is_local_transform_encounter_active():
			_discard_prediction_reconciliation()
		else:
			_prediction_history[_local_input_sequence] = global_position
			while _prediction_history.size() > PREDICTION_HISTORY_LIMIT:
				var oldest_sequence: int = _prediction_history.keys().min()
				_prediction_history.erase(oldest_sequence)
	_finish_network_tick(delta)


func _send_network_state(peer_id: int) -> void:
	# Bladder pressure is private, owner-local state. The authority keeps the
	# canonical value for every player, but only the player who owns this body
	# needs it on a client. Sending it to every replica made an accidentally
	# bound HUD/DevTools panel display another player's progress and gave remote
	# snapshots a path to overwrite local toilet reconciliation.
	var owner_bladder := (
		bladder.get_bladder()
		if bladder and peer_id == owner_peer_id
		else 0.0
	)
	_receive_network_state.rpc_id(
		peer_id,
		global_position,
		rotation.y,
		camera_pivot.rotation.x,
		velocity,
		is_crouching,
		is_alive,
		current_stamina,
		is_downed,
		is_spectator,
		downed_time_remaining,
		revive_progress,
		owner_bladder,
		_last_processed_input_sequence,
		_life_state_revision,
		_last_applied_toilet_report,
		flashlight_battery,
		_flashlight_on,
		_flashlight_focus_held
	)


@rpc("authority", "call_remote", "unreliable_ordered", 2)
func _receive_network_state(
	server_position: Vector3,
	server_yaw: float,
	server_pitch: float,
	server_velocity: Vector3,
	server_crouching: bool,
	server_alive: bool,
	server_stamina: float,
	server_downed: bool,
	server_spectator: bool,
	server_downed_remaining: float,
	server_revive_progress: float,
	server_bladder: float,
	ack_input_sequence: int,
	server_life_state_revision: int,
	server_toilet_ack: int,
	server_flashlight_battery: float,
	server_flashlight_on: bool,
	server_flashlight_focus: bool
) -> void:
	if not _network_is_reachable() or multiplayer.is_server():
		return
	flashlight_battery = clampf(server_flashlight_battery, 0.0, flashlight_battery_max)
	# The owner's own switch and focus are felt on the frame they are pressed
	# and confirmed a tick later; taking them back from the server here would
	# make the torch stutter at exactly the rate snapshots arrive.
	if not is_local_player():
		_flashlight_on = server_flashlight_on
		_flashlight_focus_held = server_flashlight_focus
	_apply_flashlight_state()
	_snapshot_position = server_position
	_snapshot_yaw = server_yaw
	_snapshot_pitch = server_pitch
	_snapshot_velocity = server_velocity
	_snapshot_age = 0.0
	_apply_remote_life_state(
		server_alive,
		server_downed,
		server_spectator,
		server_downed_remaining,
		server_revive_progress,
		server_life_state_revision
	)
	current_stamina = clampf(server_stamina, 0.0, max_stamina)
	# A finished session is not finished until the server has heard about it.
	# The minigame drains the bladder on the owning peer, clears itself, and
	# only then RPCs the result - and every snapshot that lands inside that gap
	# still carries the server's pre-session value, which snapped the bar
	# straight back to full a beat after the player had just emptied it. Hold
	# the local value until a snapshot echoes this player's report sequence.
	# Remote player replicas do not consume bladder state. Their UI is hidden,
	# their simulation lives on the server, and applying the value here only
	# creates opportunities for one player's private progress to leak into a
	# locally bound meter. The owning replica alone reconciles its own snapshot.
	if bladder and is_local_player() and not is_toilet_minigame_active():
		if _bladder_report_pending:
			if server_toilet_ack >= _toilet_report_sequence:
				_bladder_report_pending = false
				bladder.set_bladder(server_bladder)
		else:
			bladder.set_bladder(server_bladder)
	if server_crouching != is_crouching:
		if server_crouching:
			_crouch()
		else:
			_stand_up()
	# Door/toilet/breaker encounters deliberately move the owning client's real
	# camera while the authoritative body stays parked where interaction began.
	# Applying that parked server transform here pulls the flashlight away from
	# the door and makes a multiplayer-only encounter impossible to aim.
	var encounter_owns_transform := is_local_player() \
		and _is_local_transform_encounter_active()
	if encounter_owns_transform:
		_discard_prediction_reconciliation()
		_has_network_snapshot = true
	elif not _has_network_snapshot:
		global_position = server_position
		rotation.y = server_yaw
		if not is_local_player():
			camera_pivot.rotation.x = server_pitch
		_prediction_history.clear()
		_pending_reconciliation = Vector3.ZERO
		_has_network_snapshot = true
	elif is_local_player():
		_reconcile_predicted_position(server_position, server_velocity, ack_input_sequence)


func _reconcile_predicted_position(
	server_position: Vector3,
	server_velocity: Vector3,
	ack_input_sequence: int
) -> void:
	if _is_local_transform_encounter_active():
		_discard_prediction_reconciliation()
		return
	if not _prediction_history.has(ack_input_sequence):
		return
	var predicted_position: Vector3 = _prediction_history[ack_input_sequence]
	var correction := server_position - predicted_position

	# Once the authority acknowledges an input, older predictions can never be
	# useful again. Prune them before shifting the still-unacknowledged future.
	for sequence_value: Variant in _prediction_history.keys():
		if int(sequence_value) <= ack_input_sequence:
			_prediction_history.erase(sequence_value)

	var correction_distance := correction.length()
	if correction_distance <= PREDICTION_CORRECTION_DEAD_ZONE:
		_pending_reconciliation = Vector3.ZERO
		return
	if correction_distance > PREDICTION_HARD_SNAP_DISTANCE:
		_shift_prediction_space(correction)
		velocity = server_velocity
		_pending_reconciliation = Vector3.ZERO
		return

	# This snapshot supersedes the previous target. Adding corrections here made
	# an unapplied remainder grow on every 20 Hz packet until the player flew far
	# beyond both the client and server positions.
	_pending_reconciliation = correction


## Death/down/revive is gameplay-critical and cannot wait for an unreliable
## movement packet. This reliable update is broadcast by the server whenever a
## life-cycle transition happens; periodic snapshots still carry the same data
## so a newly replication-ready peer receives the complete current state.
func _publish_life_state() -> void:
	if not _is_network_session() or not multiplayer.is_server():
		return
	_life_state_revision += 1
	var manager := get_node_or_null("/root/NetworkManager")
	if manager == null:
		return
	for ready_peer: int in manager.get("replication_ready_peers"):
		if ready_peer == NETWORK_SERVER_PEER_ID:
			continue
		_receive_life_state.rpc_id(
			ready_peer,
			is_alive,
			is_downed,
			is_spectator,
			downed_time_remaining,
			revive_progress,
			_life_state_revision
		)


@rpc("authority", "call_remote", "reliable", 2)
func _receive_life_state(
	server_alive: bool,
	server_downed: bool,
	server_spectator: bool,
	server_downed_remaining: float,
	server_revive_progress: float,
	server_life_state_revision: int
) -> void:
	if not _network_is_reachable() or multiplayer.is_server():
		return
	_apply_remote_life_state(
		server_alive,
		server_downed,
		server_spectator,
		server_downed_remaining,
		server_revive_progress,
		server_life_state_revision
	)


func _apply_remote_life_state(
	server_alive: bool,
	server_downed: bool,
	server_spectator: bool,
	server_downed_remaining: float,
	server_revive_progress: float,
	server_life_state_revision: int
) -> void:
	if server_life_state_revision < _last_received_life_state_revision:
		return
	_last_received_life_state_revision = server_life_state_revision
	var was_downed := is_downed
	if server_spectator and not is_spectator:
		# Keep the established collision, audio and signal side effects instead of
		# duplicating a partial spectator transition on clients.
		_enter_spectator()
	else:
		is_alive = server_alive
		is_downed = server_downed
		is_spectator = server_spectator
		if was_downed != is_downed:
			downed_changed.emit(is_downed)
	downed_time_remaining = server_downed_remaining
	revive_progress = server_revive_progress


func _interpolate_network_snapshot(delta: float) -> void:
	if not _has_network_snapshot:
		return
	_snapshot_age += delta
	var extrapolated_position := _snapshot_position
	var horizontal_velocity := Vector3(_snapshot_velocity.x, 0.0, _snapshot_velocity.z)
	extrapolated_position += horizontal_velocity * minf(_snapshot_age, NETWORK_STATE_INTERVAL * 2.0)
	var distance := global_position.distance_to(extrapolated_position)
	if distance > 3.0:
		global_position = extrapolated_position
	else:
		global_position = global_position.lerp(extrapolated_position, minf(delta * 16.0, 1.0))
	if not is_local_player():
		rotation.y = lerp_angle(rotation.y, _snapshot_yaw, minf(delta * 16.0, 1.0))
		camera_pivot.rotation.x = lerpf(
			camera_pivot.rotation.x,
			_snapshot_pitch,
			minf(delta * 16.0, 1.0)
		)
		_update_replica_footsteps(delta)
	velocity = _snapshot_velocity
	if is_local_player():
		_update_camera_motion(delta)


## Footsteps for somebody else's body, derived from the 20 Hz snapshot.
##
## The pace is the one thing that has to be re-derived rather than sent: it is
## two footfalls a second per player, which does not belong on a reliable event
## channel next to a door breaking. Speed is enough to tell a walk from a
## sprint, and a body that is falling has a vertical speed no walk produces.
func _update_replica_footsteps(delta: float) -> void:
	if not is_alive or is_downed or is_spectator:
		_stop_footsteps()
		return
	var horizontal_speed := Vector2(_snapshot_velocity.x, _snapshot_velocity.z).length()
	_advance_footsteps(
		delta,
		horizontal_speed > walk_speed * 1.15,
		horizontal_speed,
		absf(_snapshot_velocity.y) < 1.5
	)


func _apply_pending_reconciliation(delta: float) -> void:
	if _is_local_transform_encounter_active():
		_discard_prediction_reconciliation()
		return
	if _pending_reconciliation.is_zero_approx():
		return
	var applied := _pending_reconciliation * minf(
		delta * PREDICTION_RECONCILIATION_SPEED, 1.0
	)
	_shift_prediction_space(applied)
	_pending_reconciliation -= applied
	if _pending_reconciliation.length_squared() < 0.000001:
		_pending_reconciliation = Vector3.ZERO


## These encounters temporarily own the local body transform because the real
## first-person camera is their playfield. The server continues to own every
## gameplay outcome and keeps its replica parked at the interaction point.
func _is_local_transform_encounter_active() -> bool:
	return is_door_minigame_active() \
		or is_toilet_minigame_active() \
		or is_breaker_minigame_active()


func _discard_prediction_reconciliation() -> void:
	_prediction_history.clear()
	_pending_reconciliation = Vector3.ZERO


func _shift_prediction_space(offset: Vector3) -> void:
	if offset.is_zero_approx():
		return
	global_position += offset
	# Every future prediction was recorded in the old coordinate space. Moving
	# only the body leaves those entries stale, so the next snapshot rediscovers
	# the same error and applies it again.
	for sequence_value: Variant in _prediction_history.keys():
		var predicted_position: Vector3 = _prediction_history[sequence_value]
		_prediction_history[sequence_value] = predicted_position + offset


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
	if not target or not can_interact_with(target):
		return
	target.interact(self)
	# Only the server ever reaches this function - a client's E is an RPC - so a
	# press whose whole effect is local geometry (a door leaf swinging, a switch
	# flipping a circuit) would happen on the server and nowhere else. Those
	# targets say so by joining `replicated_interactions`; the ones with their
	# own network path, a defense door and the breaker, deliberately do not.
	if _is_network_session() \
		and multiplayer.is_server() \
		and target.is_in_group(&"replicated_interactions"):
		_echo_interaction.rpc(_scene_path_of(target))


## Replays the press on every other peer, through the same public `interact()`
## the server just called. `self` is this player's replica on the receiving
## machine, so a door still swings away from the person who opened it.
@rpc("authority", "call_remote", "reliable")
func _echo_interaction(target_path: NodePath) -> void:
	if not _network_is_reachable():
		return
	var target := _scene_node(target_path)
	if target and target.has_method("interact"):
		target.interact(self)


@rpc("any_peer", "call_remote", "reliable")
func _request_interact() -> void:
	if _rpc_reached_authority() and _rpc_sender_owns_player():
		_try_interact()


@rpc("any_peer", "call_remote", "reliable")
func _request_drop_item() -> void:
	if _rpc_reached_authority() and _rpc_sender_owns_player():
		_drop_selected_item()


@rpc("any_peer", "call_remote", "reliable")
func _request_select_slot(slot_index: int) -> void:
	if _rpc_reached_authority() and _rpc_sender_owns_player() and slot_index in [0, 1]:
		equipment.select_slot(slot_index)
		_confirm_selected_slot.rpc_id(owner_peer_id, slot_index)


@rpc("authority", "call_remote", "reliable")
func _confirm_selected_slot(slot_index: int) -> void:
	if _network_is_reachable() and is_local_player() and slot_index in [0, 1]:
		equipment.select_slot(slot_index)


func _request_or_select_slot(slot_index: int) -> void:
	if _is_network_client():
		# Selecting locally keeps the equipment wheel responsive. The server
		# confirms the same bounded value over the reliable channel.
		equipment.select_slot(slot_index)
		_request_select_slot.rpc_id(NETWORK_SERVER_PEER_ID, slot_index)
	else:
		equipment.select_slot(slot_index)


func _rpc_sender_owns_player() -> bool:
	return _network_is_reachable() and multiplayer.get_remote_sender_id() == owner_peer_id


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
	WorldNet.report_holder(item, owner_peer_id)
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
	WorldNet.report_holder(item, 0)


## Hands `item` back to the world so a consumer can do something with it - the
## totem brazier uses it to take the totem out of the player's hands before it
## burns it. Mirrors try_pick_up_item(): the consumer calls into the player,
## never into the equipment slots. Returns false if it was not being carried.
func release_held_item(item: Node3D) -> bool:
	if not is_instance_valid(item) or not equipment.remove_item(item):
		return false
	item.reparent(get_tree().root)
	item.global_position = global_position + Vector3(0, standing_camera_height, 0)
	if item.has_method("set_held"):
		item.set_held(false)
	WorldNet.report_holder(item, 0)
	return true


func _physics_process(delta: float) -> void:
	# Ahead of every early return below: a downed, dead, spectating or purely
	# interpolated body still casts the torch its owner left switched on.
	_update_flashlight(delta)
	_update_lean(delta)
	if _is_network_session():
		if multiplayer.is_server():
			if owner_peer_id == NETWORK_SERVER_PEER_ID and not _is_dedicated_server():
				_capture_and_send_network_input()
			# Only the authority consumes the input state received over RPC. A local
			# client already rotated itself in _unhandled_input(); assigning these
			# server-side fields there would undo mouse-look every physics frame.
			rotation.y = _network_yaw
			camera_pivot.rotation.x = _network_pitch
		else:
			if is_local_player():
				_capture_and_send_network_input()
				_apply_pending_reconciliation(delta)
			else:
				_interpolate_network_snapshot(delta)
				return

	if is_spectator:
		_fly(delta)
		_finish_player_tick(delta)
		return

	if is_downed:
		_update_downed(delta)
		_settle_downed_body(delta)
		_update_camera_motion(delta)
		_stop_footsteps()
		_finish_player_tick(delta)
		return

	_update_minigame_ghost_safety(delta)
	if _is_any_minigame_active():
		velocity = Vector3.ZERO
		_stop_footsteps()
		_finish_player_tick(delta)
		return

	if not is_alive:
		velocity = Vector3.ZERO
		_stop_footsteps()
		_finish_player_tick(delta)
		return

	if dev_noclip:
		_fly(delta)
		_finish_player_tick(delta)
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
		_finish_player_tick(delta)
		return

	# Add the gravity.
	if not was_on_floor:
		velocity.y -= gravity * delta

	# Handle Jump
	if _input_action_just_pressed(&"jump") and is_on_floor():
		if is_crouching:
			if _can_stand():
				_stand_up()
				velocity.y = jump_velocity
		else:
			velocity.y = jump_velocity

	# Handle Crouch
	if _input_action_pressed(&"crouch"):
		if not is_crouching:
			_crouch()
	else:
		if is_crouching:
			if _can_stand():
				_stand_up()

	# Get the input direction and handle the movement/deceleration.
	# Input.get_vector automatically normalizes diagonal input
	var input_dir := _movement_input()
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	var is_sprinting = false
	# No running during an accident. This is the whole reason not to let one
	# happen: the escape from the huntsman is a sprint, and there isn't one.
	if direction != Vector3.ZERO and _input_action_pressed(&"run") \
		and current_stamina > 0.0 and not is_crouching and not is_wetting():
		is_sprinting = true

	var current_speed = walk_speed
	
	if is_sprinting:
		current_speed = walk_speed * sprint_speed_multiplier
		# Running on a full bladder is the expensive way to run. Same speed,
		# shorter sprint - so ignoring the need shortens the escape rather than
		# slowing it, which is the version a player can feel.
		current_stamina -= sprint_stamina_drain * delta \
			* (1.0 + bladder_debuff_stamina_scale * get_bladder_pressure())
	else:
		if is_crouching:
			current_speed = crouch_speed
			
		if direction == Vector3.ZERO:
			current_stamina += stamina_regen_idle * delta
		else:
			current_stamina += stamina_regen_moving * delta

	if is_wetting():
		current_speed *= wetting_speed_multiplier
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
	_finish_player_tick(delta)


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


## Drives the post-process grade in ui/horror_overlay.gdshader between the
## house as it normally plays (0) and something about to reach the player (1).
## Owned here for the same reason threat is: the overlay belongs to the player,
## and whatever is frightening them reports in rather than reaching for it.
func set_danger_intensity(amount: float) -> void:
	var overlay_material := horror_overlay_rect.material as ShaderMaterial
	if overlay_material:
		overlay_material.set_shader_parameter("danger_intensity", clampf(amount, 0.0, 1.0))


func kill_by_ghost(ghost: Node3D) -> void:
	if not is_alive or is_protected_from_ghost_attacks():
		return
	is_alive = false
	velocity = Vector3.ZERO
	_stop_footsteps()
	# Alone, a kill is still a kill and the jumpscare/game-over runs as before.
	# With a teammate left standing it becomes a rescue window instead - but
	# being caught is the scare either way, so the face still arrives; only the
	# game-over behind it is what a rescuer takes away.
	if _has_available_rescuer():
		_enter_downed()
		_present_downed_jumpscare(ghost)
	else:
		_present_death(ghost)
		_publish_life_state()
	killed_by_ghost.emit(ghost)


## The jumpscare, the game-over screen and the pause that comes with them are
## first-person, so they belong on the machine of the player who died.
##
## Ghosts run on the server, which means a kill lands on a *replica* there. Left
## as it was, a hunter catching one player played that player's death on the
## host's screen and paused the server's tree - freezing the night for everyone
## while the person who actually died saw nothing.
func _present_death(ghost: Node3D) -> void:
	if _encounter_belongs_elsewhere():
		_show_death.rpc_id(owner_peer_id, _scene_path_of(ghost))
		return
	if _start_ghost_jumpscare(ghost):
		return
	if death_ui.has_method("show_jumpscare"):
		death_ui.call("show_jumpscare", ghost)
	else:
		death_ui.visible = true
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


## Being caught with a teammate still standing: the same scare a death gets, and
## no Game Over behind it - the one still standing is the only difference.
##
## It has to be the scare belonging to *whatever caught you*. The controller
## now installs the actual Statue, Crawler, Darkness or Hunter presentation
## subtree in its isolated 3D viewport, so no catch falls back to a mismatched
## vector portrait or to the Huntsman's face.
##
## Routed to the victim's own machine for the reason _present_death() is: this
## is first-person, and the kill is resolved on the server. The controller is
## driven with a null player rather than `self` on purpose - locking a downed
## body's `_physics_process` would also stop `_update_downed()` on a listen
## server, freezing the bleed-out clock and any revive already in progress for
## the length of the sequence. There is nothing to hold still anyway: a downed
## player cannot move. And no `_pending_jumpscare_killer` is set, which is what
## keeps _on_ghost_jumpscare_finished() from raising the Game Over card.
func _present_downed_jumpscare(ghost: Node3D) -> void:
	if _encounter_belongs_elsewhere():
		_show_downed_jumpscare.rpc_id(owner_peer_id, _scene_path_of(ghost))
		return
	if not is_local_player():
		return
	if jumpscare and jumpscare.play_jumpscare(null, ghost):
		return
	if death_ui.has_method("show_downed_scare"):
		death_ui.call("show_downed_scare", ghost)


@rpc("authority", "call_remote", "reliable")
func _show_downed_jumpscare(ghost_path: NodePath) -> void:
	if not _network_is_reachable() or not is_local_player():
		return
	_present_downed_jumpscare(_scene_node(ghost_path) as Node3D)


@rpc("authority", "call_remote", "reliable")
func _show_death(ghost_path: NodePath) -> void:
	if not _network_is_reachable() or not is_local_player():
		return
	# is_alive also arrives in the next state packet; setting it here keeps the
	# screen and the body from disagreeing for the frame in between.
	is_alive = false
	_present_death(_scene_node(ghost_path) as Node3D)


func _start_ghost_jumpscare(ghost: Node3D) -> bool:
	if not is_instance_valid(ghost) or not jumpscare:
		return false
	_pending_jumpscare_killer = ghost
	if not jumpscare.play_jumpscare(self, ghost):
		_pending_jumpscare_killer = null
		return false
	var active_scene := get_tree().current_scene
	if active_scene \
			and active_scene.is_ancestor_of(self) \
			and not _is_network_session():
		get_tree().paused = true
	return true


## The controller emits this for every jumpscare it plays, and cancel() emits it
## too - a run that was cut short is not a death. Only one that came through
## _start_ghost_jumpscare() has a killer waiting, so only that one raises the
## Game Over; without the guard a killer-less finish raised one anyway, and
## death_screen.gd captions a null killer as the statue.
func _on_ghost_jumpscare_finished() -> void:
	var killer := _pending_jumpscare_killer
	_pending_jumpscare_killer = null
	if killer == null:
		return
	if death_ui.has_method("show_game_over"):
		death_ui.call("show_game_over", killer)
	elif death_ui.has_method("show_jumpscare"):
		death_ui.call("show_jumpscare", killer)


## A rescuer has to be able to walk over here: anyone already on the floor or
## watching as a spectator cannot pick this player up.
func _has_available_rescuer() -> bool:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var other := node as CharacterBody3D
		if other == self or not is_instance_valid(other):
			continue
		if bool(other.get("is_alive")) \
			and not bool(other.get("is_downed")) \
			and not bool(other.get("is_spectator")):
			return true
	return false


func _enter_downed() -> void:
	# The 60-second charge lands before the clock starts, so a player who is
	# already near the end of their budget goes straight past the floor.
	downed_time_remaining = maxf(downed_time_remaining - downed_death_cost, 0.0)
	if downed_time_remaining <= 0.0:
		_enter_spectator()
		return
	is_downed = true
	revive_progress = 0.0
	_clear_all_ghost_threat()
	downed_changed.emit(true)
	_publish_life_state()


func _enter_spectator() -> void:
	if is_spectator:
		return
	is_alive = false
	is_downed = false
	is_spectator = true
	downed_time_remaining = 0.0
	revive_progress = 0.0
	velocity = Vector3.ZERO
	# Same reasoning as dev noclip: disable the shape, not the layers, so a
	# spectator can drift through the house without shoving anything.
	collision_shape.disabled = true
	_clear_all_ghost_threat()
	_stop_footsteps()
	downed_changed.emit(false)
	became_spectator.emit()
	_publish_life_state()


## Server-side (or offline) tick for a body on the floor. Written from the
## downed player's side rather than the rescuer's so the outcome cannot depend
## on which of the two nodes `_physics_process` happens to reach first.
func _update_downed(delta: float) -> void:
	var rescuer := _find_reviver()
	if rescuer:
		revive_progress = minf(revive_progress + delta, revive_duration)
		if revive_progress >= revive_duration:
			revive()
		# The bleed-out clock is paused for as long as somebody is holding on.
		return

	revive_progress = maxf(revive_progress - delta * revive_decay_multiplier, 0.0)
	downed_time_remaining = maxf(downed_time_remaining - delta, 0.0)
	if downed_time_remaining <= 0.0:
		_enter_spectator()


## Gravity only, so a player dropped part-way up a staircase ends up lying on
## the floor a teammate can actually reach.
func _settle_downed_body(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0
	move_and_slide()


func _find_reviver() -> CharacterBody3D:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var other := node as CharacterBody3D
		if other == self or not is_instance_valid(other):
			continue
		if bool(other.call("can_revive", self)) and bool(other.call("is_holding_interact")):
			return other
	return null


## True while this player is close enough and able to lift `target` - also what
## the downed HUD reads to show the rescue prompt.
func can_revive(target: Node) -> bool:
	if not is_alive or is_downed or is_spectator or _is_any_minigame_active():
		return false
	var body := target as Node3D
	if not is_instance_valid(body) or not ("is_downed" in body and body.is_downed):
		return false
	return global_position.distance_to(body.global_position) <= revive_range


func is_holding_interact() -> bool:
	return _input_action_pressed(&"interact")


func revive() -> void:
	if not is_downed:
		return
	is_downed = false
	is_alive = true
	revive_progress = 0.0
	# Back up with nothing left in the tank: the rescue is a reprieve, not a
	# reset, and the downed budget itself is never refilled.
	current_stamina = 0.0
	downed_changed.emit(false)
	_publish_life_state()


func get_downed_time_ratio() -> float:
	return clampf(downed_time_remaining / maxf(downed_time_budget, 0.01), 0.0, 1.0)


func get_revive_ratio() -> float:
	return clampf(revive_progress / maxf(revive_duration, 0.01), 0.0, 1.0)


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
## The lean is smoothed by whoever owns the body and sent as one number, not
## re-derived from the key on the far side: the authority has to end up with the
## exact camera the player is looking through, because that camera is what the
## Statue reads to decide it is being watched and what the Darkness Ghost reads
## for its first sighting. A server that leaned a frame behind would let a
## player see a ghost the server believes is unobserved.
func _update_lean(delta: float) -> void:
	if is_local_player():
		var target := 0.0
		if _can_lean():
			if Input.is_action_pressed(&"lean_left"):
				target -= 1.0
			if Input.is_action_pressed(&"lean_right"):
				target += 1.0
		_lean = move_toward(_lean, target, lean_speed * delta)
	elif _is_network_session() and multiplayer.is_server():
		_lean = _network_lean
	else:
		# A remote body on a client: nothing here reads its camera, and the head
		# is not modelled, so there is nothing for a lean to move.
		return
	_lean_reach = _clamped_lean_reach()
	_apply_lean()


func _can_lean() -> bool:
	return is_alive and not is_downed and not is_spectator and not _is_any_minigame_active()


## How far of the wanted lean the head can actually travel. Peeking round a
## corner means putting the camera exactly where a wall is, so without this the
## peek sees through the cover instead of past it.
func _clamped_lean_reach() -> float:
	if absf(_lean) <= 0.001:
		return 0.0
	var eye := camera_pivot.global_position
	var sideways := global_basis.x * (_lean * lean_side_offset)
	var query := PhysicsRayQueryParameters3D.create(eye, eye + sideways, 1)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return _lean
	var clear: float = eye.distance_to(hit["position"] as Vector3)
	var wanted := absf(_lean) * lean_side_offset
	if wanted <= 0.001:
		return _lean
	return _lean * clampf(clear / wanted, 0.0, 1.0) * lean_wall_margin


## Written here as well as folded into _update_camera_motion()'s target, and the
## two agree by construction. Camera motion owns the pivot on an ordinary tick
## and would lerp a lean written here straight back out; the branches that skip
## it - a minigame, a death - would otherwise leave the head stuck out at the
## angle it was leaning when they started.
func _apply_lean() -> void:
	camera_pivot.position.x = _camera_pivot_base_x + _lean_reach * lean_side_offset
	camera_pivot.rotation.z = -_lean_reach * deg_to_rad(lean_max_angle)


## Only the authority spends charge, because the authority is where the
## Darkness Ghost reads the beams that kill it - a client draining its own copy
## would disagree with the body the ghost is actually measuring. Every peer
## still runs _apply_flashlight_state(), so the light itself is correct
## everywhere from the replicated switch/focus flags.
func _update_flashlight(delta: float) -> void:
	_refresh_flashlight_input()
	if not _is_network_client() and _flashlight_on and flashlight_battery > 0.0:
		var drain := (
			flashlight_focus_drain_per_second
			if _flashlight_focus_held
			else flashlight_drain_per_second
		)
		flashlight_battery = maxf(0.0, flashlight_battery - drain * delta)
	_apply_flashlight_state()


## Three bodies, three sources, and mixing them up is what makes a torch flicker
## on somebody else's screen: the body you steer reads the real keyboard, a
## remote body on the authority reads the input stream that body's owner sends,
## and a remote body on a client is told by _receive_network_state() and must
## not be overwritten here.
func _refresh_flashlight_input() -> void:
	if is_local_player():
		_flashlight_focus_held = Input.is_action_pressed(&"flashlight_focus")
	elif _is_network_session() and multiplayer.is_server():
		_flashlight_on = _network_flashlight_on
		_flashlight_focus_held = _network_flashlight_focus


## The single place the SpotLight3D is written. The toilet ghost's dimming and
## the focus beam both land here rather than each setting light_energy from the
## base value, which is how two of them at once used to mean whichever ran last.
func _apply_flashlight_state() -> void:
	if not flashlight:
		return
	var lit := _flashlight_on and flashlight_battery > 0.0
	flashlight.visible = lit
	var energy := _flashlight_base_energy
	var beam_range := _flashlight_base_range
	var angle := _flashlight_base_angle
	if lit and _flashlight_focus_held:
		energy *= flashlight_focus_energy_scale
		beam_range *= flashlight_focus_range_scale
		angle = flashlight_focus_angle
	if _toilet_ghost_present:
		energy *= toilet_ghost_flashlight_energy_multiplier
		beam_range *= toilet_ghost_flashlight_range_multiplier
	flashlight.light_energy = energy
	flashlight.spot_range = beam_range
	flashlight.spot_angle = angle


func is_flashlight_on() -> bool:
	return _flashlight_on and flashlight_battery > 0.0


## What the Darkness Ghost's kill and slow both read. A beam that is merely on
## does neither: the ghost is hurt by the focused beam or by nothing.
func is_flashlight_focused() -> bool:
	return is_flashlight_on() and _flashlight_focus_held


func get_flashlight_battery_ratio() -> float:
	return clampf(flashlight_battery / maxf(flashlight_battery_max, 0.001), 0.0, 1.0)


## Returns how much charge was actually taken, so a battery pickup can stay on
## the floor for somebody who needs it instead of being spent topping up a tank
## that is already full.
func add_flashlight_battery(amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	var accepted := minf(amount, flashlight_battery_max - flashlight_battery)
	if accepted <= 0.0:
		return 0.0
	flashlight_battery += accepted
	_apply_flashlight_state()
	return accepted


func set_toilet_ghost_presence(present: bool) -> void:
	_toilet_ghost_present = present
	_apply_flashlight_state()
	var overlay_material := horror_overlay_rect.material as ShaderMaterial
	if overlay_material:
		overlay_material.set_shader_parameter("toilet_presence", 1.0 if present else 0.0)


func start_door_minigame(door: Node, authority_already_claimed: bool = false) -> bool:
	if not is_alive \
		or not door_minigame \
		or _is_any_minigame_active() \
		or not is_instance_valid(door):
		if authority_already_claimed and is_instance_valid(door):
			report_door_outcome(door, DoorOutcome.CANCELLED)
		return false
	# A remote encounter reaches its owner only after the server has claimed the
	# authoritative door. Its replicated client copy may already say
	# `minigame_active`, so asking begin_exorcism() a second time creates a race:
	# a fast door snapshot rejects the same session the RPC is trying to open.
	if not authority_already_claimed and (
		not door.has_method("begin_exorcism") or not bool(door.call("begin_exorcism"))
	):
		return false
	# The encounter is aimed with a flashlight through this player's camera, so
	# it can only be played where that camera is. On the server another player's
	# node is a replica - no current camera, HUD force-hidden - so the door is
	# claimed here and the encounter itself is sent to the machine that pressed E.
	if _encounter_belongs_elsewhere():
		_hand_encounter_to_owner(door, &"start_door_minigame")
		door_minigame_started.emit(door)
		return true
	if not door_minigame.has_method("start") or not bool(door_minigame.call("start", self, door)):
		if authority_already_claimed:
			report_door_outcome(door, DoorOutcome.CANCELLED)
		elif door.has_method("cancel_exorcism"):
			door.call("cancel_exorcism")
		return false
	door_minigame_started.emit(door)
	return true


func is_door_minigame_active() -> bool:
	return door_minigame != null \
		and door_minigame.has_method("is_running") \
		and bool(door_minigame.call("is_running"))


## Called by a Toilet's own script when interacted with - mirrors
## start_door_minigame(): the toilet never reaches into player internals,
## it just calls this public API the same way PickupItem/LightSwitch do.
## Unlike DoorGhostMinigame, ToiletMinigame is owned per-toilet (a child of
## the Toilet, matching feat/game-character-hoang's node structure) rather
## than pre-instantiated per-player, so it's resolved from `toilet` here and
## the reference kept only for as long as this player's session lasts.
func start_toilet_minigame(toilet: Node) -> bool:
	if not is_alive or _is_any_minigame_active() or not is_instance_valid(toilet):
		return false
	var minigame: Node = toilet.get_node_or_null("ToiletMinigame")
	if not minigame or not minigame.has_method("start"):
		return false
	# Same reason as the door: it is played through this player's camera.
	if _encounter_belongs_elsewhere():
		_hand_encounter_to_owner(toilet, &"start_toilet_minigame")
		return true
	if not bool(minigame.call("start", self, toilet)):
		return false
	_active_toilet_minigame = minigame
	minigame.connect(
		&"session_ended", _on_toilet_session_ended.bind(toilet), CONNECT_ONE_SHOT
	)
	return true


func _on_toilet_session_ended(success: bool, toilet: Node) -> void:
	_active_toilet_minigame = null
	if _is_network_client():
		# See apply_network_state(): snapshots in flight still carry the level
		# this session just drained, and must not be allowed to undo it.
		_bladder_report_pending = true
		_toilet_report_sequence += 1
		_report_remote_encounter_finished.rpc_id(
			NETWORK_SERVER_PEER_ID,
			_scene_path_of(toilet),
			&"start_toilet_minigame",
			success,
			get_bladder(),
			_toilet_report_sequence
		)


## True for the whole session, deliberately *not* `is_running()`.
##
## `succeed()`/`cancel()` leave ToiletMinigame's PLAYING state the instant the
## bladder hits zero, and only then spend a second of result text plus a
## camera-release tween before emitting `session_ended`. `is_running()` was
## already false for all of it, so on a client every snapshot landing in that
## window overwrote the bladder that had just been emptied with the server's
## pre-session value - and the report that followed carried *that* value back
## to the authority as the session's result. The bar refilled at the exact
## moment the player finished, on every peer, and the drain was lost: the
## "never finishes peeing" bug. Keyed on the reference instead, which
## `_on_toilet_session_ended()` clears in the same breath as it sets
## `_bladder_report_pending`, so the two guards meet with no frame in between.
func is_toilet_minigame_active() -> bool:
	return is_instance_valid(_active_toilet_minigame)


## Called by MainBreaker's own script when its Interactable fires - the same
## per-object arrangement as start_toilet_minigame(), since BreakerMinigame is
## a child of the cabinet rather than a fixed child of Player.
func start_breaker_minigame(breaker: Node) -> bool:
	if not is_alive or _is_any_minigame_active() or not is_instance_valid(breaker):
		return false
	var minigame: Node = breaker.get_node_or_null("BreakerMinigame")
	if not minigame or not minigame.has_method("start"):
		return false
	# Same reason as the door: the wheel is drawn and timed on the machine of
	# whoever opened the cabinet. Without this a client's E opened an invisible
	# countdown on a headless server and left the breaker locked forever.
	if _encounter_belongs_elsewhere():
		_hand_encounter_to_owner(breaker, &"start_breaker_minigame")
		return true
	if not bool(minigame.call("start", self, breaker)):
		return false
	_active_breaker_minigame = minigame
	minigame.connect(
		&"session_ended", _on_breaker_session_ended.bind(breaker), CONNECT_ONE_SHOT
	)
	return true


func _on_breaker_session_ended(success: bool, breaker: Node) -> void:
	_active_breaker_minigame = null
	if _is_network_client():
		_report_remote_encounter_finished.rpc_id(
			NETWORK_SERVER_PEER_ID,
			_scene_path_of(breaker),
			&"start_breaker_minigame",
			success,
			get_bladder(),
			0
		)


func is_breaker_minigame_active() -> bool:
	return is_instance_valid(_active_breaker_minigame) \
		and _active_breaker_minigame.has_method("is_running") \
		and bool(_active_breaker_minigame.call("is_running"))


## True while this player is away in an encounter being played on their own
## machine. The body stands still here, and counting it as busy is what stops
## the server walking it and stops a second minigame starting on top.
func is_remote_encounter_active() -> bool:
	return is_instance_valid(_remote_encounter_target)


func owns_remote_encounter(target: Node, starter: StringName = &"") -> bool:
	return is_instance_valid(target) \
		and _remote_encounter_target == target \
		and (starter.is_empty() or _remote_encounter_starter == starter)


func _is_any_minigame_active() -> bool:
	return is_door_minigame_active() \
		or is_toilet_minigame_active() \
		or is_breaker_minigame_active() \
		or is_remote_encounter_active()


## True when this node is a replica of somebody else's player: an encounter
## started on it has to be played on their machine, not here.
func _encounter_belongs_elsewhere() -> bool:
	return _is_network_session() \
		and multiplayer.is_server() \
		and owner_peer_id > 0 \
		and owner_peer_id != multiplayer.get_unique_id()


func _hand_encounter_to_owner(target: Node, starter: StringName) -> void:
	_remote_encounter_target = target
	_remote_encounter_starter = starter
	_begin_remote_encounter.rpc_id(owner_peer_id, _scene_path_of(target), starter)


func _clear_remote_encounter() -> void:
	_remote_encounter_target = null
	_remote_encounter_starter = &""


func _release_remote_encounter_target() -> void:
	if not is_instance_valid(_remote_encounter_target):
		_clear_remote_encounter()
		return
	match _remote_encounter_starter:
		&"start_door_minigame":
			if _remote_encounter_target.has_method("cancel_exorcism"):
				_remote_encounter_target.call("cancel_exorcism")
		&"start_toilet_minigame":
			if _remote_encounter_target.has_method("end_session"):
				_remote_encounter_target.call("end_session")
		&"start_breaker_minigame":
			if _remote_encounter_target.has_method("cancel_remote_session"):
				_remote_encounter_target.call("cancel_remote_session")
	_clear_remote_encounter()


## Re-enters the same public API on the machine that pressed E, where
## `_encounter_belongs_elsewhere()` is false and the minigame simply runs.
@rpc("authority", "call_remote", "reliable")
func _begin_remote_encounter(target_path: NodePath, starter: StringName) -> void:
	if not _network_is_reachable() \
		or not is_local_player() \
		or starter not in REMOTE_ENCOUNTER_STARTERS:
		return
	var target := _scene_node(target_path)
	if target == null:
		return
	if starter == &"start_door_minigame":
		# The server already owns this door session. Start only the local camera,
		# flashlight and ghost presentation; never try to claim the replica again.
		start_door_minigame(target, true)
	else:
		callv(starter, [target])


## The one way an encounter's result reaches the door.
##
## On the authority it is applied straight away - the path single-player and the
## host's own player take. On a client the encounter was played here but the
## door is the server's, so the outcome is reported and comes back as durability
## in the next apply_network_state().
func report_door_outcome(door: Node, outcome: DoorOutcome) -> float:
	if not is_instance_valid(door) or not ("repair_cap" in door):
		return 0.0
	if not WorldNet.is_world_authority():
		_report_door_outcome.rpc_id(
			NETWORK_SERVER_PEER_ID, int(door.get("entrance_id")), int(outcome)
		)
		return float(door.get("repair_cap"))
	return _apply_door_outcome(door, outcome)


func _apply_door_outcome(door: Node, outcome: DoorOutcome) -> float:
	if _remote_encounter_target == door:
		_clear_remote_encounter()
	match outcome:
		DoorOutcome.CLEARED:
			if door.has_method("complete_exorcism"):
				door.call("complete_exorcism")
		DoorOutcome.FAILED:
			if door.has_method("apply_exorcism_failure"):
				return float(door.call("apply_exorcism_failure"))
		DoorOutcome.CANCELLED:
			if door.has_method("cancel_exorcism"):
				door.call("cancel_exorcism")
	return float(door.get("repair_cap"))


@rpc("any_peer", "call_remote", "reliable")
func _report_door_outcome(entrance_id: int, outcome: int) -> void:
	if not _rpc_reached_authority() or not _rpc_sender_owns_player():
		return
	if outcome < DoorOutcome.CLEARED or outcome > DoorOutcome.CANCELLED:
		return
	for node: Node in get_tree().get_nodes_in_group("defense_doors"):
		if int(node.get("entrance_id")) == entrance_id \
			and owns_remote_encounter(node, &"start_door_minigame"):
			_apply_door_outcome(node, outcome as DoorOutcome)
			return


@rpc("any_peer", "call_remote", "reliable")
func _report_remote_encounter_finished(
	target_path: NodePath,
	starter: StringName,
	success: bool,
	reported_bladder: float,
	report_id: int
) -> void:
	if not _rpc_reached_authority() or not _rpc_sender_owns_player():
		return
	if starter not in [&"start_toilet_minigame", &"start_breaker_minigame"]:
		return
	var target := _scene_node(target_path)
	if not owns_remote_encounter(target, starter):
		return
	if starter == &"start_toilet_minigame":
		if is_finite(reported_bladder):
			set_bladder(reported_bladder)
		# Acknowledged even if reported_bladder was somehow invalid - the
		# session did end, and the client must not be stuck waiting forever
		# for an ack that already happened.
		_last_applied_toilet_report = maxi(_last_applied_toilet_report, report_id)
		if target.has_method("end_session"):
			target.call("end_session")
	elif target.has_method("complete_remote_session"):
		target.call("complete_remote_session", success)
	_clear_remote_encounter()


## Node paths travel relative to the current scene, so they mean the same thing
## on a peer whose map sits somewhere else in its own tree.
## `get_tree()` is null outside the tree for the same reason `multiplayer` is,
## so both of these are reachable from a detached body - see
## `_network_is_reachable()`.
func _scene_path_of(node: Node) -> NodePath:
	if not is_inside_tree() or node == null:
		return NodePath()
	var scene := get_tree().current_scene
	if scene == null:
		return NodePath()
	return scene.get_path_to(node)


func _scene_node(path: NodePath) -> Node:
	if not is_inside_tree() or path.is_empty():
		return null
	var scene := get_tree().current_scene
	if scene == null:
		return null
	return scene.get_node_or_null(path)


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


## True while the bladder is emptying itself. Read by the movement code and by
## the vision debuff, so both agree about when an accident is running.
func is_wetting() -> bool:
	return bladder != null and bladder.is_wetting


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


## A body on the floor is out of the fight: every ghost drops it as a target
## the moment it goes down, and picks it up again only after a rescue. The
## `is_downed`/`is_spectator` terms are redundant with `is_alive` today and
## stated anyway, because that is the contract, not an implementation detail.
func can_be_targeted_by_ghosts() -> bool:
	return is_alive \
		and not is_downed \
		and not is_spectator \
		and not is_protected_from_ghost_attacks()


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
## grain, the threat distortion, and the darkness itself. The environment side
## of it (fog, ambient) belongs to the scene, so DevTools handles that; this
## covers everything the player owns.
func set_dev_clear_vision(enabled: bool) -> void:
	dev_clear_vision = enabled
	horror_overlay_rect.visible = not enabled

	if enabled:
		var overlay_material := horror_overlay_rect.material as ShaderMaterial
		if overlay_material:
			overlay_material.set_shader_parameter("threat_strength", 0.0)

	if not _dev_vision_light:
		_dev_vision_light = OmniLight3D.new()
		_dev_vision_light.name = "DevVisionLight"
		# Wide and soft rather than bright and tight: the point is to read the
		# room you are standing in, not to cast a second flashlight beam.
		_dev_vision_light.light_energy = 1.1
		_dev_vision_light.omni_range = 18.0
		_dev_vision_light.omni_attenuation = 1.2
		_dev_vision_light.light_color = Color(0.92, 0.95, 1.0)
		_dev_vision_light.add_to_group(&"local_light_sources")
		camera_pivot.add_child(_dev_vision_light)
	_dev_vision_light.visible = enabled


## Camera-relative flight: WASD follows where you are looking, Space and Ctrl
## are straight up and down. Position is written directly, so no collision,
## gravity or step-up logic gets a say.
func _fly(delta: float) -> void:
	var input_dir := _movement_input()
	var camera_basis := camera_pivot.global_basis
	var motion := (
		camera_basis * Vector3(input_dir.x, 0.0, input_dir.y)
		+ Vector3.UP * (
			(1.0 if _input_action_pressed(&"jump") else 0.0)
			- (1.0 if _input_action_pressed(&"crouch") else 0.0)
		)
	)
	var speed := walk_speed * 3.0
	if _input_action_pressed(&"run"):
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


func _update_footsteps(delta: float, is_sprinting: bool) -> void:
	var real_velocity := get_real_velocity()
	var horizontal_speed := Vector2(real_velocity.x, real_velocity.z).length()
	_advance_footsteps(delta, is_sprinting, horizontal_speed, is_on_floor())


## The footstep clock itself, told how fast this body is moving and whether it
## is on the ground rather than asking the physics server.
##
## A teammate's body on a client never calls move_and_slide(): it is placed by
## _interpolate_network_snapshot(), so get_real_velocity() reads zero and
## is_on_floor() reads false, and asking those directly meant every other
## player in the house walked in complete silence. The replicated velocity
## answers both questions instead.
func _advance_footsteps(
	delta: float,
	is_sprinting: bool,
	horizontal_speed: float,
	grounded: bool
) -> void:
	for index: int in _footstep_stop_times.size():
		if _footstep_stop_times[index] <= 0.0:
			continue
		_footstep_stop_times[index] -= delta
		if _footstep_stop_times[index] <= 0.0:
			footstep_players[index].stop()

	var walking_on_floor := grounded and horizontal_speed > 0.25
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
	if is_downed:
		target_height = downed_camera_height
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
	# The peek is part of where the head is meant to be, not a second opinion
	# about it. Left out of this target, the lerp below spends every frame
	# pulling the lean back to the centreline it does not know about.
	target_position.x += _lean_reach * lean_side_offset
	var blend := minf(crouch_transition_speed * delta, 1.0)
	# A modest roll is enough to read as "lying on the floor". Anything closer
	# to a real 90 degrees fights mouse-look, which downed players keep.
	var target_roll := threat_wave * 0.006 - _lean_reach * deg_to_rad(lean_max_angle)
	if is_downed:
		target_roll += deg_to_rad(downed_camera_roll_degrees)
	camera_pivot.position = camera_pivot.position.lerp(target_position, blend)
	camera_pivot.rotation.z = lerpf(camera_pivot.rotation.z, target_roll, blend)


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
