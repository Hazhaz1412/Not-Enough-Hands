extends Node3D

## Presentation-only body for a player. Gameplay stays on Player so this scene
## can be hidden from the owning first-person camera and replicated later
## without making the imported Kenney rig part of the movement controller.

const IDLE_SCENE: PackedScene = preload("res://assets/player/Animations/idle.fbx")
const RUN_SCENE: PackedScene = preload("res://assets/player/Animations/run.fbx")
const JUMP_SCENE: PackedScene = preload("res://assets/player/Animations/jump.fbx")

## Visual layer reserved for the owning player's own rig. Their flashlight
## drops this layer from its cull mask so the body it is standing inside
## cannot shadow the whole view. Nothing else uses layer 20.
const LOCAL_BODY_VISUAL_LAYER := 20

@export var skin: Texture2D
@export var model_scale: float = 0.46
## Kenney's character faces +Z, while Godot gameplay/camera forward is -Z.
## Keep this correction on the presentation rig so movement and flashlight
## transforms remain authoritative and unchanged.
@export var model_forward_yaw_degrees: float = 180.0
@export_range(0.4, 1.0) var crouch_height_ratio: float = 0.64
@export var crouch_visual_speed: float = 8.0
@export var show_local_body: bool = false
## Lobby previews reuse this exact rig without instancing the full gameplay
## Player (camera, collision, HUD, equipment, etc.).
@export var lobby_preview: bool = false
@export var preview_display_name: String = "Player"
@export var preview_ready: bool = false
@export var preview_slot_index: int = 0
## Capsules only hold two players 64 cm apart, but this rig's shoulders are
## much wider than that - and a jump puts one camera at another body's head
## height. Inside this radius the rig stops rendering, so a camera can never
## end up looking at the inside of a torso.
@export var camera_clear_distance: float = 0.95
@export var downed_pose_speed: float = 3.5

@onready var character: Node3D = $Character
@onready var body_mesh: MeshInstance3D = $Character/Root/Skeleton3D/characterMedium
@onready var name_tag: Label3D = $NameTag

var _animation_player: AnimationPlayer
var _current_animation: StringName = &""
var _player: CharacterBody3D
var _rig_geometry: Array[GeometryInstance3D] = []
var _is_local_rig: bool = true
var _rig_hidden: bool = true
var _spectating: bool = false
var _downed_pose: float = 0.0
var _preview_time: float = 0.0
var _preview_state_tag: Label3D


func _ready() -> void:
	_player = get_parent() as CharacterBody3D
	_apply_skin()
	_build_animation_player()
	_align_to_player_capsule()
	_collect_rig_geometry()
	if lobby_preview:
		_setup_lobby_preview()
	else:
		_update_local_render_mode()
	_update_name_tag()
	_play_animation(&"idle")
	if lobby_preview and _animation_player:
		_animation_player.speed_scale = 0.92 + float(preview_slot_index) * 0.035
		var idle := _animation_player.get_animation(&"idle")
		if idle and idle.length > 0.0:
			_animation_player.seek(fmod(float(preview_slot_index) * 0.73, idle.length), true)


func _physics_process(delta: float) -> void:
	if lobby_preview:
		_update_lobby_preview(delta)
		return
	if not is_instance_valid(_player):
		return
	_update_crouch_visual(delta)
	_update_downed_pose(delta)
	_update_locomotion_animation()
	_update_render_mode()


func configure_lobby_preview(
	player_name: String,
	player_skin: Texture2D,
	is_ready: bool,
	slot_index: int
) -> void:
	lobby_preview = true
	preview_display_name = player_name
	preview_ready = is_ready
	preview_slot_index = slot_index
	skin = player_skin


