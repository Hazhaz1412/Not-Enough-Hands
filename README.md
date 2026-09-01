# Not Enough Hands

Godot 4 first-person horror prototype built around a four-level modular house.
Running the project now opens the multiplayer menu; every hosted or joined
session loads `house3/villa_main.tscn`.

## Multiplayer development flow

The current milestone provides ENet host/join, a four-player waiting lobby,
ready states, player names, replicated player spawning in the Villa, and
server-authoritative player movement. To test locally, run two game instances:
create a room in the first, then join `127.0.0.1` on UDP port `7777` from the
second. Everyone presses Ready; only the lobby host can start the Villa.

A headless dedicated server can be started with:

```powershell
godot --headless --path . -- --server --port=7777
```

Clients can join from the menu, or directly for automated testing:

```powershell
godot --path . -- --join=127.0.0.1 --port=7777 --name=Player2
```

For Edgegap, expose the container's UDP port `7777`; players must join the
external IP and dynamically assigned external port returned by Edgegap. The
allocation/lobby API and replication of shared gameplay state (doors, items,
ghosts, clock, and win/lose state) are later milestones.

The complete export, container, registry, App Version, and join checklist is in
[`deploy/edgegap/README.md`](deploy/edgegap/README.md).

## Play

1. Open `project.godot` in Godot 4.7.
2. Press F5, enter a player name, then host locally or join a server.
3. Move with WASD, sprint with Shift, crouch with Ctrl, jump with Space, interact
   with E, blink with B, and press Alt to show or recapture the mouse.

The toilet minigame starts peeing automatically, building pressure for 0.75
seconds before it reaches full flow. Move the mouse to aim the stream and look
around at the same time; press **E** at any time to stop and leave the toilet.

Something joins you in there. It arrives at the far end of whatever the room
still lets you see, never in front of you, and from then on it alternates
between standing dead still and lurching a step closer. It keeps its own
clock: your job is to be looking during one of those lurches, not to look
often.

Catch it mid-lurch and it stutters, glitches and is gone at once - that is
the only way to be rid of it in a single look. Catch it standing still and
it counts, but only once per lurch; looking again while it is still standing
is worth nothing until it has moved. Three of those and the next sighting
banishes it, so patience works too - it just costs three well-spent looks
instead of one well-timed one.

Staring is not a strategy. It will not take its ordinary step while you are
watching, but watch one cycle for more than about three seconds - across as
many separate glances as you like, the budget does not reset - and it lunges
a long stride instead, and that lunge cannot be caught. Ignore it entirely
and five lurches is all it needs. Turning to look is never free either: the
same mouse motion that swings the camera also throws the stream off centre,
and a stream in the red is loud enough to bring the next lurch forward.

The bottom-left **THỂ LỰC** bar is connected to the player's sprint reserve: it
drains while Shift-running and refills while walking or standing still.

Press **F1** to open the development panel. It can toggle invincibility, x3
movement speed, noclip flight, clear vision and the seven-entrance x-ray, force
the existing Statue, Crawler or Huntsman to manifest, and select entrance 01-07
for an immediate real door attack.

**Bay xuyên tường (noclip)** disables the player capsule and switches to free
flight: WASD follows where the camera is pointing, Space and Ctrl are straight
up and down, Shift is three times faster. Nothing collides while it is on, so
turning it off inside a wall leaves the player inside that wall.

**Soi 7 cửa xuyên tường** outlines every defense door through the house and tags
it with its entrance number and current range, so all seven can be found and
counted from anywhere without walking the ring. It reads the `defense_doors`
group, so it works on both maps.

**Sáng tối đa** takes the night off: no fog or volumetric fog, no vignette,
grain or threat distortion, no involuntary blinking (a ghost calling
`force_blink` is ignored), ambient light raised and a soft lamp on the camera.
The original `Environment` is kept and put straight back when the toggle is
cleared, so it never leaks into a real run.

Opening the panel
releases the mouse automatically; F1 closes it and restores the previous mouse
mode. Forcing the Huntsman in puts it inside a house with no breach, which seals
it in — see below.

Interior bulbs occasionally sputter through a short, localised blackout. The
electrical snap and buzz is positional at the affected fixture, and the system
prefers a room near the player so the rare event is not wasted off-screen.

The player starts on the front path facing entrance 01. Every floor is physically
connected: cellar stairs lead into the garage, the main-hall stairs reach the
second-floor landing, and a second flight reaches the attic.

## Survive until dawn

The HUD clock starts at **11:55 PM**. Every 1.5 real seconds advances exactly
one in-game minute, including the midnight rollover. Reaching **6:00 AM** stops
the threats, pauses the world, and displays the dawn victory screen. The clock
is hidden while the door-ghost encounter owns the screen.

## The totem ritual - buying the night back

The clock can also be pushed forward by hand. A lit **brazier**
(`items/totem_brazier.tscn`) waits near where the players start. Hold **E** at
it for three uninterrupted seconds with a **totem** in hand (Kenney stone head,
`items/totem.tscn`) and it burns: the night jumps **+30 minutes**.

Four rules make it a job rather than a button:

- **A totem needs both hands.** It declares `slot_cost = 2`, so carrying one
  fills the whole two-slot inventory - no flashlight fuel, no firewood, nothing.
