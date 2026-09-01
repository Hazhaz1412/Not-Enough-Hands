extends SceneTree

## Offline texture bake for assets/ghosts/model_hunter/Meshy_AI_Midnight_Grin_biped.
##
## Run it, do not import it:
##     godot --headless --script tools/bake_midnight_grin_textures.gd
##     godot --headless --script tools/bake_midnight_grin_textures.gd -- debug
##
## It writes the PNGs beside the model. Godot does not notice a source file
## rewritten behind its back, so reimport afterwards or the game keeps using
## the previous bake:
##
##     godot --headless --editor --quit
##
## ## Why this exists
##
## The Meshy import is one MeshInstance3D with **one** surface, **one**
## StandardMaterial3D, **one** connected component, no vertex colours and no
## albedo/ORM texture of any kind - the only map that ships with it is a
## 2048 normal map of wall-to-wall noise. Skin, eyes, teeth, hair, hoodie,
## jeans and the knife are all fused into that single surface, so there is no
## material slot to tune per part and no island layout to paint into.
##
## The one attribute that identifies a part *and* survives skinning is the UV,
## so the parts have to be resolved into UV space once, offline, and shipped as
## a normal albedo + ORM pair that a plain StandardMaterial3D can use at
## runtime. That is what this does. Nothing here runs during gameplay.
##
## ## How a part is identified
##
## Two signals, both measured off the geometry rather than guessed at:
##
## **Height bands.** Shoes, jeans, hoodie and head are cleanly stacked on this
## model (measured: the hoodie hem is at 0.855 m and the jaw at 1.395 m), so a
## band gives each its own base colour and roughness.
##
## **Baked ambient occlusion.** Bands cannot tell the hair hanging over the
## face from the face behind it - and on this mesh no curvature measure can
## either, because the triangulation is uniformly lumpy (normal divergence
## reads the same on a cheek as on a strand). Occlusion can: a dense mass of
## hair strands shadows itself almost completely, an eye socket and the inside
## of a mouth are deep concavities, and a forehead is wide open. So AO is ray
## traced against the model's own collision hull and used both as the AO map
## and as a strong albedo multiplier. That is what turns one skin-coloured
## head into a pale face with black hair, dark sockets and a dark mouth,
## without ever having to decide which vertex is a hair.

const FBX := "res://assets/ghosts/model_hunter/Meshy_AI_Midnight_Grin_biped/Meshy_AI_Midnight_Grin_biped_Meshy_AI_Meshy_Merged_Animations.fbx"
const OUT_DIR := "res://assets/ghosts/model_hunter/Meshy_AI_Midnight_Grin_biped"
const ALBEDO_PATH := OUT_DIR + "/midnight_grin_albedo.png"
const ORM_PATH := OUT_DIR + "/midnight_grin_orm.png"

const TEXTURE_SIZE := 1024
## Texels of edge bleed painted outward, so a UV seam never samples background.
const DILATE_PASSES := 6

## Bands, plus the two things a band cannot reach: bare hands below the hoodie
## hem, and the knife out past the character's own silhouette. Hair, sockets,
## mouth interior and fabric folds are not regions - occlusion darkens them.
enum Region { HOODIE, JEANS, SHOE, SKIN, HAIR, KNIFE }

## Hair is the one part occlusion alone cannot find: a strand hanging in front
## of the face has open air in front of it, so it reads as exposed as the cheek
## behind it. Thickness does find it - a ray straight into a 3 mm strand comes
## out the other side almost immediately, while a ray into a cheek travels the
## width of the skull. One extra ray per vertex, and it is exact.
const THICKNESS_PROBE := 0.06
const THICKNESS_THRESHOLD := 0.011

## Ambient occlusion sampling. The ray is short on purpose: it asks "is this
## buried inside the hair / in a socket", not "how big is the room".
const AO_RAYS := 14
const AO_DISTANCE := 0.075
## How hard AO drives the albedo down. High, because it is doing the work of
## the missing hair and cavity masks.
const AO_ALBEDO_STRENGTH := 0.92
const AO_FLOOR := 0.06