func _setup_lobby_preview() -> void:
	_is_local_rig = false
	_rig_hidden = false
	_spectating = false
	_apply_rig_render_mode()
	_preview_time = float(preview_slot_index) * 1.37
	if not name_tag:
		return
	# Keep long user-entered names inside their own slot when all four players
	# are present. Short names retain the large lobby type.
	name_tag.font_size = clampi(
		int(280.0 / float(maxi(preview_display_name.length(), 1))),
		14,
		34
	)
	name_tag.outline_size = 8
	_preview_state_tag = name_tag.duplicate() as Label3D
	_preview_state_tag.name = "ReadyTag"
	_preview_state_tag.position.y += 0.7
	_preview_state_tag.font_size = 20
	_preview_state_tag.outline_size = 6
	_preview_state_tag.text = "READY" if preview_ready else "NOT READY"
	_preview_state_tag.modulate = (
		Color(0.38, 1.0, 0.56) if preview_ready else Color(1.0, 0.3, 0.2)
	)
	add_child(_preview_state_tag)


## The imported idle animation moves the whole skeleton. A very small,
## differently phased weight shift keeps a four-person lineup from looking
## synchronised or mannequin-stiff without affecting the gameplay rig.
func _update_lobby_preview(delta: float) -> void:
	_preview_time += delta
	var base_yaw := deg_to_rad(model_forward_yaw_degrees)
	character.rotation.y = base_yaw + sin(_preview_time * 0.55) * deg_to_rad(1.8)


func _apply_skin() -> void:
	if not body_mesh or not skin:
		return
	var material := StandardMaterial3D.new()
	material.albedo_texture = skin
	material.roughness = 0.9
	body_mesh.set_surface_override_material(0, material)


func _build_animation_player() -> void:
	_animation_player = AnimationPlayer.new()
	_animation_player.name = "CharacterAnimationPlayer"
	# The source FBX animation tracks target Root/Skeleton3D. Parenting the
	# player beside that Root preserves those paths without rewriting 40 tracks.
	character.add_child(_animation_player)

	var library := AnimationLibrary.new()
	_add_animation(library, IDLE_SCENE, &"Root|Idle", &"idle", true)
	_add_animation(library, RUN_SCENE, &"Root|Run", &"run", true)
	_add_animation(library, JUMP_SCENE, &"Root|Jump", &"jump", false)
	_animation_player.add_animation_library(&"", library)


func _add_animation(
	library: AnimationLibrary,
	source_scene: PackedScene,
	source_name: StringName,
	target_name: StringName,
	loop: bool
) -> void:
	var source_root := source_scene.instantiate()
	var source_player := source_root.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if source_player and source_player.has_animation(source_name):
		var animation := source_player.get_animation(source_name).duplicate(true) as Animation
		animation.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
		library.add_animation(target_name, animation)
	source_root.free()


func _align_to_player_capsule() -> void:
	var standing_height := 1.75
	if is_instance_valid(_player) and "standing_height" in _player:
		standing_height = _player.standing_height
	position.y = -standing_height * 0.5
	scale = Vector3.ONE * model_scale
	character.rotation.y = deg_to_rad(model_forward_yaw_degrees)


## The Kenney import is a single skinned mesh today, but the render decisions
## below are about "this player's whole body", not about one node name -
## collect every drawable once so an added prop cannot leak into the view.
func _collect_rig_geometry() -> void:
	_rig_geometry.clear()
	for node: Node in character.find_children("*", "GeometryInstance3D", true, false):
		_rig_geometry.append(node as GeometryInstance3D)
	if body_mesh and not _rig_geometry.has(body_mesh):
		_rig_geometry.append(body_mesh)


func _update_local_render_mode() -> void:
	if not is_instance_valid(_player):
		return
	_is_local_rig = (
		bool(_player.call("is_local_player"))
		if _player.has_method("is_local_player")
		else _player.is_multiplayer_authority()
	)
	if _is_local_rig and not show_local_body:
		# The owner's flashlight sits inside this body. Moving the rig onto its
		# own visual layer and dropping that layer from the beam is what keeps
		# a jump from smearing the player's own silhouette across the room.
		for geometry: GeometryInstance3D in _rig_geometry:
			geometry.layers |= 1 << (LOCAL_BODY_VISUAL_LAYER - 1)
		var flashlight := _player.get_node_or_null(
			"CameraPivot/Camera3D/Flashlight"
		) as SpotLight3D
		if flashlight:
			flashlight.light_cull_mask &= ~(1 << (LOCAL_BODY_VISUAL_LAYER - 1))
	_rig_hidden = not _should_render_rig()
	_spectating = _player_flag("is_spectator")
	_apply_rig_render_mode()


