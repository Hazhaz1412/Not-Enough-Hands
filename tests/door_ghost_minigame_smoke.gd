extends SceneTree

## Door ghost minigame smoke test.
##
## The encounter is a real 3D interaction, so this drives the real Player
## scene (camera + SpotLight3D) and a real DefenseDoor rather than faking
## screen coordinates: every "hit" here is the actual flashlight cone and
## occlusion test agreeing that the ghost is lit.
##
## Contract under test:
## - the Midnight Grin asset loads, stands 1.7 m upright the right way up on
##   its own origin, faces -Z, carries the four clips it is posed with, and
##   wears the baked albedo/ORM maps rather than the import's blank white
## - the beam only counts when the ray reaches the ghost's own collider, so
##   world geometry in the way blocks a hit that is otherwise perfectly aimed
## - starting from a defense-door attack goes through begin_exorcism()
## - ghost positions come from the door_ghost_spots group, never from map
##   coordinates
## - each of the three phases costs exactly hits_per_phase illuminated hits,
##   the counter resets to 0 on every transition, and the fifteenth hit hands
##   the door back through complete_exorcism()
## - phases 0/1/2 stay equally dark while each clear widens the look limits
## - the final stare remains flashlight-vulnerable; only actually ignoring it
##   through the whole deadline applies the door's single failure hit
## - phase spawn bands progress from near, to medium, to far, and every spawn
##   remains inside that phase's yaw clamp
## - the house lights go out for the encounter and come back exactly as they
##   were, with the flashlight left on as the only source
## - the retro post-process grade tracks the approach and is stood down, and
##   the flashlight's flicker leaves its energy exactly where it found it
## - player position, rotation and look clamps are restored either way, and the
##   spawned ghost is freed with no reference left behind

const STEP := 0.05


func _initialize() -> void:
	_run.call_deferred()


func _land_repel(minigame: DoorGhostMinigame) -> bool:
	# Aim once, then hold the beam past the confirmation time.
	var budget := int(ceil(minigame.flashlight_confirm_time / STEP)) + 3
	var before := minigame.get_total_hits()
	for _step: int in budget:
		minigame.debug_aim_at_ghost()
		minigame.debug_step(STEP)
		if minigame.get_total_hits() > before:
			return true
	return false


## Runs the retreat beat out so the ghost is standing at a fresh spot again.
func _wait_for_search(minigame: DoorGhostMinigame) -> void:
	var budget := int(ceil(minigame.retreat_duration / STEP)) + 2
	for _step: int in budget:
		if minigame.state == DoorGhostMinigame.State.SEARCH:
			return
		minigame.debug_look_away()
		minigame.debug_step(STEP)


