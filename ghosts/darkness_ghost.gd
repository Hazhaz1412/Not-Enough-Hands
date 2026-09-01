class_name DarknessGhost
extends WomanGhost

## The Darkness Ghost marks one player, materialises at a safe distance, warns
## them by flickering the surrounding electrical zones, then cuts that whole
## pocket of the villa and hunts whoever is currently closest to it.

signal manifested(zone: ElectricalZone)
signal retreated
signal died_in_light
signal killed_player(player: Node3D)

enum EncounterPhase {
	DORMANT,
	WARNING,
	CHASING,
}

@export_category("Darkness Ghost")
@export var auto_manifest := true
@export_range(1.0, 300.0, 1.0) var first_manifest_delay := 10.0
@export_range(1.0, 300.0, 1.0) var manifest_interval := 70.0
## How long one hunt lasts before the ghost gives up and the circuits it cut
## come back. Without this the very first manifest never ends - it holds the
## pocket dark and chases until it kills somebody or dies in light - so a night
## contained exactly one encounter. A night is 547.5 real seconds, which at the
## shipped warning/hunt/interval pacing is five.
@export_range(5.0, 300.0, 1.0) var hunt_duration := 40.0
@export_range(2.0, 30.0, 0.5) var threat_range := 12.0
@export_range(0.5, 4.0, 0.05) var kill_distance := 1.15
@export_range(1.0, 40.0, 0.5) var minimum_spawn_distance := 15.0
@export_range(1.0, 10.0, 0.25) var warning_duration := 4.0
## The target's zone plus this many authored neighbour rings flicker and fail
## together. One ring is already a broad multi-room pocket in the villa.
@export_range(0, 3, 1) var blackout_neighbour_depth := 1
## Chance that any one fixture in the cut pocket comes back jammed: its switch
## is dead for the whole hunt, so walking the lights back on is a gamble rather
## than a checklist. A zone never has every fixture jammed at once, and the jam
## lifts with the hunt.
@export_range(0.0, 1.0, 0.05) var hunt_light_lock_chance := 0.4
@export_range(0.5, 20.0, 0.05) var normal_speed := 4.0
@export_range(0.5, 20.0, 0.05) var darkness_speed := 5.25
## Powered world lights kill the ghost after one uninterrupted exposure.
@export_range(0.1, 10.0, 0.1) var light_death_seconds := 3.0
## Each distinct living player's flashlight applies this penalty while its
## unobstructed cone is actually on the ghost.
@export_range(0.0, 10.0, 0.1) var flashlight_speed_penalty := 1.9
@export_range(1, 8, 1) var flashlight_retreat_player_count := 3
@export_range(0.1, 15.0, 0.1) var flashlight_retreat_seconds := 5.0
@export_range(0.0, 5.0, 0.1) var minimum_illuminated_speed := 0.6
@export_range(0.5, 15.0, 0.05) var patrol_speed := 3.25
@export_range(0.5, 15.0, 0.1) var patrol_retarget_seconds := 3.0
## Used only when a manifest attempt fails outright (e.g. no powered zone
## could be found near the player). Short on purpose: manifest_interval is
## the pacing between *successful* hauntings, not the retry backoff for a
## failed lookup that may resolve itself a few seconds later.
@export_range(1.0, 60.0, 0.5) var failed_manifest_retry_delay := 8.0

@export_category("Darkness Footsteps")
@export_range(0.2, 1.5, 0.05) var footstep_interval := 0.55
@export_range(-30.0, 12.0, 0.5) var footstep_volume_db := -2.0
@export_range(0.5, 1.5, 0.01) var footstep_pitch_min := 0.76
@export_range(0.5, 1.5, 0.01) var footstep_pitch_max := 0.88