func _update_render_mode() -> void:
	var should_hide := not _should_render_rig()
	var spectating := _player_flag("is_spectator")
	if should_hide == _rig_hidden and spectating == _spectating:
		return
	_rig_hidden = should_hide
	_spectating = spectating
	_apply_rig_render_mode()


func _should_render_rig() -> bool:
	if _is_local_rig and not show_local_body:
		return false
	return not _is_camera_inside_body()


## Same guarded read as the existing `"is_crouching" in _player` checks:
## Object.get() answers null for anything this parent does not declare, and
## bool(null) is a runtime error rather than false.
func _player_flag(property: String) -> bool:
	return property in _player and bool(_player.get(property))


func _apply_rig_render_mode() -> void:
	var spectating := _spectating
	character.visible = not spectating
	var cast_mode := (
		GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		if _rig_hidden
		else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	)
	for geometry: GeometryInstance3D in _rig_geometry:
		geometry.cast_shadow = cast_mode
	if name_tag:
		name_tag.visible = not _is_local_rig and not _rig_hidden and not spectating


## Distance is measured to the capsule's axis rather than to this node, whose
## origin sits at the feet: a camera at head height is a metre from the feet
## while already being inside the chest.
func _is_camera_inside_body() -> bool:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return false
	var radius := 0.32
	var height := 1.75
	if "player_radius" in _player:
		radius = _player.player_radius
	if "standing_height" in _player:
		height = _player.standing_height
	var half_segment := maxf(height * 0.5 - radius, 0.01)
	var offset := camera.global_position - _player.global_position
	var closest := (
		_player.global_position
		+ Vector3.UP * clampf(offset.y, -half_segment, half_segment)
	)
	return camera.global_position.distance_to(closest) < camera_clear_distance


func _update_name_tag() -> void:
	if not name_tag:
		return
	if lobby_preview:
		name_tag.text = preview_display_name
		name_tag.visible = true
		return
	if not is_instance_valid(_player):
		return
	name_tag.text = str(_player.get("display_name"))
	name_tag.visible = not _is_local_rig and not _rig_hidden


func _update_crouch_visual(delta: float) -> void:
	var is_crouching: bool = "is_crouching" in _player and bool(_player.is_crouching)
	var target_y_scale := model_scale * (crouch_height_ratio if is_crouching else 1.0)
	scale.x = model_scale
	scale.y = move_toward(scale.y, target_y_scale, crouch_visual_speed * model_scale * delta)
	scale.z = model_scale


## No downed animation ships with the Kenney pack, so the rig is tipped onto
## its back around its own feet. The small lift keeps the lying body above the
## floor plane instead of half inside it.
func _update_downed_pose(delta: float) -> void:
	var target := 1.0 if _player_flag("is_downed") else 0.0
	if is_equal_approx(_downed_pose, target):
		return
	_downed_pose = move_toward(_downed_pose, target, downed_pose_speed * delta)
	character.rotation.x = -_downed_pose * PI * 0.5
	character.position.y = _downed_pose * 0.35


func _update_locomotion_animation() -> void:
	if not _animation_player:
		return
	if _player_flag("is_downed"):
		_play_animation(&"idle")
		return
	var horizontal_speed := Vector2(_player.velocity.x, _player.velocity.z).length()
	if not _player.is_on_floor() and absf(_player.velocity.y) > 0.1:
		_play_animation(&"jump")
		return
	if horizontal_speed > 0.18:
		_play_animation(&"run")
		var walk_speed := 4.0
		if "walk_speed" in _player:
			walk_speed = maxf(_player.walk_speed, 0.1)
		_animation_player.speed_scale = clampf(horizontal_speed / walk_speed, 0.65, 1.3)
		return
	_play_animation(&"idle")


func _play_animation(animation_name: StringName) -> void:
	if not _animation_player or not _animation_player.has_animation(animation_name):
		return
	if _current_animation == animation_name and _animation_player.is_playing():
		return
	_current_animation = animation_name
	_animation_player.speed_scale = 1.0
	_animation_player.play(animation_name, 0.15)
