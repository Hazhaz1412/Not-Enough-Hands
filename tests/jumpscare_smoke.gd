extends SceneTree

## JumpscareController smoke test.
##
## The acceptance criterion for this feature is a framing one - the real
## Meshy_AI_Midnight_Grin_biped face flies at the camera, stays centred on it
## and ends up filling the screen - so that is what this measures, by
## unprojecting the model's own crown and jaw bones through the sequence's own
## camera at both ends of the flight. Nothing here is eyeballed off a constant.
##
## Player lock/restore and the blood ramp are checked in the same pass; the
## Huntsman kill that triggers it in play is covered by
## tests/hunter_slash_smoke.gd, which this test does not duplicate.

const CONTROLLER_SCRIPT := "res://jumpscare/jumpscare_controller.gd"
const VISUAL_SCENE := "res://jumpscare/jumpscare_visual.tscn"
const BODY_GLB := "res://assets/ghosts/model_hunter/Meshy_AI_Midnight_Grin_biped/Meshy_AI_Midnight_Grin_biped_Animation_Walking_withSkin.glb"

## Chin and hairline as offsets from the face point the controller keeps pinned
## to the anchor's origin, in metres, each at the depth its own surface sits at.
## Measured off the import by slicing the mesh - the jaw line at y 1.48 / z
## 0.099, where the head stops narrowing and the neck starts, and the hairline
## at y 1.66 / z 0.056 - against that face point at y 1.583 / z 0.090.
## These are the points a player actually looks at, so this is what the close-up
## is judged on rather than the head's bounding box.
const CHIN := Vector3(0.0, -0.103, 0.009)
const HAIRLINE := Vector3(0.0, 0.077, -0.034)

var _controller: JumpscareController


func _initialize() -> void:
	_run.call_deferred()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)


