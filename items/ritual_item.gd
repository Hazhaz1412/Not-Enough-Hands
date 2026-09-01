class_name RitualItem
extends PickupItem

## A pickup that is part of the totem-burning objective: the totems the player
## has to find, and the firewood that relights the brazier between burns.
##
## Two things separate it from a plain PickupItem. It declares `slot_cost`, so
## PlayerEquipment can reserve *both* hands for a totem - carrying one means
## carrying nothing else, which is what forces the trip back for firewood to be
## a second trip. And it lights itself up only while the active camera can
## really see it: inside the frustum, within range, and with nothing solid in
## between. The glow is a "there it is" hint, never an x-ray through a wall.

## Hands this item occupies while carried. PlayerEquipment reads it; anything
## that does not declare one is a normal single-slot pickup.
@export_range(1, 2, 1) var slot_cost: int = 1

@export_category("Seen highlight")
@export var highlight_enabled: bool = true
@export var highlight_color: Color = Color(1.0, 0.62, 0.22)
## Beyond this the item stops glowing even in plain sight, so a totem two rooms
## away is a reward for looking rather than a map marker.
@export_range(1.0, 60.0, 0.5) var highlight_max_distance: float = 22.0
@export_range(0.1, 4.0, 0.05) var highlight_pulse_speed: float = 0.7
@export_range(0.0, 1.0, 0.01) var highlight_alpha_max: float = 0.55
@export_range(0.0, 8.0, 0.1) var highlight_light_energy: float = 1.6
## Seconds between line-of-sight probes. The check is a frustum test plus one
## raycast, cheap, but there is no reason to pay for it every frame.
@export_range(0.02, 1.0, 0.01) var highlight_probe_interval: float = 0.12
@export_range(0.05, 2.0, 0.05) var highlight_fade_seconds: float = 0.25
## Probed at this height above the item's origin, so a totem on the floor is
## still tested against the part of it a standing player actually sees.
@export_range(0.0, 2.0, 0.05) var highlight_probe_height: float = 0.35

@onready var glow: OmniLight3D = get_node_or_null("Glow") as OmniLight3D

var _held: bool = false
var _seen: bool = false
var _seen_blend: float = 0.0
var _probe_timer: float = 0.0
var _pulse: float = 0.0
var _overlays: Array[StandardMaterial3D] = []


func _ready() -> void:
	super()
	_build_highlight_overlays()
	_apply_highlight(0.0)


func _process(delta: float) -> void:
	if not highlight_enabled:
		return
	_probe_timer -= delta
	if _probe_timer <= 0.0:
		_probe_timer = highlight_probe_interval
		_seen = not _held and visible and is_seen_by_camera()
	_seen_blend = move_toward(
		_seen_blend, 1.0 if _seen else 0.0, delta / maxf(highlight_fade_seconds, 0.01)
	)
	_pulse += delta * highlight_pulse_speed
	_apply_highlight(_seen_blend * (0.55 + 0.45 * sin(_pulse * TAU)))


func set_held(held: bool) -> void:
	super(held)
	_held = held
	if held:
		_seen = false
		_seen_blend = 0.0
		_apply_highlight(0.0)


## Frustum + range + line of sight, in that order: the two cheap rejections
## before the raycast. The ray is masked to world geometry only and skips this
## item's own body, so the only thing that can hide a totem is a wall. Public
## because it is the whole rule the highlight exists to obey, and the smoke
## test checks it directly.
func is_seen_by_camera() -> bool:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null:
		return false
	var point := global_position + Vector3(0.0, highlight_probe_height, 0.0)
	if camera.global_position.distance_to(point) > highlight_max_distance:
		return false
	if not camera.is_position_in_frustum(point):
		return false
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, point)
	query.collision_mask = 1
	query.exclude = [get_rid()]
	var viewer := camera.get_parent()
	while viewer:
		if viewer is CollisionObject3D:
			query.exclude.append((viewer as CollisionObject3D).get_rid())
			break
		viewer = viewer.get_parent()
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## An additive unshaded overlay per surface rather than a material_override:
## the imported model keeps its own colours and only gains the glow on top.
func _build_highlight_overlays() -> void:
	for node: Node in find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		var overlay := StandardMaterial3D.new()
		overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		overlay.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		overlay.albedo_color = Color(highlight_color, 0.0)
		mesh_instance.material_overlay = overlay
		_overlays.append(overlay)


func _apply_highlight(level: float) -> void:
	var clamped := clampf(level, 0.0, 1.0)
	for overlay: StandardMaterial3D in _overlays:
		overlay.albedo_color = Color(highlight_color, clamped * highlight_alpha_max)
	if glow:
		glow.visible = clamped > 0.01
		glow.light_energy = clamped * highlight_light_energy
