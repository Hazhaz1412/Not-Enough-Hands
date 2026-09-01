class_name LightSource
extends Node3D

## Drop-in light for any furniture prop. A lamp/stand light sets
## `directly_toggleable = true` so the player can flip it by interacting with
## it directly; a ceiling light sets that `false` and gives it a `switch_id`
## so a LightSwitch elsewhere in the room controls it instead. Both can be
## combined (a lamp with its own pull-chain that a master switch also hits).
##
## Wiring to a switch is group-based, the same idiom as defense_doors /
## crawler_ghosts / power_manager elsewhere in this project - no NodePath
## needed between the switch and the lights it controls.

signal toggled(is_on: bool)

@export var start_on: bool = true
@export var directly_toggleable: bool = true
@export var interaction_range: float = 2.0
## Non-empty joins the "light_switch_<id>" group - see LightSwitch.targets.
@export var switch_id: StringName = &""
## A blackout forces the light dark regardless of its own on/off state, and
## it returns to exactly that state once power comes back. Turn this off for
## something that should not care about house power (a candle, a prop meant
## to read as battery-powered).
@export var affected_by_blackout: bool = true

var is_on: bool = true

@onready var light: Light3D = get_node_or_null("Light") as Light3D
@onready var bulb_mesh: MeshInstance3D = get_node_or_null("Bulb") as MeshInstance3D

var _power_manager: Node
var _bulb_material: StandardMaterial3D
var _bulb_base_emission: Color = Color.WHITE


func _ready() -> void:
	add_to_group("light_sources")
	if switch_id != &"":
		add_to_group("light_switch_%s" % switch_id)

	if bulb_mesh:
		# Sub-resources embedded in a .tscn are shared across every instance
		# until duplicated - without this, every lamp using this scene would
		# flip the same material and always show the same on/off state.
		var base_material := bulb_mesh.get_surface_override_material(0) as StandardMaterial3D
		_bulb_material = base_material.duplicate() if base_material else StandardMaterial3D.new()
		bulb_mesh.set_surface_override_material(0, _bulb_material)
		_bulb_base_emission = _bulb_material.emission

	is_on = start_on

	if affected_by_blackout:
		_power_manager = get_tree().get_first_node_in_group("power_manager")
		if is_instance_valid(_power_manager):
			if _power_manager.has_signal("blackout"):
				_power_manager.connect("blackout", _on_power_state_changed)
			if _power_manager.has_signal("power_restored"):
				_power_manager.connect("power_restored", _on_power_state_changed)

	_apply_state()


func interact(_player: Node3D = null) -> void:
	if not directly_toggleable:
		return
	set_light_on(not is_on)


func get_interaction_prompt(interact_key_name: String) -> String:
	if not directly_toggleable:
		return ""
	return "[center][b]%s[/b]  %s ĐÈN[/center]" % [interact_key_name, "TẮT" if is_on else "BẬT"]


## Called directly (lamp interact) or by a LightSwitch via call_group -
## either way this is the single place state actually changes.
func set_light_on(value: bool) -> void:
	if is_on == value:
		return
	is_on = value
	_apply_state()
	toggled.emit(is_on)


func toggle() -> void:
	set_light_on(not is_on)


func _on_power_state_changed() -> void:
	_apply_state()


func _is_blacked_out() -> bool:
	return affected_by_blackout \
		and is_instance_valid(_power_manager) \
		and bool(_power_manager.get("is_blackout"))


func _apply_state() -> void:
	var lit := is_on and not _is_blacked_out()
	if light:
		light.visible = lit
	if _bulb_material:
		_bulb_material.emission_enabled = lit
		_bulb_material.emission = _bulb_base_emission if lit else Color.BLACK
