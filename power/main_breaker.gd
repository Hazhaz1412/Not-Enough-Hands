class_name MainBreaker
extends StaticBody3D

## The single, physical recovery point for a house-wide outage. Room switches
## still repair a DarknessGhost outage one circuit at a time; this cabinet is
## deliberately the exception used after the entire building has gone dark.
##
## Restoring is not instant: while the house is dark the cabinet lights itself
## up as a beacon, and using it opens `BreakerMinigame` - a timed repair that
## only hands power back once its countdown is served. The breaker still owns
## every power decision; the minigame owns none.

signal power_restored

const SERVER_PEER_ID := 1

@export_range(0.5, 10.0, 0.1) var interaction_range := 2.2
@export var restore_all_zones := true

@export_category("Blackout highlight")
## Pulses per second of the outline shell and indicator while the house is
## dark. The cabinet has to be findable from anywhere in an unlit house, so the
## rim throbs instead of sitting at a constant energy that reads as just another
## dim prop.
@export_range(0.1, 4.0, 0.05) var highlight_pulse_speed := 0.85
@export_range(0.0, 8.0, 0.1) var highlight_energy_min := 0.7
@export_range(0.0, 12.0, 0.1) var highlight_energy_max := 3.4
## How solid the glow around the cabinet gets at each end of the pulse.
@export_range(0.0, 1.0, 0.01) var outline_alpha_min := 0.62
@export_range(0.0, 1.0, 0.01) var outline_alpha_max := 1.0
## Rim thickness in metres per metre of camera distance. A fixed metre rim
## shrinks to nothing across a room, so the shell is grown proportionally to
## how far away it is being looked at from - that is what keeps the cabinet
## just as findable from the far end of the house as from arm's reach.
@export_range(0.0, 0.2, 0.001) var outline_thickness_per_metre := 0.02
@export_range(0.01, 1.0, 0.01) var outline_thickness_min := 0.06
@export_range(0.05, 4.0, 0.05) var outline_thickness_max := 1.2

@onready var interactable: Interactable = $Interactable
@onready var indicator: OmniLight3D = get_node_or_null("Indicator") as OmniLight3D
@onready var indicator_mesh: MeshInstance3D = get_node_or_null("IndicatorMesh") as MeshInstance3D
## Grown shell that draws the glowing rim, kept a rim by the stencil buffer
## rather than by depth. The cabinet's own materials stamp reference 1 with
## WRITE|WRITE_DEPTH_FAIL - so they mark their silhouette even when a wall is in
## front - and this shell reads that stencil with NOT_EQUAL, so it only survives
## where the cabinet is not. That is what lets it run with `no_depth_test` (seen
## from anywhere, through anything) and still be a rim instead of a solid slab.
@onready var outline: MeshInstance3D = get_node_or_null("Outline") as MeshInstance3D
@onready var minigame: BreakerMinigame = get_node_or_null("BreakerMinigame") as BreakerMinigame

var _power_manager: PowerManager
var _outline_material: StandardMaterial3D
var _outline_base_size := Vector3.ZERO
var _pulse := 0.0


func _ready() -> void:
	add_to_group("main_breakers")
	if outline:
		_outline_material = outline.material_override as StandardMaterial3D
		var outline_mesh := outline.mesh as BoxMesh
		if outline_mesh:
			_outline_base_size = outline_mesh.size
	interactable.interaction_range = interaction_range
	interactable.interacted.connect(_on_interacted)
	if minigame:
		minigame.repair_completed.connect(_restore_power)
		minigame.session_ended.connect(_on_repair_session_ended)
	_power_manager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if _power_manager:
		_power_manager.blackout.connect(_update_presentation)
		_power_manager.power_restored.connect(_update_presentation)
	# PowerManager only emits blackout/power_restored for a *house-wide* outage.
	# A DarknessGhost darkens one zone at a time, which _needs_repair() counts
	# but neither signal reports - without this the cabinet stays dark and its
	# prompt stale until the last zone happens to go out too.
	_bind_zones.call_deferred()
	_update_presentation()


func _exit_tree() -> void:
	if _power_manager:
		if _power_manager.blackout.is_connected(_update_presentation):
			_power_manager.blackout.disconnect(_update_presentation)
		if _power_manager.power_restored.is_connected(_update_presentation):
			_power_manager.power_restored.disconnect(_update_presentation)
	for node: Node in get_tree().get_nodes_in_group("electrical_zones"):
		var zone := node as ElectricalZone
		if zone and zone.power_changed.is_connected(_on_zone_power_changed):
			zone.power_changed.disconnect(_on_zone_power_changed)


## Deferred so zones authored beside this cabinet have entered the tree (and
## the group) first. Maps without zones - House2 - simply bind nothing.
func _bind_zones() -> void:
	for node: Node in get_tree().get_nodes_in_group("electrical_zones"):
		var zone := node as ElectricalZone
		if zone and not zone.power_changed.is_connected(_on_zone_power_changed):
			zone.power_changed.connect(_on_zone_power_changed)
	_update_presentation()


