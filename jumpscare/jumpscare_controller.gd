class_name JumpscareController
extends Node

## Presentation-only jumpscare: the ghost that caught the player flies into the
## camera and fills the screen with its real in-game face.
##
## It owns no ghost, no AI and no death logic. Something else decides a ghost has
## been defeated - or has landed a kill - and calls play_jumpscare(); this
## replies with a signal when the sequence is over and touches nothing in
## between except the player's input lock, which it restores exactly as it found
## it. player.gd is the only gameplay caller, from a ghost's lethal hit or a
## catch that puts the player into the co-op downed state.
##
## The visual sits on canvas layer 140, above ui/death_screen.gd on 130, and
## both this node and it run with PROCESS_MODE_ALWAYS. The Huntsman's kill
## freezes the world for the length of the sequence - whatever killed the player
## must not still be walking around behind the face - and a sequence that paused
## with it would freeze on its first frame.
##
## ## Why it is not the ghost that is already in the world
##
## Hunter keeps the dedicated ghosts/ghost_visual.tscn copy authored in
## jumpscare_visual.tscn. Every other killer duplicates only its presentation
## subtree (or extracts that same subtree from its PackedScene as a fallback)
## inside a SubViewport with its own World3D. The player therefore sees the
## Statue, Crawler or Darkness model that actually caught them, while no ghost
## AI, collision, navmesh or world transform enters the jumpscare world.
## minigames/toilet_ghost_caught.tscn already does exactly this for the toilet
## death beat; this is the same arrangement pointed at the biped.
##
## ## Why the face lands where it lands
##
## `ModelRoot` carries a half turn, so the body faces back down the camera axis
## instead of away along it, and `_track_face()` then slides the body every
## frame so that the face itself sits exactly on `GhostAnchor`'s origin. The
## face point is read off the rig - eye level is halfway between the `Head` and
## `head_end` bones, and the face surface is where `headfront` is - so it
## follows the head wherever the animation puts it.
##
## That tracking is not a nicety. At 0.25 m from the lens the run cycle's few
## centimetres of head bob is the difference between the whole face and a pair
## of eyes, and no fixed offset can absorb it. With it, sliding and scaling the
## anchor can only ever make the same face bigger: never swing it off-screen,
## never turn it away.
##
## `impact_distance` is therefore just how far the face ends up from the lens.
## At 0.25 m the scene's 55-degree camera sees 0.26 m of height, and jaw to
## hairline is 0.23 m of it: the face covers around six sevenths of the screen
## with the crown and the jaw already past its edges, and the grin is still
## whole inside it, which is the point. The lens is 55 and not the 70 a
## first-person game would use because at this range the wider one bends the
## face into a nose - the whole reason for the shot is that the face stays
## recognisable. `tests/jumpscare_smoke.gd` unprojects real points on that face
## through the real camera, so the framing cannot silently drift.

signal jumpscare_finished

const VISUAL_SCENE := preload("res://jumpscare/jumpscare_visual.tscn")
const STATUE_SCENE := preload("res://ghosts/statue_ghost.tscn")
const CRAWLER_SCENE := preload("res://ghosts/crawler_ghost.tscn")
const DARKNESS_SCENE := preload("res://ghosts/darkness_ghost.tscn")
const STATUE_STING := preload("res://assets/audio/statue_spotted_jumpscare.mp3")
const CRAWLER_STING := preload("res://assets/audio/crawler_scream.ogg")
const DARKNESS_STING := preload("res://assets/audio/minigame/door_minigame_jumpscare.mp3")
## The one clip that keeps the face pointed at the camera. Measured across the
## whole library: Run holds the head within 1.7 cm of the centreline and 2.8
## degrees of straight ahead, where Idle wanders 9.9 cm / 22 degrees and the two
## attack clips throw it 27.8 cm and 79 degrees aside. A charge is also what
## this beat is, so the safe clip is the right clip.
const CHARGE_CLIP := &"Run"

@export_category("Timing")
## Beat between the trigger and the launch. The still frame is what makes the
## launch read as sudden.
@export var pre_delay: float = 0.16
## The flight itself.
@export var lunge_duration: float = 0.56
## How long the finished close-up is held before the overlay is dropped.
@export var hold_duration: float = 0.3

