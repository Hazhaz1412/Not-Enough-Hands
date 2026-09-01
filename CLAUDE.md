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

  `tests/world_replication_pair_smoke.gd` and `tests/lobby_reset_pair_smoke.gd` span two processes: run normally each becomes the server, spawns a second headless copy of itself with `--client`, binds a UDP port (47311 / 47312) and asserts on the verdict the child writes to `user://`. Run them after touching anything in `network/` — a channel can be entirely dead without a single-process test noticing. `tests/villa_run_wipe_smoke.gd` covers the other end of a session (a wiped team handing the room back) and needs only one process, but does load the villa.

- **Budget the villa.** Anything that loads `house3/villa_main.tscn` bakes the navmesh with Recast at runtime and spends most of its wall clock there: **5–8 minutes each**, well past a default two-minute command timeout. Run those in the background or with an explicit long timeout, and don't read a timeout as a failure. House2 and bare-scene tests finish in seconds.

- **Two tests already fail on a clean checkout**, so don't spend time thinking you broke them:
  - `tests/hunter_slash_smoke.gd` was written against a Huntsman retune that never landed. Its first two sub-tests have since been corrected to the shipped contract (a `seize_clip_speed` property that never existed anywhere, and a 0.2 s commitment window against the real `seize_windup` of 0.5 s) and now pass. It still fails on the third, `_test_backpedal_cannot_escape_a_committed_grab`, which asserts a player holding the back key cannot walk out of a committed grab — arithmetically impossible with the shipped numbers: `seize_kill_radius` is 2.8 m and has always been, `Player.walk_speed` is 6 m/s and has always been, so 0.5 s of wind-up carries a walking player 3.1 m from a 2.3 m start to 5.4 m. It fails at a 0.2 s wind-up too, so no retune ever made it pass. Closing it is a **balance** decision (kill radius, wind-up, or player speed), not a test fix — don't quietly invert the assertion.
  - `tests/villa_boot_smoke.gd` fails on absent art: `.gitignore` excludes `/assets/map/**`, so the furniture and texture packs the villa generates from are not in the repo. It surfaces as `... has 0 Mirror fixture(s), expected exactly one` because `assets/map/Furniture/FBX/Separated/Mirror.fbx` cannot load. It is an asset-availability failure, not a villa geometry bug — do not "fix" it by editing the layout.

### When something "does nothing", suspect loading before logic

Godot fails soft here in a way that looks exactly like a gameplay bug, and it has cost real time twice:

- A `.tscn` whose `ext_resource` path does not resolve (a missing asset, or one that is gitignored and only exists on one machine) fails to parse **the whole scene**. Instancing it elsewhere leaves a node that exists but is inert.
- A GDScript parse error does the same to one node: the scene still loads, the node is still there, but it has **no script** — so every property reads as `<null>`, every method is missing, and nothing it owns ever runs.

In both cases the game keeps running and the only evidence is in the editor/stdout output. **Read the console before reading the AI code**: `godot --headless --script tests/<name>.gd 2>&1 | grep -i "parse error\|not found"` settles it in seconds. See also the release-build warning under *Multiplayer* — a different silent-failure class with the same symptom.

## Core working rule (inlined below; `.ai/RULES.md` itself is gitignored)

Write less, do less, change only what's required: smallest implementation that satisfies the requirement, reuse existing architecture/groups before adding new ones, don't touch unrelated systems, every change needs a reason and a verification step. Priority order: Correctness > Simplicity > Maintainability > Completeness > Extra features.

`.gitignore` excludes `.ai/` wholesale, so nothing in it is in the repo — the rule above is reproduced here because a fresh clone has no copy of it. Two other things live there locally, and neither is authoritative:

- `.ai/CONTEXT.md` is **stale**: it documents only the early prototype (player controller, stamina, a door) and predates the ghosts, both maps and the whole network layer. Do not use it to orient yourself; this file and `README.md` are current.
- `.ai/godot-*/SKILL.md` are ~30 general Godot reference packs written around **GdUnit4**. This repository does not use GdUnit and must not gain it — see *Running & testing* above for what the tests actually are. Treat those packs as engine reference only, never as this project's conventions.

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
| Sense | sight (freezes if seen) | sound (blind) | line of sight from any angle, plus hearing |
| Entry | scripted ambush | announced fly-past + patrol/hunt/retreat cycle | via a door's `breached` signal, walks in on foot |