- **The fire dies with every totem it eats.** Burning one puts the brazier out,
  and the next totem cannot go in until somebody has carried a piece of
  **firewood** (`items/firewood.tscn`, one slot) back to it and held **E** for
  1.5 seconds to relight it. Because a totem takes both hands, that is always a
  separate trip.
- **The map holds one totem and one log per player still in the run**, and
  nothing is scattered up front. Picking an item up does not replace it -
  burning it does, and the replacement appears somewhere else entirely.
- **4:00 AM is a ceiling, not a target.** A burn is granted only the minutes
  that are left below 4:00 AM, so burning at 3:50 buys ten minutes and lands on
  4:00 exactly. Once the night is there - burned to it or simply arrived at it -
  every totem and log still lying around vanishes and the brazier reads
  `NGHI LỄ ĐÃ HOÀN TẤT`. Dawn is still 6:00 AM; the ritual only ever shortens
  the two hours before it.

Every drop point has to be **at least 40 m from every player**
(`min_spawn_distance` on the `TotemRitual` node), chosen at random among the
rooms that qualify - 16 of the villa's 37 rooms do, so an item lands 40-55 m
away and somewhere different every time. House2 is 18 x 12 m and cannot honour
any such rule, so there the pick falls back to a random room out of the farthest
quarter. It degrades to "as far away as this map gets", never to "next to the
player".

Totems and firewood **glow only while you can actually see them**: inside the
camera frustum, within 22 m (16 m for firewood), and with nothing solid in the
way. The check is a frustum test plus one world-masked raycast every 0.12 s, so
the glow is a reward for sweeping a room with your eyes and never an x-ray
through a wall.

## Going down, and being picked back up

Being caught by a ghost is only the end of the run when nobody is left to come
back for you. With at least one teammate still on their feet, a kill puts you on
the floor instead:

- **Downed.** You cannot move, interact, or use an item. You can still look
  around from where you are lying, and ghosts stop treating you as a target the
  moment you go down — they will not finish a body on the floor, and they lose
  interest until somebody lifts you.
- **The budget is a whole run, not one death.** Every player has **180 seconds**
  of total floor time. Each death takes a flat **60 seconds** off that budget up
  front, and the rest drains in real time while you lie there. It never refills,
  so a rescue is a reprieve, not a reset, and three deaths is normally the limit.
- **The ring is the clock.** Downed players show as a ring drawn straight onto
  every teammate's HUD, so it reads through walls, and it stays pinned to the
  screen edge when the body is behind you. The outer sweep is the time left, the
  inner sweep is how far the rescue has got. Deliberately no numbers.
- **Ten seconds, held.** A teammate stands next to the body and holds **E** for
  ten uninterrupted seconds. The bleed-out clock is **frozen** for the whole
  rescue, so being reached in time is what matters, not being reached quickly.
  Letting go unwinds the progress at double speed.
- **Spectator.** When the budget reaches zero — bled out, or spent by a death
  with under 60 seconds left — the player becomes a spectator: no collision, no
  body, free flight, and no ghost will ever look at them again.

Alone, none of this applies. A kill with no teammate left standing runs the
original jumpscare and game-over screen exactly as before.

## House2 layout

- Basement: boiler and storage room; cellar exit 06 opens into a sunken exterior
  stairwell.
- Ground floor: kitchen, living room, dining room, garage, main hall, and storage.
  Entrances 01–03 are the front door, kitchen side door, and dining patio door.
- Second floor: two bedrooms, a large hall/stair landing, and bathroom. Entrances
  04 and 05 connect to separate exterior balconies.
- Attic: one full-footprint storage space beneath a pitched modular roof. Entrance
  07 opens onto a roof-entry deck.

Interior partitions use open modular frames so the navigation mesh, player, and
statue can circulate through every room. The seven exterior entrances remain
repairable defense doors used by the attack director.

## Door-ghost encounter

As soon as a door starts rustling, scratching, or being smashed, approach it,
aim at it, and press E. Control does not leave the world: the player is pinned to
the attacked door with the flashlight forced on, and the attacker is a real 3D
ghost standing somewhere in the exterior - the `Meshy_AI_Midnight_Grin_biped`
biped, in `ghosts/door_ghost.tscn`. Find it and hold the beam on it for
0.18 seconds and it is pushed back one step. **Each of the three phases costs
five hits of its own**, and the counter resets to `0 / 5` on every transition -
so the whole encounter is **fifteen** hits. Clearing the third phase hands the
door back through the same `complete_exorcism()` the previous version used - at
an intact door that drives the attacker away, at a breached one it unlocks
physical repairs.

The ghost's approach window is **5 seconds** per search/hit cycle - not per
phase - and every landed hit resets it in full. Ignore it and it walks in from its spot toward the door, the heartbeat
tightens, and teeth close in from the edges of the screen. With **1 second** left
(1.5 in the final phase) it stops where it stands, directly in front of the
player, and simply looks at them. At zero it attacks: the door takes its own
single **20-point** hit through `apply_exorcism_failure()` - the same call, so
durability, the repair ceiling and breaching are still owned entirely by
`door/defense_door.gd` - and the encounter hands the door back to the normal
attack flow instead of retrying.

The encounter opens up one phase at a time, each cleared by its own five hits:

