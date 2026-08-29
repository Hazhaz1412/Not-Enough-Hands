class_name DarknessGhost
extends WomanGhost

## The Darkness Ghost turns off one coherent electrical zone, materialises in
## that zone and hunts the player while the room is dark. It deliberately uses
## the reusable WomanGhost model/controller and the zone power contract.

signal manifested(zone: ElectricalZone)
signal retreated
signal killed_player(player: Node3D)

@export_category("Darkness Ghost")
@export var auto_manifest := true
@export_range(1.0, 300.0, 1.0) var first_manifest_delay := 20.0
@export_range(1.0, 300.0, 1.0) var manifest_interval := 55.0
@export_range(2.0, 30.0, 0.5) var threat_range := 12.0
@export_range(0.5, 4.0, 0.05) var kill_distance := 1.15
@export_range(0.1, 10.0, 0.1) var minimum_spawn_distance := 7.0
@export_range(0.5, 5.0, 0.05) var patrol_speed := 1.35
@export_range(0.5, 15.0, 0.1) var patrol_retarget_seconds := 3.0
@export_range(2.0, 120.0, 0.5) var zone_expansion_seconds := 15.0
@export_range(0.3, 3.0, 0.05) var zone_expansion_walk_speed := 1.0
@export_range(0.5, 5.0, 0.05) var zone_blackout_arrival_distance := 1.4
## Used only when a manifest attempt fails outright (e.g. no powered zone
## could be found near the player). Short on purpose: manifest_interval is
## the pacing between *successful* hauntings, not the retry backoff for a
## failed lookup that may resolve itself a few seconds later.
@export_range(1.0, 60.0, 0.5) var failed_manifest_retry_delay := 8.0

@export_category("Stuck Recovery")
## If the ghost hasn't covered stuck_movement_threshold metres toward its
## current target within this many seconds, it's considered stuck (wedged
## against geometry, blocked by another avoidance agent, or given an
## unreachable target) and a context-specific recovery kicks in.
@export_range(1.0, 15.0, 0.5) var stuck_detection_seconds := 3.0
@export_range(0.05, 2.0, 0.05) var stuck_movement_threshold := 0.4
@export_range(0.1, 2.0, 0.05) var stuck_nudge_seconds := 0.6

var _power_effect: DarknessEntityPowerEffect
var _is_manifested := false
var _next_manifest_in := 0.0
var _patrol_target := Vector3.ZERO
var _patrol_retarget_in := 0.0
var _zone_expansion_in := 0.0
var _pending_expansion_zone: ElectricalZone
var _pending_expansion_position := Vector3.ZERO
## Godot resolves avoidance-aware velocity asynchronously via the
## NavigationAgent3D's velocity_computed signal, which does not carry delta.
## We stash the delta from the physics frame that requested it so the actual
## move_and_slide() (done in the callback) still uses the right timestep.
var _pending_move_delta := 0.0
## Stuck watchdog state.
var _stuck_timer := 0.0
var _stuck_reference_position := Vector3.ZERO
var _unstick_direction := Vector3.ZERO
var _unstick_seconds_left := 0.0


func _ready() -> void:
	super._ready()
	# The shared WomanGhost scene only knows its reusable base group. Death UI
	# and other presentation systems need the gameplay identity explicitly.
	add_to_group("darkness_ghosts")
	_power_effect = get_node_or_null("DarknessEntityPowerEffect") as DarknessEntityPowerEffect
	# NavigationAgent3D has avoidance_enabled = true in the scene, but avoidance
	# only takes effect once we feed it a desired velocity via set_velocity()
	# and consume the resolved, collision-avoided result from this signal.
	if not $NavigationAgent3D.velocity_computed.is_connected(_on_navigation_velocity_computed):
		$NavigationAgent3D.velocity_computed.connect(_on_navigation_velocity_computed)
	_set_manifested(false)
	_next_manifest_in = first_manifest_delay


func _process(delta: float) -> void:
	if _is_manifested:
		# Darkness is a persistent hunting ground. It ends only when players
		# have reset every lamp in its zone, not after an arbitrary timer.
		if not _power_effect or not _power_effect.has_active_zone_outage():
			retreat()
			return
		if not _pending_expansion_zone:
			_zone_expansion_in -= delta
			if _zone_expansion_in <= 0.0:
				_begin_expansion_travel()
		return
	if auto_manifest:
		_next_manifest_in -= delta
		if _next_manifest_in <= 0.0:
			manifest()