@export_category("Framing")
## Metres from the camera to the face at each end of the flight. The far one
## shows the whole body; the near one is the number the close-up is built on -
## see the class doc.
@export var start_distance: float = 3.4
@export var impact_distance: float = 0.25
@export var impact_scale: float = 1.3
## Shape of the flight: Godot's in-out easing, so it hangs for an instant, rushes
## and arrives without overshooting the face out of frame.
@export var lunge_easing: float = -1.9
## Roll on the way in, in degrees. Roll and not yaw or drift, because roll is the
## one rotation that cannot move the face off the camera axis.
@export var roll_degrees: float = 5.0

@export_category("Effects")
## Blood starts a quarter of the way in and is at full flow on impact.
@export_range(0.0, 1.0, 0.01) var blood_start_fraction: float = 0.25
## Kept low and short on purpose: a flash that hides the face defeats the shot.
@export_range(0.0, 1.0, 0.01) var flash_peak: float = 0.28
@export var flash_fade: float = 0.1
@export_range(0.0, 0.5, 0.01) var tint_peak: float = 0.12
## Metres of camera shake at impact, and how fast it dies away.
@export var shake_amplitude: float = 0.012
@export var shake_duration: float = 0.24
@export var shake_frequency: float = 34.0

var _visual: CanvasLayer
var _camera: Camera3D
var _anchor: Node3D
var _ghost: GhostVisual
var _killer_model: Node3D
var _model_root: Node3D
var _skeleton: Skeleton3D
## Rig points the framing is pinned to: eye level is halfway between the head
## joint and the crown, and the face surface is where the front marker is.
var _head_bone: int = -1
var _crown_bone: int = -1
var _front_bone: int = -1
var _generic_head: Node3D
var _generic_head_point := Vector3.ZERO
var _generic_head_bone: int = -1
var _generic_crown_bone: int = -1
var _generic_front_bone: int = -1
var _killer_variant: StringName = &"hunter"
var _model_source: String = "res://ghosts/ghost_visual.tscn"
var _variant_tint_peak: float = 0.12
var _darkness_eyes: Array[MeshInstance3D] = []
var _blood: ShaderMaterial
var _flash: ColorRect
var _tint: ColorRect
var _sting: AudioStreamPlayer
var _elapsed: float = 0.0
var _playing: bool = false
var _player: Node
var _saved_physics_process: bool = false
var _saved_unhandled_input: bool = false


func _ready() -> void:
	set_process(false)


## The whole API. `player` is optional and only used to hold input still for the
## length of the sequence; pass null and the jumpscare is pure picture. `killer`
## selects the identity shown by the shot. Omitting it preserves the original
## Hunter preview/tool behaviour.
func play_jumpscare(player: Node = null, killer: Node3D = null) -> bool:
	if _playing:
		return false
	_killer_variant = _identify_killer(killer)
	_visual = VISUAL_SCENE.instantiate() as CanvasLayer
	if not _visual:
		return false
	add_child(_visual)
	_camera = _visual.get_node("VisualRoot/Viewport/World/Camera3D") as Camera3D
	_anchor = _visual.get_node("VisualRoot/Viewport/World/GhostAnchor") as Node3D
	_model_root = _visual.get_node("VisualRoot/Viewport/World/GhostAnchor/ModelRoot") as Node3D
	_flash = _visual.get_node("Flash") as ColorRect
	_tint = _visual.get_node("Tint") as ColorRect
	_sting = _visual.get_node("ImpactAudio") as AudioStreamPlayer
	if not _camera or not _anchor or not _model_root:
		_visual.queue_free()
		_visual = null
		return false
	if not _install_killer_model(killer):
		_visual.queue_free()
		_visual = null
		return false
	_configure_variant_effects()

	# Hunter's body lights itself for the shot; its own gaze lamp points back
	# down the camera axis and would only wash the frame out.
	if _ghost:
		if _ghost.gaze_light:
			_ghost.gaze_light.visible = false
		_ghost.play_clip(CHARGE_CLIP, true)
	_blood = _first_blood_material()
	_skeleton = _killer_model.find_child("Skeleton3D", true, false) as Skeleton3D
	if _ghost and _skeleton:
		_head_bone = _skeleton.find_bone("Head")
		_crown_bone = _skeleton.find_bone("head_end")
		_front_bone = _skeleton.find_bone("headfront")
	else:
		_configure_generic_face_tracker()

	_playing = true
	_elapsed = 0.0
	_lock_player(player)
	_apply_frame(0.0)
	set_process(true)
	return true


func is_playing() -> bool:
	return _playing


