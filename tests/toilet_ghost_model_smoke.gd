extends SceneTree

## Toilet Ghost *model* smoke test (Sprint 3). Asset-only: it checks that the
## model imports, is built from real 3D geometry, and lands at the right
## scale/orientation/pivot for the player. It deliberately asserts nothing
## about gameplay - the ghost's spawn/detection behaviour is not this scene's
## concern.

const MODEL_SCENE := "res://assets/ghosts/toilet_ghost/toilet_ghost_model.tscn"
const DEV_SCENE := "res://tests/toilet_ghost_model_devscene.tscn"

# player.gd: standing_height 1.75 (capsule centred on the origin) + camera
# pivot 0.62 -> the player's eye is 1.495 m above the floor.
const PLAYER_EYE := 1.495


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := load(MODEL_SCENE) as PackedScene
	if packed == null:
		push_error("Toilet ghost model scene failed to load.")
		quit(1)
		return
	var model := packed.instantiate()
	root.add_child(model)
	await physics_frame

	var meshes: Array[MeshInstance3D] = []
	var stack: Array[Node] = [model]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D:
			meshes.append(node)
		stack.append_array(node.get_children())
	if meshes.is_empty():
		push_error("Model scene contains no MeshInstance3D - nothing was imported.")
		quit(1)
		return

	# --- Real 3D geometry, not a flat billboard/sprite substitute. ---
	var total_faces := 0
	var aabb := AABB()
	var first := true
	for mi in meshes:
		var mesh := mi.mesh
		if mesh == null:
			push_error("MeshInstance3D '%s' has no mesh resource." % mi.name)
			quit(1)
			return
		for s in mesh.get_surface_count():
			if mesh.surface_get_material(s) == null:
				push_error("Surface %d of '%s' has no material." % [s, mi.name])
				quit(1)
				return
			var arrays := mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			total_faces += indices.size() / 3
			if verts.size() < 8:
				push_error("Surface %d of '%s' is too sparse to be 3D." % [s, mi.name])
				quit(1)
				return
		var world := mi.global_transform * mi.get_aabb()
		aabb = world if first else aabb.merge(world)
		first = false

	if total_faces < 500:
		push_error("Model has only %d triangles - that is not a 3D apparition." % total_faces)
		quit(1)
		return

	# A billboard/plane would be flat on one axis. Require real depth.
	if aabb.size.z < 0.20 or aabb.size.x < 0.20:
		push_error("Model is flat (size %s); Sprint 3 requires a 3D model." % aabb.size)
		quit(1)
		return

	# --- Scale: readable next to a 1.75 m player, neither tiny nor huge. ---
	if aabb.size.y < 1.2 or aabb.size.y > 2.2:
		push_error("Model height %.2f m is not human-scale." % aabb.size.y)
		quit(1)
		return

	# --- Pivot/origin: on the floor, so gameplay can place it without an
	# awkward offset, with the body above and no geometry sunk below.
	if aabb.position.y < -0.05:
		push_error("Model extends %.2f m below its own origin." % aabb.position.y)
		quit(1)
		return
	if aabb.position.y > 0.45:
		push_error("Model floats %.2f m above its origin - pivot is wrong." % aabb.position.y)
		quit(1)
		return
	if absf(aabb.get_center().x) > 0.25 or absf(aabb.get_center().z) > 0.25:
		push_error("Model is not centred on its origin (centre %s)." % aabb.get_center())
		quit(1)
		return

	# --- The face must be at the player's eye level to be found and read. ---
	var face: Variant = _material_bounds(meshes, "GhostEyeWhite")
	if face == null:
		push_error("Could not find the eye material - the face is missing.")
		quit(1)
		return
	var eyes: AABB = face
	if absf(eyes.get_center().y - PLAYER_EYE) > 0.30:
		push_error("Eyes sit at %.2f m; the player's eye height is %.2f m."
			% [eyes.get_center().y, PLAYER_EYE])
		quit(1)
		return

	# --- Orientation: Godot's forward is -Z, so the face must be on -Z. ---
	if eyes.get_center().z > 0.0:
		push_error("Eyes are on +Z: the model faces backwards for Godot.")
		quit(1)
		return
	var hair: Variant = _material_bounds(meshes, "GhostHair")
	if hair != null and (hair as AABB).get_center().z < eyes.get_center().z:
		push_error("Hair is in front of the eyes - the head is inside out.")
		quit(1)
		return

	# --- The dev inspection scene must still open. ---
	var dev := load(DEV_SCENE) as PackedScene
	if dev == null or dev.instantiate() == null:
		push_error("Toilet ghost model dev scene failed to load.")
		quit(1)
		return

	print("Toilet ghost model smoke test passed: %d tris, %.2f m tall, eyes at %.2f m, faces -Z."
		% [total_faces, aabb.size.y, eyes.get_center().y])
	quit()


## World-space bounds of just the surfaces using the named material.
func _material_bounds(meshes: Array[MeshInstance3D], material_name: String):
	var out := AABB()
	var found := false
	for mi in meshes:
		var mesh := mi.mesh
		for s in mesh.get_surface_count():
			var mat := mesh.surface_get_material(s)
			if mat == null or not mat.resource_name.begins_with(material_name):
				continue
			var verts: PackedVector3Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for v in verts:
				var w: Vector3 = mi.global_transform * v
				if not found:
					out = AABB(w, Vector3.ZERO)
					found = true
				else:
					out = out.expand(w)
	return out if found else null