func _physics_process(delta: float) -> void:
	if not _is_manifested:
		return
	var player := _nearest_player()
	var player_in_dark_zone := _player_is_in_active_zone(player)
	if _pending_expansion_zone:
		# The ghost is still a hunting threat while walking to its next zone: a
		# player standing right next to it in already-dark territory should
		# still register threat/be at risk, not get a free pass just because
		# the ghost's current goal is a waypoint instead of the player.
		if player_in_dark_zone:
			_update_player_threat_and_contact(player)
			if not _is_manifested:
				return
		# The next zone remains lit while the ghost approaches it. It is cut only
		# after the ghost has physically crossed into the target area.
		if global_position.distance_to(_pending_expansion_position) <= zone_blackout_arrival_distance:
			_power_effect.cause_zone_outage(_pending_expansion_zone)
			_pending_expansion_zone = null
			_zone_expansion_in = zone_expansion_seconds
			_patrol_retarget_in = 0.0
			_stuck_timer = 0.0
			return
		_pursue(_pending_expansion_position, zone_expansion_walk_speed, delta, &"expansion")
		return
	var target := player if player_in_dark_zone else null
	if target:
		_pursue(target.global_position, chase_speed, delta, &"chase")
		_update_player_threat_and_contact(target)
	else:
		_clear_player_threat()
		_patrol_retarget_in -= delta
		if _patrol_retarget_in <= 0.0 or global_position.distance_to(_patrol_target) <= stopping_distance:
			_patrol_target = _random_patrol_point()
			_patrol_retarget_in = patrol_retarget_seconds
			_stuck_timer = 0.0
			_stuck_reference_position = global_position
		_pursue(_patrol_target, patrol_speed, delta, &"patrol")


## Public gameplay hook. The first affected zone is the Player's current (or
## nearest) zone, so the ghost never teleports to a random remote wing.
func manifest() -> bool:
	return _manifest_in_zone(_zone_near_player())


## Used by the F1 panel: cut the developer's nearby zone and place the ghost
## a few metres away on valid room floor, ready to be observed immediately.
## Automatic appearances use that same Player-near zone through manifest().
func manifest_for_dev() -> bool:
	if not _manifest_in_zone(_zone_near_player()):
		return false
	global_position = _spawn_near_player()
	return true


func _manifest_in_zone(preferred_zone: ElectricalZone) -> bool:
	if _is_manifested or not _power_effect:
		return false
	var zone := _power_effect.cause_zone_outage(preferred_zone) if preferred_zone \
		else _power_effect.cause_first_available_zone_outage()
	if not zone:
		_next_manifest_in = failed_manifest_retry_delay
		return false
	global_position = _spawn_position_for_zone(zone)
	_set_manifested(true)
	_patrol_target = _random_patrol_point()
	_patrol_retarget_in = patrol_retarget_seconds
	_zone_expansion_in = zone_expansion_seconds
	_pending_expansion_zone = null
	_stuck_timer = 0.0
	_stuck_reference_position = global_position
	_unstick_seconds_left = 0.0
	manifested.emit(zone)
	return true


func retreat() -> void:
	if not _is_manifested:
		return
	_clear_player_threat()
	_set_manifested(false)
	_pending_expansion_zone = null
	_stuck_timer = 0.0
	_unstick_seconds_left = 0.0
	if _power_effect:
		_power_effect.clear_zone_outage()
	_next_manifest_in = manifest_interval
	retreated.emit()


func is_manifested() -> bool:
	return _is_manifested


func _set_manifested(value: bool) -> void:
	_is_manifested = value
	chase_enabled = value
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


func _begin_expansion_travel() -> void:
	if not _power_effect:
		return
	var next_zone := _power_effect.get_next_neighbouring_zone()
	if not next_zone:
		# The current dark territory has no powered neighbour left. Try again
		# later in case the player restores/changes the grid.
		_zone_expansion_in = zone_expansion_seconds
		return
	_pending_expansion_zone = next_zone
	_pending_expansion_position = _spawn_position_for_zone(next_zone)
	# Avoid an immediate repeated call while moving toward the lit zone.
	_zone_expansion_in = 0.0


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


func _recover_from_stuck(target_position: Vector3, context: StringName) -> void:
	match context:
		&"expansion":
			# The next zone's clear point must eventually be reached for the
			# darkness to keep spreading; if pathing to it is physically
			# blocked (closed door, misplaced marker, dynamic obstacle), snap
			# there directly rather than soft-locking expansion forever.
			push_warning("DarknessGhost: stuck walking to next zone (%s), snapping to it." % target_position)
			global_position = target_position
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