@export_category("Stuck Recovery")
## If the ghost hasn't covered stuck_movement_threshold metres toward its
## current target within this many seconds, it's considered stuck (wedged
## against geometry, blocked by another avoidance agent, or given an
## unreachable target) and a context-specific recovery kicks in.
@export_range(1.0, 15.0, 0.5) var stuck_detection_seconds := 3.0
@export_range(0.05, 2.0, 0.05) var stuck_movement_threshold := 0.4
@export_range(0.1, 2.0, 0.05) var stuck_nudge_seconds := 0.6
## Even at chase pace the ghost can cross a narrow stair-link waypoint between
## physics frames. A wider acceptance radius lets NavigationAgent3D advance to
## the next hop instead of ordering it back down the stair it just climbed.
@export_range(0.35, 1.5, 0.05) var stair_waypoint_tolerance := 0.7
@export_range(0.1, 1.0, 0.05) var max_step_height := 0.6
@export_range(0.05, 0.2, 0.01) var step_floor_margin := 0.08
@export_range(0.1, 0.8, 0.05) var step_probe_distance := 0.3

var _power_effect: DarknessEntityPowerEffect
var _is_manifested := false
var encounter_phase := EncounterPhase.DORMANT
var _next_manifest_in := 0.0
var _warning_time_left := 0.0
var _hunt_time_left := 0.0
var _target_player: Node3D
var _encounter_zones: Array[ElectricalZone] = []
var _warning_visual_active := false
var _patrol_target := Vector3.ZERO
var _patrol_retarget_in := 0.0
## Godot resolves avoidance-aware velocity asynchronously via the
## NavigationAgent3D's velocity_computed signal, which does not carry delta.
## We stash the delta from the physics frame that requested it so the actual
## move_and_slide() (done in the callback) still uses the right timestep.
var _pending_move_delta := 0.0
var _moving_directly_on_stair := false
## Stuck watchdog state.
var _stuck_timer := 0.0
var _stuck_reference_position := Vector3.ZERO
var _unstick_direction := Vector3.ZERO
var _unstick_seconds_left := 0.0
var _environment_light_exposure := 0.0
var _flashlight_focus_time := 0.0
var _flashlight_player_count := 0
var _is_dead := false
var _footstep_time_left := 0.0
var _footstep_slice_left := 0.0

@onready var _footstep_audio: AudioStreamPlayer3D = $FootstepAudio

const FOOTSTEP_OFFSETS: Array[float] = [0.12, 0.68, 1.21, 1.79, 2.34, 2.92, 3.44]
const FOOTSTEP_SLICE := 0.34


func _ready() -> void:
	super._ready()
	add_to_group("darkness_ghosts")
	_power_effect = get_node_or_null("DarknessEntityPowerEffect") as DarknessEntityPowerEffect
	$NavigationAgent3D.path_desired_distance = stair_waypoint_tolerance
	# NavigationAgent3D has avoidance_enabled = true in the scene, but avoidance
	# only takes effect once we feed it a desired velocity via set_velocity()
	# and consume the resolved, collision-avoided result from this signal.
	if not $NavigationAgent3D.velocity_computed.is_connected(_on_navigation_velocity_computed):
		$NavigationAgent3D.velocity_computed.connect(_on_navigation_velocity_computed)
	_set_manifested(false)
	_next_manifest_in = first_manifest_delay


func _process(delta: float) -> void:
	_update_footsteps(delta)
	_update_warning_visuals()
	# Manifesting, expanding and retreating all cut real circuits, so they are
	# the server's alone; a client takes the darkened zones through
	# PowerManager.apply_network_state() and this body through WorldReplicator.
	if not WorldNet.is_world_authority():
		return
	if _is_manifested:
		if encounter_phase == EncounterPhase.WARNING:
			_warning_time_left -= delta
			if _warning_time_left <= 0.0:
				_finish_warning()
			return
		# Restoring the grid no longer makes the ghost disappear instantly. It
		# must remain inside light for light_death_seconds, giving it a chance to
		# escape a briefly lit doorway while rewarding a sustained exposure.
		if encounter_phase == EncounterPhase.CHASING:
			_hunt_time_left -= delta
			if _hunt_time_left <= 0.0:
				retreat()
		return
	if auto_manifest and not _is_dead:
		_next_manifest_in -= delta
		if _next_manifest_in <= 0.0:
			manifest()