func get_killer_variant() -> StringName:
	return _killer_variant


func get_model_source() -> String:
	return _model_source


## Seconds of sequence still to run, so a caller can line something else up
## behind it without duplicating the timing constants.
func get_total_duration() -> float:
	return maxf(pre_delay, 0.0) + maxf(lunge_duration, 0.01) + maxf(hold_duration, 0.0)


func _process(delta: float) -> void:
	_advance(delta)


func _advance(delta: float) -> void:
	if not _playing:
		return
	var previous := _elapsed
	_elapsed += delta
	# The sting is started on the launch, not on the arrival: it is a rising
	# hit, so it has to be already running when the face lands.
	if previous < pre_delay and _elapsed >= pre_delay and _sting and _sting.stream:
		_sting.play()
	# The run cycle bobs the head several centimetres fore and aft, which at
	# arm's length is nothing and at 0.27 m is the difference between the whole
	# face and a pair of eyes. Freezing the pose on the hit is what makes the
	# held close-up the same shot the impact landed on.
	var impact_time := pre_delay + lunge_duration
	if previous < impact_time and _elapsed >= impact_time and is_instance_valid(_ghost):
		_ghost.set_clip_speed(0.0)
	_apply_frame(_elapsed)
	if _elapsed >= get_total_duration():
		_finish()


## The entire sequence as a function of time, which is what makes it testable:
## a smoke test can ask for any instant without waiting for it.
func _apply_frame(time: float) -> void:
	if not is_instance_valid(_anchor):
		return
	var flight := clampf((time - pre_delay) / maxf(lunge_duration, 0.01), 0.0, 1.0)
	var eased := ease(flight, lunge_easing)

	var final_distance := impact_distance
	if _killer_variant == &"darkness":
		final_distance = 0.92
	elif _killer_variant == &"crawler":
		final_distance = 0.5
	_anchor.position = Vector3(0.0, 0.0, -lerpf(start_distance, final_distance, eased))
	_anchor.scale = Vector3.ONE * lerpf(1.0, impact_scale, eased)
	_anchor.rotation = Vector3(0.0, 0.0, deg_to_rad(roll_degrees) * flight * sin(flight * TAU * 1.2))
	if _killer_variant == &"darkness":
		# Darkness advances in short, unnatural snaps instead of a clean dolly.
		# The shake dies at the lens so the face still lands legibly.
		var unrest := 1.0 - flight
		_anchor.position.x = sin(time * 61.0) * 0.045 * unrest
		_anchor.position.y = cos(time * 47.0) * 0.03 * unrest
		_anchor.rotation.z += sin(time * 39.0) * 0.075 * unrest
		_anchor.scale.x *= 1.0 + sin(time * 52.0) * 0.055 * unrest
		var visible_beat := int(maxf(time - pre_delay, 0.0) * 38.0) % 7 not in [1, 4]
		if _killer_model:
			_killer_model.visible = visible_beat or flight >= 0.88
		for eye: MeshInstance3D in _darkness_eyes:
			eye.visible = (visible_beat and flight >= 0.18) or flight >= 0.88
	_track_face()

	if _blood:
		var flow := clampf(
			(flight - blood_start_fraction) / maxf(1.0 - blood_start_fraction, 0.01), 0.0, 1.0
		)
		_blood.set_shader_parameter("blood_amount", flow)

	# Everything past this point is the impact, and all of it is short.
	var since_impact := time - (pre_delay + lunge_duration)
	if _flash:
		var flash := 0.0
		if since_impact >= 0.0:
			flash = flash_peak * (1.0 - clampf(since_impact / maxf(flash_fade, 0.01), 0.0, 1.0))
		_flash.color.a = flash
	if _tint:
		var tint := 0.0
		if since_impact >= 0.0:
			tint = _variant_tint_peak * (
				1.0 - clampf(since_impact / maxf(hold_duration, 0.01), 0.0, 1.0)
			)
		_tint.color.a = tint
	if is_instance_valid(_camera):
		var shake := 0.0
		if since_impact >= 0.0:
			shake = shake_amplitude * (
				1.0 - clampf(since_impact / maxf(shake_duration, 0.01), 0.0, 1.0)
			)
		# Shaken about the camera's own origin, so the face it is pointed at
		# stays the thing in the middle of the frame.
		_camera.position = Vector3(
			sin(time * shake_frequency) * shake,
			cos(time * shake_frequency * 1.37) * shake,
			0.0
		)
		_camera.rotation.z = sin(time * shake_frequency * 0.83) * shake * 3.0


