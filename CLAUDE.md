# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Godot 4.7 first-person horror prototype ("Not Enough Hands"). GDScript only, no build step. Physics is Jolt (`project.godot` `[physics]`).

## Running & testing

- Open `project.godot` in Godot 4.7. `main.tscn` (House2 map) is the default `run/main_scene`; run it with F5/F6.
- The second map lives beside it: run `house3/villa_main.tscn` directly (F6) to play the villa instead of House2.
- Tests are standalone headless smoke scripts under `tests/`, **not** GdUnit — each is a `SceneTree` subclass with `_initialize()` → `_run()` → `_fail(msg)`/`quit()`. Run one at a time:
  ```
  godot --headless --script tests/<name>.gd
  ```
  There is no aggregate test runner; run the specific smoke test(s) relevant to the area you changed. `tests/villa_layout_smoke.gd`, `villa_seal_smoke.gd`, and `villa_boot_smoke.gd` are the load-bearing ones for the villa map (reachability, wall-seal raycasts, baked navmesh). `tests/villa_screenshot.gd` / `villa_devshot.gd` are not tests — they write PNGs to `user://villa_shots` for visual inspection.

## Core working rule (`.ai/RULES.md`)

Write less, do less, change only what's required: smallest implementation that satisfies the requirement, reuse existing architecture/groups before adding new ones, don't touch unrelated systems, every change needs a reason and a verification step. Priority order: Correctness > Simplicity > Maintainability > Completeness > Extra features.

## Architecture

### Two parallel maps, one gameplay layer

`house2/` (hand-authored, 18×12 m, current default) and `house3/` (generated, 80×60 m "Biệt thự Vành Đai") are independent scene trees that both plug into the *same* gameplay systems — player, the three ghosts, defense doors, power, audio — entirely through **node groups**, not direct references. Editing gameplay code must not assume which map is loaded.

- `house3/neh_map_spec_v2.json` is the sole source of villa geometry (spec tables verbatim; the ASCII plans in the JSON are documentation only, not parsed).
- `house3/villa_spec.gd` rasterizes the spec into a per-storey cell grid (walls, rooms, corridors, junctions, doors, entrances).
- `house3/villa_house.gd` turns the cell grid into real geometry (floors, wall runs, doorways, stairs, railings, lights) and publishes room/junction/entrance/spawn/ghost-route markers, plus procedural furniture placement (`FURNITURE_PLANS`, seeded per room id).
- When changing villa layout rules, the spec JSON + `villa_spec.gd` §10.x validation is upstream of `villa_house.gd` geometry — fix reachability/adjacency at the spec/rasterization layer, not by patching generated geometry.

### Runtime collision & navigation (not baked at edit time)

`main.gd` (and the villa equivalent) generates trimesh collision from the visual meshes and bakes the `NavigationMesh` **at runtime** in `_ready()`, because the source art packs ship render geometry only. The navmesh is parsed from the *generated static colliders*, not the raw render meshes — this is deliberate so navigation and physics can't disagree. Smooth stair ramps need explicit `NavigationLink3D`s added by code (`_add_stair_navigation_links`) because Recast erodes the ramp/landing seam otherwise; if you add a new ramp, add it to the `smooth_stair_ramps` group or it won't get a nav link.

### Level data lives in node groups, not code

Ghost routes, patrol points, spawn points, and defense doors are all discovered via `get_tree().get_nodes_in_group(...)` (e.g. `crawler_patrol_points`, `crawler_lair`, `hunter_sweep_points`, `defense_doors`). Placing/moving `Marker3D`s in a scene reconfigures behavior with no script changes — this is how both maps share one set of ghost/door/power scripts.

### The three ghosts (`ghosts/`)

Each ghost is built to counter a different player behavior, and each subscribes to signals/groups rather than polling the player directly:

| | Statue | Crawler | Huntsman |
|---|---|---|---|
| Script | `statue_ghost.gd` | `crawler_ghost.gd` | `hunter_ghost.gd` |
| Sense | sight (freezes if seen) | sound (blind) | scent trail on the floor |
| Entry | scripted ambush | announced fly-past + patrol/hunt/retreat cycle | via a door's `breached` signal, walks in on foot |

`hunter_ghost.gd` subscribes to every defense door's `breached` signal — a door reaching zero durability is what lets it in; rebuilding the door before its entry delay elapses keeps it out entirely. See `README.md` for the full behavioral contract of each (this is the design spec, not just flavor text — the smoke tests in `tests/` assert these specifics).

### Doors, power, and the flashlight minigame

- `door/door.gd` is the interactive door (state machine: `CLOSED`/`OPENING`/`OPEN`/`CLOSING`); `door/defense_door.gd` adds durability/breach for the seven exterior entrances, all in the `defense_doors` group.
- `door/door_attack_director.gd` orchestrates ghost attacks on defense doors.
- `power/power_manager.gd` is a group-registered (`power_manager`) singleton-per-scene: devices register themselves and expose `get_power_consumption()`; it drains `current_power` and emits `blackout`/`power_restored`.
- `minigames/door_ghost_minigame.gd` is the shared flashlight repel minigame used both to drive off an attacker at an intact door and to physically repair a breach.

### Player & threat reporting

`player/player.gd` owns movement, camera, stamina, and blink. All three ghosts report danger through `Player.set_threat_from(...)`, which the horror overlay (`ui/`) uses to always reflect whichever threat is currently worse — new ghosts/hazards should report through this same call rather than driving the overlay directly.

### Dev tools

`ui/dev_tools.gd` (F1 panel) provides invincibility, speed/noclip, forced ghost manifestation, and door/entrance selection for manual testing; `tests/dev_tools_smoke.gd` covers it. It reads/writes the same groups and signals gameplay code uses, so it's a reference for "how do I reach this system" as much as a debug tool.

## Godot MCP tooling

The `godot-ai` addon (`addons/godot_ai/`) exposes a running editor over MCP for other AI clients (Cursor, Claude Desktop, etc.) — it is infrastructure for external tooling, not part of the game itself. Don't attribute gameplay behavior to it.
