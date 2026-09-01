class_name JumpscareController
extends Node

## Presentation-only jumpscare: the Midnight Grin body flies into the camera and
## fills the screen with its face.
##
## It owns no ghost, no AI and no death logic. Something else decides a ghost has
## been defeated - or has landed a kill - and calls play_jumpscare(); this
## replies with a signal when the sequence is over and touches nothing in
## between except the player's input lock, which it restores exactly as it found
## it. player.gd is the only caller, from two places: the door encounter closing
## on a win, and the Huntsman's lethal hit.
##
## The visual sits on canvas layer 140, above ui/death_screen.gd on 130, and
## both this node and it run with PROCESS_MODE_ALWAYS. The Huntsman's kill
## freezes the world for the length of the sequence - whatever killed the player
## must not still be walking around behind the face - and a sequence that paused
## with it would freeze on its first frame.
##
## ## Why it is not the ghost that is already in the world
##
## jumpscare_visual.tscn renders its own copy of ghosts/ghost_visual.tscn - the
## same one imported Meshy_AI_Midnight_Grin_biped the Huntsman and the door
## encounter wear, no second asset - inside a SubViewport with its own World3D.
## Nothing in that viewport shares a physics space, a navmesh or a scent map
## with the running game, so no ghost script can be disturbed by it and the
## framing cannot be spoiled by where the real ghost happens to be standing.
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
var _model_root: Node3D
var _skeleton: Skeleton3D
## Rig points the framing is pinned to: eye level is halfway between the head
## joint and the crown, and the face surface is where the front marker is.
var _head_bone: int = -1
var _crown_bone: int = -1
var _front_bone: int = -1
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
## length of the sequence; pass null and the jumpscare is pure picture.
func play_jumpscare(player: Node = null) -> bool:
	if _playing:
		return false
	_visual = VISUAL_SCENE.instantiate() as CanvasLayer
	if not _visual:
		return false
	add_child(_visual)
	_camera = _visual.get_node("VisualRoot/Viewport/World/Camera3D") as Camera3D
	_anchor = _visual.get_node("VisualRoot/Viewport/World/GhostAnchor") as Node3D
	_model_root = _visual.get_node("VisualRoot/Viewport/World/GhostAnchor/ModelRoot") as Node3D
	_ghost = _visual.get_node("VisualRoot/Viewport/World/GhostAnchor/ModelRoot/Model") as GhostVisual
	_flash = _visual.get_node("Flash") as ColorRect
	_tint = _visual.get_node("Tint") as ColorRect
	_sting = _visual.get_node("ImpactAudio") as AudioStreamPlayer
	if not _camera or not _anchor or not _ghost:
		_visual.queue_free()
		_visual = null
		return false

	# The body lights itself for the shot; its own gaze lamp points back down
	# the camera axis and would only wash the frame out.
	if _ghost.gaze_light:
		_ghost.gaze_light.visible = false
	_ghost.play_clip(CHARGE_CLIP, true)
	_blood = _first_blood_material()
	_skeleton = _ghost.find_child("Skeleton3D", true, false) as Skeleton3D
	if _skeleton:
		_head_bone = _skeleton.find_bone("Head")
		_crown_bone = _skeleton.find_bone("head_end")
		_front_bone = _skeleton.find_bone("headfront")

	_playing = true
	_elapsed = 0.0
	_lock_player(player)
	_apply_frame(0.0)
	set_process(true)
	return true


func is_playing() -> bool:
	return _playing


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

	_anchor.position = Vector3(0.0, 0.0, -lerpf(start_distance, impact_distance, eased))
	_anchor.scale = Vector3.ONE * lerpf(1.0, impact_scale, eased)
	_anchor.rotation = Vector3(0.0, 0.0, deg_to_rad(roll_degrees) * flight * sin(flight * TAU * 1.2))
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
			tint = tint_peak * (1.0 - clampf(since_impact / maxf(hold_duration, 0.01), 0.0, 1.0))
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
	if not _skeleton or not is_instance_valid(_model_root) or _head_bone < 0 \
		or _crown_bone < 0 or _front_bone < 0:
		return
	var skeleton_to_world := _skeleton.global_transform
	var head := skeleton_to_world * _skeleton.get_bone_global_pose(_head_bone).origin
	var crown := skeleton_to_world * _skeleton.get_bone_global_pose(_crown_bone).origin
	var front := skeleton_to_world * _skeleton.get_bone_global_pose(_front_bone).origin
	var face := Vector3(front.x, (head.y + crown.y) * 0.5, front.z)
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
	_model_root = null
	_skeleton = null
	_head_bone = -1
	_crown_bone = -1
	_front_bone = -1
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
	for mesh: MeshInstance3D in _ghost.find_children("*", "MeshInstance3D", true, false):
		var material := mesh.material_override as ShaderMaterial
		if material:
			return material
	return null


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
