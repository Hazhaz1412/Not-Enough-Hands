"""Builds the Toilet Ghost 3D model and exports it as GLB.

Run:  blender --background --python build_toilet_ghost.py -- <out.glb>

Geometry is authored procedurally (seeded) so the model can be regenerated
and tweaked deterministically. Blender is Z-up / -Y-forward; the glTF
exporter converts that to Godot's Y-up / -Z-forward automatically.

Scale reference (player/player.gd): standing_height 1.75, capsule centred on
the node origin, camera pivot +0.62 -> player eye height = 1.75/2 + 0.62 =
1.495 m above the floor. The ghost's face sits at ~1.55 m so it meets the
player's gaze slightly from above. Model origin (0,0,0) is on the floor; the
wisps stop ~0.1 m short of it so the ghost reads as floating.
"""

import math
import random
import sys

import bpy
import bmesh
from mathutils import Matrix, Quaternion, Vector

SEED = 20
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT_GLB = argv[0] if argv else "/tmp/toilet_ghost.glb"

rng = random.Random(SEED)

# --- Palette sampled directly from assets/images/anh-ma-kinh-di-20.jpg -------
# pale skin mean (84,87,119) / highlight (111,119,155) / shadow (36,34,51) /
# dark surround (2,2,6). Albedo is brightened from the photographed (very
# low-key) values because albedo is what scene light multiplies against.
SKIN = (150, 158, 188)
EYE_WHITE = (215, 219, 231)
IRIS = (6, 6, 11)
TEETH = (176, 173, 156)
MAW = (3, 3, 6)
HAIR = (5, 5, 9)
SHROUD = (13, 14, 22)
WISP = (26, 28, 42)


def srgb_to_linear(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def lin(rgb, alpha=1.0):
    return (srgb_to_linear(rgb[0]), srgb_to_linear(rgb[1]), srgb_to_linear(rgb[2]), alpha)


def make_material(name, color, roughness=0.7, metallic=0.0, emission=None,
                  emission_strength=1.0, alpha=1.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = lin(color)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Alpha"].default_value = alpha
    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = lin(emission)
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    if alpha < 1.0:
        for attr, value in (("blend_method", "BLEND"),
                            ("surface_render_method", "BLENDED")):
            try:
                setattr(mat, attr, value)
            except (AttributeError, TypeError):
                pass
    return mat


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.objects):
        for item in list(block):
            if item.users == 0:
                block.remove(item)


def new_mesh_object(name, bm):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def shade_smooth(obj):
    for poly in obj.data.polygons:
        poly.use_smooth = True


def assign_material(obj, mat):
    obj.data.materials.clear()
    obj.data.materials.append(mat)


def apply_transform(obj):
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    obj.select_set(False)


def jitter_vertices(obj, amount, seed, axis_scale=(1.0, 1.0, 1.0)):
    jr = random.Random(seed)
    for v in obj.data.vertices:
        v.co.x += jr.uniform(-amount, amount) * axis_scale[0]
        v.co.y += jr.uniform(-amount, amount) * axis_scale[1]
        v.co.z += jr.uniform(-amount, amount) * axis_scale[2]


def uv_sphere(name, radius, location=(0, 0, 0), scale=(1, 1, 1), segments=32, rings=16):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings,
                                         radius=radius, location=location)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = scale
    return obj


def boolean_difference(target, cutter):
    mod = target.modifiers.new("cut", "BOOLEAN")
    mod.object = cutter
    mod.operation = "DIFFERENCE"
    mod.solver = "EXACT"
    bpy.context.view_layer.objects.active = target
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(cutter, do_unlink=True)