func _run() -> void:
	# --- The visual is the real imported body, not a stand-in. ---
	var packed := load(VISUAL_SCENE) as PackedScene
	if packed == null:
		_fail("Failed to load %s." % VISUAL_SCENE)
		return
	var scene_text := FileAccess.get_file_as_string(VISUAL_SCENE)
	if not scene_text.contains("res://ghosts/ghost_visual.tscn"):
		_fail("Jumpscare must wear ghosts/ghost_visual.tscn, the shared imported body.")
		return
	if not ResourceLoader.exists(BODY_GLB):
		_fail("Meshy_AI_Midnight_Grin_biped is missing from the project.")
		return

	var script := load(CONTROLLER_SCRIPT)
	if script == null:
		_fail("Failed to load %s." % CONTROLLER_SCRIPT)
		return
	_controller = JumpscareController.new()
	root.add_child(_controller)
	await physics_frame

	# --- A stand-in for the player: the controller must not care what it is,
	# only that it can hold and restore its processing flags. ---
	var player := CharacterBody3D.new()
	root.add_child(player)
	player.set_physics_process(true)
	player.set_process_unhandled_input(true)
	await physics_frame

	if _controller.is_playing():
		_fail("Controller must be idle until asked to play.")
		return
	if not _controller.play_jumpscare(player):
		_fail("play_jumpscare() refused to start.")
		return
	if not _controller.is_playing():
		_fail("Controller is not playing after play_jumpscare().")
		return
	# From here the test owns the clock, so every measurement below lands on
	# the instant it asks for rather than on that instant plus a frame or two.
	_controller.set_process(false)
	if _controller.play_jumpscare(player):
		_fail("A second jumpscare started on top of the running one.")
		return
	await physics_frame

	# --- Player control is held for the sequence. ---
	if player.is_physics_processing() or player.is_processing_unhandled_input():
		_fail("Player movement/look was not locked for the jumpscare.")
		return

	var visual := _controller.get_child(0) as CanvasLayer
	if visual == null:
		_fail("Controller did not instance its visual.")
		return
	var background := visual.get_node_or_null("Background") as ColorRect
	if background == null or background.color != Color.BLACK:
		_fail("Hunter jumpscare must cover gameplay with an opaque black background.")
		return
	var camera := visual.get_node_or_null("VisualRoot/Viewport/World/Camera3D") as Camera3D
	var anchor := visual.get_node_or_null("VisualRoot/Viewport/World/GhostAnchor") as Node3D
	var ghost := visual.get_node_or_null(
		"VisualRoot/Viewport/World/GhostAnchor/ModelRoot/Model"
	) as GhostVisual
	if camera == null or anchor == null or ghost == null:
		_fail("Jumpscare visual is missing its camera, anchor or body.")
		return
	var skeleton := ghost.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null or skeleton.find_bone("Head") < 0:
		_fail("The imported biped's skeleton did not load.")
		return
	if ghost.get_current_clip() != &"Run":
		_fail("Jumpscare must hold the one clip that keeps the head facing the camera.")
		return

	var viewport := visual.get_node("VisualRoot/Viewport") as SubViewport
	var view_height := float(viewport.size.y)
	var view_width := float(viewport.size.x)

	# --- Opening frame: the whole ghost is on screen and the face is small. ---
	var opening := _face_span(camera, anchor, viewport)
	if opening.y / view_height > 0.20:
		_fail("Face starts too large (%.0f%% of the screen); it has nowhere to grow." % [
			opening.y / view_height * 100.0
		])
		return
	if _blood_amount(ghost) > 0.01:
		_fail("Blood must start dry and grow with the approach.")
		return

	# --- Fly it. The face must never leave the centre of the frame. ---
	var total := _controller.get_total_duration()
	var steps := 60
	var worst_offset := 0.0
	var previous_span := 0.0
	var shrank := false
	for i in range(1, steps + 1):
		_controller.debug_step(total / float(steps))
		await physics_frame
		if not is_instance_valid(anchor):
			break
		var span := _face_span(camera, anchor, viewport)
		worst_offset = maxf(worst_offset, absf(span.x - view_width * 0.5) / view_width)
		# Up to the impact the face only ever gets bigger.
		if float(i) / float(steps) <= (_controller.pre_delay + _controller.lunge_duration) / total:
			if span.y < previous_span - 1.0:
				shrank = true
			previous_span = span.y
	if worst_offset > 0.06:
		_fail("Face drifted %.1f%% of the screen width off centre." % [worst_offset * 100.0])
		return
	if shrank:
		_fail("Face got smaller during the approach instead of only larger.")
		return

	# --- The sequence ends, and ends cleanly. ---
	if _controller.is_playing():
		_fail("Jumpscare did not finish within its own reported duration.")
		return
	if not player.is_physics_processing() or not player.is_processing_unhandled_input():
		_fail("Player control was not restored after the jumpscare.")
		return
	if _controller.get_child_count() > 0 and is_instance_valid(_controller.get_child(0)):
		var leftover := _controller.get_child(0)
		if not leftover.is_queued_for_deletion():
			_fail("Jumpscare visual outlived the sequence.")
			return

	# --- The close-up itself, measured one step before the end so the visual
	# is still alive: the face has to fill most of the screen, and be bloodied. ---
	if not _controller.play_jumpscare(player):
		_fail("Controller could not be replayed after finishing.")
		return
	_controller.set_process(false)
	await physics_frame
	visual = _controller.get_child(0) as CanvasLayer
	camera = visual.get_node("VisualRoot/Viewport/World/Camera3D") as Camera3D
	anchor = visual.get_node("VisualRoot/Viewport/World/GhostAnchor") as Node3D
	ghost = visual.get_node("VisualRoot/Viewport/World/GhostAnchor/ModelRoot/Model") as GhostVisual
	viewport = visual.get_node("VisualRoot/Viewport") as SubViewport
	_controller.debug_step(_controller.pre_delay + _controller.lunge_duration)
	await physics_frame

	var impact := _face_span(camera, anchor, viewport)
	var fill := impact.y / view_height
	if fill < 0.78:
		_fail("Close-up only fills %.0f%% of the screen height; the face must dominate it." % [
			fill * 100.0
		])
		return
	if absf(impact.x - view_width * 0.5) / view_width > 0.06:
		_fail("Close-up is not centred on the camera.")
		return
	if _blood_amount(ghost) < 0.95:
		_fail("Blood is not running by the time the face lands.")
		return
	var flash := (visual.get_node("Flash") as ColorRect).color.a
	if flash > 0.5:
		_fail("Impact flash at %.2f alpha would wash the face out." % flash)
		return

	# The hold has to be the shot the impact landed on, not a face that keeps
	# growing out of frame behind the flash.
	_controller.debug_step(_controller.hold_duration * 0.9)
	await physics_frame
	var held := _face_span(camera, anchor, viewport)
	if absf(held.y - impact.y) / impact.y > 0.05:
		_fail("Close-up drifted %.0f%% during the hold instead of holding still." % [
			absf(held.y - impact.y) / impact.y * 100.0
		])
		return

	_controller.cancel()
	await physics_frame
	if _controller.is_playing() or not player.is_physics_processing():
		_fail("cancel() left the sequence or the player in a broken state.")
		return

	_controller.queue_free()
	player.queue_free()
	await physics_frame

	if not await _check_trigger():
		return

	print("jumpscare_smoke: OK (face fills %.0f%% of screen height at impact)" % [fill * 100.0])
	quit()