## Slides the body so its face sits on the anchor's origin. One frame, one
## exact correction: the body is a rigid child of the anchor, so moving it by
## the face's own offset moves the face to zero and nothing else drifts.
func _track_face() -> void:
	if not is_instance_valid(_model_root):
		return
	var face := Vector3.ZERO
	if _ghost and _skeleton and _head_bone >= 0 and _crown_bone >= 0 and _front_bone >= 0:
		var skeleton_to_world := _skeleton.global_transform
		var head := skeleton_to_world * _skeleton.get_bone_global_pose(_head_bone).origin
		var crown := skeleton_to_world * _skeleton.get_bone_global_pose(_crown_bone).origin
		var front := skeleton_to_world * _skeleton.get_bone_global_pose(_front_bone).origin
		face = Vector3(front.x, (head.y + crown.y) * 0.5, front.z)
	elif _generic_head:
		face = _generic_head.global_transform * _generic_head_point
	elif _skeleton and _generic_head_bone >= 0:
		var skeleton_to_world := _skeleton.global_transform
		var head := skeleton_to_world \
			* _skeleton.get_bone_global_pose(_generic_head_bone).origin
		face = head
		if _generic_crown_bone >= 0:
			var crown := skeleton_to_world \
				* _skeleton.get_bone_global_pose(_generic_crown_bone).origin
			face.y = (head.y + crown.y) * 0.5
		if _generic_front_bone >= 0:
			var front := skeleton_to_world \
				* _skeleton.get_bone_global_pose(_generic_front_bone).origin
			face.x = front.x
			face.z = front.z
	else:
		return
	_model_root.position -= _anchor.to_local(face)


func _finish() -> void:
	_playing = false
	set_process(false)
	_restore_player()
	if is_instance_valid(_visual):
		# Hidden before it is freed, not merely freed: queue_free() lands at the
		# end of the frame, and jumpscare_finished is what raises the Game Over
		# screen underneath. One frame of a dead ghost's face over it is one
		# frame too many.
		_visual.visible = false
		_visual.queue_free()
	_visual = null
	_camera = null
	_anchor = null
	_ghost = null
	_killer_model = null
	_model_root = null
	_skeleton = null
	_head_bone = -1
	_crown_bone = -1
	_front_bone = -1
	_generic_head = null
	_generic_head_point = Vector3.ZERO
	_generic_head_bone = -1
	_generic_crown_bone = -1
	_generic_front_bone = -1
	_darkness_eyes.clear()
	_blood = null
	_flash = null
	_tint = null
	_sting = null
	jumpscare_finished.emit()


## Cuts the sequence short - used when whatever is watching goes away mid-beat
## (the player dies, the scene changes). The player is restored either way.
func cancel() -> void:
	if _playing:
		_finish()


func _first_blood_material() -> ShaderMaterial:
	if not _ghost:
		return null
	for mesh: MeshInstance3D in _ghost.find_children("*", "MeshInstance3D", true, false):
		var material := mesh.material_override as ShaderMaterial
		if material:
			return material
	return null


func _identify_killer(killer: Node3D) -> StringName:
	if not is_instance_valid(killer):
		return &"hunter"
	var lower_name := killer.name.to_lower()
	if killer.is_in_group(&"darkness_ghosts") or "darkness" in lower_name:
		return &"darkness"
	if killer.is_in_group(&"crawler_ghosts") or "crawler" in lower_name:
		return &"crawler"
	if killer.is_in_group(&"hunter_ghosts") or "hunter" in lower_name:
		return &"hunter"
	return &"statue"