The Huntsman deliberately has **no** scent/footprint memory: it investigates only
direct evidence (a heard noise, the last place it saw somebody) and otherwise
patrols the `hunter_sweep_points` route. `tests/hunter_ghost_smoke.gd` asserts
that negatively - a `get_trail_size()`/`has_trail_lead()` hook on the hunter is a
test failure. Restoring a trail system means changing that test first, not
half-reintroducing the call sites.

`hunter_ghost.gd` subscribes to every defense door's `breached` signal — a door reaching zero durability is what lets it in, and it answers on the next physics tick — `entry_delay_min`/`entry_delay_max` ship at 0, so there is no longer a grace period in which rebuilding the door keeps it out. Raising either export restores that window; `tests/hunter_ghost_smoke.gd` covers both the zero-delay arrival and the sealed-out behaviour a non-zero delay still gives. See `README.md` for the full behavioral contract of each (this is the design spec, not just flavor text — the smoke tests in `tests/` assert these specifics).

### Doors, power, and the flashlight minigame

- `door/door.gd` is the interactive door (state machine: `CLOSED`/`OPENING`/`OPEN`/`CLOSING`); `door/defense_door.gd` adds durability/breach for the seven exterior entrances, all in the `defense_doors` group.
- `door/door_attack_director.gd` orchestrates ghost attacks on defense doors.
- `power/power_manager.gd` is a group-registered (`power_manager`) singleton-per-scene: devices register themselves and expose `get_power_consumption()`; it drains `current_power` and emits `blackout`/`power_restored`. The reserve is spent against `full_load_reserve_seconds` (a full battery lasts that long with the whole house lit), not against raw device wattage — House2's lights alone total ~2900/s and would empty a 1000-unit battery in under a second. At the default 220s a night goes dark twice; `tests/power_pacing_smoke.gd` pins that.
- `power/main_breaker.gd` is the one physical recovery point for a full-house blackout, instanced in both maps. While the house is dark it highlights itself: the indicator pulses and an `Outline` shell draws a glowing rim around the cabinet, visible from any distance and through walls — a stencil effect (cabinet materials stamp reference 1 with WRITE|WRITE_DEPTH_FAIL, the shell reads it back NOT_EQUAL under `no_depth_test`), grown with camera distance so it never shrinks to nothing. Using it opens `minigames/breaker_minigame.gd` rather than restoring anything: a 10-second countdown wheel where SPACE has to land a reversing, accelerating needle on a white mark, each failure adding 1.5s. `max_repair_seconds` (20s) caps it from both ends — failures stop adding time there, and 20s of actual play auto-completes — and `hit_forgiveness` widens the hit window past the drawn mark. Progress survives a cancel; only `repair_completed` makes the breaker restore the zones and the manager. Same split as the door minigame — the minigame owns no power logic, the breaker owns no minigame logic.
- `minigames/door_ghost_minigame.gd` is the shared first-person 3D repel encounter fought at the attacked door, used both to drive off an attacker at an intact door and to unlock repairs at a breach. Three phases (peephole → ajar → wide open), each cleared by its own `hits_per_phase` flashlight hits with the counter reset on every transition — never a running total. It owns no durability logic — failure and success both go back through `defense_door.gd`'s `apply_exorcism_failure()`/`complete_exorcism()`. Ghost positions come from `Marker3D`s in the `door_ghost_positions` group authored in `door/defense_door.tscn`, so it stays map-agnostic. The ghost itself is `ghosts/door_ghost.tscn` (the `Meshy_AI_Midnight_Grin_biped` import plus an `Area3D` the flashlight ray must actually reach; the body itself is the shared `ghosts/ghost_visual.tscn`, whose material override cancels the fully-metallic/full-emission material Meshy ships so the beam actually lights it — see `assets/ghosts/model_hunter/README.md`) — a body with poses and no AI, spawned into the running scene for the encounter and freed with it; `hunter_ghost.gd` is untouched by it.

### The totem ritual

`items/totem_ritual.gd` (group `totem_ritual`, one node per map scene) is the
director for the collect-and-burn objective; `items/totem_brazier.gd` (group
`totem_braziers`) is the fire it is burned at. Same split as the breaker and its
minigame: the brazier owns the fire and the three-second hold and knows nothing
about the clock; the ritual owns how much night a burn is worth, how many items
exist and when it is over, and never touches the fire. Both are map-agnostic -
drop points come from the `house2_rooms` markers *both* maps publish, and the villa, which places no
brazier of its own, gets one dropped at the room nearest the player spawn.