## The wiring, end to end: every lethal ghost plays this with its own real 3D
## identity. The door encounter is checked here too, as the thing that must
## *not* play it - winning a repel used to fire a jumpscare as a flourish, which
## read as being killed at the moment of victory. The encounter itself belongs
## to tests/door_ghost_minigame_smoke.gd; this owns the presentation routing.
func _check_trigger() -> bool:
	var player_scene := load("res://player/player.tscn") as PackedScene
	if player_scene == null:
		_fail("Failed to load the player scene.")
		return false
	var player := player_scene.instantiate()
	root.add_child(player)
	await physics_frame

	var jumpscare := player.get_node_or_null("Jumpscare") as JumpscareController
	if jumpscare == null:
		_fail("Player carries no JumpscareController.")
		return false
	var minigame := player.get_node_or_null("DoorGhostMinigame")
	if minigame == null:
		_fail("Player carries no DoorGhostMinigame to check the trigger against.")
		return false
	var death_ui := player.get_node_or_null("DeathUI") as CanvasLayer
	if death_ui == null:
		_fail("Player carries no DeathUI to check the won encounter against.")
		return false

	# Driving the ghost off is the win. Nothing is owed to the player for it -
	# no face in the doorway, and above all no death screen.
	minigame.minigame_completed.emit(null)
	await physics_frame
	if jumpscare.is_playing():
		_fail("Winning the door encounter played a jumpscare.")
		return false
	if death_ui.visible or int(death_ui.get("phase")) != 0:
		_fail("Winning the door encounter raised the death screen.")
		return false

	# Nor does any other way the encounter can end reach the controller.
	minigame.minigame_closed.emit()
	await physics_frame
	if jumpscare.is_playing() or death_ui.visible:
		_fail("Closing the door encounter played a jumpscare.")
		return false

	player.queue_free()
	await physics_frame

	# Every lethal ghost reaches it. Group-only stand-ins deliberately carry no
	# visuals, forcing the controller to extract each source scene's exact visual
	# subtree rather than accidentally duplicating the Huntsman for all four.
	var huntsman := Node3D.new()
	huntsman.name = "HunterKiller"
	huntsman.add_to_group(&"hunter_ghosts")
	root.add_child(huntsman)
	await physics_frame

	# A fresh body per kill: a death screen only presents one death, so a player
	# that has already been killed once would refuse the second on those grounds
	# rather than on the ones being tested.
	var victim := player_scene.instantiate()
	root.add_child(victim)
	await physics_frame
	var victim_jumpscare := victim.get_node("Jumpscare") as JumpscareController
	var victim_death_ui := victim.get_node("DeathUI") as CanvasLayer

	victim.call("kill_by_ghost", huntsman)
	await physics_frame
	if not victim_jumpscare.is_playing():
		_fail("The Huntsman landed a lethal hit and no jumpscare played.")
		return false
	# The 3D face plays alone. The death screen has taken the death but drawn none
	# of its old vector portrait.
	if victim_death_ui.visible:
		_fail("The old death screen was on screen underneath the Huntsman's jumpscare.")
		return false
	if int(victim_death_ui.get("phase")) != 0:
		_fail("The death screen started its own drawn jumpscare for the Huntsman.")
		return false

	# ... and Game Over waits behind it until the face is gone.
	victim_jumpscare.set_process(false)
	victim_jumpscare.debug_step(victim_jumpscare.get_total_duration())
	await physics_frame
	if victim_jumpscare.is_playing():
		_fail("The Huntsman's jumpscare did not finish.")
		return false
	if victim_jumpscare.get_child_count() > 0:
		var overlay := victim_jumpscare.get_child(0) as CanvasLayer
		if overlay and overlay.visible and not overlay.is_queued_for_deletion():
			_fail("The jumpscare overlay was still on screen when Game Over came up.")
			return false
	if not victim_death_ui.visible or int(victim_death_ui.get("phase")) == 0:
		_fail("The jumpscare finished and Game Over never came up behind it.")
		return false

	var variants: Array[Dictionary] = [
		{
			"name": &"statue",
			"group": &"statue_ghosts",
			"source": "res://ghosts/statue_ghost.tscn::Model",
			"signature": NodePath(),
		},
		{
			"name": &"crawler",
			"group": &"crawler_ghosts",
			"source": "res://ghosts/crawler_ghost.tscn::VisualRoot",
			"signature": NodePath("BodyPivot/NeckPivot/HeadPivot/Skull"),
		},
		{
			"name": &"darkness",
			"group": &"darkness_ghosts",
			"source": "res://ghosts/darkness_ghost.tscn::AnimatedModel",
			"signature": NodePath(),
		},
	]
	for row: Dictionary in variants:
		if not await _check_killer_variant(player_scene, row):
			return false

	huntsman.queue_free()
	victim.queue_free()
	await physics_frame
	return true


