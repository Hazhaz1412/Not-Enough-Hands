extends SceneTree


func _init() -> void:
	var villa_scene := load("res://house3/villa_main.tscn") as PackedScene
	_assert(villa_scene != null, "Could not load villa_main.tscn")

	var villa := villa_scene.instantiate()
	var switch_path := "ElectricalFixtures/Floor_00/FoyerLightSwitch"
	var light_switch := villa.get_node_or_null(switch_path)
	_assert(light_switch != null, "FoyerLightSwitch is missing from villa_main")
	_assert(light_switch.get("controlled_device_id") == &"R_FOYER", "Switch must control R_FOYER")
	_assert(light_switch.get_node_or_null("Visual") != null, "Switch model is missing")
	_assert(light_switch.get_node_or_null("CollisionShape3D") != null, "Switch collision is missing")

	print("Villa main switch smoke test passed: %s -> R_FOYER" % switch_path)
	villa.free()
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)
