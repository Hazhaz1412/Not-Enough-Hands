class_name LightSwitch
extends StaticBody3D

## Wall switch that toggles one or more LightSource nodes by switch_id,
## without knowing where they are - it just calls into the
## "light_switch_<id>" group each of them joined.
##
## The lever reads as a normal, faintly neon-green switch under working
## power. During a blackout it glows brighter and turns translucent, like a
## glow-in-the-dark plate - the one time it actually needs to be findable
## without a light on it.

@export var interaction_range: float = 2.0
## One entry per LightSource.switch_id this switch should control.
@export var targets: Array[StringName] = []

@export_category("Glow")
@export var neon_color: Color = Color(0.28, 1.0, 0.45)
@export var idle_emission_energy: float = 0.6
@export var blackout_emission_energy: float = 3.2
@export_range(0.0, 1.0) var blackout_alpha: float = 0.6

var is_on: bool = true

@onready var lever_mesh: MeshInstance3D = get_node_or_null("Lever") as MeshInstance3D

var _lever_material: StandardMaterial3D
var _power_manager: Node


func _ready() -> void:
	add_to_group("light_switches")
	if lever_mesh:
		var base_material := lever_mesh.get_surface_override_material(0) as StandardMaterial3D
		_lever_material = base_material.duplicate() if base_material else StandardMaterial3D.new()
		_lever_material.emission_enabled = true
		lever_mesh.set_surface_override_material(0, _lever_material)

	_power_manager = get_tree().get_first_node_in_group("power_manager")
	if is_instance_valid(_power_manager):
		if _power_manager.has_signal("blackout"):
			_power_manager.connect("blackout", _update_lever)
		if _power_manager.has_signal("power_restored"):
			_power_manager.connect("power_restored", _update_lever)

	_update_lever()


func interact(_player: Node3D = null) -> void:
	is_on = not is_on
	for target_id: StringName in targets:
		if target_id == &"":
			continue
		get_tree().call_group("light_switch_%s" % target_id, "set_light_on", is_on)
	_update_lever()


func get_interaction_prompt(interact_key_name: String) -> String:
	return "[center][b]%s[/b]  CÔNG TẮC ĐÈN[/center]" % interact_key_name


func _is_blacked_out() -> bool:
	return is_instance_valid(_power_manager) and bool(_power_manager.get("is_blackout"))


func _update_lever() -> void:
	if lever_mesh:
		lever_mesh.rotation_degrees.x = -20.0 if is_on else 20.0
	if not _lever_material:
		return

	var blacked_out := _is_blacked_out()
	_lever_material.emission = neon_color
	if blacked_out:
		_lever_material.albedo_color = Color(neon_color.r, neon_color.g, neon_color.b, blackout_alpha)
		_lever_material.emission_energy_multiplier = blackout_emission_energy
		_lever_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	else:
		_lever_material.albedo_color = Color(neon_color.r, neon_color.g, neon_color.b, 1.0)
		_lever_material.emission_energy_multiplier = idle_emission_energy
		_lever_material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