## Height bands, in metres up the 1.70 m model.
const SHOE_TOP := 0.115
const JEANS_TOP := 0.855
const HEAD_BOTTOM := 1.395
## The face is the front of the head below the crown; the scalp above that line
## and the whole back of the head are hair, however thick the shell is there.
const CROWN_Y := 1.605
const FACE_Z := 0.0

## Palette. Every value is the target from the brief, converted from hex.
const COLORS := {
	Region.HOODIE: Color("b8b5af"),
	Region.JEANS: Color("292a29"),
	Region.SHOE: Color("171818"),
	Region.SKIN: Color("cdcac6"),
	Region.HAIR: Color("090a0b"),
	Region.KNIFE: Color("686c6c"),
}
## Roughness per region, and which regions are metal.
const ROUGHNESS := {
	Region.HOODIE: 0.87,
	Region.JEANS: 0.78,
	Region.SHOE: 0.72,
	Region.SKIN: 0.76,
	Region.HAIR: 0.42,
	Region.KNIFE: 0.24,
}
## Occluded skin is wet skin: sockets, the mouth and the creases either side of
## it come out glossier than the dry cheek around them.
const WET_ROUGHNESS := 0.22
const METALLIC := {Region.KNIFE: 1.0}

## Debug palette used with `-- debug`, so the classification can be looked at
## directly instead of inferred from the finished skin.
const DEBUG_COLORS := {
	Region.HOODIE: Color(1, 0, 1),
	Region.JEANS: Color(0.1, 0.3, 1),
	Region.SHOE: Color(0, 0, 0.35),
	Region.SKIN: Color(1, 0.75, 0.55),
	Region.HAIR: Color(0, 0.9, 0.2),
	Region.KNIFE: Color(0, 1, 1),
}

var _debug := false
var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	_debug = "debug" in OS.get_cmdline_user_args()
	_run.call_deferred()


