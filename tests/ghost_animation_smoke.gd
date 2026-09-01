extends SceneTree

## Proves the baked clips actually move the body's visible skeleton, which is the
## only thing that matters here: the library is retargeted onto that rig from
## three separate sources, and a bone-name or track-path slip would leave
## AnimationPlayer happily "playing" a clip that drives nothing.
##
##   godot --headless --script tests/ghost_animation_smoke.gd

const VISUAL := "res://ghosts/ghost_visual.tscn"
## Clips the two ghosts actually ask for, and whether they hold or fire once.
const EXPECTED := {
	"Idle": true, "Walk": true, "Run": true, "Skill 3": false, "Attack": false,
}
## A bone has to turn by at least this much across the clip for it to count as
## animated. Well under any real motion, well over float noise.
const MIN_ROTATION_DEGREES := 5.0


func _initialize() -> void:
	_run.call_deferred()


func _fail(msg: String) -> void:
	push_error("FAIL: " + msg)
	print("FAIL: ", msg)
	quit(1)


func _run() -> void:
	var visual: GhostVisual = (load(VISUAL) as PackedScene).instantiate()
	root.add_child(visual)

	var player := visual.model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if not player:
		return _fail("GhostVisual built no AnimationPlayer")
	var skeleton := visual.model.find_child("Skeleton3D", true, false) as Skeleton3D
	if not skeleton:
		return _fail("no Skeleton3D under the ghost body")

	# The tracks must target the skeleton the meshes are actually skinned to,
	# not some second one left over from the import.
	var meshes := skeleton.find_children("*", "MeshInstance3D", true, false)
	if meshes.is_empty():
		return _fail("no MeshInstance3D parented to the animated Skeleton3D")
	for mesh in meshes:
		if (mesh as MeshInstance3D).skin == null:
			return _fail("%s has no skin, so bone motion cannot reach it" % mesh.name)

	# The rig's rest pose is a bare T-pose, because it is imported through a
	# humanoid BoneMap. A body that has been built but not yet told what to do
	# has to already be idling rather than standing in it.
	if player.current_animation != "Idle" or not player.is_playing():
		return _fail("a freshly built body is not idling (current '%s', playing %s) - it is T-posing"
			% [player.current_animation, player.is_playing()])

	var clips := player.get_animation_list()
	print("clips: ", clips)
	for clip_name in EXPECTED:
		if not player.has_animation(clip_name):
			return _fail("library is missing clip '%s'" % clip_name)
		var anim: Animation = player.get_animation(clip_name)

		var wants_loop: bool = EXPECTED[clip_name]
		if (anim.loop_mode != Animation.LOOP_NONE) != wants_loop:
			return _fail("'%s' loop_mode %d does not match expected loop=%s"
				% [clip_name, anim.loop_mode, wants_loop])

		# Rotation-only, so no clip can translate the body out from under the
		# navigation and CharacterBody3D movement that own its position.
		for i in anim.get_track_count():
			if anim.track_get_type(i) != Animation.TYPE_ROTATION_3D:
				return _fail("'%s' still carries a non-rotation track (%s) - root motion risk"
					% [clip_name, anim.track_get_path(i)])
			var bone := str(anim.track_get_path(i)).get_slice(":", 1)
			if skeleton.find_bone(bone) == -1:
				return _fail("'%s' drives bone '%s', which the body's skeleton does not have"
					% [clip_name, bone])

		# Sample the actual skeleton pose across the clip.
		var samples: Array[Array] = []
		for step in 5:
			player.play(clip_name)
			player.seek(anim.length * float(step) / 4.0, true)
			var pose: Array[Quaternion] = []
			for b in skeleton.get_bone_count():
				pose.append(skeleton.get_bone_pose_rotation(b))
			samples.append(pose)

		var moved := 0
		var widest := 0.0
		for b in skeleton.get_bone_count():
			var spread := 0.0
			for s in samples.size():
				for t in range(s + 1, samples.size()):
					spread = maxf(spread, rad_to_deg(samples[s][b].angle_to(samples[t][b])))
			widest = maxf(widest, spread)
			if spread >= MIN_ROTATION_DEGREES:
				moved += 1
		if moved == 0:
			return _fail("'%s' plays but no bone turns more than %.1f deg (widest %.2f)"
				% [clip_name, MIN_ROTATION_DEGREES, widest])
		print("  %-8s %5.2fs  %2d tracks  %2d bones move  widest %6.1f deg"
			% [clip_name, anim.length, anim.get_track_count(), moved, widest])

	# play_clip() is the guard both ghosts go through: same clip twice must not
	# restart it.
	if not visual.play_clip(&"Attack", false):
		return _fail("play_clip() refused a clip the library has")
	player.seek(0.5, true)
	var before := player.current_animation_position
	visual.play_clip(&"Attack", false)
	if not is_equal_approx(player.current_animation_position, before):
		return _fail("play_clip() restarted a clip that was already running")
	if visual.play_clip(&"NoSuchClip", false):
		return _fail("play_clip() claimed success for a clip that does not exist")

	print("PASS ghost_animation_smoke")
	quit()
