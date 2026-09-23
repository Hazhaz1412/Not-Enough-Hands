class_name TrapItem
extends PickupItem

## A placed trap is intentionally a world interaction, not a thrown projectile:
## players must spend a second looking at it and holding E before it can save
## them. The server owns every transition and clients receive the compact state.

@export var arm_duration: float = 1.0
@export var trigger_radius: float = 0.9

var is_placed := false
var is_armed := false
var is_spent := false
var arm_progress := 0.0
var _arming_player: Node = null

@onready var visual: MeshInstance3D = $Visual


func _ready() -> void:
	super()
	_update_visual()


func use(player: Node) -> bool:
	if not WorldNet.is_world_authority() or is_placed or is_spent:
		return false
	if player == null or not player.has_method(&"release_held_item"):
		return false
	var position := player.call(&"get_tactical_placement_position") as Vector3
	if not bool(player.call(&"release_held_item", self)):
		return false
	global_position = position
	global_rotation = Vector3.ZERO
	is_placed = true
	freeze = true
	interactable.enabled = true
	interactable.prompt_text = "GIỮ E ĐỂ GÀI BẪY"
	WorldNet.report_entity_state(self)
	return true


func _on_interacted(player: Node) -> void:
	if not is_placed or is_spent:
		super(player)
		return
	if is_armed:
		return
	_arming_player = player


func _process(delta: float) -> void:
	if not WorldNet.is_world_authority() or is_spent:
		return
	if not is_armed:
		_update_arming(delta)
		return
	for node: Node in _tactical_ghosts():
		var ghost := node as Node3D
		if ghost == null or ghost.global_position.distance_to(global_position) > trigger_radius:
			continue
		_trigger(ghost)
		return


func _update_arming(delta: float) -> void:
	if not is_instance_valid(_arming_player) \
		or not _arming_player.has_method(&"is_holding_interact") \
		or not bool(_arming_player.call(&"is_holding_interact")) \
		or not _arming_player.has_method(&"get_interaction_target") \
		or _arming_player.call(&"get_interaction_target") != interactable:
		arm_progress = 0.0
		_arming_player = null
		return
	arm_progress = minf(arm_progress + delta, arm_duration)
	if arm_progress < arm_duration:
		return
	is_armed = true
	arm_progress = arm_duration
	interactable.prompt_text = "BẪY ĐÃ GÀI"
	_update_visual()
	WorldNet.report_entity_state(self)


func _trigger(ghost: Node) -> void:
	# The APIs identify the two ghosts with tactical responses. The Statue has
	# neither and therefore only destroys the trap, exactly as designed.
	var resolved := false
	if ghost.has_method(&"apply_stun"):
		resolved = bool(ghost.call(&"apply_stun", 3.0))
	elif ghost.has_method(&"apply_snare"):
		resolved = bool(ghost.call(&"apply_snare", 1.5))
	else:
		resolved = true
	if resolved:
		_spend()


func _tactical_ghosts() -> Array[Node]:
	var ghosts: Array[Node] = []
	for group: StringName in [&"hostile_ghosts", &"darkness_ghosts"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			if node not in ghosts:
				ghosts.append(node)
	return ghosts


func _spend() -> void:
	if is_spent:
		return
	is_spent = true
	is_armed = false
	interactable.enabled = false
	_update_visual()
	WorldNet.report_entity_state(self)
	queue_free()


func get_replication_state() -> Array:
	return [is_placed, is_armed, is_spent, arm_progress]


func apply_replication_state(state: Array) -> void:
	if state.size() < 4:
		return
	is_placed = bool(state[0])
	is_armed = bool(state[1])
	is_spent = bool(state[2])
	arm_progress = float(state[3])
	interactable.enabled = not is_spent
	interactable.prompt_text = "BẪY ĐÃ GÀI" if is_armed else "GIỮ E ĐỂ GÀI BẪY"
	_update_visual()


func _update_visual() -> void:
	if visual:
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.95, 0.16, 0.08) if is_armed else Color(0.28, 0.28, 0.28)
		material.emission_enabled = is_armed
		material.emission = material.albedo_color
		visual.material_override = material