| | Cost | Look limit | View |
|---|---|---|---|
| 1 · LỖ CHỐNG TRỘM | 5 hits | ±45° | behind the leaf, spyhole aperture |
| 2 · MỞ HÉ CỬA | 5 hits | ±60° | leaf swung 26°, wider opening |
| 3 · MỞ TOANG CỬA | 5 hits | free | leaf swung 88°, standing in the opening |

The overlay always shows where the player is *in the current phase* -
`PHASE 2 · MỞ HÉ CỬA` over `SOI MA: 0 / 5` - never a running total. The state is
`(state, phase)`: the SEARCH → RETREAT → SEARCH loop and the timeout path out of
it (STARE → JUMPSCARE) are identical in all three phases, so the phase is a
second axis rather than three copied sets of states.

Whether the beam is on the ghost is decided by the player's own `SpotLight3D` -
its range, its cone, and **one ray that has to arrive at the ghost's own
collider**. Being somewhere on screen is never enough, and a wall in the way
stops a perfectly aimed beam. Caught in it, the ghost stops walking, recoils
where it stands for a beat, and only then goes.

Its standing positions are `Marker3D`s in the **`door_ghost_positions`** group -
`DoorGhostPosition_A`…`_E`, authored once in `door/defense_door.tscn`, so both
maps get them from the shared door scene and the count stays open-ended. Each is
rebuilt on the encounter's own upright plane, floor-snapped, and pulled back out
of anything in front of it; a position the beam cannot reach from the doorway is
discarded, so the ghost can never hide somewhere unwinnable. A development safety
switch also suspends statue and crawler attacks until 1.5 seconds after the
encounter closes.

The ghost itself is only a body: `ghosts/door_ghost.gd` holds the model, its
poses and its hit volume, and is driven entirely by the encounter.
`ghosts/hunter_ghost.gd` keeps the Huntsman's real behaviour and does not know
it exists, so nothing here can change how the Huntsman plays.

## Ghosts

The three ghosts are built to be opposites, so that learning one teaches you
nothing about surviving the others.

| | Statue (`ghosts/statue_ghost.gd`) | Crawler (`ghosts/crawler_ghost.gd`) | Huntsman (`ghosts/hunter_ghost.gd`) |
|---|---|---|---|
| Senses | Sight — it freezes while any player can see it | Sound — it is blind, and hears movement | Tracks the floor you walked on, then sees you — in every direction at once |
| Counterplay | Keep looking at it, do not blink, and never let it inside 2 m | Go quiet: crouch, or stop moving entirely | Keep a wall between you for five whole seconds — then it walks away from you, not toward you |
| Space | Floors and stairs, on the navmesh | Floors, walls and ceilings; travels overhead | Every room on every floor, on foot, room by room |
| Arrival | Teleports into a scripted ambush, then vanishes | Announces itself with a fly-past, then sweeps the house | Walks in through a door it has already broken |
| Presence | Gone the moment you look away | Gone between hunts | Never teleports, never vanishes while inside |
| Kill | Grabs you during a blink or a look-away; distant statues surge much farther per blink, and a blink inside `blink_kill_distance` (2 m) kills outright with no wind-up | Leaps 13 m at 21 m/s, or mauls what it touches | Roars for 2.5 s, then charges a shade faster than a sprint and grabs |

Standing still is the correct answer to the crawler, staring is the correct
answer to the statue, and neither does anything at all to the huntsman. That is
what it is for.

The crawler hunts the last noise it *heard*, not where you are now. Sprinting,
landing a jump and working a door are loud; crouch-walking barely carries; and
standing still makes no sound at all, so its fix on you rots (`trail_decay`) and
it commits to a stale position. It leaves a trail of sound of its own — nails on
plaster as it moves, joints snapping every time it changes surface, breathing
once it is within a few metres.

The main-house instance also has an authored containment volume. Outside noises
cannot lure it through an exterior opening, and any pounce or wall transition
that crosses the building limit is cancelled back to the previous valid frame.

### The crawler's hunt cycle

It is not a permanent threat. It runs an announced cycle out of its attic lair:

1. **Hidden.** Not in the house at all, for `hidden_delay_min`–`hidden_delay_max`
   seconds. Nothing can hurt you, and noise cannot summon it — a loud house only
   shortens the wait.
2. **Omen.** It appears and bolts across one player's field of view at
   `omen_speed`, far too fast to catch and unable to kill during the dash. This
   is the only warning, and a hunt never starts without it. If no player can be
   given a clean fly-past it screams from overhead instead.
3. **Patrol.** It sweeps a fixed route (`crawler_patrol_points` markers, in tree
   order) `patrol_laps` times, at `crawl_speed` — under half a walking pace,
   biased upward so it travels the walls and ceilings. It can crawl right over a
   player who is holding still, and will.
4. **Hunt.** A noise above `patrol_alert_loudness` breaks the sweep. This is the
   dangerous state: from up to `pounce_range` (13 m) it launches at
   `pounce_speed` (21 m/s), so making a noise anywhere near it is fatal. A
   missed pounce leaves it face down and helpless for `pounce_recovery` seconds;
   that window is the escape.
5. **Retreat.** Laps finished with nobody found: one scream, and it is gone.
   That scream is also the all-clear.

