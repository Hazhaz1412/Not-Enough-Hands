# House electrical architecture

The two house maps share one electrical contract through node groups and stable
device IDs. Map-specific gameplay must not keep direct references to a
`PowerManager`.

## Responsibilities

- `PowerManager` owns total load and global/regional outages. Each house scene
  has exactly one manager in the `power_manager` group.
- `ElectricalDevice` owns configured consumption, requested on/off state, and
  forced-off reasons. Device scripts react to its `state_changed` signal.
- `LightSwitch` owns player interaction only. It resolves either a direct
  `controlled_device` NodePath or a stable `controlled_device_id`.
- `MainBreaker` is the one shared, physical recovery point for a full-house
  blackout. It restores the manager and every electrical zone; individual
  `LightSwitch` nodes still restore a DarknessGhost outage circuit by circuit.
- `Interactable` remains the shared player-interaction contract. Electrical
  code does not duplicate raycast, prompt, range, or lock behavior.

## Reserve pacing (why the battery is not spent in watts)

Device wattages are art-side flavour: House2's authored lights alone total
~2900 per second, which against any readable `max_power` emptied a 1000-unit
battery in under half a second. So the reserve is **not** spent at the raw
load. `PowerManager.get_drain_per_second()` spends it against
`full_load_reserve_seconds` instead — a full battery lasts that long with the
whole house lit, whatever the wattages happen to be, and proportionally longer
once rooms are switched off. The reference for "the whole house is on" is the
peak load ever observed, tracked as a running maximum because the villa
registers its lights at runtime.

At the default 220 s, one night (23:55 → 06:00 = 547.5 real seconds at 1.5 s per
game minute) goes dark **twice** if the players leave every light on, and less
often if they run the house dark on purpose. `tests/power_pacing_smoke.gd`
drains the real House2 map for exactly one night and asserts that count, so
retuning wattages or `max_power` can no longer silently wreck the pacing.

Both maps therefore ship `enable_power_drain = true`. `get_seconds_until_blackout()`
is what the F1 panel reports, since remaining seconds is the number that
actually matters.

## Generated house lights

Authored lights belong to `flickering_house_lights`. After a procedural house
finishes building, `PowerManager` gives every such light one runtime
`ElectricalDevice` child. The default load is configured by
`default_light_consumption`.

The stable device ID is the light node name without its final `Light` suffix:

| Light node | Device ID |
| --- | --- |
| `R_LIVINGLight` | `R_LIVING` |
| `R_KITCHENLight` | `R_KITCHEN` |
| `J1Light` | `J1` |

This convention lets procedural geometry be rebuilt without breaking switches.
Generated device IDs must be unique within one house.

## Persistent Villa fixtures

Manually positioned switches for the main Villa map are authored directly in
`villa_main.tscn`, outside `VillaHouse/Generated`:

```text
ElectricalFixtures/
  Floor_B1/
  Floor_00/
  Floor_01/
  Floor_02/
```

Set a switch's `controlled_device_id` to the room/junction ID it controls. Use
the direct `controlled_device` picker only for non-generated scenes or special
devices whose node path is intentionally stable.

Never place manual switches below `VillaHouse/Generated`; clearing or rebuilding
the procedural map deletes that subtree. `villa_house.tscn` remains responsible
only for the reusable procedural house structure.

## Main breaker

`power/main_breaker.tscn` is placed in both House2 and the Villa electrical
room. Whenever any zone is dark (or `PowerManager` has a global blackout) the
cabinet highlights itself: the indicator pulses and the `Outline` child draws a
pulsing glowing rim around the object, visible from anywhere in the house and
through walls.

That rim is a **stencil** effect, not a depth effect, and both halves are
load-bearing:

- The cabinet's own materials set `stencil_flags = WRITE | WRITE_DEPTH_FAIL`
  with `stencil_reference = 1`, so they stamp their silhouette into the stencil
  buffer *even when a wall is in front of them*.
- `Outline` is a shell grown past the cabinet, running `no_depth_test` (so it is
  never occluded) with `stencil_flags = READ`, `stencil_compare = NOT_EQUAL`,
  reference 1 - so it is carved back to just the rim.

Drop the stencil and the shell renders as a solid orange slab that hides the
cabinet; drop `WRITE_DEPTH_FAIL` and the rim fills in whenever a wall is in the
way. `tests/main_breaker_smoke.gd` pins both.

A rim of fixed metre width shrinks to nothing across a large map, so
`MainBreaker._scale_outline_for_distance()` grows the shell proportionally to
camera distance (`outline_thickness_per_metre`, clamped by
`outline_thickness_min`/`_max`). That is what keeps it equally findable at 2 m
and at 40 m.

`PowerManager` emits `blackout`/`power_restored` only for a *house-wide*
outage, but a `DarknessGhost` darkens one zone at a time. `MainBreaker`
therefore also subscribes to every `ElectricalZone.power_changed`; without that
it stays dark and its prompt stale until the last zone happens to go out too.

Using it is not instant. Aim at the cabinet, press **E**, and
`minigames/breaker_minigame.tscn` opens: a `repair_duration` (10 s) countdown
that only runs while the player holds the wheel. A red needle sweeps a dial and
**SPACE** has to be pressed while it covers the white mark.

- Every press reverses the sweep, whether or not it landed.
- Every resolved attempt speeds the needle up by `needle_speed_gain`, to a
  ceiling of `needle_max_speed`.
- Every failure - a mistimed press *or* a mark swept past untouched - adds
  `fail_penalty` (1.5 s) back onto the countdown.
- Each new mark is placed a fixed *time* ahead of the needle, not a fixed arc,
  so a faster wheel is harder without becoming unreactable.
- `hit_forgiveness` (7°) widens the hit window beyond the drawn mark, so a press
  a shade early or late still lands. It also decides when an ignored mark counts
  as missed: the needle must clear the whole window, not just the mark's centre,
  or the late half of the slack would be unreachable.
- `max_repair_seconds` (20 s) caps a repair from both ends: failures stop adding
  time there, and 20 seconds of actual play completes the repair whatever the
  countdown reads. A bad run is bounded rather than an endless wheel while the
  house stays dark - `_elapsed` is carried across a cancel just like the
  countdown, so breaking off and returning cannot reset that budget.

**E** leaves the cabinet, keeping the seconds already served and every penalty
earned, so a player can break off for a ghost and resume. Serving the countdown
emits `repair_completed` and `MainBreaker` then does what it always did in one
step: clear persistent zone failures and restore the global power state. The
minigame owns no power logic and the breaker owns no minigame logic.

## Adding another device type

Add an `ElectricalDevice` child, configure `device_id` and
`power_consumption`, then connect `state_changed` to the appliance's visual,
audio, or motor behavior. Registration, total-load updates, and blackout
behavior require no appliance-specific PowerManager code.
