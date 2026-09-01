class_name JeffGhostVisual
extends Node3D

## The shared body both ghosts wear: assets/ghosts/model_hunter/jeff_the_killer.glb,
## instanced once per ghost from the one GLB (no copy of the asset exists).
##
## ## Why this node also answers StalkerRig's API
##
## ghosts/hunter_ghost.gd drives its visual through eight properties, a
## `foot_planted` signal and a `gaze_light` it borrows for the lantern. Matching
## that surface here is what lets the Huntsman's model be swapped without
## touching a line of its AI, navigation, scent or attack code - the script
## keeps setting exactly what it always set.
##
## ## Where the animations come from
##
## jeff_the_killer.glb is a Sketchfab export whose glTF carries no `animations`
## array at all - zero clips, and the imported scene has no AnimationPlayer. The
## clips it plays are baked into ghosts/jeff_animations.res out of the two
## sibling assets that do have motion, retargeted onto Jeff's skeleton through a
## shared humanoid BoneMap; tools/build_jeff_animations.gd is that step and
## documents it. This node builds the AnimationPlayer the GLB does not ship and
## hands it that library, so `play_clip()` drives the real skeleton.
##
## The baked clips are rotation-only - the hips position track is dropped when
## they are baked - so nothing here can translate the body. Movement stays with
## hunter_ghost.gd's CharacterBody3D and with the door encounter's own placement.
##
## The locomotion sway in `advance()` predates the clips and stays: it is what
## keeps the footstep signal firing and adds lean on top of whatever is playing.

signal foot_planted(speed: float)

## Measured off the import: the rig stands 1.40 m from sole to crown with its
## feet already on the node's own origin, and it looks down +Z. The wrapper
## scales it to the 1.70 m the ghosts were built around and yaws it onto
## Godot's -Z forward.
const SOURCE_HEIGHT := 1.40
const SOURCE_FORWARD_YAW := 180.0
## Baked by tools/build_jeff_animations.gd; see the class doc.
const ANIMATION_LIBRARY := "res://ghosts/jeff_animations.res"

@export var target_height: float = 1.70
## Sway applied per unit of locomotion speed, in degrees. Small - this is a
## stand-in for a walk cycle, not a performance.
@export var sway_degrees: float = 4.5
@export var sway_speed: float = 7.0
@export var stride_length: float = 1.15
@export var gaze_casts_shadows: bool = false

# --- the surface hunter_ghost.gd writes every frame -------------------------
var locomotion_speed: float = 0.0
var agitation: float = 0.0
var searching: bool = false
var charging: bool = false
var look_point: Vector3 = Vector3.ZERO
var has_look_point: bool = false
var gaze_light: SpotLight3D

var _built: bool = false
var _sway_time: float = 0.0
var _stride_travel: float = 0.0
var _animation: AnimationPlayer
## The clip that was last *asked* for, which is not the same as the one the
## player is running: a one-shot that has finished is no longer playing but is
## still the pose the ghost is meant to be holding. See play_clip().
var _current_clip: StringName = &""

@onready var model: Node3D = $Model


func _ready() -> void:
	build()


## Kept as a method because StalkerRig had one and hunter_ghost.gd calls it.
## Safe to call twice.
func build() -> void:
	if _built:
		return
	_built = true
	if not model:
		model = get_node_or_null("Model") as Node3D
	if model:
		var scale_factor := target_height / SOURCE_HEIGHT
		model.scale = Vector3.ONE * scale_factor
		model.rotation_degrees = Vector3(0.0, SOURCE_FORWARD_YAW, 0.0)
		_animation = _build_animation_player()
		# Something has to be playing from the moment the body exists. The rig is
		# imported through a humanoid BoneMap, which leaves its rest pose a bare
		# T-pose - that is what shows if nothing has claimed the skeleton yet.
		play_clip(&"Idle", true)
	if not gaze_light:
		gaze_light = SpotLight3D.new()
		gaze_light.name = "GazeLight"
		gaze_light.light_color = Color(0.62, 0.70, 0.82)
		gaze_light.light_energy = 3.2
		gaze_light.light_indirect_energy = 0.6
		gaze_light.shadow_enabled = gaze_casts_shadows
		gaze_light.spot_range = 15.0
		gaze_light.spot_attenuation = 1.35
		gaze_light.spot_angle = 34.0
		gaze_light.spot_angle_attenuation = 0.55
		gaze_light.position = Vector3(0.0, 1.45, 0.0)
		add_child(gaze_light)