Route markers and the lair are level data, not code — drop `Marker3D`s into the
`crawler_patrol_points` and `crawler_lair` groups and the creature picks them up.
With no markers present it falls back to sweeping around wherever it was placed.

### The Huntsman — what comes in when a door finally breaks

The other two are summoned by the night. This one is summoned by failure: a
defense door that reaches zero durability is a hole, and `hunter_ghost.gd`
subscribes to every door's `breached` signal. `entry_delay_min`–`entry_delay_max`
seconds later it is standing outside that doorway, and then it walks in — on
foot, in view, no teleport. Rebuild the door inside that window and nothing ever
enters.

Once inside it stops in the doorway and sweeps the house with its gaze for
`entry_scan_duration` seconds. That is the announcement, and it is the only one.

**The body.** `ghosts/stalker_rig.gd` builds it: a hunched 2.1 m skeleton with
arms longer than its legs, two rings of thin jointed arms writhing around a hole
where a face should be, and about forty eyes scattered over its chest, ribs,
joints, back and tail — every one of them independently aimed at whoever is
nearest, and independently blinking. It is ~280 parts, all of them procedural
primitives under `stalker_flesh.gdshader` (wet chitin, with a drier bone
variant) and `stalker_eye.gdshader` (a whole eye resolved from one sphere, so
the creature can afford to wear forty). It is written as a builder rather than
laid out in the `.tscn` because almost every part of it is a *chain*, and a
builder means the proportions are twenty constants at the top of one file and
every joint that exists is automatically a joint that animates. It is also
`@tool`, purely so that opening `hunter_ghost.tscn` shows the creature instead
of one empty `VisualRoot`; the parts it builds have no owner and are never
written into the scene file. The AI never touches a bone: it sets speed,
agitation, searching, charging and a look point, and the rig works out the gait,
the breathing, the crown writhe, the tail whip, the finger twitch and the drips.

Three hundred moving parts is enough to be a frame-rate problem, so the rig pays
for itself in three places. `stalker_flesh.gdshader` runs two noise octaves
rather than four — the four-octave version cost about a hundred and fifty hashed
lookups per fragment and was the most expensive thing in the frame. Only the
twenty-odd biggest masses cast shadows (`SHADOW_CASTERS`), because a finger bone
costs a shadow map exactly what a thigh does and is invisible in the result. And
`gaze_casts_shadows` is off by default: a *moving* shadow-casting spotlight
re-renders every lit caster in range, creature and house both, every single
frame. Turn it back on if the budget allows — it is the best-looking thing the
creature does. Per-frame animation costs about 0.45 ms with the eye aiming
spread round-robin over three frames and the drips and eye-tracking dropped past
`detail_distance`.

**Looking at it corrupts the camera.** Keeping the Huntsman near the centre of
the view inside `hunter_gaze_range` drives a dedicated full-screen interference
signal: animated sensor grain, scanlines, horizontal tearing and a red/cyan
split. It fades with angle and distance and a wall blocks the strong version.
A Huntsman within `hunter_gaze_through_wall_range` still leaks a faint signal
through that wall, regardless of camera direction, so being one thin partition
away feels wrong without turning the effect into a long-range detector. This is
computed on each player's local camera and therefore remains per-player in a
multiplayer session.

**It hunts by track.** Every `spoor_interval` (0.4 s) each player writes a mark
to the floor: a position, a time, and a strength. Sprinting prints hard,
crouch-walking barely prints, and standing perfectly still still prints — faintly,
directly under your feet. Marks fade over `spoor_lifetime` (110 s) and become
unreadable below `cold_trail_strength`. The huntsman reads only what is inside
`nose_range` (7.5 m), takes the freshest mark it can find there, walks to it, and
reads again — and it only ever accepts marks *newer* than the last one it used,
so it walks your route forwards and can never be sent in a circle by your
history. Its knowledge is therefore local: rooms it has not physically reached
are genuinely safe, and the trail it is following is one you already left.

Outside a direct charge, every walking/tracking pace is multiplied by
`non_chase_speed_multiplier` (1.3), so its search movement is 30% faster than
the authored base speeds.

**Losing it and being found again.** With no readable mark it stops, sniffs and
turns on the spot (`cast_duration`). Then it lifts its head and takes the longest
scent it has — the freshest mark anywhere within `cast_lead_range` (30 m, most of
the house) — and walks to where that was. Against a player who keeps moving this
lead is always one address out of date and costs them nothing. Against a player
who has stopped, it is the thing that eventually opens their door. Only with
nothing readable anywhere does it fall back to quartering the house along the
`hunter_sweep_points` markers. A full sprint within `running_hearing_range` does
not make it hunt sound; it just gives it somewhere new to go and read the floor.

**Knowing when it is beaten.** Two separate tests, because wedging has two
shapes. The fast one watches the ground it actually covers, not the distance to
its destination — a route to the room above starts by walking *away* from it
toward the stairs, so distance-closed is a lie on a staircase. The slow one
(`no_closing_time`) watches whether it has closed any distance on its goal at
all over several seconds, which is what catches a body sliding back and forth
along a rail at full speed and getting nowhere. Fail either and it gives up on
that destination: it peels off at an angle
(`unstick_duration`), burns the mark, and writes off that patch of floor for
`give_up_memory` seconds so a motionless player printing fresh marks in an
unreachable spot cannot pin it there. Three failures in a row and, only while
nobody can see it, it relocates to the nearest room on its route. Without all of
this it was possible to leave it standing on a staircase for the rest of the
night, which is the one failure state a creature built on relentlessness cannot
have.