Items are a live population, not a one-off scatter: a restock pass every two
seconds tops both groups back up to one per player still in the run (carried
items count, so burning is what puts the next one on the map, not picking one
up), and a drop point must be at least `min_spawn_distance` (40 m) from every
player. Where no room clears that bar - House2 is 18 x 12 m - `_pick_far_room()`
falls back to a random pick from the farthest quarter of the rooms, so the rule
degrades to "the farthest there is", never to "underfoot".

The 4:00 AM ceiling lives in `NightClock.skip_minutes()` (group `night_clock`),
not in the ritual: it grants only the minutes left below `skip_limit_hour` and
returns how many it actually gave. `items/ritual_item.gd` is the shared pickup
for totems and firewood - it adds `slot_cost` (which `PlayerEquipment` reads to
reserve both hands for a totem) and the seen-by-camera highlight. Consumers take
an item out of a player's hands through `Player.release_held_item()`, the
counterpart to `try_pick_up_item()`; nothing reaches into the equipment slots.

### Player & threat reporting

`player/player.gd` owns movement, camera, and stamina. All three ghosts report danger through `Player.set_threat_from(...)`, which the horror overlay (`ui/`) uses to always reflect whichever threat is currently worse — new ghosts/hazards should report through this same call rather than driving the overlay directly.

### Multiplayer: one authority, three kinds of seam

`network/` holds two autoloads. `NetworkManager` owns the *session* — roster, lobby, and `game_started`, which is also the door: `_register_player()` refuses newcomers while a night is running. `WorldReplicator` owns the *world* — it streams ghosts and loose items at 20 Hz, doors/power/the brazier at 5 Hz, and spawn/despawn/clock as reliable events. `WorldNet` is the one seam world scripts reach both through, because an autoload's identifier does not resolve in the `--script` smoke tests; **never name `NetworkManager` directly outside `network/`**.

Every world system guards its own simulation with `WorldNet.is_world_authority()` (true offline and on the server) and takes the server's word through its own `apply_network_state()`. Three things do *not* fit that mould and each has its own seam:

- **Presentation a client cannot derive.** Placing a ghost is not enough — all three hide their rig through `_set_manifested()`, which only the brain calls, so that flag is replicated too. A client that gets position but not this shows a moving light with no model.
- **Anything played through a camera.** Minigames and the death screen are first-person, so the server claims the target and hands the encounter to the owning peer (`Player._begin_remote_encounter`, `_show_death`); the outcome is reported back. Never run one on a replica.
- **Presses whose whole effect is local geometry.** Interior doors and light switches join `replicated_interactions`, and `Player._try_interact()` echoes the press to every peer. Targets with their own network path deliberately stay out of that group.

A run ends exactly one way: `NetworkManager.end_run()`, which clears `game_started` and the ready flags and returns everyone to the lobby. `villa_main.gd` decides *when* (wipe, dawn, or the last player leaving); NetworkManager decides what to do about it.

**An RPC can land on a node that has already left the tree.** Ending a run swaps the villa for the lobby, and for the frame or two that takes, every peer is still streaming input — none of them has heard yet. Those packets arrive at a body being freed with the map, where `Node.multiplayer` and `get_tree()` are both **null**, so a guard opening with `multiplayer.is_server()` is the crash rather than the check. Every RPC entry point on a node that lives *inside a map scene* (`player/player.gd`, `power/main_breaker.gd` — the `network/` ones are autoloads and always in the tree) must therefore open with `Player._network_is_reachable()` or its equivalent; `tests/detached_player_rpc_smoke.gd` pins it.

Beware that **a debug build hides this entire class of bug**: it reports "Cannot call method 'x' on a null value" and carries on, so every headless smoke test passes, while the exported server dereferences null and dies with SIGSEGV (exit 139). When a bug reproduces only on Edgegap, export a release build and run it locally before reading any more code — `--script` does not work in an exported binary, so drive it as a real `--server` + `--join=` pair instead.

### Dev tools

`ui/dev_tools.gd` (F1 panel) provides invincibility, speed/noclip, forced ghost manifestation, and door/entrance selection for manual testing; `tests/dev_tools_smoke.gd` covers it. It reads/writes the same groups and signals gameplay code uses, so it's a reference for "how do I reach this system" as much as a debug tool.

## Godot MCP tooling

The `godot-ai` addon (`addons/godot_ai/`) exposes a running editor over MCP for other AI clients (Cursor, Claude Desktop, etc.) — it is infrastructure for external tooling, not part of the game itself. Don't attribute gameplay behavior to it.
