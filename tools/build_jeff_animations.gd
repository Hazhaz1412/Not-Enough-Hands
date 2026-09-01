extends SceneTree

## Bakes ghosts/jeff_animations.res: the clip library both Jeff-bodied ghosts play.
##
## jeff_the_killer.glb ships no animations at all - its glTF has no `animations`
## array and the imported scene has no AnimationPlayer. The clips live in the two
## sibling files that do carry motion, on two other skeletons:
##
##   Meshy_AI_Midnight_Grin_biped/..._Merged_Animations.fbx  24-bone Meshy rig
##   Running.fbx / Stabbing.fbx                              65-bone Mixamo rig
##
## All three rigs are imported through a BoneMap onto SkeletonProfileHumanoid
## (see the `retarget/` block in each .import), so after import every one of them
## names its bones Hips/Spine/LeftUpperArm/... That renaming is what makes a clip
## authored on one of them drive Jeff's skeleton; this script only copies the
## tracks across and drops what would fight gameplay.
##
## Position and scale tracks are stripped on purpose. The hips track is the one
## that carries root motion, and movement here belongs to hunter_ghost.gd's
## CharacterBody3D/NavigationAgent3D and to the door encounter's own placement -
## a hips track would translate the body a second time. Rotation is also the only
## channel that survives the rigs' different unit scales unharmed.
##
## Run after changing the sources or the bone maps:
##   godot --headless --script tools/build_jeff_animations.gd

const OUT := "res://ghosts/jeff_animations.res"
const JEFF := "res://assets/ghosts/model_hunter/jeff_the_killer.glb"

const GRIN := "res://assets/ghosts/model_hunter/Meshy_AI_Midnight_Grin_biped/Meshy_AI_Midnight_Grin_biped_Meshy_AI_Meshy_Merged_Animations.fbx"
const RUNNING := "res://assets/ghosts/model_hunter/Running.fbx"
const STABBING := "res://assets/ghosts/model_hunter/Stabbing.fbx"

## clip name -> [source scene, animation in that source, loops]
const CLIPS := {
	"Idle": [GRIN, "Idle_9_frame_rate_60_fbx", true],
	"Walk": [GRIN, "Unsteady_Walk_frame_rate_60_fbx", true],
	"Run": [RUNNING, "mixamo_com", true],
	"Skill 3": [GRIN, "Skill_03_frame_rate_60_fbx", false],
	"Attack": [STABBING, "mixamo_com", false],
}


func _source_animation(path: String, anim_name: String) -> Animation:
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var root := packed.instantiate()
	var players := root.find_children("*", "AnimationPlayer", true, false)
	var found: Animation = null
	if not players.is_empty():
		var player := players[0] as AnimationPlayer
		if player.has_animation(anim_name):
			found = (player.get_animation(anim_name) as Animation).duplicate(true)
	root.free()
	return found


## Every bone Jeff's rig actually has, under its post-retarget profile name.
## The two source rigs are richer than his - they carry an UpperChest, hands and
## full finger chains that his 58-bone rig simply has no equivalent for - and a
## track naming a bone the target lacks is a dead track, so they are dropped
## here rather than left to fail silently at runtime.
func _jeff_bones() -> Dictionary:
	var root := (load(JEFF) as PackedScene).instantiate()
	var skeleton := root.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var bones := {}
	for i in skeleton.get_bone_count():
		bones[skeleton.get_bone_name(i)] = true
	root.free()
	return bones


## Rewrites `<whatever>/Skeleton3D:Bone` to `Skeleton3D:Bone` and throws away
## every track that is not a rotation on a bone Jeff has.
func _rebase(anim: Animation, loops: bool, bones: Dictionary) -> int:
	for i in range(anim.get_track_count() - 1, -1, -1):
		var bone := str(anim.track_get_path(i)).get_slice(":", 1)
		if anim.track_get_type(i) != Animation.TYPE_ROTATION_3D or not bones.has(bone):
			anim.remove_track(i)
			continue
		anim.track_set_path(i, NodePath("Skeleton3D:" + bone))
	anim.loop_mode = Animation.LOOP_LINEAR if loops else Animation.LOOP_NONE
	return anim.get_track_count()


func _initialize() -> void:
	var bones := _jeff_bones()
	var library := AnimationLibrary.new()
	var failed := false
	for clip_name in CLIPS:
		var spec: Array = CLIPS[clip_name]
		var anim := _source_animation(spec[0], spec[1])
		if anim == null:
			push_error("Missing source animation %s in %s" % [spec[1], spec[0]])
			failed = true
			continue
		var tracks := _rebase(anim, spec[2], bones)
		library.add_animation(clip_name, anim)
		print("%-8s <- %-34s %.3fs  %d rotation tracks  loop=%s" % [
			clip_name, spec[1], anim.length, tracks, spec[2]])
	if failed:
		quit(1)
		return
	var err := ResourceSaver.save(library, OUT)
	print("saved ", OUT, " err=", err)
	quit(0 if err == OK else 1)
