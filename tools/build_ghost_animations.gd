extends SceneTree

## Bakes ghosts/ghost_animations.res: the clip library both ghosts play.
##
## Every clip comes out of the Meshy_AI_Midnight_Grin_biped download, which
## ships one skinned GLB per animation - same mesh, same 24-bone Armature in
## all four. That is the whole reason no retargeting happens here any more: the
## clips were authored on the exact skeleton they drive, so a track only has to
## be rebased onto the instanced body's node path.
##
## The download carries four animations and the two ghosts ask for five clips,
## so Weapon_Combo covers both one-shots - see CLIPS.
##
## Position and scale tracks are stripped on purpose. The hips track is the one
## that carries root motion, and movement here belongs to hunter_ghost.gd's
## CharacterBody3D/NavigationAgent3D and to the door encounter's own placement -
## a hips track would translate the body a second time.
##
## Run after changing the sources:
##   godot --headless --script tools/build_ghost_animations.gd

const OUT := "res://ghosts/ghost_animations.res"
const DIR := "res://assets/ghosts/model_hunter/Meshy_AI_Midnight_Grin_biped/"
const BODY := DIR + "Meshy_AI_Midnight_Grin_biped_Animation_Walking_withSkin.glb"

const RUNNING := DIR + "Meshy_AI_Midnight_Grin_biped_Animation_Running_withSkin.glb"
const UNSTEADY := DIR + "Meshy_AI_Midnight_Grin_biped_Animation_Unsteady_Walk_withSkin.glb"
const WALKING := BODY
const COMBO := DIR + "Meshy_AI_Midnight_Grin_biped_Animation_Weapon_Combo_withSkin.glb"

## clip name -> [source scene, animation in that source, loops]
##
## Idle is the unsteady walk with its position tracks dropped, which leaves the
## sway and drops the travel - the download ships no standing clip. Attack and
## Skill 3 are both the weapon combo for the same reason: four animations, five
## clips, and the combo is the only aggressive one in the set.
const CLIPS := {
	"Idle": [UNSTEADY, "Armature|Unsteady_Walk|baselayer", true],
	"Walk": [WALKING, "Armature|walking_man|baselayer", true],
	"Run": [RUNNING, "Armature|running|baselayer", true],
	"Skill 3": [COMBO, "Armature|Weapon_Combo|baselayer", false],
	"Attack": [COMBO, "Armature|Weapon_Combo|baselayer", false],
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


## Every bone the body's rig actually has. All four sources share it, so this is
## a guard against a bad source rather than a filter that does real work.
func _body_bones() -> Dictionary:
	var root := (load(BODY) as PackedScene).instantiate()
	var skeleton := root.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var bones := {}
	for i in skeleton.get_bone_count():
		bones[skeleton.get_bone_name(i)] = true
	root.free()
	return bones


## Rewrites `Armature/Skeleton3D:Bone` to `Skeleton3D:Bone` - the path
## GhostVisual's AnimationPlayer resolves, rooted at the skeleton's parent - and
## throws away every track that is not a rotation on a bone the body has.
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
	var bones := _body_bones()
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
