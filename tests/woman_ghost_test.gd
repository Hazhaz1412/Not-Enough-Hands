extends Node3D

## Test-only movement. The Idle/Walk controller lives in woman_ghost.tscn.
@export var patrol_radius := 3.2
@export var walk_speed := 1.15

@onready var _ghost: WomanGhost = $WomanGhost

var _angle := 0.0
var _last_position := Vector3.ZERO

func _ready() -> void:
	_last_position = _ghost.global_position

func _process(delta: float) -> void:
	if not _ghost.is_walking():
		return
	_angle = fmod(_angle + delta * walk_speed / patrol_radius, TAU)
	_ghost.global_position = Vector3(cos(_angle) * patrol_radius, 0.08, sin(_angle) * patrol_radius)
	var travel := _ghost.global_position - _last_position
	travel.y = 0.0
	if travel.length_squared() > 0.0001:
		_ghost.look_at(_ghost.global_position + travel, Vector3.UP, true)
	_last_position = _ghost.global_position

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		_ghost.set_walking(not _ghost.is_walking())
		get_viewport().set_input_as_handled()