func _run() -> void:
	_rng.seed = 20260829
	var scene := (load(FBX) as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	var mesh_node := scene.find_child("char1", true, false) as MeshInstance3D
	var arrays := (mesh_node.mesh as ArrayMesh).surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	print("mesh: %d vertices, %d triangles" % [verts.size(), indices.size() / 3])

	var probe := await _bake_probes(mesh_node, verts, normals)
	var occlusion: PackedFloat32Array = probe["occlusion"]
	var regions := _classify(verts, probe["thickness"])
	var tally := {}
	for region: int in regions:
		tally[region] = int(tally.get(region, 0)) + 1
	for region: int in Region.values():
		print("  %-7s %6d verts" % [Region.keys()[region], int(tally.get(region, 0))])

	var albedo := Image.create(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	var orm := Image.create(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	albedo.fill(Color(0, 0, 0, 0))
	orm.fill(Color(0, 0, 0, 0))
	_rasterize(albedo, orm, verts, uvs, indices, regions, occlusion)
	for _pass: int in DILATE_PASSES:
		_dilate(albedo)
		_dilate(orm)
	albedo.convert(Image.FORMAT_RGB8)
	orm.convert(Image.FORMAT_RGB8)

	if _debug:
		DirAccess.make_dir_recursive_absolute("user://grin_bake")
		albedo.save_png("user://grin_bake/debug_regions.png")
		print("wrote debug regions to user://grin_bake/debug_regions.png")
	else:
		albedo.save_png(ProjectSettings.globalize_path(ALBEDO_PATH))
		orm.save_png(ProjectSettings.globalize_path(ORM_PATH))
		print("wrote %s and %s" % [ALBEDO_PATH, ORM_PATH])
	quit()


## Ray traces the model against itself. Uses the physics server's own BVH via
## a trimesh collider rather than a hand-rolled acceleration structure - the
## project already builds trimesh colliders from render meshes this way.
func _bake_probes(
	mesh_node: MeshInstance3D,
	verts: PackedVector3Array,
	normals: PackedVector3Array
) -> Dictionary:
	var body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(mesh_node.mesh.get_faces())
	# Both probes look at the model from the inside as often as the outside:
	# the thickness ray leaves through a hair strand's far wall, and an
	# occlusion ray inside a socket sees the surrounding surface from behind.
	# Without this the trimesh reports neither and everything reads as solid
	# and unoccluded.
	shape.backface_collision = true
	collider.shape = shape
	body.add_child(collider)
	root.add_child(body)
	await physics_frame

	var space := root.get_world_3d().direct_space_state
	var exclude: Array[RID] = []
	var occlusion := PackedFloat32Array()
	var thickness := PackedFloat32Array()
	occlusion.resize(verts.size())
	thickness.resize(verts.size())
	for i: int in verts.size():
		var normal := normals[i]
		# Start just off the surface so a ray cannot hit its own triangle.
		var origin := verts[i] + normal * 0.0015
		var hits := 0
		for ray: int in AO_RAYS:
			var direction := _hemisphere_direction(normal, ray)
			var query := PhysicsRayQueryParameters3D.create(
				origin, origin + direction * AO_DISTANCE, 0xFFFFFFFF, exclude
			)
			if space.intersect_ray(query):
				hits += 1
		occlusion[i] = 1.0 - float(hits) / float(AO_RAYS)

		var inward := PhysicsRayQueryParameters3D.create(
			verts[i] - normal * 0.0015,
			verts[i] - normal * THICKNESS_PROBE,
			0xFFFFFFFF,
			exclude
		)
		var behind := space.intersect_ray(inward)
		thickness[i] = (
			verts[i].distance_to(behind["position"]) if behind else THICKNESS_PROBE
		)
	body.queue_free()
	return {"occlusion": occlusion, "thickness": thickness}


## Deterministic low-discrepancy hemisphere sample around `normal`, so two
## bakes of the same mesh produce byte-identical maps.
func _hemisphere_direction(normal: Vector3, index: int) -> Vector3:
	var offset := float(index) + 0.5
	var cosine := 1.0 - offset / float(AO_RAYS)
	var sine := sqrt(maxf(1.0 - cosine * cosine, 0.0))
	var angle := offset * 2.399963
	var tangent := normal.cross(Vector3.UP)
	if tangent.length_squared() < 0.001:
		tangent = normal.cross(Vector3.RIGHT)
	tangent = tangent.normalized()
	var bitangent := normal.cross(tangent)
	return (tangent * (cos(angle) * sine) + bitangent * (sin(angle) * sine) + normal * cosine).normalized()


func _classify(verts: PackedVector3Array, thickness: PackedFloat32Array) -> PackedInt32Array:
	var regions := PackedInt32Array()
	regions.resize(verts.size())
	for i: int in verts.size():
		regions[i] = _classify_vertex(verts[i], thickness[i])
	return regions


func _classify_vertex(v: Vector3, thickness: float) -> int:
	# The blade is the only thing that reaches past the character's silhouette
	# at hand height, which is what makes it separable on a mesh with no parts.
	# Checked first, because a blade is thin enough to read as a hair strand.
	if _is_knife(v):
		return Region.KNIFE
	if v.y < SHOE_TOP:
		return Region.SHOE
	if v.y < JEANS_TOP:
		return Region.JEANS
	# Anything paper-thin from the shoulders up is a hair strand - including
	# the lengths hanging across the face, which is the whole point.
	if thickness < THICKNESS_THRESHOLD and v.y > 1.02:
		return Region.HAIR
	if v.y >= HEAD_BOTTOM:
		# The scalp and the back of the head are a solid shell, not strands, so
		# thickness cannot reach them - but they are still hair.
		if v.y >= CROWN_Y or v.z < FACE_Z:
			return Region.HAIR
		return Region.SKIN
	return _hands_or_hoodie(v)


## Bare hands are skin, and they are the only skin below the head.
func _hands_or_hoodie(v: Vector3) -> int:
	if absf(v.x) > 0.40 and v.y < 1.02:
		return Region.SKIN
	return Region.HOODIE


func _is_knife(v: Vector3) -> bool:
	return v.y > 0.78 and v.y < 1.03 and v.x < -0.44 and v.x > -0.58 and v.z > 0.06


## Paints each triangle's texels with its own vertices' region, picking the
## nearest vertex by barycentric weight so a boundary lands on the edge
## between two parts rather than smearing a blend across both.
func _rasterize(
	albedo: Image,
	orm: Image,
	verts: PackedVector3Array,
	uvs: PackedVector2Array,
	indices: PackedInt32Array,
	regions: PackedInt32Array,
	occlusion: PackedFloat32Array
) -> void:
	var palette: Dictionary = DEBUG_COLORS if _debug else COLORS
	var size := float(TEXTURE_SIZE)
	for t: int in indices.size() / 3:
		var ia := indices[t * 3]
		var ib := indices[t * 3 + 1]
		var ic := indices[t * 3 + 2]
		var a := uvs[ia] * size
		var b := uvs[ib] * size
		var c := uvs[ic] * size
		var min_x := maxi(int(floor(minf(a.x, minf(b.x, c.x)))) - 1, 0)
		var max_x := mini(int(ceil(maxf(a.x, maxf(b.x, c.x)))) + 1, TEXTURE_SIZE - 1)
		var min_y := maxi(int(floor(minf(a.y, minf(b.y, c.y)))) - 1, 0)
		var max_y := mini(int(ceil(maxf(a.y, maxf(b.y, c.y)))) + 1, TEXTURE_SIZE - 1)
		var area := (b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y)
		if absf(area) < 0.000001:
			continue
		for py: int in range(min_y, max_y + 1):
			for px: int in range(min_x, max_x + 1):
				var point := Vector2(px + 0.5, py + 0.5)
				var w0 := ((b.x - point.x) * (c.y - point.y) - (c.x - point.x) * (b.y - point.y)) / area
				var w1 := ((c.x - point.x) * (a.y - point.y) - (a.x - point.x) * (c.y - point.y)) / area
				var w2 := 1.0 - w0 - w1
				if w0 < -0.002 or w1 < -0.002 or w2 < -0.002:
					continue
				var region := regions[ia]
				if w1 >= w0 and w1 >= w2:
					region = regions[ib]
				elif w2 >= w0 and w2 >= w1:
					region = regions[ic]
				var position := verts[ia] * w0 + verts[ib] * w1 + verts[ic] * w2
				var ao := clampf(
					occlusion[ia] * w0 + occlusion[ib] * w1 + occlusion[ic] * w2, 0.0, 1.0
				)
				var base: Color = palette[region]
				if _debug:
					albedo.set_pixel(px, py, base)
				else:
					albedo.set_pixel(px, py, _shade(base, region, position, ao))
				var roughness := float(ROUGHNESS[region])
				if region == Region.SKIN:
					roughness = lerpf(WET_ROUGHNESS, roughness, ao)
				orm.set_pixel(px, py, Color(
					maxf(ao, AO_FLOOR),
					roughness,
					float(METALLIC.get(region, 0.0)),
					1.0
				))


## Per-texel variation, blood, and the occlusion multiply. Deterministic:
## the same mesh always bakes to the same maps.
func _shade(base: Color, region: int, position: Vector3, ao: float) -> Color:
	var grain := _noise(position * 61.0) - 0.5
	var patch := _noise(position * 7.3)
	var color := base

	match region:
		Region.SKIN:
			# Blotching between the two skin variations in the brief.
			color = Color("a9a6a3").lerp(Color("d8d5d0"), clampf(patch * 1.25, 0.0, 1.0))
			# Blood around the mouth, thinning outward, and never a flat field.
			var mouth := clampf(1.0 - absf(position.y - 1.445) / 0.075, 0.0, 1.0)
			mouth *= clampf(1.0 - absf(position.x) / 0.075, 0.0, 1.0)
			mouth *= clampf(_noise(position * 23.0) * 1.8 - 0.25, 0.0, 1.0)
			color = color.lerp(Color("7d2022"), mouth * 0.8)
			# Dried staining lower down the chin and jaw.
			var dried := clampf(1.0 - absf(position.y - 1.415) / 0.06, 0.0, 1.0)
			dried *= clampf(_noise(position * 13.0) * 1.7 - 0.55, 0.0, 1.0)
			color = color.lerp(Color("4a1718"), dried * 0.7)
		Region.HAIR:
			color = Color("090a0b").lerp(Color("202326"), clampf(patch * 1.5, 0.0, 1.0) * 0.7)
			color = color.lerp(Color("111416"), clampf(1.0 - patch, 0.0, 1.0) * 0.5)
		Region.HOODIE:
			color = Color("96938d").lerp(Color("d0cdc5"), clampf(patch * 1.3, 0.0, 1.0))
			var stain := clampf(_noise(position * 11.0 + Vector3(31.0, 0.0, 0.0)) * 1.9 - 1.0, 0.0, 1.0)
			color = color.lerp(Color("5a2423"), stain * 0.85)
			var old_stain := clampf(_noise(position * 4.5 + Vector3(0.0, 57.0, 0.0)) * 1.6 - 0.9, 0.0, 1.0)
			color = color.lerp(Color("70413a"), old_stain * 0.6)
			var deep := clampf(_noise(position * 17.0 + Vector3(0.0, 0.0, 12.0)) * 2.0 - 1.35, 0.0, 1.0)
			color = color.lerp(Color("391719"), deep * 0.7)
		Region.JEANS:
			color = Color("292a29").lerp(Color("555653"), clampf(patch * 1.5 - 0.3, 0.0, 1.0))
			color = color.lerp(Color("171818"), clampf(0.55 - patch, 0.0, 1.0))
		Region.SHOE:
			color = Color("171818").lerp(Color("3a3b39"), clampf(patch * 0.9, 0.0, 1.0))
		Region.KNIFE:
			# Handle below the fist, blade above it.
			if position.y < 0.86:
				color = Color("292421")
			else:
				color = Color("686c6c").lerp(Color("353838"), clampf(patch * 1.4, 0.0, 1.0))
			var gore := clampf(_noise(position * 29.0) * 1.9 - 1.15, 0.0, 1.0)
			color = color.lerp(Color("4b1718"), gore)
			color = color.lerp(Color("761c1e"), clampf(gore - 0.55, 0.0, 1.0) * 0.8)

	# Occlusion does the work the missing hair/socket/mouth masks would have
	# done: the hair mass, the eye sockets and the mouth interior are the only
	# places on this model that are this deeply buried.
	var shade := lerpf(1.0 - AO_ALBEDO_STRENGTH, 1.0, ao)
	color = Color(color.r * shade, color.g * shade, color.b * shade, 1.0)
	return Color(
		clampf(color.r + grain * 0.03, 0.0, 1.0),
		clampf(color.g + grain * 0.03, 0.0, 1.0),
		clampf(color.b + grain * 0.03, 0.0, 1.0),
		1.0
	)


## Smooth value noise. The earlier plain hash produced per-texel static, which
## reads as sensor noise rather than as stains; interpolating between lattice
## corners gives blotches with an actual size to them.
func _noise(p: Vector3) -> float:
	var cell := p.floor()
	var f := p - cell
	f = f * f * (Vector3.ONE * 3.0 - f * 2.0)
	var result := 0.0
	for corner: int in 8:
		var offset := Vector3(float(corner & 1), float((corner >> 1) & 1), float((corner >> 2) & 1))
		var weight := absf(1.0 - offset.x - f.x + 2.0 * offset.x * f.x)
		weight *= absf(1.0 - offset.y - f.y + 2.0 * offset.y * f.y)
		weight *= absf(1.0 - offset.z - f.z + 2.0 * offset.z * f.z)
		result += _hash(cell + offset) * weight
	return clampf(result, 0.0, 1.0)


func _hash(p: Vector3) -> float:
	var value := sin(p.x * 12.9898 + p.y * 78.233 + p.z * 37.719) * 43758.5453
	return value - floor(value)


## Grows the painted area outward into the empty margin, so bilinear filtering
## at a UV seam picks up neighbouring skin instead of transparent background.
func _dilate(image: Image) -> void:
	var source := image.duplicate() as Image
	for y: int in TEXTURE_SIZE:
		for x: int in TEXTURE_SIZE:
			if source.get_pixel(x, y).a > 0.0:
				continue
			var sum := Color(0, 0, 0, 0)
			var count := 0
			for dy: int in 3:
				for dx: int in 3:
					var nx := x + dx - 1
					var ny := y + dy - 1
					if nx < 0 or ny < 0 or nx >= TEXTURE_SIZE or ny >= TEXTURE_SIZE:
						continue
					var sample := source.get_pixel(nx, ny)
					if sample.a > 0.0:
						sum += sample
						count += 1
			if count > 0:
				image.set_pixel(x, y, Color(sum.r / count, sum.g / count, sum.b / count, 1.0))
