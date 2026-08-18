extends SceneTree
func _init():
    var test_scene = load("res://tests/player_test.tscn").instantiate()
    root.add_child(test_scene)
    var ui = test_scene.get_node("CanvasLayer/CarrySlotsUI")
    print("UI is ", ui)
    print("Player path: ", ui.player_path)
    var player = ui.get_node_or_null(ui.player_path)
    print("Player is ", player)
    quit()
