# Project status

Working notes on what's in progress right now, separate from `README.md`
(which documents shipped, player-facing features). Update this as things
move from "built in isolation" to "wired into the real game."

## This session

### Debug/test sandbox — `tests/debug_room.tscn` + `tests/debug_room.gd`
A standalone room (not part of `main.tscn`) for manually testing ghosts,
doors, power, and props without loading the real house. Player, all three
ghosts, a defense door, a plain interior door, `PowerManager` (auto-drains to
a blackout every ~30s), and the `F1` dev panel are all present, wired the
same way `main.tscn` wires them. Run it directly (`tests/debug_room.tscn`,
F6) - it doesn't touch anything `main.tscn`-related.

### Blackout repair minigame — `power/fusebox.gd`/`.tscn`, `minigames/fusebox_minigame.*`
A `Fusebox` prop (`interact()`/`get_interaction_prompt()`, same contract as
`DefenseDoor`) that, during a `PowerManager` blackout, hands off to
`FuseboxMinigame` - a needle/safe-band/nerve-meter minigame (ported from a
provided HTML demo) using the existing **interact** key as the only input.
Seat 3 fuses to restore power; missing costs nerve and reports noise to the
crawler (deliberately does **not** suspend ghost attacks, unlike the door
minigame - being at the panel is meant to be risky). Wired into
`player.gd`/`player.tscn` alongside `DoorGhostMinigame`
(`start_fusebox_minigame`, `is_fusebox_minigame_active`,
`is_any_minigame_active`).

**Only placed in `tests/debug_room.tscn` so far - not in `main.tscn`/`house2`.**
No blackout-repair loop exists in the real game yet.

### Dev panel (F1) additions — `ui/dev_tools.gd`/`.tscn`
Added **"NGẮT ĐIỆN NGAY"** button: forces a blackout on demand by zeroing
`PowerManager.current_power` (looked up by group, so it's a no-op with a
status message in scenes that have no power system, e.g. `main.tscn` today).

### Reusable light component — `props/light_source.gd`/`.tscn`, `props/light_switch.gd`/`.tscn`
- `LightSource`: drop-in light for any furniture. `directly_toggleable`
  (walk up, press E) and/or `switch_id` (a `LightSwitch` elsewhere controls
  it via the `light_switch_<id>` group - no NodePath wiring). Listens for
  `PowerManager.blackout`/`power_restored` and forces itself dark regardless
  of its own on/off state (`affected_by_blackout`, on by default).
- `LightSwitch`: wall switch, `targets: Array[StringName]` of switch_ids.
  Lever is a mild neon green under normal power; goes bright and translucent
  during a blackout so it stays findable in the dark.
- **Both require `collision_layer = 3`** on their physics body or the
  player's interact raycast (`collision_mask = 2`) never sees them - this bit
  the fusebox once already (fixed) and is worth remembering for any new prop
  of this kind.
- Demoed live in `tests/debug_room.tscn` under the `LightDemo` node before
  being trusted anywhere else.

### House2 integration — `house2/house2.gd`
All 10 authored room lights (`_build_lighting`, previously bare
`OmniLight3D.new()`) now go through `LightSource` instead, via `_add_light`
(same call signature, so the 10 call sites didn't need to change).
Each is `directly_toggleable = true` (no switches placed in House2 yet, so a
non-toggleable light would be permanently stuck on) and
`affected_by_blackout = true` - **this is the first place a `PowerManager`
blackout actually darkens the real game**, though nothing in `main.tscn`
currently drives a real blackout (no `Fusebox`, no registered
`ElectricalDevice` load). The inner `Light3D` still joins
`flickering_house_lights` exactly as before, so the ambient flicker system
(`audio/light_flicker.gd`) is unaffected. `LightSource`'s own placeholder
bulb mesh is freed for these instances - House2 already places a proper
`FURNITURE_CEILING_LAMP`/fixture mesh at each position.

**Not yet touched:** House3/the villa (`house3/villa_house.gd` has its own,
separate `_add_light`/light-generation code, untouched), and House2's purely
decorative table lamps (`FURNITURE_TABLE_LAMP` placements - meshes only, no
light was ever attached, so there's nothing to "replace" there yet).

## Open items / natural next steps

- Give House2 actual wall switches (none exist yet - every room light is
  independently direct-toggle only). Would need per-room `LightSwitch`
  placement and `switch_id` decisions.
- Place a `Fusebox` + register some `ElectricalDevice` load in `main.tscn`/
  `house2.tscn` so a real blackout can actually happen in the shipped game.
- Decide whether House3/the villa gets the same `LightSource` treatment.
- Wire `LightSource` into the purely-decorative table lamp placements
  (`FURNITURE_TABLE_LAMP`) if stand lamps should be interactive too.

## Known pre-existing test failures (not caused by any of the above)

Confirmed via `git stash` before starting this session's work - both fail
identically with none of this session's changes applied:
- `tests/door_ghost_minigame_smoke.gd` - "easier minigame balance defaults
  drifted" (asserts exact `DoorGhostMinigame` export defaults; something in
  already-uncommitted `ghosts/hunter_ghost.tscn` work, unrelated to anything
  above).
- `tests/statue_hunt_cycle_smoke.gd` - "Statue did not disappear after its
  post-sighting countdown."

Every other test under `tests/*_smoke.gd` passes as of this file's last
update, including all house2/navigation/collision tests after the light
replacement above.

Yes this was made by Claude, don't expect much b, yeah also fix the god damn Player Controller, it broken af!
stupid bitch ahh nigga can't even make a controller without it break.