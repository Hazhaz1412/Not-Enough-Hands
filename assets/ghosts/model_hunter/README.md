# Midnight Grin (Door Ghost and Huntsman)

`Meshy_AI_Midnight_Grin_biped/` is the body both the Door Ghost and the Huntsman
wear, wrapped for gameplay by `ghosts/ghost_visual.tscn` — one instance of the
one file per ghost, no copy of the asset.

## What the asset actually ships

The download is four skinned GLBs, one per animation. **All four carry the same
mesh (`char1`, one surface) and the same 24-bone `Armature`** — they differ only
in the clip inside them. So any one of them is the entire character, and the
other three are pure clip sources.

| File | Clip inside | Role |
|---|---|---|
| `..._Animation_Walking_withSkin.glb` | `Armature\|walking_man\|baselayer`, 1.07 s | **The body.** This is the one `ghost_visual.tscn` instances, and it also supplies `Walk`. |
| `..._Animation_Unsteady_Walk_withSkin.glb` | `Armature\|Unsteady_Walk\|baselayer`, 3.00 s | Clip source → `Idle` |
| `..._Animation_Running_withSkin.glb` | `Armature\|running\|baselayer`, 0.67 s | Clip source → `Run` |
| `..._Animation_Weapon_Combo_withSkin.glb` | `Armature\|Weapon_Combo\|baselayer`, 3.70 s | Clip source → `Attack` and `Skill 3` |
| `Meshy_AI_Midnight_Grin_biped.zip` | — | The original download. The same four files, nothing more. |

The three clip sources are imported with `gltf/embedded_image_handling=0`
(Discard All Textures). Each GLB embeds its own copy of the same 5.1 MB texture,
and only the body needs one — left at the default every source would extract a
fourth identical PNG beside the model.

## The two facts that drive the wrapper

Both were re-measured on this GLB rather than carried over, and both came back
the same as the model it replaced, so `ghost_visual.gd` needed no new numbers:

- **1.70 m, feet on the origin.** The crown bone `head_end` rests at
  y = 1.700 and the toes at y ≈ 0.03. `SOURCE_HEIGHT` is that, and the wrapper
  scales by `target_height / SOURCE_HEIGHT`.
- **It looks along +Z, so it needs a 180° yaw.** The bone literally named
  `headfront` rests 0.19 m ahead of `Head` in **+Z**, and `LeftToeBase` sits +Z
  of `LeftFoot`. Godot's forward is −Z. That is `SOURCE_FORWARD_YAW`.

Unlike the model this replaced, nothing is retargeted: no BoneMap, no
`SkeletonProfileHumanoid`, and the rest pose is the GLB's own bind pose rather
than a degenerate T-pose.

## Why the material is overridden

The GLB *does* ship its own texture — but Meshy wraps it in a material this game
cannot use. As imported it is:

```
metallic         = 1.0      # glTF's default metallicFactor, which Meshy never set
emission_enabled = true
emission         = (1,1,1)  with the albedo wired in as the emission map
```

Fully metallic with no environment map renders black, and the full-white
emission is what Meshy adds to hide that. The result is a body lit from the
inside — which is exactly wrong for the one the player is supposed to hunt with
a flashlight, since it would glow in a dark house and never respond to the beam.

`ghosts/midnight_grin_body.tres` is the same texture on an honest dielectric
material (`metallic = 0`, `roughness = 0.9`, emission off, culling left disabled
to match the source's `doubleSided`). `GhostVisual.build()` applies it as a
`material_override`. No offline texture bake is involved any more — the previous
model shipped no texture at all and had its albedo/ORM synthesised, which is why
that step existed.

## Clips

`tools/build_ghost_animations.gd` bakes `ghosts/ghost_animations.res` from the
four GLBs. It strips position and scale tracks — movement belongs to
`hunter_ghost.gd`'s `CharacterBody3D` and to the door encounter's own placement,
so a hips track would translate the body a second time.

The two ghosts ask for five clips and the download has four animations, so:

- **`Idle` is the unsteady walk with its position tracks dropped**, which leaves
  the sway and discards the travel. The download ships no standing clip.
- **`Attack` and `Skill 3` are both the weapon combo** — it is the only
  aggressive animation in the set. They read as one move rather than two; adding
  a distinct one means adding a fifth animation to the download, not changing
  code.

Regenerate after changing the sources:

```
godot --headless --script tools/build_ghost_animations.gd
```

`Stabbing.fbx` and `mixamo_bone_map.tres` are left over from the previous model
and are no longer part of this pipeline.