func _check_killer_variant(player_scene: PackedScene, row: Dictionary) -> bool:
	var killer := Node3D.new()
	killer.name = "%sKiller" % String(row["name"]).capitalize()
	killer.add_to_group(StringName(row["group"]))
	root.add_child(killer)
	var victim := player_scene.instantiate()
	root.add_child(victim)
	await physics_frame

	var scare := victim.get_node("Jumpscare") as JumpscareController
	var death_ui := victim.get_node("DeathUI") as CanvasLayer
	victim.call("kill_by_ghost", killer)
	await physics_frame
	var expected := StringName(row["name"])
	if not scare.is_playing():
		_fail("The %s kill did not start a 3D jumpscare." % expected)
		return false
	if scare.get_killer_variant() != expected:
		_fail("The %s kill rendered the %s identity." % [expected, scare.get_killer_variant()])
		return false
	if scare.get_model_source() != String(row["source"]):
		_fail("The %s jumpscare did not use its gameplay model source." % expected)
		return false
	if death_ui.visible or int(death_ui.get("phase")) != 0:
		_fail("The old drawn %s portrait appeared underneath its 3D model." % expected)
		return false

	var model := scare.get_child(0).get_node(
		"VisualRoot/Viewport/World/GhostAnchor/ModelRoot/Model"
	) as Node3D
	if model == null:
		_fail("The %s jumpscare contains no 3D model." % expected)
		return false
	var signature := NodePath(row["signature"])
	if not signature.is_empty() and model.get_node_or_null(signature) == null:
		_fail("The %s jumpscare does not contain its recognisable head hierarchy." % expected)
		return false
	if model.find_children("*", "MeshInstance3D", true, false).is_empty():
		_fail("The %s jumpscare model contains no real render mesh." % expected)
		return false

	scare.set_process(false)
	scare.debug_step(scare.get_total_duration())
	await physics_frame
	if scare.is_playing() or not death_ui.visible \
			or not bool(death_ui.call("is_showing_game_over")):
		_fail("The %s 3D scare did not hand off cleanly to Game Over." % expected)
		return false
	if death_ui.get("killer_variant") != expected:
		_fail("The %s Game Over card lost its killer identity." % expected)
		return false

	killer.queue_free()
	victim.queue_free()
	await physics_frame
	return true


## Screen-space x centre and vertical height of the head, unprojected through
## the sequence's own camera. This is the whole acceptance criterion in one
## measurement, so it deliberately uses the real transforms rather than
## re-deriving the framing from the controller's exports.
func _face_span(camera: Camera3D, anchor: Node3D, viewport: SubViewport) -> Vector2:
	var chin := camera.unproject_position(anchor.global_transform * CHIN)
	var hairline := camera.unproject_position(anchor.global_transform * HAIRLINE)
	var _unused := viewport
	return Vector2((chin.x + hairline.x) * 0.5, absf(chin.y - hairline.y))


func _blood_amount(ghost: GhostVisual) -> float:
	for mesh: MeshInstance3D in ghost.find_children("*", "MeshInstance3D", true, false):
		var material := mesh.material_override as ShaderMaterial
		if material:
			return float(material.get_shader_parameter("blood_amount"))
	return -1.0