func _physics_process(delta: float) -> void:
	if not _is_manifested or not WorldNet.is_world_authority():
		return
	if encounter_phase != EncounterPhase.CHASING:
		velocity = Vector3.ZERO
		play_idle()
		return
	_update_light_exposure(delta)
	if not _is_manifested:
		return
	var player := _nearest_living_player()
	# Aggro is recalculated from the ghost every frame. This is deliberately not
	# sticky: the moment another living player is closer, they become the target.
	var hunting := player != null
	if hunting:
		_target_player = player
		var speed := _chase_speed_at(global_position)
		_pursue(player.global_position, speed, delta, &"chase")
		_update_player_threat_and_contact(player)
	else:
		_target_player = null
		_clear_player_threat()
		_patrol_retarget_in -= delta
		if _patrol_retarget_in <= 0.0 or global_position.distance_to(_patrol_target) <= stopping_distance:
			_patrol_target = _random_patrol_point()
			_patrol_retarget_in = patrol_retarget_seconds
			_stuck_timer = 0.0
			_stuck_reference_position = global_position
		_pursue(_patrol_target, patrol_speed, delta, &"patrol")


## Public gameplay hook. The affected cluster begins at the selected player's
## current (or nearest) zone, never a random remote wing.
func manifest() -> bool:
	return _begin_manifest_for_target(_nearest_living_player())


## The F1 panel uses the exact production warning/spawn rules too, including
## the 15m safety check, so debugging cannot hide an invalid spawn layout.
func manifest_for_dev() -> bool:
	return _begin_manifest_for_target(_nearest_living_player())


func _begin_manifest_for_target(player: Node3D) -> bool:
	if _is_dead or _is_manifested or not _power_effect or not player:
		return false
	var preferred_zone := _zone_near_position(player.global_position)
	if not preferred_zone:
		_next_manifest_in = failed_manifest_retry_delay
		return false
	var zones := _power_effect.get_zone_cluster(preferred_zone, blackout_neighbour_depth)
	var spawn_position := _safe_spawn_position(zones)
	if spawn_position == Vector3.INF:
		_next_manifest_in = failed_manifest_retry_delay
		return false
	_target_player = player
	_encounter_zones.assign(zones)
	global_position = spawn_position
	encounter_phase = EncounterPhase.WARNING
	_warning_time_left = warning_duration
	_set_manifested(true)
	velocity = Vector3.ZERO
	_stuck_timer = 0.0
	_stuck_reference_position = global_position
	_unstick_seconds_left = 0.0
	_reset_light_exposure()
	manifested.emit(preferred_zone)
	return true


func _finish_warning() -> void:
	if encounter_phase != EncounterPhase.WARNING or not _power_effect:
		return
	# Which fixtures the hunt refuses to give back is rolled here, once, and kept
	# on ElectricalZone where it replicates. It used to be answered from
	# `_target_player` instead - a variable only the authority ever assigns - so a
	# client believed every switch would work, turned one on locally, and watched
	# the server's next snapshot put it straight back out.
	var cut_zones := _power_effect.cause_zone_outages(_encounter_zones, hunt_light_lock_chance)
	if cut_zones.is_empty():
		retreat()
		return
	_encounter_zones.assign(cut_zones)
	encounter_phase = EncounterPhase.CHASING
	_warning_time_left = 0.0
	_hunt_time_left = hunt_duration
	_patrol_target = _random_patrol_point()
	_patrol_retarget_in = patrol_retarget_seconds
	_stop_warning_visuals(false)


func retreat() -> void:
	if not _is_manifested:
		return
	_clear_player_threat()
	_stop_warning_visuals(true)
	_set_manifested(false)
	encounter_phase = EncounterPhase.DORMANT
	_target_player = null
	_encounter_zones.clear()
	_stuck_timer = 0.0
	_unstick_seconds_left = 0.0
	_hunt_time_left = 0.0
	_reset_light_exposure()
	if _power_effect:
		_power_effect.clear_zone_outage()
	_next_manifest_in = manifest_interval
	retreated.emit()


func is_manifested() -> bool:
	return _is_manifested


func is_dead() -> bool:
	return _is_dead


