class_name GhostVisual
extends Node3D

## The shared body both ghosts wear: the Midnight Grin biped, instanced once per
## ghost from the one imported file (no copy of the asset exists).
##
##   assets/ghosts/model_hunter/Meshy_AI_Midnight_Grin_biped/
##     Meshy_AI_Midnight_Grin_biped_Animation_Walking_withSkin.glb
##
## The download ships one skinned GLB per animation, all four carrying the same
## mesh and the same 24-bone Armature. Any one of them is therefore the whole
## body; the walking one is simply the one picked to be it, and the other three
## are clip sources that never load at runtime.
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
## The clips are baked into ghosts/ghost_animations.res out of the four GLBs by
## tools/build_ghost_animations.gd, which documents the step. Nothing is
## retargeted: the clips were authored on the exact skeleton they drive, so the
## bake only rebases their track paths. This node builds the AnimationPlayer and
## hands it that library, so `play_clip()` drives the real skeleton.
##
## The baked clips are rotation-only - the hips position track is dropped when
## they are baked - so nothing here can translate the body. Movement stays with
## hunter_ghost.gd's CharacterBody3D and with the door encounter's own placement.
##
## The locomotion sway in `advance()` predates the clips and stays: it is what
## keeps the footstep signal firing and adds lean on top of whatever is playing.

signal foot_planted(speed: float)

## Measured off the import: the rig stands this tall from sole to crown with its
## feet already on the node's own origin, and it looks down +Z. The wrapper
## scales it to the 1.70 m the ghosts were built around and yaws it onto
## Godot's -Z forward. Both numbers were re-measured on the GLB - crown bone at
## y=1.700, `headfront` a fifth of a metre ahead of `Head` in +Z - and both came
## back unchanged from the model this replaced.
const SOURCE_HEIGHT := 1.70
const SOURCE_FORWARD_YAW := 180.0
## Baked by tools/build_ghost_animations.gd; see the class doc.
const ANIMATION_LIBRARY := "res://ghosts/ghost_animations.res"

@export var target_height: float = 1.70
## The GLB does ship its own texture, but wrapped in a material this game cannot
## use: Meshy exports it fully metallic and then hides the black that produces
## behind a full-white emission map. That reads as a ghost lit from inside,
## which is precisely wrong for a body the player is meant to hunt with a
## flashlight. This override is the same texture on an honest dielectric
## material - see the README beside the model.
@export var body_material: Material = preload("res://ghosts/midnight_grin_body.tres")
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
		if body_material:
			for mesh in model.find_children("*", "MeshInstance3D", true, false):
				(mesh as MeshInstance3D).material_override = body_material
		_animation = _build_animation_player()
		# Something has to be playing from the moment the body exists, or what
		# shows is the bare bind pose the GLB rests in.
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


## The AnimationPlayer that plays the baked library, rooted at the skeleton's
## parent so the library's `Skeleton3D:<Bone>` track paths resolve against the
## real, visible skeleton. Returns null if either piece is absent, which leaves
## `play_clip()` reporting false rather than pretending.
##
## The body GLB ships an AnimationPlayer of its own holding the one clip that
## file was downloaded for. That node is taken over rather than left beside a
## second one: its own library is dropped, ours is installed, and its root_node
## is repointed. Left alone it would shadow the library.
func _build_animation_player() -> AnimationPlayer:
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	var library: AnimationLibrary = load(ANIMATION_LIBRARY)
	if not skeleton or not library:
		push_warning("GhostVisual: no skeleton or no clip library; body will not animate")
		return null
	var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if not player:
		player = AnimationPlayer.new()
		player.name = "AnimationPlayer"
		skeleton.get_parent().add_child(player)
	for imported in player.get_animation_library_list():
		player.remove_animation_library(imported)
	player.add_animation_library("", library)
	player.root_node = player.get_path_to(skeleton.get_parent())
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


## The clip last asked for, which is the pose the body is meant to be holding
## even once a one-shot has finished playing. See play_clip().
func get_current_clip() -> StringName:
	return _current_clip


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