## The AnimationPlayer the GLB is missing, rooted at the skeleton's parent so the
## baked library's `Skeleton3D:<Bone>` track paths resolve against the real,
## visible skeleton. Returns null if either piece is absent, which leaves
## `play_clip()` reporting false rather than pretending.
func _build_animation_player() -> AnimationPlayer:
	var existing := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if existing:
		return existing
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	var library: AnimationLibrary = load(ANIMATION_LIBRARY)
	if not skeleton or not library:
		push_warning("JeffGhostVisual: no skeleton or no clip library; body will not animate")
		return null
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	skeleton.get_parent().add_child(player)
	player.root_node = player.get_path_to(skeleton.get_parent())
	player.add_animation_library("", library)
	return player


## True only if the library actually supplies the clip. Both ghosts route their
## animation through here, and it is also what keeps them from restarting a clip
## every frame: they ask for the pose they are in on every update, so the guard
## has to be "is this already the requested clip", not "is it still playing".
## The difference matters for the one-shots - Attack and Skill 3 stop playing
## when they finish, and testing is_playing() would fire them again on the very
## next frame for as long as the ghost stayed in that state. Holding the last
## frame is what an attack that has landed should look like.
func play_clip(clip: StringName, loop: bool) -> bool:
	if not _animation or not _animation.has_animation(clip):
		return false
	if _current_clip == clip:
		return true
	_current_clip = clip
	_animation.get_animation(clip).loop_mode = (
		Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	)
	_animation.play(clip)
	return true


## How fast whatever is playing runs. The clips have no agitated variants, so
## escalation is carried by the rate of the same body rather than a new one.
func set_clip_speed(scale: float) -> void:
	if _animation:
		_animation.speed_scale = maxf(scale, 0.0)


func has_clip(clip: StringName) -> bool:
	return _animation != null and _animation.has_animation(clip)


func get_clip_names() -> PackedStringArray:
	return _animation.get_animation_list() if _animation else PackedStringArray()


func stop_clip() -> void:
	_current_clip = &""
	if _animation:
		_animation.stop()


## Driven from hunter_ghost.gd's own per-frame update, exactly as StalkerRig's
## was. Only the visual sways - the ghost's position stays wherever its AI put
## it, so nothing here can move the character.
func advance(delta: float) -> void:
	if not model:
		return
	var speed := maxf(locomotion_speed, 0.0)
	_sway_time += delta * sway_speed * clampf(speed / maxf(stride_length, 0.01), 0.0, 2.5)
	var lean := sway_degrees * clampf(speed * 0.5, 0.0, 1.0) * (1.0 + agitation * 0.6)
	model.rotation_degrees = Vector3(
		sin(_sway_time * 2.0) * lean * 0.35,
		SOURCE_FORWARD_YAW,
		sin(_sway_time) * lean
	)
	if has_look_point and gaze_light:
		gaze_light.look_at(look_point, Vector3.UP)

	# Footfalls, so the Huntsman's existing footstep audio keeps firing off the
	# body rather than off a timer it does not own.
	if speed > 0.05:
		_stride_travel += speed * delta
		if _stride_travel >= maxf(stride_length, 0.05):
			_stride_travel = 0.0
			foot_planted.emit(speed)
	else:
		_stride_travel = 0.0