func get_replication_state() -> Array:
	var zone_ids := PackedStringArray()
	for zone: ElectricalZone in _encounter_zones:
		if is_instance_valid(zone):
			zone_ids.append(String(zone.zone_id))
	return [encounter_phase, _warning_time_left, zone_ids, _is_dead]


func apply_replication_state(state: Array) -> void:
	if state.size() < 3:
		return
	var incoming_phase := int(state[0])
	var incoming_ids := state[2] as PackedStringArray
	var changed := incoming_phase != encounter_phase or not _zone_ids_match(incoming_ids)
	encounter_phase = incoming_phase
	_warning_time_left = float(state[1])
	if state.size() >= 4:
		_is_dead = bool(state[3])
	if changed:
		_encounter_zones.clear()
		for zone_id: String in incoming_ids:
			var zone := _power_effect.find_zone(StringName(zone_id)) if _power_effect else null
			if zone:
				_encounter_zones.append(zone)
		if encounter_phase == EncounterPhase.DORMANT:
			_stop_warning_visuals(true)


func _set_manifested(value: bool) -> void:
	_is_manifested = value
	chase_enabled = value
	if value:
		# _finish_warning() restarts this when the chase actually begins. Arming
		# it here as well means a body dropped straight into CHASING - the dev
		# panel, a test - still gets a whole hunt instead of a clock already at
		# zero, which the countdown below would read as "time to leave".
		_hunt_time_left = hunt_duration
	$AnimatedModel.visible = value
	# IdleAnimationSource is an internal animation-retargeting helper, not a
	# renderable state of the ghost — it must never be visible, manifested or
	# not, so this is unconditional by design (not a copy-paste of the line above).
	$IdleAnimationSource.visible = false
	$CollisionShape3D.set_deferred("disabled", not value)
	if value:
		play_idle()
	else:
		velocity = Vector3.ZERO
		_stop_footsteps()


## Runs on every peer. The server/host hears its authoritative body directly;
## clients derive the same local 3D presentation from replicated velocity, so
## footsteps need no extra audio RPC and stay positioned on the ghost.
func _update_footsteps(delta: float) -> void:
	if _footstep_slice_left > 0.0:
		_footstep_slice_left -= delta
		if _footstep_slice_left <= 0.0 and _footstep_audio.playing:
			_footstep_audio.stop()
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if not _is_manifested \
		or encounter_phase != EncounterPhase.CHASING \
		or horizontal_speed <= 0.15:
		_footstep_time_left = 0.0
		if _footstep_audio.playing:
			_footstep_audio.stop()
		_footstep_slice_left = 0.0
		return
	_footstep_time_left -= delta
	if _footstep_time_left > 0.0:
		return
	_play_footstep(horizontal_speed)
	var pace_scale := clampf(3.2 / maxf(horizontal_speed, 0.1), 0.8, 1.15)
	_footstep_time_left = footstep_interval * pace_scale


func _play_footstep(horizontal_speed: float) -> void:
	if not _footstep_audio.stream:
		return
	_footstep_audio.pitch_scale = randf_range(
		minf(footstep_pitch_min, footstep_pitch_max),
		maxf(footstep_pitch_min, footstep_pitch_max)
	)
	_footstep_audio.volume_db = footstep_volume_db + minf(horizontal_speed * 0.35, 1.5)
	_footstep_audio.play(FOOTSTEP_OFFSETS.pick_random())
	_footstep_slice_left = FOOTSTEP_SLICE


func _stop_footsteps() -> void:
	_footstep_time_left = 0.0
	_footstep_slice_left = 0.0
	if is_instance_valid(_footstep_audio) and _footstep_audio.playing:
		_footstep_audio.stop()


## Wraps a movement call with stuck-progress tracking. Every other call site
## in this file should go through here instead of _move_within_dark_zone()
## directly, so no movement context is left without a recovery path.
func _pursue(target_position: Vector3, speed: float, delta: float, context: StringName) -> void:
	_move_within_dark_zone(target_position, speed, delta)
	_track_stuck_progress(target_position, delta, context)