func _spawn_position_for_zone(zone: ElectricalZone) -> Vector3:
	var player := _nearest_player()
	var candidates: Array[Vector3] = []
	for marker_node: Node in get_tree().get_nodes_in_group("villa_rooms"):
		var marker := marker_node as Marker3D
		if marker and zone.contains_device_id(StringName(marker.get_meta("room_id", marker.name))):
			candidates.append(marker.get_meta("clear_point", marker.global_position) as Vector3)
	for device: ElectricalDevice in zone.get_devices():
		if device.powered_light:
			candidates.append(device.powered_light.global_position - Vector3.UP * 2.7)
	if candidates.is_empty():
		return global_position
	if not player:
		return candidates[0] + Vector3.UP * 0.05
	# Farthest-from-player first. This guarantees the fallback below (when no
	# candidate clears minimum_spawn_distance, e.g. a small zone) still picks
	# the safest point available instead of whichever happened to be added
	# first to the array.
	candidates.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		return a.distance_to(player.global_position) > b.distance_to(player.global_position)
	)
	for candidate: Vector3 in candidates:
		if candidate.distance_to(player.global_position) >= minimum_spawn_distance:
			return candidate + Vector3.UP * 0.05
	return candidates[0] + Vector3.UP * 0.05


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


func _on_navigation_velocity_computed(safe_velocity: Vector3) -> void:
	if not _is_manifested:
		return
	var delta := _pending_move_delta
	velocity.x = move_toward(velocity.x, safe_velocity.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, safe_velocity.z, acceleration * delta)
	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta
	else:
		velocity.y = 0.0
	move_and_slide()


func _clear_player_threat() -> void:
	for player_node: Node in get_tree().get_nodes_in_group("players"):
		if player_node.has_method("set_threat_from"):
			player_node.call("set_threat_from", &"darkness_ghost", 0.0)


func _zone_near_player() -> ElectricalZone:
	var player := _nearest_player()
	if not player:
		return null
	var closest: ElectricalZone
	var closest_distance := INF
	for marker_node: Node in get_tree().get_nodes_in_group("villa_rooms"):
		var marker := marker_node as Marker3D
		if not marker:
			continue
		var size := marker.get_meta("room_size", Vector3.ZERO) as Vector3
		var offset := player.global_position - marker.global_position
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


func _player_is_in_active_zone(player: Node3D) -> bool:
	if not player or not _power_effect:
		return false
	for marker_node: Node in get_tree().get_nodes_in_group("villa_rooms"):
		var marker := marker_node as Marker3D
		if not marker:
			continue
		var room_id := StringName(marker.get_meta("room_id", marker.name))
		var in_dark_territory := false
		for zone: ElectricalZone in _power_effect.darkened_zones:
			if zone.contains_device_id(room_id):
				in_dark_territory = true
				break
		if not in_dark_territory:
			continue
		var size := marker.get_meta("room_size", Vector3.ZERO) as Vector3
		var offset := player.global_position - marker.global_position
		if absf(offset.x) <= size.x * 0.5 and absf(offset.z) <= size.z * 0.5:
			return true
	return false


func _random_patrol_point() -> Vector3:
	if not _power_effect or _power_effect.darkened_zones.is_empty():
		return global_position
	var candidates: Array[Vector3] = []
	for zone: ElectricalZone in _power_effect.darkened_zones:
		for marker_node: Node in get_tree().get_nodes_in_group("villa_rooms"):
			var marker := marker_node as Marker3D
			if marker and zone.contains_device_id(StringName(marker.get_meta("room_id", marker.name))):
				candidates.append(marker.get_meta("clear_point", marker.global_position) as Vector3)
		for device: ElectricalDevice in zone.get_devices():
			if device.powered_light:
				candidates.append(device.powered_light.global_position - Vector3.UP * 2.7)
	if candidates.is_empty():
		return global_position
	return candidates.pick_random() + Vector3.UP * 0.05


func _spawn_near_player() -> Vector3:
	var player := _nearest_player()
	if not player or not _power_effect or not _power_effect.active_zone:
		return global_position
	# _spawn_position_for_zone() picks a clear authored floor point. Move from
	# the player towards it, but clamp the distance so the dev can see the
	# manifestation without starting inside the kill radius.
	var clear_floor := _spawn_position_for_zone(_power_effect.active_zone)
	var offset := clear_floor - player.global_position
	offset.y = 0.0
	if offset.length_squared() < 0.01:
		offset = player.global_basis.z
		offset.y = 0.0
	if offset.length_squared() < 0.01:
		offset = Vector3(0.0, 0.0, 1.0)
	offset = offset.normalized() * minf(offset.length(), 3.5)
	return Vector3(
		player.global_position.x + offset.x,
		clear_floor.y,
		player.global_position.z + offset.z,
	)
