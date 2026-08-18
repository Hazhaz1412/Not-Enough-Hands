extends Resource
class_name ItemData

@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D = null
@export var max_stack: int = 1
@export var held_scene: PackedScene = null