func _track_stuck_progress(target_position: Vector3, delta: float, context: StringName) -> void:
	# A ghost standing right next to its own target has arrived, not stuck.
	if global_position.distance_to(target_position) <= stopping_distance + 0.3:
		_stuck_timer = 0.0
		_stuck_reference_position = global_position
		return
	_stuck_timer += delta
	if _stuck_timer < stuck_detection_seconds:
		return
	var progressed := global_position.distance_to(_stuck_reference_position)
	_stuck_reference_position = global_position
	_stuck_timer = 0.0
	if progressed >= stuck_movement_threshold:
		return  # Real progress happened during the window; not stuck.
	_recover_from_stuck(target_position, context)


func _recover_from_stuck(_target_position: Vector3, context: StringName) -> void:
	match context:
		&"patrol":
			# The chosen patrol point may simply be unreachable (bad navmesh
			# marker) — pick a different one instead of waiting out the full
			# retarget timer while stuck.
			_patrol_target = _random_patrol_point()
			_patrol_retarget_in = patrol_retarget_seconds
		&"chase":
			# Likely wedged against geometry the navmesh thinks is clear
			# (e.g. a tight doorway corner). A short sideways push is enough
			# to break most such deadlocks without teleporting the ghost
			# toward the player, which would be unfair.
			var lateral := global_transform.basis.x
			_unstick_direction = lateral if randf() < 0.5 else -lateral
			_unstick_seconds_left = stuck_nudge_seconds


## Every point inside a zone the ghost may legitimately stand on: the authored
## room clear points plus a spot under each of the zone's lights. Spawning,
## patrolling and zone ranking all read the same list.
func _zone_clear_points(zone: ElectricalZone) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for marker_node: Node in get_tree().get_nodes_in_group("villa_rooms"):
		var marker := marker_node as Marker3D
		if marker and zone.contains_device_id(StringName(marker.get_meta("room_id", marker.name))):
			points.append(marker.get_meta("clear_point", marker.global_position) as Vector3)
	for device: ElectricalDevice in zone.get_devices():
		if device.powered_light:
			points.append(device.powered_light.global_position - Vector3.UP * 2.7)
	return points


func _safe_spawn_position(zones: Array[ElectricalZone]) -> Vector3:
	var candidates: Array[Vector3] = []
	for zone: ElectricalZone in zones:
		candidates.append_array(_zone_clear_points(zone))
	var players := _living_players()
	var best := Vector3.INF
	var best_nearest_distance := -INF
	for candidate: Vector3 in candidates:
		var nearest_distance := INF
		for player: Node3D in players:
			nearest_distance = minf(nearest_distance, candidate.distance_to(player.global_position))
		if nearest_distance >= minimum_spawn_distance and nearest_distance > best_nearest_distance:
			best = candidate + Vector3.UP * 0.05
			best_nearest_distance = nearest_distance
	return best


func _update_player_threat_and_contact(player: Node3D) -> void:
	var distance := global_position.distance_to(player.global_position)
	if player.has_method("set_threat_from"):
		player.call("set_threat_from", &"darkness_ghost", clampf(1.0 - distance / threat_range, 0.0, 1.0))
	# The threat meter can stay a straight-line estimate, but the kill check
	# uses the navmesh path distance whenever the agent is already routed to
	# the player, so a thin wall between them (small straight-line distance,
	# much larger walking distance) can't register as contact.
	var kill_check_distance := distance
	if $NavigationAgent3D.target_position.distance_to(player.global_position) <= 0.1:
		kill_check_distance = $NavigationAgent3D.distance_to_target()
	if kill_check_distance <= kill_distance and player.has_method("kill_by_ghost"):
		player.call("kill_by_ghost", self)
		killed_player.emit(player)
		retreat()