func _install_killer_model(killer: Node3D) -> bool:
	var authored := _model_root.get_node_or_null("Model") as Node3D
	if _killer_variant == &"hunter":
		_ghost = authored as GhostVisual
		_killer_model = _ghost
		_model_source = "res://ghosts/ghost_visual.tscn"
		return _ghost != null

	if authored:
		authored.free()
	match _killer_variant:
		&"crawler":
			_model_source = "res://ghosts/crawler_ghost.tscn::VisualRoot"
		&"darkness":
			_model_source = "res://ghosts/darkness_ghost.tscn::AnimatedModel"
		_:
			_model_source = "res://ghosts/statue_ghost.tscn::Model"
	var source := _visual_source_from_killer(killer)
	if source:
		_killer_model = source.duplicate() as Node3D
	else:
		_killer_model = _visual_from_packed_scene()
	if not _killer_model:
		return false
	_killer_model.name = "Model"
	_killer_model.visible = true
	_model_root.add_child(_killer_model)
	_model_root.transform = Transform3D.IDENTITY
	# Statue and Crawler author their faces toward local -Z; the half-turn points
	# that face back at the camera. Darkness' woman model is authored +Z-front.
	if _killer_variant in [&"statue", &"crawler"]:
		_model_root.rotation.y = PI
	# Imported walk clips can rotate their skeleton/root during the lunge. The
	# gameplay ghost already supplied the identity and pose; the scare moves the
	# whole copy itself, so keep that face looking at the lens throughout.
	for animation_player: AnimationPlayer in _killer_model.find_children(
		"*", "AnimationPlayer", true, false
	):
		animation_player.active = false
	_normalise_model_scale()
	return true


func _visual_source_from_killer(killer: Node3D) -> Node3D:
	if not is_instance_valid(killer):
		return null
	match _killer_variant:
		&"darkness":
			return killer.get_node_or_null("AnimatedModel") as Node3D
		&"crawler":
			return killer.get_node_or_null("VisualRoot") as Node3D
		&"statue":
			return killer.get_node_or_null("VisualRoot/Model") as Node3D
	return null


func _visual_from_packed_scene() -> Node3D:
	var packed: PackedScene
	var visual_path := NodePath("VisualRoot")
	match _killer_variant:
		&"crawler":
			packed = CRAWLER_SCENE
			_model_source = "res://ghosts/crawler_ghost.tscn::VisualRoot"
		&"darkness":
			packed = DARKNESS_SCENE
			visual_path = NodePath("AnimatedModel")
			_model_source = "res://ghosts/darkness_ghost.tscn::AnimatedModel"
		_:
			packed = STATUE_SCENE
			visual_path = NodePath("VisualRoot/Model")
			_model_source = "res://ghosts/statue_ghost.tscn::Model"
	var root := packed.instantiate() as Node3D
	if not root:
		return null
	var source := root.get_node_or_null(visual_path) as Node3D
	if source:
		source.get_parent().remove_child(source)
	root.free()
	return source


func _configure_variant_effects() -> void:
	if not _sting or not _tint:
		return
	_variant_tint_peak = tint_peak
	match _killer_variant:
		&"crawler":
			_sting.stream = CRAWLER_STING
			_sting.pitch_scale = 0.92
			_tint.color = Color(0.34, 0.015, 0.008, 0.0)
		&"darkness":
			_sting.stream = DARKNESS_STING
			_sting.pitch_scale = 0.52
			_tint.color = Color(0.015, 0.08, 0.34, 0.0)
			_variant_tint_peak = 0.28
			_flash.color = Color(0.58, 0.72, 1.0, 0.0)
			_configure_darkness_lighting()
			_add_darkness_eyes()
		&"statue":
			_sting.stream = STATUE_STING
			_sting.pitch_scale = 0.97
			_tint.color = Color(0.24, 0.28, 0.3, 0.0)
		_:
			_tint.color = Color(0.52, 0.02, 0.03, 0.0)


func _configure_darkness_lighting() -> void:
	var key := _visual.get_node_or_null("VisualRoot/Viewport/World/KeyLight") as DirectionalLight3D
	var fill := _visual.get_node_or_null("VisualRoot/Viewport/World/FillLight") as DirectionalLight3D
	if key:
		key.light_color = Color(0.3, 0.42, 1.0)
		key.light_energy = 1.45
	if fill:
		fill.light_color = Color(0.34, 0.02, 0.12)
		fill.light_energy = 0.7
	var face_light := SpotLight3D.new()
	face_light.name = "DarknessFaceLight"
	face_light.light_color = Color(0.42, 0.56, 1.0)
	face_light.light_energy = 1.7
	face_light.spot_range = 5.0
	face_light.spot_angle = 42.0
	face_light.shadow_enabled = false
	_camera.add_child(face_light)