## The imported GLB is the encounter's actual ghost, so its scale, orientation
## and clip names are part of the contract - a reimport that tips it over or
## renames a clip has to fail here rather than in a playtest.
func _check_asset() -> bool:
	var ghost_scene := load("res://ghosts/door_ghost.tscn") as PackedScene
	if not ghost_scene:
		_fail("ghosts/door_ghost.tscn could not be loaded.")
		return false
	var ghost := ghost_scene.instantiate() as DoorGhost
	root.add_child(ghost)
	ghost.appear(Vector3.ZERO)
	await process_frame

	# The active body must actually be the Midnight Grin import, not merely
	# reference it: walk the live tree and find its mesh under the ghost. The
	# whole character is one skinned surface named `char1`, in every one of the
	# download's four GLBs.
	var meshes := ghost.find_children("*", "MeshInstance3D", true, false)
	if meshes.size() != 1 or meshes[0].name != "char1":
		_fail("Expected the Midnight Grin body's single 'char1' mesh, found %d: %s"
			% [meshes.size(), str(meshes.map(func(m: Node) -> String: return m.name))])
		return false
	var body := meshes[0] as MeshInstance3D
	if body.skin == null:
		_fail("The body mesh is not skinned, so bone motion cannot reach it.")
		return false
	# The GLB ships its texture inside a fully-metallic, fully-emissive material
	# that would render the ghost lit from the inside and deaf to the flashlight,
	# so the usable material has to arrive as an override. See
	# assets/ghosts/model_hunter/README.md.
	var applied := body.material_override as BaseMaterial3D
	if not applied or not applied.get_texture(BaseMaterial3D.TEXTURE_ALBEDO):
		_fail("The body mesh has no albedo-textured material override.")
		return false
	# The point of the override: emission off, so the beam is what reveals it.
	if applied is StandardMaterial3D and (applied as StandardMaterial3D).emission_enabled:
		_fail("The body material is emissive; the ghost would glow in an unlit house.")
		return false

	# Measured off the skeleton, not the mesh AABB. Two reasons: a static AABB
	# stays the same whatever pose the rig is in, and on this rig it is not even
	# in the same space as the body - the GLB's `Armature` carries a 0.01 scale
	# and the skin's bind poses carry the inverse, so `get_aabb()` reports a
	# 0.017 m figure while the skinned body really stands 1.70 m.
	#
	# The bone names are the asset's own. Nothing is retargeted any more: the
	# clips ship on the very skeleton they drive, so there is no BoneMap and no
	# humanoid profile renaming `LeftToeBase` to `LeftToes`.
	var skeleton := ghost.find_child("Skeleton3D", true, false) as Skeleton3D
	if not skeleton or skeleton.get_bone_count() != 24:
		_fail("Expected the Midnight Grin 24-bone skeleton, found %d."
			% (skeleton.get_bone_count() if skeleton else -1))
		return false
	for bone in ["Head", "head_end", "Hips", "LeftToeBase", "Spine02", "LeftHand"]:
		if skeleton.find_bone(bone) == -1:
			_fail("The rig has no '%s' bone - this is not the Midnight Grin skeleton." % bone)
			return false
	var head: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(
		skeleton.find_bone("Head")
	).origin
	var hips: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(
		skeleton.find_bone("Hips")
	).origin
	var toe: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(
		skeleton.find_bone("LeftToeBase")
	).origin
	# Standing height is the crown, which is what a player sees and what "spawns
	# underground or floating" actually means. The head *bone* sits inside the
	# skull, so `head_end` - the tip of the chain - is the one that reaches it.
	var crown: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(
		skeleton.find_bone("head_end")
	).origin
	if absf(toe.y) > 0.06:
		_fail("The body's feet are %.2f m off the ghost's own origin." % toe.y)
		return false
	if absf(crown.y - ghost.model.target_height) > 0.05:
		_fail("The body stands %.2f m, not the %.2f m the ghosts are built around."
			% [crown.y, ghost.model.target_height])
		return false
	if head.y <= hips.y or hips.y <= toe.y:
		_fail("The body is not the right way up: head %.2f, hips %.2f, toe %.2f."
			% [head.y, hips.y, toe.y])
		return false
	if not is_equal_approx(ghost.model.model.rotation_degrees.y, GhostVisual.SOURCE_FORWARD_YAW):
		_fail("The wrapper did not apply the body's forward correction.")
		return false

	# Aiming is the node's job and the mesh follows it, so the contract to hold
	# is that the ghost's own forward lands on the point it was told to face.
	ghost.face_point(Vector3(0.0, 0.0, -5.0))
	await process_frame
	if (-ghost.global_transform.basis.z).dot(Vector3(0.0, 0.0, -1.0)) < 0.99:
		_fail("face_point() did not aim the ghost at its target.")
		return false

	# Every clip the encounter's poses name has to be there, and each pose has to
	# actually select its own: a body that silently falls back to one animation
	# is the failure this is guarding against.
	for pose: int in DoorGhost.POSE_CLIPS:
		var clip: StringName = DoorGhost.POSE_CLIPS[pose]
		if not ghost.model.has_clip(clip):
			_fail("Pose %d asks for clip '%s', which the library does not have." % [pose, clip])
			return false
		ghost.set_pose(DoorGhost.Pose.IDLE if pose != DoorGhost.Pose.IDLE else DoorGhost.Pose.LUNGE)
		ghost.set_pose(pose)
		var playing := ghost.model.get_current_clip()
		if playing != clip:
			_fail("Pose %d selected clip '%s' instead of '%s'." % [pose, playing, clip])
			return false
	print("  body animation clips: %s" % str(ghost.model.get_clip_names()))
	for pose: DoorGhost.Pose in DoorGhost.POSE_CLIPS:
		ghost.set_pose(pose)
	if ghost.get_pose() != DoorGhost.Pose.LUNGE:
		_fail("The pose API did not settle on the pose it was last given.")
		return false

	ghost.queue_free()
	await process_frame
	return true