func _move_within_dark_zone(target_position: Vector3, speed: float, delta: float) -> void:
	if _unstick_seconds_left > 0.0:
		_unstick_seconds_left -= delta
		_pending_move_delta = delta
		look_at(global_position + _unstick_direction, Vector3.UP, true)
		play_walk()
		$NavigationAgent3D.set_velocity(_unstick_direction * speed)
		return
	# NavigationLink3D supplies the route onto the staircase, but a fast agent
	# can oscillate around its intermediate ramp waypoint. Once physically on a
	# villa ramp, follow the ramp's own axis until reaching the landing; this is
	# still ordinary collision movement, not a teleport.
	var stair_direction := _stair_direction_toward(target_position)
	if not stair_direction.is_zero_approx():
		_moving_directly_on_stair = true
		look_at(global_position + stair_direction, Vector3.UP, true)
		play_walk()
		velocity.x = move_toward(velocity.x, stair_direction.x * speed, acceleration * delta)
		velocity.z = move_toward(velocity.z, stair_direction.z * speed, acceleration * delta)
		if not is_on_floor():
			velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta
		else:
			velocity.y = 0.0
		_try_step_up(Vector3(velocity.x, 0.0, velocity.z) * delta)
		move_and_slide()
		return
	_moving_directly_on_stair = false
	var direction := target_position - global_position
	direction.y = 0.0
	var desired_horizontal_velocity := Vector3.ZERO
	if direction.length_squared() > 0.001:
		$NavigationAgent3D.target_position = target_position
		var next_position := target_position
		if not $NavigationAgent3D.is_navigation_finished():
			next_position = $NavigationAgent3D.get_next_path_position()
		direction = next_position - global_position
		direction.y = 0.0
		if direction.length_squared() > 0.001:
			direction = direction.normalized()
			desired_horizontal_velocity = direction * speed
			look_at(global_position + direction, Vector3.UP, true)
			play_walk()
		else:
			play_idle()
	else:
		play_idle()
	# Hand the desired velocity to the NavigationAgent3D's avoidance system.
	# The actual move happens in _on_navigation_velocity_computed() once the
	# NavigationServer has resolved it against nearby avoidance agents/obstacles.
	_pending_move_delta = delta
	$NavigationAgent3D.set_velocity(desired_horizontal_velocity)


func _stair_direction_toward(target_position: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 0.45,
		global_position + Vector3.DOWN * 0.9,
		collision_mask
	)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var ramp := hit.get("collider") as StaticBody3D
	if not ramp or not ramp.is_in_group(&"villa_stair_ramps"):
		return Vector3.ZERO
	var uphill := ramp.global_basis.x
	uphill.y = 0.0
	if uphill.length_squared() <= 0.001:
		return Vector3.ZERO
	uphill = uphill.normalized()
	return uphill if target_position.y > global_position.y + 0.25 else -uphill


## The side entry at V01 meets the smooth ramp above floor level. This probe
## lets the capsule mount that lip immediately instead of waiting for the
## generic three-second stuck recovery to kick it sideways at random.
func _try_step_up(horizontal_motion: Vector3) -> void:
	if horizontal_motion.is_zero_approx():
		return
	if is_on_floor() and get_floor_normal().dot(up_direction) < 0.98:
		return
	var forward_collision := KinematicCollision3D.new()
	if not test_move(global_transform, horizontal_motion, forward_collision, safe_margin, false):
		return
	if forward_collision.get_normal().dot(up_direction) >= cos(floor_max_angle):
		return
	var available_step_height := max_step_height
	var up_collision := KinematicCollision3D.new()
	if test_move(
		global_transform,
		Vector3.UP * max_step_height,
		up_collision,
		safe_margin,
		false
	):
		available_step_height = up_collision.get_travel().y
	if available_step_height <= 0.02:
		return
	var probe_motion := horizontal_motion
	if probe_motion.length() < step_probe_distance:
		probe_motion = probe_motion.normalized() * step_probe_distance
	var raised_transform := global_transform
	raised_transform.origin += Vector3.UP * available_step_height
	if test_move(raised_transform, probe_motion):
		return
	var forward_transform := raised_transform
	forward_transform.origin += probe_motion
	var down_collision := KinematicCollision3D.new()
	if not test_move(
		forward_transform,
		Vector3.DOWN * (available_step_height + step_floor_margin),
		down_collision
	):
		return
	if down_collision.get_normal().dot(up_direction) < 0.65:
		return
	var landing_y := forward_transform.origin.y + down_collision.get_travel().y
	var step_height := landing_y - global_position.y
	if step_height > 0.02 and step_height <= available_step_height + step_floor_margin:
		global_position.y += step_height