func _add_darkness_eyes() -> void:
	var eye_material := StandardMaterial3D.new()
	eye_material.albedo_color = Color(0.01, 0.015, 0.035)
	eye_material.emission_enabled = true
	eye_material.emission = Color(0.38, 0.56, 1.0)
	eye_material.emission_energy_multiplier = 2.5
	for x: float in [-0.034, 0.034]:
		var eye := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.006
		sphere.height = 0.012
		sphere.radial_segments = 12
		sphere.rings = 6
		sphere.material = eye_material
		eye.mesh = sphere
		eye.position = Vector3(x, 0.014, 0.025)
		_anchor.add_child(eye)
		_darkness_eyes.append(eye)


func _configure_generic_face_tracker() -> void:
	if _killer_variant == &"crawler":
		var crawler_head := _killer_model.get_node_or_null(
			"BodyPivot/NeckPivot/HeadPivot"
		) as Node3D
		if crawler_head:
			_generic_head = crawler_head
			var crawler_head_bounds := _bounds_for(crawler_head)
			_generic_head_point = crawler_head_bounds.get_center() + Vector3(0.0, 0.22, 0.0)
			return
	for candidate: String in ["HeadPivot", "Head", "head"]:
		var found := _killer_model.find_child(candidate, true, false) as Node3D
		if found:
			_generic_head = found
			var head_bounds := _bounds_for(found)
			if head_bounds.size != Vector3.ZERO:
				_generic_head_point = head_bounds.get_center()
			return
	_skeleton = _killer_model.find_child("Skeleton3D", true, false) as Skeleton3D
	if not _skeleton:
		return
	var preferred_head := &"mixamorig_Head_014" if _killer_variant == &"statue" else &"Head"
	_generic_head_bone = _skeleton.find_bone(preferred_head)
	if _killer_variant == &"statue":
		_generic_crown_bone = _skeleton.find_bone(&"mixamorig_HeadTop_End_015")
	elif _killer_variant == &"darkness":
		_generic_crown_bone = _skeleton.find_bone(&"head_end")
		_generic_front_bone = _skeleton.find_bone(&"headfront")
	if _generic_head_bone >= 0:
		return
	for bone: int in _skeleton.get_bone_count():
		var bone_name := _skeleton.get_bone_name(bone).to_lower()
		if bone_name == "head" or bone_name.ends_with(":head") \
				or bone_name.ends_with("_head"):
			_generic_head_bone = bone
			return


func _normalise_model_scale() -> void:
	var bounds := _bounds_for(_killer_model)
	if bounds.size == Vector3.ZERO:
		return
	var scale_factor := 1.0
	var head := _killer_model.find_child("HeadPivot", true, false) as Node3D
	if head:
		var head_bounds := _bounds_for(head)
		if head_bounds.size.y > 0.01:
			scale_factor = 0.3 / head_bounds.size.y
	else:
		var largest := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
		if largest > 0.01:
			scale_factor = 1.8 / largest
	_model_root.scale = Vector3.ONE * clampf(scale_factor, 0.35, 3.0)


func _bounds_for(root: Node3D) -> AABB:
	var bounds := AABB()
	var has_bounds := false
	var meshes: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		meshes.append(root as MeshInstance3D)
	for child: Node in root.find_children("*", "MeshInstance3D", true, false):
		meshes.append(child as MeshInstance3D)
	for mesh: MeshInstance3D in meshes:
		if not mesh.visible or not mesh.mesh:
			continue
		var relative := root.global_transform.affine_inverse() * mesh.global_transform
		var mesh_bounds := relative * mesh.get_aabb()
		bounds = bounds.merge(mesh_bounds) if has_bounds else mesh_bounds
		has_bounds = true
	return bounds


## Movement and look are held still for the sequence, and both are put back the
## way they were rather than forced on: a player who was already input-disabled
## (a remote body, a running minigame) must not be handed control by this.
func _lock_player(player: Node) -> void:
	_player = player
	if not is_instance_valid(_player):
		return
	_saved_physics_process = _player.is_physics_processing()
	_saved_unhandled_input = _player.is_processing_unhandled_input()
	_player.set_physics_process(false)
	_player.set_process_unhandled_input(false)


func _restore_player() -> void:
	if is_instance_valid(_player):
		_player.set_physics_process(_saved_physics_process)
		_player.set_process_unhandled_input(_saved_unhandled_input)
	_player = null


## Steps the sequence by hand, for tests and for tools/jumpscare_devshot - the
## same door the door encounter opens for tests/door_ghost_minigame_smoke.gd.
## The caller takes over the clock entirely, so it must stop this node's own
## `_process` first or the sequence runs at two speeds at once.
func debug_step(delta: float) -> void:
	_advance(delta)