def ellipse_loft(name, profile, segs=28, jitter=0.0, jitter_seed=0):
    """Stacked elliptical rings -> a shaped solid. profile: (z, rx, ry)."""
    jr = random.Random(jitter_seed)
    bm = bmesh.new()
    rings = []
    for z, rx, ry in profile:
        ring = []
        for k in range(segs):
            a = 2.0 * math.pi * k / segs
            f = 1.0 + jr.uniform(-jitter, jitter)
            ring.append(bm.verts.new((math.cos(a) * rx * f, math.sin(a) * ry * f, z)))
        rings.append(ring)
    bm.verts.ensure_lookup_table()
    for i in range(len(rings) - 1):
        a, b = rings[i], rings[i + 1]
        for k in range(segs):
            k2 = (k + 1) % segs
            bm.faces.new((a[k], a[k2], b[k2], b[k]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bm.normal_update()
    return new_mesh_object(name, bm)


def make_tube(name, points, radii, segs=18, cap_start=True, cap_end=True,
              jitter=0.0, jitter_seed=0):
    """Loft a closed tube along a polyline, with per-vertex radial jitter."""
    jr = random.Random(jitter_seed)
    pts = [Vector(p) for p in points]

    tangents = []
    for i in range(len(pts)):
        if i == 0:
            t = pts[1] - pts[0]
        elif i == len(pts) - 1:
            t = pts[-1] - pts[-2]
        else:
            t = pts[i + 1] - pts[i - 1]
        tangents.append(t.normalized())

    # Parallel-transport a frame along the path so the rings do not twist.
    up = Vector((0.0, 1.0, 0.0))
    if abs(tangents[0].dot(up)) > 0.9:
        up = Vector((1.0, 0.0, 0.0))
    side = tangents[0].cross(up).normalized()
    frames = [(side, tangents[0].cross(side).normalized())]
    for i in range(1, len(pts)):
        q = tangents[i - 1].rotation_difference(tangents[i])
        side = (q @ frames[-1][0]).normalized()
        frames.append((side, tangents[i].cross(side).normalized()))

    bm = bmesh.new()
    rings = []
    for i, (centre, radius) in enumerate(zip(pts, radii)):
        s, u = frames[i]
        ring = []
        for k in range(segs):
            a = 2.0 * math.pi * k / segs
            r = radius * (1.0 + jr.uniform(-jitter, jitter))
            ring.append(bm.verts.new(centre + (math.cos(a) * s + math.sin(a) * u) * r))
        rings.append(ring)
    bm.verts.ensure_lookup_table()

    for i in range(len(rings) - 1):
        a, b = rings[i], rings[i + 1]
        for k in range(segs):
            k2 = (k + 1) % segs
            bm.faces.new((a[k], a[k2], b[k2], b[k]))
    if cap_start:
        bm.faces.new(list(reversed(rings[0])))
    if cap_end:
        bm.faces.new(rings[-1])

    bm.normal_update()
    return new_mesh_object(name, bm)


# ---------------------------------------------------------------------------
clear_scene()

mat_skin = make_material("GhostSkin", SKIN, roughness=0.60,
                         emission=(34, 38, 52), emission_strength=1.0)
mat_eye = make_material("GhostEyeWhite", EYE_WHITE, roughness=0.22,
                        emission=(86, 90, 104), emission_strength=1.0)
mat_iris = make_material("GhostIris", IRIS, roughness=0.12)
mat_teeth = make_material("GhostTeeth", TEETH, roughness=0.48,
                          emission=(30, 29, 24), emission_strength=1.0)
mat_maw = make_material("GhostMaw", MAW, roughness=0.95)
mat_hair = make_material("GhostHair", HAIR, roughness=0.96)
mat_shroud = make_material("GhostShroud", SHROUD, roughness=0.93)
mat_wisp = make_material("GhostWisp", WISP, roughness=0.9, alpha=0.42)

HEAD_Z = 1.55
# The reference face is rolled almost onto its side. Roll happens about the
# forward axis, so the face keeps pointing at the viewer while the features
# rotate in-plane - exactly the reference's read. The chin is lifted (-X) to
# keep the open maw facing the player rather than tucking it behind the neck.
HEAD_ROT = (Matrix.Rotation(math.radians(52.0), 4, "Y")
            @ Matrix.Rotation(math.radians(-7.0), 4, "Z")
            @ Matrix.Rotation(math.radians(-14.0), 4, "X"))

head_parts = []

# --- Gaunt skull: tapering jaw, wide cheekbones, narrow crown --------------
skull_profile = [
    (-0.172, 0.030, 0.040),   # chin
    (-0.148, 0.060, 0.072),
    (-0.118, 0.084, 0.093),   # jaw
    (-0.082, 0.101, 0.107),
    (-0.040, 0.114, 0.118),
    (0.000, 0.121, 0.125),    # cheekbones, widest
    (0.046, 0.122, 0.127),
    (0.092, 0.114, 0.119),
    (0.132, 0.093, 0.100),
    (0.164, 0.049, 0.057),    # crown
]
head = ellipse_loft("Head", skull_profile, segs=30, jitter=0.018, jitter_seed=11)
# Flatten the face plane and break the symmetry so it never reads as a ball.
for v in head.data.vertices:
    if v.co.y < 0.0:
        v.co.y *= 0.86
    v.co.x *= 1.0 + 0.05 * (1.0 if v.co.x > 0 else -1.0)

# --- The maw: the single most important feature. Enormous, deep, gaping ----
# Wide and stretched rather than round (a circular hole reads as a lamprey,
# not a screaming face), tilted diagonally like the reference's grin, and
# widened again at one corner so it is never symmetrical.
MOUTH_C = Vector((0.008, -0.030, -0.072))
MOUTH_TILT = math.radians(19.0)
cutter = uv_sphere("MouthCutter", 1.0, location=MOUTH_C,
                   scale=(0.101, 0.115, 0.045), segments=30, rings=18)
cutter.rotation_euler = (0.0, MOUTH_TILT, 0.0)
apply_transform(cutter)
boolean_difference(head, cutter)

corner = uv_sphere("MouthCorner", 1.0,
                   location=MOUTH_C + Vector((-0.055, 0.004, -0.019)),
                   scale=(0.052, 0.104, 0.030), segments=22, rings=14)
corner.rotation_euler = (0.0, math.radians(38.0), 0.0)
apply_transform(corner)
boolean_difference(head, corner)

# Eye sockets carved as real hollows, so the eyeballs sit *in* the skull.
for sx, sr in ((0.063, 0.052), (-0.060, 0.047)):
    soc = uv_sphere(f"SocketCut{sx}", 1.0,
                    location=(sx, -0.062, 0.040),
                    scale=(sr, sr * 0.85, sr), segments=22, rings=14)
    apply_transform(soc)
    boolean_difference(head, soc)

assign_material(head, mat_skin)  # after booleans: clears the cutters' slots
shade_smooth(head)
head_parts.append(head)

# Dark interior filling the carved maw.
maw = uv_sphere("Maw", 1.0, location=MOUTH_C + Vector((-0.012, 0.012, -0.005)),
                scale=(0.104, 0.098, 0.044), segments=26, rings=16)
maw.rotation_euler = (0.0, MOUTH_TILT, 0.0)
apply_transform(maw)
assign_material(maw, mat_maw)
shade_smooth(maw)
head_parts.append(maw)


def add_teeth(name, angle_range, count, inward_sign, skip=()):
    """Teeth crowding the upper and lower lips only, never a full ring."""
    made = []
    ax, az = 0.094, 0.038
    tilt = Matrix.Rotation(MOUTH_TILT, 4, "Y")
    for i in range(count):
        if i in skip:
            continue
        t = i / max(count - 1, 1)
        a = angle_range[0] + (angle_range[1] - angle_range[0]) * t
        a += rng.uniform(-0.09, 0.09)
        local = Vector((ax * math.cos(a), -0.050, az * math.sin(a)))
        base = MOUTH_C + Vector((-0.010, 0.0, -0.004)) + (tilt @ local)
        length = rng.uniform(0.015, 0.046)
        radius = rng.uniform(0.008, 0.017)
        bpy.ops.mesh.primitive_cone_add(vertices=8, radius1=radius, radius2=0.001,
                                        depth=length, location=base)
        tooth = bpy.context.active_object
        tooth.name = f"{name}{i}"
        # Point each tooth across the opening, then break the alignment.
        target = Vector((MOUTH_C.x * 0.4, MOUTH_C.y - 0.03,
                         MOUTH_C.z + inward_sign * 0.016))
        direction = (target - base).normalized()
        q = Quaternion(direction, rng.uniform(-0.55, 0.55)) @ \
            Vector((0, 0, 1)).rotation_difference(direction)
        tooth.rotation_mode = "QUATERNION"
        tooth.rotation_quaternion = q
        tooth.location = base + direction * (length * 0.30)
        apply_transform(tooth)
        assign_material(tooth, mat_teeth)
        made.append(tooth)
    return made


head_parts += add_teeth("ToothUpper", (math.radians(26), math.radians(154)), 9, -1,
                        skip=(3, 7))
head_parts += add_teeth("ToothLower", (math.radians(206), math.radians(334)), 8, 1,
                        skip=(2,))

# --- Eyes: wide, staring, whites visible all around a small dark iris ------
for side, radius, dz, dx in ((1, 0.0405, 0.043, 0.064), (-1, 0.0365, 0.033, -0.059)):
    centre = Vector((dx, -0.049, dz))
    eye = uv_sphere(f"Eye{side}", radius, location=centre, segments=26, rings=16)
    apply_transform(eye)
    assign_material(eye, mat_eye)
    shade_smooth(eye)
    head_parts.append(eye)

    iris = uv_sphere(f"Iris{side}", radius * 0.40,
                     location=centre + Vector((dx * 0.05, -radius * 0.86, -0.003)),
                     segments=18, rings=12)
    apply_transform(iris)
    assign_material(iris, mat_iris)
    shade_smooth(iris)
    head_parts.append(iris)

    # Dark lid ring framing the socket, so the eye reads at distance.
    bpy.ops.mesh.primitive_torus_add(
        major_radius=radius * 1.16, minor_radius=radius * 0.20,
        major_segments=22, minor_segments=8,
        location=centre + Vector((0, -0.012, 0)),
        rotation=(math.radians(90), 0, 0))
    rim = bpy.context.active_object
    rim.name = f"Lid{side}"
    apply_transform(rim)
    assign_material(rim, mat_hair)
    shade_smooth(rim)
    head_parts.append(rim)

# --- Nose ------------------------------------------------------------------
bpy.ops.mesh.primitive_cone_add(vertices=12, radius1=0.023, radius2=0.003,
                                depth=0.046, location=(0.002, -0.088, -0.014))
nose = bpy.context.active_object
nose.name = "Nose"
nose.rotation_euler = (math.radians(-98.0), 0.0, 0.0)
apply_transform(nose)
assign_material(nose, mat_skin)
shade_smooth(nose)
head_parts.append(nose)

# --- Hair: wild ragged mass wrapping everything except the face -----------
bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=0.185,
                                      location=(0.0, 0.040, 0.030))
hair = bpy.context.active_object
hair.name = "Hair"
hair.scale = (1.05, 1.02, 1.12)
apply_transform(hair)
bm = bmesh.new()
bm.from_mesh(hair.data)
bmesh.ops.delete(bm, geom=[f for f in bm.faces
                           if f.calc_center_median().y < -0.070], context="FACES")
bm.to_mesh(hair.data)
bm.free()
jitter_vertices(hair, 0.030, 7)
assign_material(hair, mat_hair)
shade_smooth(hair)
head_parts.append(hair)

# Straggling strands breaking the silhouette.
for i in range(11):
    a = 2.0 * math.pi * i / 11 + rng.uniform(-0.3, 0.3)
    el = rng.uniform(0.35, 1.15)
    base = Vector((math.cos(a) * 0.150, 0.045 + rng.uniform(-0.03, 0.05),
                   0.030 + math.sin(a) * 0.130))
    tip = base + Vector((math.cos(a) * rng.uniform(0.05, 0.13),
                         rng.uniform(0.02, 0.10),
                         math.sin(a) * rng.uniform(0.04, 0.12) - el * 0.10))
    strand = make_tube(f"Strand{i}", [base, base.lerp(tip, 0.5), tip],
                       [rng.uniform(0.016, 0.030), 0.012, 0.002],
                       segs=7, jitter=0.16, jitter_seed=70 + i)
    assign_material(strand, mat_hair)
    shade_smooth(strand)
    head_parts.append(strand)

# --- Place the whole head group with its unnatural tilt --------------------
head_origin = Vector((0.0, 0.0, HEAD_Z))
for obj in head_parts:
    obj.matrix_world = Matrix.Translation(head_origin) @ HEAD_ROT @ obj.matrix_world

# --- Neck: thin, elongated, attached well back so it never blocks the maw --
neck_top = head_origin + HEAD_ROT @ Vector((0.0, 0.052, -0.150))
neck = make_tube(
    "Neck",
    [(0.008, 0.030, 1.212), (0.014, 0.026, 1.290),
     (neck_top.x * 0.7, neck_top.y * 0.7 + 0.010, 1.360), tuple(neck_top)],
    [0.070, 0.052, 0.043, 0.039],
    segs=16, cap_start=True, cap_end=True, jitter=0.06, jitter_seed=3)
assign_material(neck, mat_skin)
shade_smooth(neck)

# --- Shroud body: narrow shoulders -> waist -> flaring, tapering tail ------
lean = lambda z: (z - 0.70) * 0.055
profile = [(1.255, 0.070), (1.235, 0.150), (1.200, 0.212), (1.13, 0.216),
           (1.04, 0.196), (0.93, 0.172), (0.82, 0.166), (0.71, 0.188),
           (0.60, 0.228), (0.49, 0.268), (0.40, 0.262), (0.33, 0.208),
           (0.28, 0.140)]
body = make_tube("Shroud",
                 [(lean(z), 0.0, z) for z, _ in profile],
                 [r for _, r in profile],
                 segs=24, cap_start=True, cap_end=True, jitter=0.14, jitter_seed=5)
assign_material(body, mat_shroud)
shade_smooth(body)

# Tattered flaps hanging off the shroud so the outline is never a clean
# column - this is what stops the silhouette reading as a person in a sack.
flaps = []
for i in range(7):
    a = 2.0 * math.pi * i / 7 + rng.uniform(-0.25, 0.25)
    z_top = rng.uniform(0.86, 1.16)
    z_bot = z_top - rng.uniform(0.26, 0.52)
    r_top = 0.185 + rng.uniform(-0.02, 0.03)
    r_bot = r_top + rng.uniform(0.05, 0.16)
    flap = make_tube(
        f"Flap{i}",
        [(lean(z_top) + math.cos(a) * r_top, math.sin(a) * r_top, z_top),
         (lean(z_bot) + math.cos(a) * r_bot * 0.92,
          math.sin(a) * r_bot * 0.92, (z_top + z_bot) * 0.5),
         (lean(z_bot) + math.cos(a) * r_bot, math.sin(a) * r_bot, z_bot)],
        [rng.uniform(0.045, 0.075), rng.uniform(0.030, 0.055), 0.004],
        segs=8, jitter=0.22, jitter_seed=90 + i)
    assign_material(flap, mat_shroud)
    shade_smooth(flap)
    flaps.append(flap)

# --- Arms: too long, hanging limp, slightly wrong --------------------------
arms = []
for side in (1, -1):
    # Held clear of the torso so they read as separate limbs in silhouette,
    # and unnaturally long - the hands hang far below a human wrist line.
    sx = 0.185 * side
    pts = [(sx, 0.010, 1.200), (sx * 1.42, -0.030, 1.07), (sx * 1.62, -0.078, 0.90),
           (sx * 1.58, -0.112, 0.72), (sx * 1.40, -0.108, 0.55),
           (sx * 1.30, -0.092, 0.44)]
    radii = [0.056, 0.045, 0.037, 0.030, 0.025, 0.021]
    arm = make_tube(f"Arm{side}", pts, radii, segs=14, jitter=0.07,
                    jitter_seed=13 + side)
    assign_material(arm, mat_shroud)
    shade_smooth(arm)
    arms.append(arm)

    hand = uv_sphere(f"Hand{side}", 1.0,
                     location=(sx * 1.29, -0.088, 0.406),
                     scale=(0.028, 0.034, 0.052), segments=16, rings=10)
    apply_transform(hand)
    jitter_vertices(hand, 0.008, 31 + side)
    assign_material(hand, mat_skin)
    shade_smooth(hand)
    arms.append(hand)

# --- Wisps: the dissolving, never-quite-materialised lower body ------------
wisps = []
for i in range(13):
    a = 2.0 * math.pi * i / 13 + rng.uniform(-0.24, 0.24)
    r0 = rng.uniform(0.070, 0.140)
    r1 = rng.uniform(0.150, 0.310)
    z_end = rng.uniform(0.102, 0.300)
    pts = [(lean(0.32) + math.cos(a) * r0 * 0.5, math.sin(a) * r0 * 0.5, 0.335),
           (lean(0.25) + math.cos(a) * r0, math.sin(a) * r0, 0.250),
           (math.cos(a) * r1, math.sin(a) * r1, (0.250 + z_end) * 0.5),
           (math.cos(a) * r1 * 1.16, math.sin(a) * r1 * 1.16, z_end)]
    radii = [rng.uniform(0.055, 0.085), rng.uniform(0.038, 0.062), 0.024, 0.004]
    wisp = make_tube(f"Wisp{i}", pts, radii, segs=10, jitter=0.16, jitter_seed=50 + i)
    assign_material(wisp, mat_wisp)
    shade_smooth(wisp)
    wisps.append(wisp)


def join(objects, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    joined = bpy.context.active_object
    joined.name = name
    joined.data.name = name
    bpy.ops.object.select_all(action="DESELECT")
    return joined


solid = join(head_parts + [neck, body] + flaps + arms, "GhostBody")
wisp_obj = join(wisps, "GhostWisps")

# join() inherits the active object's transform (the head, which carries the
# tilt). Bake it out so the mesh keeps its world positions and the object
# origin lands on the floor at (0,0,0) with no residual rotation.
for obj in (solid, wisp_obj):
    apply_transform(obj)

# The model is authored facing Blender -Y. glTF maps that to +Z, but Godot's
# forward is -Z, which would import the ghost back-to-front. Spin it 180 deg
# about the up axis and bake that in, so the exported asset needs no
# corrective rotation in the .tscn.
for obj in (solid, wisp_obj):
    obj.rotation_euler = (0.0, 0.0, math.pi)
    apply_transform(obj)

bbox_min = Vector((1e9, 1e9, 1e9))
bbox_max = Vector((-1e9, -1e9, -1e9))
for obj in (solid, wisp_obj):
    for corner in obj.bound_box:
        w = obj.matrix_world @ Vector(corner)
        for i in range(3):
            bbox_min[i] = min(bbox_min[i], w[i])
            bbox_max[i] = max(bbox_max[i], w[i])

tris = 0
for o in (solid, wisp_obj):
    o.data.calc_loop_triangles()
    tris += len(o.data.loop_triangles)
print("BBOX_MIN %.3f %.3f %.3f" % tuple(bbox_min))
print("BBOX_MAX %.3f %.3f %.3f" % tuple(bbox_max))
print("HEIGHT %.3f  WIDTH_X %.3f  DEPTH_Y %.3f"
      % (bbox_max.z - bbox_min.z, bbox_max.x - bbox_min.x, bbox_max.y - bbox_min.y))
print("TRIS %d" % tris)
print("MATERIAL_SLOTS %s" % [m.name for m in solid.data.materials])

# The glTF scene name becomes the imported root node's name in Godot.
bpy.context.scene.name = "ToiletGhostModel"

bpy.ops.object.select_all(action="DESELECT")
solid.select_set(True)
wisp_obj.select_set(True)
bpy.context.view_layer.objects.active = solid
bpy.ops.export_scene.gltf(
    filepath=OUT_GLB,
    export_format="GLB",
    use_selection=True,
    export_apply=True,
    export_yup=True,
    export_cameras=False,
    export_lights=False,
)
print("EXPORTED %s" % OUT_GLB)