func _on_navigation_velocity_computed(safe_velocity: Vector3) -> void:
	if not _is_manifested or _moving_directly_on_stair:
		return
	var delta := _pending_move_delta
	velocity.x = move_toward(velocity.x, safe_velocity.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, safe_velocity.z, acceleration * delta)
	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta
	else:
		velocity.y = 0.0
	_try_step_up(Vector3(velocity.x, 0.0, velocity.z) * delta)
	move_and_slide()


func _clear_player_threat() -> void:
	for player_node: Node in get_tree().get_nodes_in_group("players"):
		if player_node.has_method("set_threat_from"):
			player_node.call("set_threat_from", &"darkness_ghost", 0.0)


func _living_players() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Node3D
		if player \
			and (not "is_alive" in player or bool(player.get("is_alive"))) \
			and (not "is_downed" in player or not bool(player.get("is_downed"))) \
			and (not "is_spectator" in player or not bool(player.get("is_spectator"))):
			result.append(player)
	return result


func _nearest_living_player() -> Node3D:
	var nearest: Node3D
	var nearest_distance := INF
	for player: Node3D in _living_players():
		var distance := global_position.distance_squared_to(player.global_position)
		if distance < nearest_distance:
			nearest = player
			nearest_distance = distance
	return nearest


func _zone_near_player() -> ElectricalZone:
	var player := _nearest_living_player()
	if not player:
		return null
	return _zone_near_position(player.global_position)


func _zone_near_position(position: Vector3) -> ElectricalZone:
	var closest: ElectricalZone
	var closest_distance := INF
	for marker_node: Node in get_tree().get_nodes_in_group("villa_rooms"):
		var marker := marker_node as Marker3D
		if not marker:
			continue
		var size := marker.get_meta("room_size", Vector3.ZERO) as Vector3
		var offset := position - marker.global_position
		var room_id := StringName(marker.get_meta("room_id", marker.name))
		for zone_node: Node in get_tree().get_nodes_in_group("electrical_zones"):
			var zone := zone_node as ElectricalZone
			if not zone or not zone.is_powered or not zone.contains_device_id(room_id):
				continue
			if absf(offset.x) <= size.x * 0.5 and absf(offset.z) <= size.z * 0.5:
				return zone
			var distance := Vector2(offset.x, offset.z).length()
			if distance < closest_distance:
				closest = zone
				closest_distance = distance
	return closest


## World lighting selects the normal/dark base speed. Player flashlights then
## subtract their penalty independently, once per distinct player whose beam
## reaches the ghost. Walls block both checks.
func _chase_speed_at(position: Vector3) -> float:
	var base_speed := normal_speed if _is_position_environmentally_lit(position) else darkness_speed
	var flashlight_count := _player_flashlight_count_at(position)
	return maxf(minimum_illuminated_speed, base_speed - flashlight_count * flashlight_speed_penalty)


func _is_position_locally_lit(position: Vector3) -> bool:
	for node: Node in get_tree().get_nodes_in_group(&"local_light_sources"):
		var light := node as Light3D
		if light and _light_reaches_position(light, position):
			return true
	return false


func _is_position_environmentally_lit(position: Vector3) -> bool:
	for node: Node in get_tree().get_nodes_in_group(&"local_light_sources"):
		var light := node as Light3D
		if light and not _owning_player(light) and _light_reaches_position(light, position):
			return true
	return false


func _player_flashlight_count_at(position: Vector3) -> int:
	var count := 0
	for player: Node3D in _living_players():
		var flashlight := player.get_node_or_null(^"CameraPivot/Camera3D/Flashlight") as SpotLight3D
		if flashlight and _light_reaches_position(flashlight, position):
			count += 1
	return count


