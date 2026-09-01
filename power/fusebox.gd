class_name Fusebox
extends StaticBody3D

## Physical repair point for a PowerManager blackout. Interacting while the
## house has no power hands control to FuseboxMinigame; interacting while
## power is fine is a no-op. The indicator light is purely cosmetic feedback
## for "is there a reason to come over here".

signal repair_started(fusebox: Node)
signal repair_completed(fusebox: Node)
signal repair_failed(fusebox: Node)

@export var interaction_range: float = 2.2
@export var powered_color: Color = Color(0.2, 0.85, 0.35)
@export var blackout_color: Color = Color(0.85, 0.15, 0.1)

var repairing: bool = false
var _power_manager: Node
var _indicator_material: StandardMaterial3D

@onready var indicator_mesh: MeshInstance3D = get_node_or_null("Indicator") as MeshInstance3D
@onready var indicator_light: OmniLight3D = get_node_or_null("IndicatorLight") as OmniLight3D


func _ready() -> void:
	add_to_group("fuseboxes")
	_power_manager = get_tree().get_first_node_in_group("power_manager")
	if indicator_mesh:
		# Sub-resources embedded in a .tscn are shared across every instance of
		# it until duplicated - without this, two fuseboxes in one scene would
		# flip the same material and always show the same colour.
		var base_material := indicator_mesh.get_surface_override_material(0) as StandardMaterial3D
		_indicator_material = base_material.duplicate() if base_material else StandardMaterial3D.new()
		indicator_mesh.set_surface_override_material(0, _indicator_material)
	_update_indicator()


func _process(_delta: float) -> void:
	_update_indicator()


func interact(player: Node3D = null) -> void:
	if repairing or not _is_blackout():
		return
	if player and player.has_method("start_fusebox_minigame"):
		player.call("start_fusebox_minigame", self)


func get_interaction_prompt(interact_key_name: String) -> String:
	if repairing:
		return "[center][color=#b9d7e8]ĐANG SỬA CẦU CHÌ...[/color][/center]"
	if _is_blackout():
		return "[center][b]%s[/b]  SỬA CẦU CHÌ — MẤT ĐIỆN[/center]" % interact_key_name
	return "[center]HỘP CẦU CHÌ — ĐIỆN ỔN ĐỊNH[/center]"


## Minigame contract, mirrors DefenseDoor's begin/cancel/complete/fail shape
## so both minigames plug into the player the same way.
func begin_repair() -> bool:
	if repairing or not _is_blackout():
		return false
	repairing = true
	repair_started.emit(self)
	return true


func cancel_repair() -> void:
	repairing = false


func complete_repair() -> bool:
	if not repairing:
		return false
	repairing = false
	if is_instance_valid(_power_manager) and _power_manager.has_method("restore_power"):
		_power_manager.call("restore_power")
	repair_completed.emit(self)
	return true


func apply_repair_failure() -> void:
	if not repairing:
		return
	repairing = false
	repair_failed.emit(self)


func _is_blackout() -> bool:
	return is_instance_valid(_power_manager) and bool(_power_manager.get("is_blackout"))


func _update_indicator() -> void:
	var color := blackout_color if _is_blackout() else powered_color
	if _indicator_material:
		_indicator_material.albedo_color = color
		_indicator_material.emission = color
	if indicator_light:
		indicator_light.light_color = color
