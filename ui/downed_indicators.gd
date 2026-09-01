extends Control

## Screen-space rings for downed players: the owner's own bleed-out clock and
## a marker over every downed teammate.
##
## Drawn on the HUD rather than as world geometry because "see the downed
## player through walls" and "no depth test" are the same requirement - a
## CanvasLayer is already in front of the whole 3D frame, so this needs no
## second render pass, no outline material, and nothing on the rig itself.
## Time is only ever shown as a swept arc: no numbers anywhere.

@export var player_path: NodePath
@export var self_ring_radius: float = 46.0
@export var self_ring_width: float = 7.0
@export var teammate_ring_radius: float = 22.0
@export var teammate_ring_width: float = 4.0
## Keeps an off-screen teammate's ring inside the frame so their direction
## still reads while the player looks somewhere else.
@export var screen_edge_margin: float = 56.0

const ARC_SEGMENTS := 48
const TRACK_COLOR := Color(0.06, 0.05, 0.06, 0.72)
const TIME_COLOR := Color(0.9, 0.25, 0.22, 0.95)
const TIME_LOW_COLOR := Color(1.0, 0.62, 0.2, 0.98)
const REVIVE_COLOR := Color(0.42, 0.92, 0.68, 0.95)
const LABEL_COLOR := Color(0.93, 0.86, 0.86, 0.92)

var player: CharacterBody3D
var _revive_key_name: String = "E"


func _ready() -> void:
	if not player_path.is_empty():
		player = get_node_or_null(player_path) as CharacterBody3D
	var events := InputMap.action_get_events("interact")
	if not events.is_empty() and events[0] is InputEventKey:
		var event := events[0] as InputEventKey
		_revive_key_name = OS.get_keycode_string(
			event.physical_keycode if event.physical_keycode != 0 else event.keycode
		)


func _process(_delta: float) -> void:
	# Remote players carry a full copy of this HUD with its layer switched off.
	# Nothing here should cost them a redraw request every frame.
	if not is_visible_in_tree():
		return
	queue_redraw()


func _draw() -> void:
	if not is_instance_valid(player) or not player.has_method("get_downed_time_ratio"):
		return
	if _is_downed(player):
		_draw_own_ring()
	_draw_teammate_rings()


## Object.get() answers null for anything the node does not declare, and
## bool(null) is a runtime error rather than false.
func _is_downed(body: Node) -> bool:
	return "is_downed" in body and bool(body.get("is_downed"))


func _draw_own_ring() -> void:
	var center := Vector2(size.x * 0.5, size.y - self_ring_radius - 96.0)
	_draw_progress_ring(
		center,
		self_ring_radius,
		self_ring_width,
		float(player.call("get_downed_time_ratio")),
		float(player.call("get_revive_ratio"))
	)


func _draw_teammate_rings() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var other := node as CharacterBody3D
		if other == player or not is_instance_valid(other) or not _is_downed(other):
			continue
		if not other.has_method("get_downed_time_ratio"):
			continue
		var marker_position := other.global_position + Vector3.UP * 0.4
		var screen_position := _project_to_screen(camera, marker_position)
		_draw_progress_ring(
			screen_position,
			teammate_ring_radius,
			teammate_ring_width,
			float(other.call("get_downed_time_ratio")),
			float(other.call("get_revive_ratio"))
		)
		if font == null:
			continue
		var caption := str(other.get("display_name"))
		if bool(player.call("can_revive", other)):
			caption += "  [%s]" % _revive_key_name
		var caption_width := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string(
			font,
			screen_position + Vector2(-caption_width * 0.5, teammate_ring_radius + font_size + 4.0),
			caption,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			LABEL_COLOR
		)


## Unprojecting a point behind the camera mirrors it into the frame, so flip it
## deliberately and pin it to the border instead of drawing a ring on the wrong
## side of the screen.
func _project_to_screen(camera: Camera3D, world_position: Vector3) -> Vector2:
	var projected := camera.unproject_position(world_position)
	var center := size * 0.5
	if camera.is_position_behind(world_position):
		projected = center - (projected - center)
	# A marker sitting exactly on the camera plane unprojects to infinity, and
	# clamping propagates that rather than fixing it.
	if not projected.is_finite():
		return center
	return Vector2(
		clampf(projected.x, screen_edge_margin, maxf(size.x - screen_edge_margin, screen_edge_margin)),
		clampf(projected.y, screen_edge_margin, maxf(size.y - screen_edge_margin, screen_edge_margin))
	)


## The outer sweep is the time this player has left; the inner sweep is how far
## a teammate has carried the ten-second rescue.
func _draw_progress_ring(
	center: Vector2,
	radius: float,
	width: float,
	time_ratio: float,
	revive_ratio: float
) -> void:
	draw_arc(center, radius, 0.0, TAU, ARC_SEGMENTS, TRACK_COLOR, width, true)
	var remaining := clampf(time_ratio, 0.0, 1.0)
	if remaining > 0.0:
		draw_arc(
			center,
			radius,
			-PI * 0.5,
			-PI * 0.5 + TAU * remaining,
			ARC_SEGMENTS,
			TIME_LOW_COLOR if remaining < 0.25 else TIME_COLOR,
			width,
			true
		)
	var rescue := clampf(revive_ratio, 0.0, 1.0)
	if rescue > 0.0:
		draw_arc(
			center,
			radius - width * 1.6,
			-PI * 0.5,
			-PI * 0.5 + TAU * rescue,
			ARC_SEGMENTS,
			REVIVE_COLOR,
			width * 0.7,
			true
		)