func _owning_player(node: Node) -> Node3D:
	var ancestor := node.get_parent()
	while ancestor:
		if ancestor.is_in_group(&"players"):
			return ancestor as Node3D
		ancestor = ancestor.get_parent()
	return null


func _update_light_exposure(delta: float) -> void:
	if _is_position_environmentally_lit(global_position):
		_environment_light_exposure += delta
	else:
		_environment_light_exposure = 0.0
	if _environment_light_exposure >= light_death_seconds:
		_die_in_light()
		return

	_flashlight_player_count = _player_flashlight_count_at(global_position)
	if _flashlight_player_count >= flashlight_retreat_player_count:
		_flashlight_focus_time += delta
	else:
		_flashlight_focus_time = 0.0
	if _flashlight_focus_time >= flashlight_retreat_seconds:
		retreat()


func _die_in_light() -> void:
	if _is_dead:
		return
	_is_dead = true
	auto_manifest = false
	_clear_player_threat()
	_stop_warning_visuals(true)
	_set_manifested(false)
	encounter_phase = EncounterPhase.DORMANT
	_target_player = null
	_encounter_zones.clear()
	_stuck_timer = 0.0
	_unstick_seconds_left = 0.0
	_hunt_time_left = 0.0
	if _power_effect:
		_power_effect.clear_zone_outage()
	_reset_light_exposure()
	died_in_light.emit()


func _reset_light_exposure() -> void:
	_environment_light_exposure = 0.0
	_flashlight_focus_time = 0.0
	_flashlight_player_count = 0


func _light_reaches_position(light: Light3D, position: Vector3) -> bool:
	if not light.visible or not light.is_visible_in_tree() or light.light_energy <= 0.05:
		return false
	var offset := position - light.global_position
	var distance := offset.length()
	if light is OmniLight3D:
		if distance > (light as OmniLight3D).omni_range:
			return false
	elif light is SpotLight3D:
		var spot := light as SpotLight3D
		if distance > spot.spot_range or distance <= 0.001:
			return false
		var forward := -spot.global_basis.z.normalized()
		var cone_cosine := cos(deg_to_rad(spot.spot_angle * 0.5))
		if forward.dot(offset / distance) < cone_cosine:
			return false
	else:
		return false
	var query := PhysicsRayQueryParameters3D.create(light.global_position, position, 1)
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _update_warning_visuals() -> void:
	if encounter_phase == EncounterPhase.DORMANT:
		if _warning_visual_active:
			_stop_warning_visuals(true)
		return
	if encounter_phase != EncounterPhase.WARNING:
		_warning_visual_active = false
		return
	_warning_visual_active = true
	var lights_on := fmod(maxf(_warning_time_left, 0.0), 0.22) >= 0.09
	for zone: ElectricalZone in _encounter_zones:
		if not is_instance_valid(zone):
			continue
		for device: ElectricalDevice in zone.get_devices():
			if device.powered_light:
				device.powered_light.visible = lights_on and device.is_on
			if device.powered_emission:
				device.powered_emission.visible = lights_on and device.is_on


func _stop_warning_visuals(restore_from_device_state: bool) -> void:
	_warning_visual_active = false
	if not restore_from_device_state:
		return
	for zone: ElectricalZone in _encounter_zones:
		if not is_instance_valid(zone):
			continue
		for device: ElectricalDevice in zone.get_devices():
			if device.powered_light:
				device.powered_light.visible = device.is_on
			if device.powered_emission:
				device.powered_emission.visible = device.is_on


func _zone_ids_match(ids: PackedStringArray) -> bool:
	if ids.size() != _encounter_zones.size():
		return false
	for index: int in ids.size():
		if String(_encounter_zones[index].zone_id) != ids[index]:
			return false
	return true


func _random_patrol_point() -> Vector3:
	if not _power_effect or _power_effect.darkened_zones.is_empty():
		return global_position
	var candidates: Array[Vector3] = []
	for zone: ElectricalZone in _power_effect.darkened_zones:
		candidates.append_array(_zone_clear_points(zone))
	if candidates.is_empty():
		return global_position
	return candidates.pick_random() + Vector3.UP * 0.05