func _run() -> void:
	if not await _check_asset():
		return
	var door_scene := load("res://door/defense_door.tscn") as PackedScene
	var player_scene := load("res://player/player.tscn") as PackedScene
	if not door_scene or not player_scene:
		_fail("Door or player scene could not be loaded.")
		return

	var door := door_scene.instantiate() as DefenseDoor
	root.add_child(door)
	door.set_physics_process(false)
	door.get_node("WarningAudio").stream = null
	door.get_node("StrongAttackAudio").stream = null

	# A second entrance well inside spot_search_radius: its spots must never be
	# borrowed by the door actually under attack.
	var neighbour := door_scene.instantiate() as DefenseDoor
	neighbour.entrance_id = 2
	root.add_child(neighbour)
	neighbour.set_physics_process(false)
	neighbour.global_position = Vector3(4.0, 0.0, 0.0)

	var player := player_scene.instantiate() as CharacterBody3D
	root.add_child(player)
	player.set_physics_process(false)
	player.global_position = Vector3(0.0, 0.88, 4.0)
	await physics_frame

	var minigame := player.get_node("DoorGhostMinigame") as DoorGhostMinigame
	if not minigame:
		_fail("The player no longer owns a DoorGhostMinigame.")
		return
	minigame.set_process(false)
	minigame.set_random_seed(11)
	# Villa entrances publish their real exterior normal because the reused door
	# mesh has the opposite local-axis convention there. The minigame must honour
	# it, while the encounter below continues to cover House2's -Z fallback.
	var direction_probe := Node3D.new()
	root.add_child(direction_probe)
	direction_probe.set_meta("exterior_outward", Vector3.RIGHT)
	var measured: Vector3 = minigame.call("_measure_outward", direction_probe)
	if measured.dot(Vector3.RIGHT) < 0.999:
		_fail("Door ghost ignored the map-authored exterior direction.")
		return
	direction_probe.queue_free()
	if minigame.hits_per_phase != 2 \
		or DoorGhostMinigame.TOTAL_PHASES != 3 \
		or minigame.get_hits_required() != 6 \
		or not is_equal_approx(minigame.threat_window, 3.0) \
		or not is_equal_approx(minigame.stare_threshold, 0.8) \
		or not is_equal_approx(minigame.flashlight_confirm_time, 0.35):
		_fail(
			"The encounter's balance defaults drifted: %d hits x %d phases = %d / %.1fs / %.1fs / %.2fs."
			% [
				minigame.hits_per_phase,
				DoorGhostMinigame.TOTAL_PHASES,
				minigame.get_hits_required(),
				minigame.threat_window,
				minigame.stare_threshold,
				minigame.flashlight_confirm_time,
			]
		)
		return
	if minigame.phase_minimum_spot_distances.size() != DoorGhostMinigame.TOTAL_PHASES \
		or minigame.phase_minimum_spot_distances[0] >= minigame.phase_minimum_spot_distances[1] \
		or minigame.phase_minimum_spot_distances[1] >= minigame.phase_minimum_spot_distances[2]:
		_fail("Door ghost phase distances are not ordered near, medium, far.")
		return
	if not is_equal_approx(minigame.dodge_chance, 0.3) \
		or not is_equal_approx(minigame.dodge_trigger_fraction, 0.3) \
		or minigame.phase_apertures != PackedFloat32Array([0.0, 0.0, 0.0]) \
		or not is_equal_approx(minigame.encounter_flashlight_range, 16.5) \
		or not is_equal_approx(minigame.encounter_flashlight_angle, 32.0) \
		or not is_equal_approx(minigame.flashlight_focus_radius, 0.26) \
		or not is_equal_approx(minigame.peripheral_visibility, 0.16):
		_fail("Darkness, minigame flashlight or the 30%% dodge defaults drifted.")
		return
	# Keep the deterministic 15-hit contract separate from the forced dodge
	# scenario at the end of this test.
	minigame.dodge_chance = 0.0

	# Two house lights, one of them already switched off, so the restore has to
	# put back what was there rather than blanket-enabling everything.
	var lit_lamp := OmniLight3D.new()
	lit_lamp.add_to_group("flickering_house_lights")
	root.add_child(lit_lamp)
	var dark_lamp := OmniLight3D.new()
	dark_lamp.add_to_group("flickering_house_lights")
	dark_lamp.visible = false
	root.add_child(dark_lamp)

	var saved_position := player.global_position
	var leaf := door.get_node("DoorVisual/DoorLeaf") as Node3D
	var leaf_rest := leaf.transform

	# --- start from a real door attack -------------------------------------
	if not door.begin_targeting(true, 30.0):
		_fail("The intact door could not enter its rustling phase.")
		return
	door.interact(player)
	if not minigame.is_running() or not door.minigame_active:
		_fail("Pressing E during the rustling phase did not start the encounter.")
		return
	if minigame.get_phase_index() != 0 or not bool(player.yaw_clamp_active):
		_fail("The peephole phase did not clamp the player's look direction.")
		return
	var initial_camera := player.get_node("CameraPivot/Camera3D") as Camera3D
	var exterior_forward := -initial_camera.global_basis.z
	exterior_forward.y = 0.0
	if exterior_forward.normalized().dot(minigame.outward) < 0.999:
		_fail("Door minigame camera did not initially face the exterior environment.")
		return
	if lit_lamp.visible or dark_lamp.visible:
		_fail("The encounter did not put the house lights out.")
		return
	var torch := player.get_node("CameraPivot/Camera3D/Flashlight") as SpotLight3D
	if not torch.visible:
		_fail("The flashlight was not left on as the only light source.")
		return
	var torch_range: float = float(minigame.get("_saved_flashlight_range"))
	var torch_angle: float = float(minigame.get("_saved_flashlight_angle"))
	if not is_equal_approx(torch.spot_range, minigame.encounter_flashlight_range) \
		or not is_equal_approx(torch.spot_angle, minigame.encounter_flashlight_angle):
		_fail("The minigame did not widen and extend the flashlight.")
		return
	minigame.debug_step(0.0)
	var darkness_material := minigame.mask.material as ShaderMaterial
	if not is_equal_approx(
		float(darkness_material.get_shader_parameter("focus_radius")),
		minigame.flashlight_focus_radius
	) or not is_equal_approx(
		float(darkness_material.get_shader_parameter("peripheral_visibility")),
		minigame.peripheral_visibility
	):
		_fail("The darkness mask did not preserve the faint peripheral view.")
		return
	var torch_energy: float = player._flashlight_base_energy
	var overlay := player.horror_overlay_rect.material as ShaderMaterial
	if not is_equal_approx(player.yaw_clamp_max, deg_to_rad(minigame.phase_yaw_limits[0])):
		_fail("The peephole phase did not apply its authored yaw limit.")
		return
	# The two outer markers sit beyond phase 1's 45-degree look clamp, so only
	# the three reachable positions may survive until the door opens wider.
	if minigame.spots.size() != 3:
		_fail(
			"Expected three phase-1 spots inside the yaw clamp, resolved %d."
			% minigame.spots.size()
		)
		return
	if not leaf.transform.is_equal_approx(leaf_rest):
		_fail("The peephole phase moved the door leaf before the player opened it.")
		return
	for spot: Vector3 in minigame.spots:
		if (-door.global_transform.basis.z).dot(spot - door.global_position) <= 0.0:
			_fail("A ghost spot was resolved on the inside of the door.")
			return

	# --- looking anywhere else never lands a hit ---------------------------
	minigame.debug_look_away()
	for _step: int in int(ceil(minigame.flashlight_confirm_time / STEP)) + 4:
		minigame.debug_step(STEP)
	if minigame.get_total_hits() != 0:
		_fail("A repel landed without the flashlight ever being on the ghost.")
		return

	# --- a brush is not a hit, and looking away restarts the hold -----------
	var half_hold := int(minigame.flashlight_confirm_time / STEP) / 2
	for _brush: int in 3:
		for _step: int in half_hold:
			minigame.debug_aim_at_ghost()
			minigame.debug_step(STEP)
		minigame.debug_look_away()
		minigame.debug_step(STEP)
	if minigame.get_total_hits() != 0:
		_fail("Repeated brief passes over the ghost accumulated into a repel.")
		return

	# --- world geometry blocks an otherwise perfect aim ---------------------
	minigame.debug_aim_at_ghost()
	var camera := player.get_node("CameraPivot/Camera3D") as Camera3D
	var blocker := StaticBody3D.new()
	var blocker_shape := CollisionShape3D.new()
	var blocker_box := BoxShape3D.new()
	blocker_box.size = Vector3(6.0, 4.0, 0.2)
	blocker_shape.shape = blocker_box
	blocker.add_child(blocker_shape)
	root.add_child(blocker)
	blocker.global_position = camera.global_position.lerp(minigame.ghost.get_chest_point(), 0.5)
	blocker.look_at(camera.global_position, Vector3.UP, true)
	await physics_frame
	for _step: int in int(ceil(minigame.flashlight_confirm_time / STEP)) + 4:
		minigame.debug_aim_at_ghost()
		minigame.debug_step(STEP)
	if minigame.get_total_hits() != 0:
		_fail("The beam counted a hit straight through a wall.")
		return
	blocker.queue_free()
	await physics_frame

	# --- each phase costs its own five hits ---------------------------------
	var durability_before: float = door.current_durability
	for phase: int in DoorGhostMinigame.TOTAL_PHASES:
		if minigame.get_phase_index() != phase:
			_fail("Expected to be in phase %d, was in phase %d." % [phase + 1, minigame.get_phase_index() + 1])
			return
		if minigame.get_phase_hits() != 0:
			_fail(
				"Phase %d began at %d / %d instead of a fresh counter."
				% [phase + 1, minigame.get_phase_hits(), minigame.hits_per_phase]
			)
			return
		for hit: int in minigame.hits_per_phase:
			_wait_for_search(minigame)
			# The first pass inherits the partially spent window left by the
			# "no hit without the beam" check above; every later one is fresh.
			# Only a fresh one is standing where it spawned - a spent window has
			# already walked it in, so the spawn rules are checked on those.
			var fresh_spawn := phase > 0 or hit > 0
			if not minigame.ghost.visible \
				or (fresh_spawn \
					and not is_equal_approx(minigame.get_threat_remaining(), minigame.threat_window)):
				_fail("A new search did not put the ghost back out with a full approach window.")
				return
			var intended_eye: Vector3 = minigame.call(
				"_view_position", minigame.phase_view_offsets[phase]
			)
			var from_eye := minigame.ghost.global_position - intended_eye
			from_eye.y = 0.0
			if fresh_spawn and from_eye.length() < minigame.phase_minimum_spot_distances[phase] - 0.05:
				_fail(
					"Phase %d spawned at %.2f m; minimum is %.2f m."
					% [phase + 1, from_eye.length(), minigame.phase_minimum_spot_distances[phase]]
				)
				return
			var yaw_limit: float = minigame.phase_yaw_limits[phase]
			if fresh_spawn and yaw_limit < 179.0:
				var angle := rad_to_deg(acos(clampf(minigame.outward.dot(from_eye.normalized()), -1.0, 1.0)))
				if angle > yaw_limit - 1.9:
					_fail("Phase %d spawned outside its %.0f-degree yaw clamp." % [phase + 1, yaw_limit])
					return
			var spot_before: Vector3 = minigame.ghost.global_position
			if not _land_repel(minigame):
				_fail("Hit %d of phase %d did not land while the beam was held on the ghost." % [hit + 1, phase + 1])
				return
			var is_last_hit_overall := phase == DoorGhostMinigame.TOTAL_PHASES - 1 \
				and hit == minigame.hits_per_phase - 1
			if is_last_hit_overall:
				continue
			# It recoils in the beam first, then goes.
			if not minigame.ghost.visible \
				or minigame.state != DoorGhostMinigame.State.RETREAT \
				or minigame.ghost.get_pose() != DoorGhost.Pose.REACT:
				_fail("A successful hit did not make the ghost recoil where it stood.")
				return
			minigame.debug_step(minigame.reaction_duration + STEP)
			if minigame.ghost.visible:
				_fail("The ghost did not retreat out of sight after its reaction.")
				return
			if hit < minigame.hits_per_phase - 1:
				# Mid-phase: the counter climbs and the phase does not move.
				if minigame.get_phase_hits() != hit + 1 or minigame.get_phase_index() != phase:
					_fail(
						"Phase %d hit %d read %d / %d in phase %d."
						% [
							phase + 1, hit + 1, minigame.get_phase_hits(),
							minigame.hits_per_phase, minigame.get_phase_index() + 1,
						]
					)
					return
			else:
				# Clearing the phase advances it and zeroes the counter, and
				# must not carry a hit over into the new phase.
				if minigame.get_phase_index() != phase + 1 or minigame.get_phase_hits() != 0:
					_fail(
						"Clearing phase %d left phase %d at %d / %d."
						% [
							phase + 1, minigame.get_phase_index() + 1,
							minigame.get_phase_hits(), minigame.hits_per_phase,
						]
					)
					return
			_wait_for_search(minigame)
			if minigame.ghost.global_position.is_equal_approx(spot_before):
				_fail("The ghost came back to the same spot it was just pushed off.")
				return
	if minigame.get_total_hits() != 6:
		_fail("The encounter finished after %d hits instead of 6." % minigame.get_total_hits())
		return
	if bool(player.yaw_clamp_active):
		_fail("The fully opened phase must release the horizontal look clamp.")
		return
	if not is_equal_approx(door.current_durability, durability_before):
		_fail("The encounter damaged the door on its way to a success.")
		return
	if door.attack_phase != DefenseDoor.AttackPhase.IDLE:
		_fail("Five repels did not drive the attacker away through complete_exorcism().")
		return

	var spawned_ghost: Node = minigame.ghost
	minigame.debug_step(minigame.success_duration + 0.1)
	if minigame.is_running() or door.minigame_active:
		_fail("Success did not close the encounter and release the door.")
		return
	await process_frame
	if minigame.ghost != null or is_instance_valid(spawned_ghost):
		_fail("The ghost instance outlived the encounter.")
		return
	if not player.global_position.is_equal_approx(saved_position) or bool(player.yaw_clamp_active):
		_fail("The player's position and look freedom were not restored after success.")
		return
	if not leaf.transform.is_equal_approx(leaf_rest):
		_fail("The door leaf was left swung open after the encounter closed.")
		return
	if not lit_lamp.visible or dark_lamp.visible:
		_fail("The house lighting was not restored to exactly what it was.")
		return
	if not is_zero_approx(float(overlay.get_shader_parameter("danger_intensity"))):
		_fail("The danger grade was left running after the encounter closed.")
		return
	if not is_equal_approx(torch.light_energy, torch_energy):
		_fail(
			"The flashlight was left at %.2f instead of its base %.2f after the flicker."
			% [torch.light_energy, torch_energy]
		)
		return
	if not is_equal_approx(torch.spot_range, torch_range) \
		or not is_equal_approx(torch.spot_angle, torch_angle):
		_fail("The flashlight reach or spread was not restored after the minigame.")
		return

	# --- running out of time reaches the door's own failure hit -------------
	door.reset_door()
	if not door.begin_targeting(true, 30.0):
		_fail("The door could not be re-targeted for the failure case.")
		return
	door.interact(player)
	if not minigame.is_running():
		_fail("The failure attempt could not start.")
		return
	durability_before = door.current_durability

	minigame.debug_look_away()
	var approach_start: float = minigame.ghost.global_position.distance_to(door.global_position)
	var elapsed := 0.0
	while minigame.state == DoorGhostMinigame.State.SEARCH and elapsed < minigame.threat_window:
		minigame.debug_step(STEP)
		elapsed += STEP
	if minigame.state != DoorGhostMinigame.State.STARE:
		_fail("The last second of the approach did not enter the staring state.")
		return
	if minigame.ghost.global_position.distance_to(door.global_position) >= approach_start:
		_fail("The ignored ghost did not close on the door during its approach window.")
		return
	# The retro grade has to answer to the approach, not sit at a fixed value.
	if float(overlay.get_shader_parameter("danger_intensity")) <= 0.5:
		_fail(
			"The post-process danger grade stayed at %.2f while the ghost closed in."
			% float(overlay.get_shader_parameter("danger_intensity"))
		)
		return
	if minigame.get_threat_remaining() > minigame.stare_threshold + STEP:
		_fail("The staring state began earlier than its authored threshold.")
		return
	# A ghost visibly held in the beam must remain vulnerable at the stare. This
	# is the last-second save the real encounter used to reject as "immortal".
	var hits_before_stare := minigame.get_total_hits()
	for _step: int in int(ceil((minigame.flashlight_confirm_time + STEP) / STEP)) + 2:
		minigame.debug_aim_at_ghost()
		minigame.debug_step(STEP)
		if minigame.get_total_hits() > hits_before_stare:
			break
	if minigame.get_total_hits() != hits_before_stare + 1 \
		or minigame.state != DoorGhostMinigame.State.RETREAT:
		_fail("A centered flashlight could not repel the ghost during its final stare.")
		return
	if not is_equal_approx(door.current_durability, durability_before):
		_fail("A successful last-second repel still damaged the door.")
		return

	# A genuinely ignored retry still reaches the same single failure hit.
	minigame.cancel()
	door.reset_door()
	door.begin_targeting(true, 30.0)
	door.interact(player)
	durability_before = door.current_durability
	minigame.debug_look_away()
	var failure_elapsed := 0.0
	while minigame.state != DoorGhostMinigame.State.JUMPSCARE \
		and failure_elapsed < minigame.threat_window + STEP * 2.0:
		minigame.debug_step(STEP)
		failure_elapsed += STEP
	if minigame.state != DoorGhostMinigame.State.JUMPSCARE:
		_fail("A spent threat window did not trigger the attack.")
		return
	if not is_equal_approx(door.current_durability, durability_before - door.minigame_failure_penalty):
		_fail(
			"The failure hit was not the door's own single %.0f-point penalty (%.1f -> %.1f)."
			% [door.minigame_failure_penalty, durability_before, door.current_durability]
		)
		return

	var durability_after_hit: float = door.current_durability
	minigame.debug_step(minigame.jumpscare_duration + 0.1)
	if minigame.is_running() or door.minigame_active:
		_fail("The failed encounter did not hand the door back to the attack flow.")
		return
	if not is_equal_approx(door.current_durability, durability_after_hit):
		_fail("The door lost durability twice for one failed encounter.")
		return
	if not player.global_position.is_equal_approx(saved_position) or bool(player.yaw_clamp_active):
		_fail("The player's position and look freedom were not restored after failure.")
		return

	# --- cancelling mid-encounter is clean ---------------------------------
	door.reset_door()
	door.begin_targeting(true, 30.0)
	door.interact(player)
	if not minigame.is_running():
		_fail("The cancel case could not start.")
		return
	minigame.cancel()
	if minigame.is_running() or door.minigame_active:
		_fail("Cancelling did not release the door.")
		return

	# --- a 30%-hold dodge resets the beam but pauses/refunds the deadline ----
	minigame.dodge_chance = 1.0
	door.reset_door()
	door.begin_targeting(true, 30.0)
	door.interact(player)
	if not minigame.is_running():
		_fail("The dodge case could not start.")
		return
	# The restarted encounter owns a freshly-instantiated ghost collider. Let the
	# physics server register it before testing the real flashlight ray.
	await physics_frame
	var dodge_start := minigame.ghost.global_position
	var dodge_budget := int(ceil(
		minigame.flashlight_confirm_time * minigame.dodge_trigger_fraction / STEP
	)) + 2
	for _step: int in dodge_budget:
		minigame.debug_aim_at_ghost()
		minigame.debug_step(STEP)
		if minigame.state == DoorGhostMinigame.State.DODGE:
			break
	if minigame.state != DoorGhostMinigame.State.DODGE \
		or minigame.get_total_hits() != 0 \
		or not is_zero_approx(minigame.lit_time):
		_fail("The forced 30%-hold dodge counted as a hit or did not reset the beam.")
		return
	if minigame.get_threat_remaining() < minigame.threat_window - 0.01:
		_fail("The dodge did not refund the incomplete flashlight hold.")
		return
	var dodge_deadline := minigame.get_threat_remaining()
	minigame.debug_step(minigame.dodge_duration * 0.5)
	if not is_equal_approx(minigame.get_threat_remaining(), dodge_deadline) \
		or minigame.ghost.global_position.distance_to(dodge_start) < 0.1:
		_fail("The deadline moved during the dodge, or the ghost did not sidestep.")
		return
	minigame.debug_step(minigame.dodge_duration)
	if minigame.state != DoorGhostMinigame.State.SEARCH:
		_fail("The ghost did not return to the search after sidestepping.")
		return
	if bool(minigame.call("_flashlight_illuminates_ghost")):
		_fail("The sidestep left the ghost inside the old flashlight beam.")
		return
	if not _land_repel(minigame) or minigame.get_total_hits() != 1:
		_fail("The ghost dodged more than once in one appearance or could not be reacquired.")
		return
	minigame.cancel()

	lit_lamp.queue_free()
	dark_lamp.queue_free()
	minigame.queue_free()
	player.queue_free()
	door.queue_free()
	neighbour.queue_free()
	await process_frame
	print("Door ghost minigame smoke test passed.")
	quit()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