func _on_zone_power_changed(_is_powered: bool) -> void:
	_update_presentation()


## Only ever processing while the house is dark - _update_presentation() turns
## this off again the moment power is back.
func _process(delta: float) -> void:
	_pulse = fposmod(_pulse + delta * highlight_pulse_speed, 1.0)
	var wave := 0.5 + 0.5 * sin(_pulse * TAU)
	if indicator:
		indicator.light_energy = lerpf(highlight_energy_min, highlight_energy_max, wave)
	if _outline_material:
		_outline_material.albedo_color.a = lerpf(outline_alpha_min, outline_alpha_max, wave)
		_outline_material.emission_energy_multiplier = lerpf(4.0, 10.0, wave)
	_scale_outline_for_distance()


## The shell carries the rim, and the stencil keeps it a rim; this is what
## keeps that rim a usable width no matter how far off the viewer is.
func _scale_outline_for_distance() -> void:
	if not outline or _outline_base_size == Vector3.ZERO:
		return
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return
	var distance := global_position.distance_to(camera.global_position)
	var thickness := clampf(
		distance * outline_thickness_per_metre, outline_thickness_min, outline_thickness_max
	)
	outline.scale = (_outline_base_size + Vector3.ONE * thickness * 2.0) / _outline_base_size


## The interaction no longer restores anything by itself: it hands the player
## the repair minigame, and _restore_power() runs only when that finishes.
func _on_interacted(player: Node) -> void:
	if not _needs_repair() or not minigame:
		return
	if not player or not player.has_method("start_breaker_minigame"):
		return
	if not bool(player.call("start_breaker_minigame", self)):
		return
	interactable.lock()


func _restore_power() -> void:
	# There is one reserve for the house. A client that served the countdown has
	# nothing to restore locally - it reports the outcome from
	# _on_repair_session_ended() and takes the lights back through
	# PowerManager.apply_network_state() a fraction of a second later.
	if not WorldNet.is_world_authority():
		return
	# Zone blackouts keep PowerManager's global outage reason active. Reset
	# those circuits first, then restore the reserve/manual blackout state.
	if restore_all_zones:
		for node: Node in get_tree().get_nodes_in_group("electrical_zones"):
			var zone := node as ElectricalZone
			if zone and (not zone.is_powered or zone.requires_switch_restore):
				zone.set_powered(true)
	if _power_manager:
		_power_manager.restore_power()
	if minigame:
		minigame.reset_progress()
	power_restored.emit()
	_update_presentation()


## Both outcomes land here. A cancelled repair keeps the seconds it already
## served (BreakerMinigame owns that), so this only has to reopen the cabinet.
func _on_repair_session_ended(success: bool) -> void:
	# Played on a client, finished on a client - but the cabinet the server
	# locked when it handed the repair out is the one that has to be reopened,
	# or nobody could ever use this breaker again.
	if not WorldNet.is_world_authority():
		_report_repair_session.rpc_id(SERVER_PEER_ID, success)
		return
	interactable.unlock()
	_update_presentation()


## The outcome of a repair played on somebody else's machine. Honoured only
## while this cabinet is still locked, which is the server's own record that it
## handed a repair out - so a report cannot arrive out of nowhere.
@rpc("any_peer", "call_remote", "reliable")
func _report_repair_session(success: bool) -> void:
	if not WorldNet.is_world_authority() or interactable.can_interact():
		return
	if success:
		_restore_power()
	interactable.unlock()
	_update_presentation()


func _needs_repair() -> bool:
	if _power_manager and _power_manager.is_blackout:
		return true
	for node: Node in get_tree().get_nodes_in_group("electrical_zones"):
		var zone := node as ElectricalZone
		if zone and not zone.is_powered:
			return true
	return false


func _update_presentation() -> void:
	if not is_instance_valid(interactable):
		return
	var needs_repair := _needs_repair()
	if needs_repair:
		var seconds: float = minigame.get_repair_remaining() if minigame else 0.0
		interactable.prompt_text = "SỬA CẦU DAO TỔNG (%.0f GIÂY)" % ceilf(seconds)
	else:
		interactable.prompt_text = "CẦU DAO ĐANG ỔN ĐỊNH"
	if indicator:
		indicator.light_color = Color(0.98, 0.18, 0.08) if needs_repair else Color(0.18, 0.95, 0.38)
		indicator.visible = true
		if not needs_repair:
			indicator.light_energy = 1.3
	if indicator_mesh:
		var material := indicator_mesh.material_override as StandardMaterial3D
		if material:
			material.albedo_color = (
				Color(0.98, 0.18, 0.08) if needs_repair else Color(0.18, 0.95, 0.38)
			)
			material.emission = material.albedo_color
	if outline:
		outline.visible = needs_repair
	set_process(needs_repair)