**It sees in every direction.** There is no cone and no spotting meter: it is
covered in eyes, so any player inside `sight_range` (15 m) with an unbroken line
to it is seen the frame they become visible — from behind exactly as readily as
from in front. Crouching does not help. Standing behind a wall does. The gaze
cone that sweeps the corridor is now cosmetic (`gaze_sweep_speed`,
`gaze_sweep_half_angle`); it is how the player sees it coming, not how it sees
the player.

**It also has ears.** Not the crawler's — that creature *is* its hearing, and
reaches 16 m — but good enough that being near it while upright brings it over.
Range scales with how loud you are on the same curve, over a smaller radius
(`hearing_range`, 13 m at a full sprint, about a room's width at a walk).
Crouch-walking falls under `hearing_loudness_floor` at any distance and standing
still makes no sound at all, so crouching is the one movement it cannot hear.
Hearing never locks on; it only ever hands it somewhere new to go and read the
floor.

**Being seen: the roar, and then the run.** The instant it has somebody it
plants, turns to face them and roars for `roar_duration` (2.5 s) at a volume the
whole house hears — including the players it has *not* seen. Those seconds are
the entire warning, and the entire head start: about eighteen metres at a
sprint. Then it charges at `charge_speed` (8 m/s against a 7.5 m/s sprint), so
it closes half a metre a second — a corridor is a slow loss rather than an
instant one, and eighteen metres is enough room to actually reach the corner you
were running for. It also has `acceleration` of a loaded truck and cannot move
at full speed in a direction it is not already facing (`off_axis_speed_floor`),
so corners, doorways and stairs are where the chase is actually won. What you
cannot do is duck behind one sofa: losing line of sight does not shake it, it
keeps coming to where you were, and only a full `lose_sight_time` (5 s) unseen
drops the chase. And when it does give up it does not do the correct thing: the
trail you just laid getting away is the hottest thing in the building, and
reading it would walk it straight back onto you, which is unbeatable and
therefore not a game. Instead it turns around and walks `disengage_distance`
(11 m) in the *opposite* direction from where it last saw you, reading nothing
at all on the way, and its trail clock resets to the moment it gave up so those
fresh marks are already too old to use. It can only pick you up again from
wherever you go next. Once it has seen you it does keep your scent for the rest
of the night (`marked_nose_bonus`).

Everything short of that charge moves at `walk_speed` (2 m/s) — slower than a
walking player, so an unaware huntsman can be walked away from in any direction.
Its footfalls are deliberately loud and carry most of the way across the house,
getting louder as it closes: hearing which room it is in and going the other way
is the counterplay to something that outruns you once it looks up.

**And it never leaves.** There is no hunt timer, no giving up, and no walking
back out through the hole it came in by. Once it is inside, it is inside until
dawn. Rebuilding every breach behind it therefore no longer locks it out of an
exit it wanted — it only trips `sealed_inside`, which makes it faster
(`trapped_speed_bonus`) and sharper-nosed (`trapped_nose_bonus`) for the rest of
the night. It lays no traps either; that behaviour is gone.

**The grab.** At `seize_range` it plants and reaches: `seize_windup` is half a
second, and that half second is the only window there is. The reach is
deliberately longer than a person's (2.35 m) because it is two and a half metres
of hunched shoulders with a hook on one arm — it takes people over the stairwell
bannister and through the gap in a doorway it cannot itself fit through. A
shorter reach left a player standing two metres away, lit, being stared at, and
completely untouchable.

**It does not give up on somebody it can see.** If it cannot close — pressed
against a rail with you on the other side — it drops navigation for
`direct_press_duration` and pushes straight at you instead, because pathfinding
is exactly what dithers along a railing. Only losing sight of you for
`lose_sight_time` (5 s) ends a lock.

**Sealed in.** It has no exit behaviour at all: no hunt timer, no giving up, no
walking back out through the hole it came in by. Once it is inside it is inside
until dawn. Rebuilding every breach behind it therefore does not shut a door it
wanted — it trips `sealed_inside`, and being sealed in with you makes it faster
(`trapped_speed_bonus`) and sharper-nosed (`trapped_nose_bonus`) for the rest of
the night. Repairing your own house is still not an unambiguously correct move,
but for the opposite reason it used to be.

Route markers are level data, not code — drop `Marker3D`s into the
`hunter_sweep_points` group and it picks them up, and the average of those
markers is also what tells it which side of any doorway is indoors.

All three ghosts report threat through `Player.set_threat_from`, which keeps the
horror overlay on whichever is currently worse.

## Second map — Biệt thự Vành Đai (`house3/`)

House2 is 18 × 12 m and its seven entrances are close enough that one player can
cover several of them. `NEH_map_spec_v2.md` asks for a house about four times
that size, where the geometry itself forces the team apart. That map lives in
`house3/` **beside** House2. The multiplayer entry point now selects the Villa,
while the House2 scenes and tests remain available. The villa reaches the
player, the three ghosts, the defense doors, the power system and the audio
through exactly the same node groups.

Run the full multiplayer flow with F5, or run `house3/villa_main.tscn` directly
with F6 for an offline Villa session.

The one behavioural difference is the huntsman. House2 has a single one that
walks in through whichever breach it likes; the villa is big enough that one
creature is not a threat to a spread-out team, so `villa_main.gd` spawns a fresh
huntsman *at* each entrance that breaks — capped at `MAX_BREACH_HUNTERS` (3).
The cap matters because a huntsman never leaves: without it, seven lost doors
would mean seven bodies in the building for the rest of the night, and the
fourth one is a frame-rate problem before it is a difficulty problem. Further
breaches past the cap are still holes the player has to live with, they just do
not add another creature. The scene's own dormant `HunterGhost` stays out of it
entirely, as a DevTools template with `entry_enabled` off.

The one behavioural difference is the huntsman. House2 has a single one that
walks in through whichever breach it likes; the villa is big enough that one
creature is not a threat to a spread-out team, so `villa_main.gd` spawns a fresh
huntsman *at* each entrance that breaks — capped at `MAX_BREACH_HUNTERS` (3).
The cap matters because a huntsman never leaves: without it, seven lost doors
would mean seven bodies in the building for the rest of the night, and the
fourth one is a frame-rate problem before it is a difficulty problem. Further
breaches past the cap are still holes the player has to live with, they just do
not add another creature. The scene's own dormant `HunterGhost` stays out of it
entirely, as a DevTools template with `entry_enabled` off.

| | House2 | Villa |
|---|---|---|
| Footprint | 18 × 12 m | 80 × 60 m, 40 × 30 cells of 2 m |
| Storeys | 4 at 3.0 m | 4 at 3.5 m (cellar, ground, first, attic) |
| Rooms | 12 | 33 plus a light shaft |
| Circulation | central hall | ring corridor + cross, 9 junctions per floor |
| Authoring | hand-placed in GDScript | generated from `neh_map_spec_v2.json` |

### How it is built

`house3/neh_map_spec_v2.json` holds the spec's §5–§9 tables verbatim and is the
only source of geometry. Per spec §10.2 nothing parses the ASCII plans in §3 —
they are for human readers, and their Vietnamese labels overwrite the cells they
sit on.

`villa_spec.gd` reads that file and rasterises one storey at a time following
§10.2: fill the footprint with wall, carve the rooms, carve the corridors, tag
the junctions, open the door cells, repaint the light shaft solid on the floor
above it, and cut the entrances into the outer wall. `villa_house.gd` then turns
that cell grid into geometry — greedy-rectangle floor slabs, wall runs merged
along each straight face, doorways, ramps and railings — and publishes
room, junction, entrance, spawn and ghost-route markers.

Four compact 4 × 4 m WCs are cut into the outer room bands: two on the ground
floor and two upstairs, staggered between the north and south sides. Each is a
single-door dead end with one interactive toilet, one sink and one mirror. The
separate upstairs main bathroom is also reduced to 8 × 8 m and retains its
bathtub and shower.

### Editing generated villa parts

Open the scene the parts should live in - `house3/villa_main.tscn` is the one
that is played, and it is where the current bake sits - select its `VillaHouse`
node, and use the **Villa Authoring** controls in the Inspector:

1. Set detail and furniture to the version you want to edit.
2. Press **Bake Editable Parts**, then save the scene.
3. Expand `Generated/Level_*/Architecture`. Walls, floor slabs, ceilings and
   railings are now separate 2 m modules. Moving a body moves both its visual
   mesh and collider, while imported FBX and door scenes remain packed instances.

**Rebuild Preview** replaces `Generated` but keeps it disposable and unsaved.
**Clear Generated Parts** removes a baked version; save after clearing to return
to generation from `neh_map_spec_v2.json` at runtime. Baking deliberately switches
`Authoring Granularity` to `Editable Modules`. The default `Optimized` mode still
merges long wall and slab runs and should be used when no hand editing is needed.

Do not press either rebuild button after hand-adjusting baked parts unless those
changes can be discarded: rebuilding treats the JSON spec as authoritative.

The trade runs the other way too. `VillaHouse._ready()` returns as soon as a
baked `Generated` node exists, so a baked scene stops following
`villa_house.gd`: fix the builder and the saved parts keep the old geometry
until they are baked again. Re-bake after every builder or spec change, and run
`tests/villa_boot_smoke.gd`, which measures the baked stairs against the floors
they are supposed to join.

Two departures from the document, both deliberate:

- **The attic ladder (`V04`) is built as a steep companionway, not a ladder.** A
  `CharacterBody3D` cannot climb a vertical ladder in this project yet, so a map
  that shipped one would have an unreachable attic and an unreachable `E07`. It
  keeps its `hands_required: 2` and `cost: 5.0` metadata, so the two-handed rule
  from §11 can be enforced in gameplay code later without touching the geometry.
- **`E07` is laid flat.** The attic skylight has no wall to sit in, so its
  defense door is tipped onto its back and set into the attic ceiling as a
  boarded roof hatch. Standing it upright would have left a door slab in the
  middle of the attic floor and the skylight itself open to the sky.
- **`E05` gets a service culvert.** The spec puts the "outdoor" cellar door on
  the basement's west wall at column 19 — which is under the west wing, not
  outdoors. The coal chute therefore runs west as a covered culvert and surfaces
  in the garden. This preserves what §11 actually wants from `E05`: it stays the
  door that is 30–42 s from everything else.

One inconsistency in the spec is worth knowing about. §10.6 rule 5 forbids a room
with exactly one door, but the §5 door tables give exactly one to Thư viện,
Kho thực phẩm, Phòng trẻ em, Phòng tắm lớn and Phòng máy. The diagrams agree with
the tables, so the tables win and those rooms are listed in `single_door_rooms`
in the JSON. Any *new* one-door room still fails validation.

### Getting a ghost across the villa

Two things about the villa - neither of which House2 has - stopped every hunt
dead, and both look identical from the hallway: the statue manifests, walks a
few metres, then wanders off and never arrives.

**The staircases bake as islands.** Recast erodes every walkable surface by the
agent radius, and a 45-degree ramp is narrow enough that the erosion regularly
lifts a whole run clear of the floor it starts on. `V01`, the grand staircase in
the room the player spawns in, came out joined to the upper landing and to
nothing below it: a route from the foyer to the landing five metres overhead
went 152 m around the entire building. The statue only ever hunts a target on
its own storey, so it simply never used the stairs.

`villa_main.gd` therefore states each staircase as a chain of three
`NavigationLink3D`s - floor to the bottom step, bottom step to top step, top
step to the landing - rather than one span from storey to storey. Three hops
instead of one because **a link is not a teleport**: `NavigationAgent3D` hands
the far end over as the next path position and the body steers straight at it,
so every hop has to be walkable on its own. A single floor-to-landing span is
only walkable when it happens to lie along the run, and V01's does not - its
bottom step stops half a metre from the foyer's east wall, so its lower anchor
has to sit beside the staircase rather than in front of it. The middle hop
covers the other half of the problem: `V03` bakes with a metre-wide hole
halfway down the run, where the ground floor's slab edge clips its headroom.

None of the anchors are dead-reckoned. Each end is searched for - out along the
run, then to either side of it - and the first probe that lands on real
navigation at the right storey wins. The links can only be placed once the
NavigationServer has folded the region into its map and then re-iterated with
the links in it, so `villa_main` exposes `navigation_is_ready` and a
`navigation_ready` signal; a route asked for before that still walks around
every staircase in the house.

**Every internal doorway carries a closed door.** The navmesh is baked with the
door leaves deliberately lifted out - a closed door would otherwise freeze into
the route graph as a permanent wall and cut each storey into one island per
room - so ghost routes run straight through doorways. Nothing then opened them.
A ghost has no hands and never presses E, so the first door on its route held
the hunt for the rest of the night; a statue sent after a player two rooms away
would jam against a leaf and stand there. House2 has only open door frames,
which is why this never showed up there.

`door.gd` now lets anything in `hostile_ghosts` shoulder a leaf open, at the
cost of the swing, and swings it shut again five seconds after the doorway is
clear - leaving 48 doors standing open would quietly retire the "shut it behind
you" tactic. A hidden ghost clears its own collision mask, so asking whether the
leaf can block it is also asking whether it is really in the house yet: doors do
not open for something that has not manifested. `ghost_shoulder_enabled` turns
it off per door.

### Furniture

Rooms are not dressed by hand. `FURNITURE_PLANS` in `villa_house.gd` gives each
room *kind* four lists — `unique` pieces it has exactly one of, `large` carcass
furniture, `small` accents, and an optional `table`/`seat` centre group. The
builder walks the room's perimeter, collects every cell that has a wall on one
side and is not reserved, and stands pieces against those walls facing into the
room, one per four cells of floor. Bigger rooms also get a few pieces dropped on
a three-cell lattice in the middle, so a 24 m attic does not read as a furnished
corridor around an empty hall. Placement is seeded per room id, so a room looks
the same every launch and players can learn where the cover is.

Doorways, breach points and staircases — plus a one-cell margin around each —
are reserved before anything is placed. And because a room's geometric centre is
usually occupied by that room's own table, every room marker also publishes a
`clear_point` meta: the nearest tile something can actually stand on. Ghost
patrol routes, sweep points and the statue's start position all use it.

### Verifying the villa

```
godot --headless --script tests/villa_layout_smoke.gd
godot --headless --script tests/villa_seal_smoke.gd
godot --headless --script tests/villa_boot_smoke.gd
godot --headless --script tests/villa_editable_parts_smoke.gd
godot --headless --script tests/villa_ghost_chase_smoke.gd
```

`villa_layout_smoke.gd` runs spec §10.6 against the tables before any geometry
exists: flood-fill reachability from `SP_PLAYER_1` across all four storeys
including the vertical links, the light shaft being solid on `F_01`, every
entrance touching the room it claims, the junction graph being connected and
still containing a cycle (lose the cycle and the ring design is broken), and no
undeclared single-door room. It then builds the house in blockout detail and
checks the markers and groups it publishes.

`villa_seal_smoke.gd` fires rays out of all 1998 walkable cells — down, up, and
sideways at both waist and head height — and fails on any that escape through
something the spec did not ask for. The only openings it permits are the light
shaft, the stairwell holes and the attic skylight, and it derives all three from
the spec rather than from a hardcoded list.

`villa_boot_smoke.gd` boots `villa_main.tscn` at full detail and asks the baked
navmesh for real paths — hall to cellar, hall to attic, library to kitchen — plus
the seven defense doors at their correct storey heights, and that every one of
the 50-odd ghost route markers is reachable from the player spawn. That last
check is the guard against furnishing a room shut.

`villa_editable_parts_smoke.gd` builds the authoring variant, checks that walls,
floors and ceilings are cell-sized, then packs and reloads the result to prove
that generated nodes and gameplay groups survive baking.

`villa_ghost_chase_smoke.gd` covers the two hunt-killers above, because both are
invisible to a route query: it puts a player on V01's landing and the statue in
the foyer below and requires it to climb, then puts a player in the foyer and
the statue in the corridor behind it and requires it to come through the shut
door between them.

Between them these five caught every bug in this map worth recording: a
storey's worth of walls stacked at y=0, closed interior doors baking into the
navmesh as permanent walls, the basement stair running out of floor at its foot,
untiled floor strips in odd-height rooms, an unlined light shaft, unrailed
stairwell openings, and a wardrobe parked on the approach to the cellar stair.

`tests/villa_screenshot.gd` and `tests/villa_devshot.gd` are not tests — they
park a camera in the house (the second one with the dev toggles flipped) and
write PNGs to `user://villa_shots`. `tests/stalker_devshot.gd` does the same for
the huntsman's body, rendering it from the concept sheet's own angles (front,
three-quarter, side, back, charging) into `user://stalker_shots`, which is how
its proportions get retuned without guessing. Two bugs got past every
assertion above and were only visible in those images: the kit staircase was
being scaled on the wrong axes, which made it twice its own length and half a
storey too tall, and the balustrades were placing one 1 m panel per 2 m cell,
leaving a metre of open air between every section. Both are now driven by
constants measured off the kit (`KIT_STAIR_RUN`, `KIT_STAIR_RISE`,
`KIT_RAIL_WIDTH`) instead of guessed factors.

The stair's 4.2 m full height includes a 1.2 m handrail above its 3 m landing;
it is not the tread rise. `villa_boot_smoke.gd` measures the tread mesh against
both connected floors so confusing those two dimensions cannot leave the upper
step floating below its landing again.

## Verification

The smoke tests under `tests/` cover the four-level layout, all seven entrance
IDs, generated collision, basement-to-attic navigation, physical stair traversal,
statue stair chases and ambushes, crawler surface-crawling and noise hunting,
doors, the breached-door minigame, temporary ghost safety, interaction, and
house audio. `dev_tools_smoke.gd` covers the F1 development controls, while
`night_clock_smoke.gd` verifies the 1.5-second minute tick,
midnight rollover, and the 6:00 AM victory boundary.

`hunter_ghost_smoke.gd` covers the huntsman's contract: it only gets in through a
breach, a door rebuilt before it arrives keeps it out entirely, it follows a
trail laid on the floor with no sight or sound to go on, a mark it can smell but
cannot reach does not freeze it, it hears an upright player and not a crouched
one, seeing a player produces a full roar before a single step, that roar leads
to a kill, losing a player sends it walking away from them rather than back onto
them, attack safety still blocks that kill, sealing the last breach traps it
inside, and a wide-open breach and twelve quiet seconds still leave it in the
house - because it never leaves.
`hunter_body_smoke.gd` covers its body instead of its hunt, because a model swap
rots silently: that the body under `VisualRoot` really is the shared Midnight
Grin biped, that it still fits through a 2.4 m doorway in every pose, that its
feet still meet the floor the collision capsule stands on, that every clip the
hunt can ask for is actually in the library (a clip the library lacks leaves the
creature holding whichever pose it was already in, which is the one bug a
screenshot will not show), and that the gaze light is still at head height.
`crawler_locomotion_smoke.gd` covers how the crawler gets about, as opposed to
what it wants: that it works its way round an obstruction instead of shoving at
the face of it, and picks the side the obstruction actually ends on; that
holding still on purpose is not mistaken for being wedged; that a player who
keeps moving cannot stop it noticing it is wedged, which is what used to pin it
on a ceiling indefinitely; that its search sweeps pick points on its own side of
a wall; and that with a navigation mesh baked under it, a patrol still leaves the
floor for the wall - the navmesh used to suppress the climb entirely, so in both
shipping houses the wall-crawling never actually happened.
`downed_revive_smoke.gd` covers the co-op downed contract above: that a kill with
a teammate still standing puts a player on the floor rather than ending their
run, that no ghost will target them there and will again once they are up, that
each death charges exactly 60 seconds of the 180-second budget, that the
bleed-out clock is genuinely frozen for all ten seconds of a rescue and the
budget is not refilled by one, that a teammate out of range cannot start a
rescue, that spending the last of the budget goes straight to spectator with no
collision left in the world, and that a kill with nobody left standing still
shows the original death screen.
`house_hunter_sweep_smoke.gd` then drops it into House2 itself, in three stages:
it must search real rooms across the baked navmesh instead of grinding into the
first wall; it must find a player standing perfectly still two floors above it;
and it must take a player who stands at the head of the stairs with the bannister
between them, which is the specific place it used to fail.

Run one with:

```
godot --headless --script tests/crawler_ghost_smoke.gd
```
