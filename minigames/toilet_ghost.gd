class_name ToiletGhost
extends Node3D

## Toilet-minigame-specific threat, owned and driven entirely by
## ToiletMinigame (arm()/update()/reset() called from its start_session()/
## _process()/_cleanup()). This has no _process() of its own, so it cannot
## run a single frame outside the toilet minigame's own already-guarded
## loop - nothing to leak, nothing to stop separately on exit.
##
## ## Catching it in the act
##
## The ghost appears as far from the player as the room still lets them see
## it, and from then on alternates between standing dead still and lurching
## a step closer. It advances on its own clock whether or not it is being
## watched - that is the whole point: the player's job is to be looking
## during one of those windows, not to look often.
##
## What a sighting does depends on what it was doing:
##
## - **Caught mid-lurch** - it stutters, glitches and is gone at once. This
##   is the skill play, and it is the only way to be rid of it in one look.
## - **Caught standing still** - it counts, but only once per lurch. Looking
##   again while it is still standing does nothing; the tally only moves
##   again after it has taken another step. Three tallies and the next
##   sighting banishes it, so patient checking works too - it just costs
##   three well-spent looks instead of one well-timed one.
##
## Staring is not a strategy. Observation time accumulates across looks in
## `_stare_time` and does not decay when the player glances away; spend more
## than stare_tolerance watching a single lurch cycle and the ghost takes a
## long stride instead of its usual step. Only its own movement resets that
## budget. Without this the dominant play is simply to watch it forever,
## which is safe from the ghost and fatal to the bladder - the stream is in
## the red the whole time, so nothing drains and the session never ends.
##
## Distance is tracked as `advance` in [0, 1] rather than as an integer step
## count, because a stare-punishment stride is longer than a normal one; the
## step *counters* (`step_index`, `spot_count`) drive the rules above, while
## `advance` alone decides where it stands and how far it leans. In a room
## with no floor left to give - the villa's WCs are 4x4 m dead ends - the
## lean/lift axis absorbs whatever advance the geometry refused, so the
## escalation stays readable without per-map tuning (see _apply_lean()).
##
## Visibility detection duplicates ghosts/statue_ghost.gd's
## _camera_can_see_point() idiom (FOV cone + frustum + occlusion raycast)
## rather than sharing code with it - that mirrors the existing project
## convention (each of the three ghosts already owns its own copy of this
## check; there is no shared perception utility today), and keeps
## statue_ghost.gd completely untouched.

signal ghost_seen
signal ghost_timed_out

## HOLDING and MOVING are the two halves of the lurch cycle the whole design
## turns on - which one the ghost is in when it is seen decides what that
## sighting is worth. STUTTER is the caught-in-the-act beat before it
## actually vanishes; DISAPPEARING is the forced blink after that.
enum GhostPhase { IDLE, WAITING, HOLDING, MOVING, STUTTER, DISAPPEARING }

## The rear-left and rear-right arcs are each sliced into two zones. A spawn
## must use the opposite side from the previous one, so the player has to
## turn back and forth instead of camping one shoulder. There is deliberately
## no front-facing zone: every arrival is behind the seated player and costs
## a real turn, which also throws the nozzle off centre.
enum SpawnZone { LEFT_OUTER, LEFT_INNER, RIGHT_INNER, RIGHT_OUTER }
const SPAWN_ZONE_COUNT := 4

## Vertical span of the downward ray _floor_y() uses to find the floor: far
## enough above the seated player to start outside any slab, far enough below
## to still find the floor of a tall room.
const FLOOR_PROBE_UP := 0.5
const FLOOR_PROBE_DOWN := 3.0

## Key into the player's per-source threat table (player.gd
## set_threat_from()) - the horror overlay shows the worst live threat, so
## reporting the ghost's advance through it is what makes the screen react
## without this file touching the overlay, and what lets a crawler in the
## hallway still out-dread a ghost that has only just appeared.
const THREAT_SOURCE := &"toilet_ghost"

@export_category("Spawn Timing")
## The first Ghost of a session always appears at exactly this many seconds
## in - not randomized, unlike the repeat spawns below.
@export var initial_spawn_delay: float = 4.0
## A ghost carried over from a cancelled attempt skips the suspense delay. A
## fraction of a second remains only so the camera can finish seating the
## player before spawn geometry is measured.
@export var resumed_spawn_delay: float = 0.3
## After a Ghost is banished, the next one appears after a fresh random wait
## in this range - never sooner than the minimum, never later than the
## maximum. Re-rolled every time.
@export var min_respawn_delay: float = 7.0
@export var max_respawn_delay: float = 10.0

@export_category("The Lurch Cycle")
## How long it stands still between lurches. This is the window the player is
## actually playing against: check too early and it is still standing (worth
## a tally), check during the lurch and it is gone.
@export var hold_duration: float = 3.0
## Randomness either side of hold_duration, so the cycle cannot be counted
## out loud after the first two.
@export var hold_duration_jitter: float = 0.8
## How long one lurch takes. The entire window in which the ghost can be
## caught in the act - long enough to be catchable by someone already
## turning, short enough that it cannot be waited for.
@export var move_duration: float = 0.7
## Lurches before it reaches the player. Ignore it completely and this many
## cycles is how long you have.
@export var steps_to_reach: int = 5
## Sightings-while-standing needed before one banishes it. Each lurch can
## only ever yield one, no matter how many times the player looks - see
## _register_spot().
@export var spots_to_banish: int = 3
## Total seconds of watching one lurch cycle before the ghost punishes it
## with a long stride. Accumulates across separate looks and is only cleared
## by its own movement, so glancing away does not bank progress back.
@export var stare_tolerance: float = 3.0
## How much longer a stare-punishment stride is than a normal lurch.
@export var stare_step_multiplier: float = 1.8
## How long the caught-in-the-act glitch runs before it actually vanishes.
@export var stutter_duration: float = 0.45
## Peak size of the stutter's positional jitter, in metres.
@export var stutter_amplitude: float = 0.09

@export_category("Presence")
## Closest a lurch brings the ghost to the player, in metres. Has to stay
## clear of the player's own capsule and the toilet they are sitting on -
## the model is 0.69 m wide, so anything under about a metre puts it
## visually inside them rather than looming over them.
@export var contact_distance: float = 1.15
@export var lean_max_degrees: float = 18.0
@export var lift_max: float = 0.3
## Fraction of a full lurch that one danger-zone noise burst shaves off the
## current hold. Bad aim is loud, and loud brings the next lurch forward -
## which is what couples the two halves of the toilet minigame instead of
## running them as two unrelated timers.
@export_range(0.0, 1.0) var noise_hold_penalty: float = 0.35
@export var lurch_volume_offset_db: float = -8.0
@export var lurch_pitch_scale: float = 0.72

@export_category("Spawn Position")
## Nearest and furthest the ghost may first appear. It always takes the
## furthest its chosen bearing actually allows (see _pick_spawn_position) -
## it should start at the far end of what the player can still see, so the
## lurches have somewhere to come from. The minimum is what makes a bearing
## usable at all; a real bathroom does not have 2 m of clear floor in most
## directions - House2's has 1.55 m straight ahead and 2.00 m to the left -
## and a minimum the room cannot satisfy is what used to send every
## candidate in those directions into a wall.
@export var spawn_min_distance: float = 1.5
@export var spawn_max_distance: float = 4.0
## How far short of whatever is behind it the ghost is kept. The spawn
## distance is clamped to the measured free floor on the chosen bearing
## minus this, so it stands in the room rather than in the wall panel.
@export var wall_margin: float = 0.45
## Used instead of spawning when no bearing in the whole arc can host the
## ghost. A ghost that cannot legally appear must not appear - the previous
## behaviour here was to place it anyway, unchecked, at spawn_min_distance,
## which is how it ended up inside walls where it could never be seen or
## caught.
@export var blocked_spawn_retry_delay: float = 1.0
## Ghost spawns are sampled within this many degrees either side of the
## camera's orientation at the moment the toilet minigame started (not the
## camera's current, possibly-already-turned orientation). This is the outer
## edge of the rear diagonal and must stay inside ToiletMinigame's yaw clamp.
@export var spawn_yaw_range: float = 165.0
## Inner edge of the rear diagonal. At 120 degrees, every spawn is behind
## the player but still clearly to the left or right rather than directly at
## six o'clock. The matching-side alternation is enforced in _next_zone_angle.
@export var min_spawn_offset_angle: float = 120.0
## Consecutive spawns must differ in yaw by at least this much. Alternating
## rear sides already guarantees a large turn; this remains an extra guard
## for customized spawn arcs.
@export var min_spawn_angle_separation: float = 25.0
## How many times to re-roll a rear-opposite zone/angle that violates the
## angle-separation rule before taking the best available pick (see
## _furthest_zone_angle()). Bounded so this can never spin.
@export var max_spawn_attempts: int = 10
@export var spawn_sample_count: int = 12
@export_flags_3d_physics var spawn_blocking_mask: int = 1
## Radius of the point-overlap check used to reject a spawn candidate that
## would land inside a wall/floor - mirrors player.gd's own _can_stand()
## shape-query idiom, not a new physics convention. The same check gates
## every lurch, which is how a cramped room converts walking into leaning
## instead of pushing the ghost through a wall.
@export var spawn_clearance_radius: float = 0.2

@export_category("Detection")
@export var observation_half_angle: float = 30.0
## Must stay comfortably above spawn_max_distance. The ghost's head sits
## fractionally *above* the camera, so a ghost spawned at exactly
## spawn_max_distance is slightly further than that in true 3D distance -
## with the two equal, the furthest spawns fell the wrong side of this
## check and could never be seen at all.
@export var maximum_observation_distance: float = 6.0
@export_flags_3d_physics var sight_blocking_mask: int = 1
## Height of the Sprint 3 model's face above its own floor-anchored root
## (see assets/ghosts/toilet_ghost/README.md). The "seen" check targets this
## point rather than the root, so the player has to actually look at the
## head - not just glance at the ghost's feet.
@export var head_height: float = 1.58

var phase: GhostPhase = GhostPhase.IDLE
## Distance travelled along the rail so far, 0 at the spawn point and 1 at
## the player. Not derived from step_index because a stare-punishment stride
## is longer than a normal lurch - see the class doc comment.
var advance: float = 0.0
## Lurches completed. Only used by the rules (the tally cycle), never to
## position the ghost.
var step_index: int = 0
## Sightings-while-standing banked so far, capped by spots_to_banish.
var spot_count: int = 0
## Whether this lurch cycle has already yielded its one tally. Cleared when
## the ghost moves, which is what makes looking twice at a stationary ghost
## worth nothing.
var _spotted_this_cycle: bool = false
## Observation time accumulated in this lurch cycle. Deliberately never
## decays - see the class doc comment.
var _stare_time: float = 0.0
var _spawn_timer: float = 0.0
var _hold_timer: float = 0.0
var _move_elapsed: float = 0.0
var _move_from: float = 0.0
var _move_to: float = 0.0
## Whether the lurch under way is the stare punishment rather than an
## ordinary timed step. Punishment lunges cannot be caught and do not
## re-arm the tally - see _update_moving().
var _move_is_punishment: bool = false
var _stutter_timer: float = 0.0
var _blink_timer: float = 0.0
var _active_player: Node3D
var _rng := RandomNumberGenerator.new()
## Direction of the previous spawn, so the next one can be kept away from
## it. -1 means "no previous spawn this session" (the first ghost is free to
## use any zone). Reset with the rest of the session state.
var _last_spawn_zone: int = -1
var _last_spawn_angle: float = 0.0
## Advance restored from earlier cancelled sessions. It is applied only after
## a legal rail has been found, because the rail defines what "closer" means
## in the current bathroom.
var _pending_start_advance: float = 0.0

## The rail the lurches travel down, captured once at spawn. The player
## cannot move for the rest of the session (movement is locked by the
## minigame), so the origin, eye, floor and bearing are all fixed and there
## is nothing to recompute per frame.
var _rail_origin: Vector3 = Vector3.ZERO
var _rail_eye: Vector3 = Vector3.ZERO
var _rail_floor_y: float = 0.0
var _rail_direction: Vector3 = Vector3.FORWARD
var _rail_far_distance: float = 0.0
## Highest advance whose rail position actually passed the clearance and
## line-of-sight checks. Anything above it is advance the room had no space
## to express as movement, and gets spent on lean/lift instead - see
## _apply_lean().
var _expressed_advance: float = 0.0
## Resting offset written by _ready(), so lift can be added on top of it
## without the two fighting over visual.position.y.
var _visual_base_y: float = 0.0
var _teleport_base_volume_db: float = 0.0

@onready var visual: Node3D = $Visual
@onready var teleport_audio: AudioStreamPlayer3D = $TeleportAudio


func _ready() -> void:
	_rng.randomize()
	# Danger-zone noise from the player's own bad aim brings the next lurch
	# forward - ToiletMinigame._emit_danger_noise() calls this group alongside
	# the crawler's and hunter's. Every other toilet in the map is in the
	# group too; report_noise() no-ops unless this particular ghost is live.
	add_to_group(&"toilet_ghosts")
	visual.visible = false
	# _pick_spawn_position() nudges its candidate up by spawn_clearance_radius
	# so the clearance-check sphere clears the floor - a physics-query fudge,
	# not the ghost's true resting height. Cancel it back out here so the
	# model's own floor-anchored root actually touches the floor instead of
	# hovering by that same amount.
	visual.position.y = -(spawn_clearance_radius + 0.02)
	_visual_base_y = visual.position.y
	_teleport_base_volume_db = teleport_audio.volume_db


## Called by ToiletMinigame.start_session() - arms the fixed, non-random wait
## before the FIRST ghost of the session may spawn. Repeat spawns after that
## go through _arm_respawn() instead (see _finish_blink()).
func arm(
		starting_advance: float = 0.0,
		spawn_immediately: bool = false
) -> void:
	phase = GhostPhase.WAITING
	_spawn_timer = resumed_spawn_delay if spawn_immediately else initial_spawn_delay
	_clear_transient_state()
	_pending_start_advance = clampf(starting_advance, 0.0, 1.0)
	# A new session starts with no spawn history, so its first ghost may use
	# any zone. _arm_respawn() deliberately does NOT clear this - the
	# "different zone from last time" rule has to survive between the ghosts
	# of one session, which is the whole point of tracking it.
	_last_spawn_zone = -1
	_last_spawn_angle = 0.0


## Re-arms the wait for the next ghost after the previous one was banished -
## a fresh random roll every time, unlike the fixed initial delay in arm().
func _arm_respawn() -> void:
	phase = GhostPhase.WAITING
	_spawn_timer = _rng.randf_range(min_respawn_delay, maxf(min_respawn_delay, max_respawn_delay))
	_clear_transient_state()


## Everything that describes one live encounter, cleared between them.
## Deliberately does not touch the spawn-zone history, which has to survive
## across the ghosts of a session.
func _clear_transient_state() -> void:
	_clear_threat()
	_clear_presence()
	advance = 0.0
	step_index = 0
	spot_count = 0
	_spotted_this_cycle = false
	_stare_time = 0.0
	_hold_timer = 0.0
	_move_elapsed = 0.0
	_move_from = 0.0
	_move_to = 0.0
	_move_is_punishment = false
	_stutter_timer = 0.0
	_blink_timer = 0.0
	_expressed_advance = 0.0
	_active_player = null
	visual.visible = false
	visual.rotation.x = 0.0
	visual.position = Vector3(0.0, _visual_base_y, 0.0)


## Called every frame by ToiletMinigame._process(), only while its own state
## is PLAYING - this is the only place update() is ever invoked from.
func update(delta: float, player: Node3D, camera: Camera3D) -> void:
	match phase:
		GhostPhase.WAITING:
			_spawn_timer -= delta
			if _spawn_timer <= 0.0:
				_spawn(player, camera)
		GhostPhase.HOLDING:
			_update_holding(delta, player, camera)
		GhostPhase.MOVING:
			_update_moving(delta, player, camera)
		GhostPhase.STUTTER:
			_update_stutter(delta)
		GhostPhase.DISAPPEARING:
			_blink_timer -= delta
			if _blink_timer <= 0.0:
				_finish_blink()


## Standing still, waiting out the hold. Being seen here is worth one tally
## per cycle and nothing more - looking again changes nothing until the ghost
## has moved. Watching too long across the whole cycle is punished with a
## long stride rather than a normal lurch.
func _update_holding(delta: float, player: Node3D, camera: Camera3D) -> void:
	if not is_instance_valid(player) or not is_instance_valid(camera):
		return
	if _is_being_watched(player, camera):
		_stare_time += delta
		if _register_spot(player):
			return
		if _stare_time >= stare_tolerance:
			_begin_move(stare_step_multiplier, true)
		# The hold clock is frozen for as long as the player is watching.
		# Letting it run meant the ghost would eventually take its ordinary
		# lurch right in front of a staring player, who would catch it for
		# free - staring was the dominant strategy. It will not move while
		# watched except to punish the staring itself, and that lunge is not
		# catchable (see _update_moving()).
		return
	_hold_timer -= delta
	if _hold_timer <= 0.0:
		_begin_move(1.0, false)


## Mid-lurch. The whole of this window is the player's chance to catch it in
## the act; a single sighting here ends the encounter outright, which is the
## reward for having timed the look rather than merely repeated it.
func _update_moving(delta: float, player: Node3D, camera: Camera3D) -> void:
	if not is_instance_valid(player) or not is_instance_valid(camera):
		return
	# A punishment lunge cannot be caught. It is the ghost lunging *because*
	# the player stared, not a sneaky step they timed - letting a stare
	# convert into a free catch would make staring the dominant strategy
	# all over again, from the other direction.
	if not _move_is_punishment and _is_being_watched(player, camera):
		_on_caught(player)
		return
	_move_elapsed += delta
	var t := clampf(_move_elapsed / maxf(move_duration, 0.001), 0.0, 1.0)
	# Ease-in-out, so the lurch reads as a deliberate stride rather than a
	# constant slide - the player is meant to notice motion, not drift.
	var eased := t * t * (3.0 - 2.0 * t)
	advance = lerpf(_move_from, _move_to, eased)
	_apply_advance(player)
	if t < 1.0:
		return
	# Arrived. A completed lurch is what re-arms the tally and clears the
	# stare budget, so each cycle is worth exactly one sighting and each
	# cycle's watching is judged on its own.
	step_index += 1
	# Only a lurch the player did NOT force is worth a fresh tally. Without
	# this a staring player banks a spot, gets lunged at, banks another,
	# and stares their way to a banish - the exact behaviour
	# stare_tolerance exists to punish.
	if not _move_is_punishment:
		_spotted_this_cycle = false
	_stare_time = 0.0
	if advance >= 1.0:
		_resolve_failure()
		return
	phase = GhostPhase.HOLDING
	_hold_timer = _next_hold_duration()


## The caught-in-the-act beat: it jitters in place for stutter_duration and
## then goes. Purely presentational, but it is the feedback that tells the
## player their timing was what did it, rather than the ghost happening to
## leave.
func _update_stutter(delta: float) -> void:
	_stutter_timer -= delta
	var shake := stutter_amplitude * clampf(_stutter_timer / maxf(stutter_duration, 0.001), 0.0, 1.0)
	visual.position = Vector3(
		_rng.randf_range(-shake, shake),
		_visual_base_y + _rng.randf_range(-shake, shake),
		_rng.randf_range(-shake, shake)
	)
	visual.rotation.x = _rng.randf_range(-shake, shake) * 4.0
	if _stutter_timer <= 0.0:
		_disappear()


## True when the player is looking straight at the ghost's head with nothing
## in the way - the one perception call the rules above are built on.
func _is_being_watched(player: Node3D, camera: Camera3D) -> bool:
	return _camera_can_see_point(camera, player, _head_position())


## Banks the one tally this lurch cycle is worth, and banishes the ghost if
## that was the last one needed. Returns true when the encounter is over, so
## callers stop touching it this frame.
##
## The once-per-cycle guard is the rule that stops a player simply holding
## the camera on a stationary ghost until it leaves: the second, third and
## hundredth look at the same standing ghost are all worth nothing.
func _register_spot(player: Node3D) -> bool:
	if _spotted_this_cycle:
		return false
	_spotted_this_cycle = true
	spot_count += 1
	if spot_count >= spots_to_banish:
		_on_caught(player)
		return true
	# A tally that did not finish it still reads - the ghost acknowledges
	# being seen, so the player knows the look counted for something.
	_play_cue(lurch_volume_offset_db * 0.5, lurch_pitch_scale * 1.6)
	return false


## Starts a lurch. `step_scale` is 1.0 for the ordinary timed one and
## stare_step_multiplier for the punishment lunge, which is also flagged
## so _update_moving() knows not to let it be caught or counted.
func _begin_move(step_scale: float, is_punishment: bool) -> void:
	_move_is_punishment = is_punishment
	phase = GhostPhase.MOVING
	_move_elapsed = 0.0
	_move_from = advance
	_move_to = clampf(advance + step_scale / float(maxi(steps_to_reach, 1)), 0.0, 1.0)


func _next_hold_duration() -> float:
	var jitter := maxf(hold_duration_jitter, 0.0)
	return maxf(hold_duration + _rng.randf_range(-jitter, jitter), 0.35)


## Called by ToiletMinigame._cleanup() on every exit path (success, cancel,
## and death - which is itself just a cancel triggered by the existing
## is_alive guard). Unconditional, so nothing can outlive the session.
##
## If the minigame is exited mid-blink (DISAPPEARING - force_blink_now()
## already fired, end_forced_blink() has not run yet), the player's eyes
## would otherwise stay forced shut forever, since nothing else is left to
## reopen them once this ghost stops being driven. Reopening here is what
## satisfies "leaving the minigame must never leave a delayed callback able
## to blink the player later" for the one case that could actually strand
## the eyes closed.
func reset() -> void:
	if phase == GhostPhase.DISAPPEARING and is_instance_valid(_active_player) \
			and _active_player.has_method("end_forced_blink"):
		_active_player.call("end_forced_blink")
	phase = GhostPhase.IDLE
	_spawn_timer = 0.0
	_clear_transient_state()
	_last_spawn_zone = -1
	_last_spawn_angle = 0.0
	_pending_start_advance = 0.0
	# Cancelling shortly after a lurch cue (the stinger is only ~0.5s) could
	# otherwise leave it audibly finishing after the ghost has already gone
	# and the minigame has moved on.
	teleport_audio.stop()


## Danger-zone noise from ToiletMinigame._emit_danger_noise(), matching the
## crawler's and hunter's own report_noise() signature so all three can be
## driven by the same call_group(). Position is ignored - the player and this
## ghost are in the same small room by construction; what matters is that the
## player just made a mess of their aim, which brings the next lurch forward.
## Only shortens a hold: it can never interrupt a lurch already under way,
## which would rob the player of the window they are playing for.
func report_noise(_position: Vector3, loudness: float, _source: Node = null) -> void:
	if phase != GhostPhase.HOLDING:
		return
	_hold_timer = maxf(
		_hold_timer - hold_duration * noise_hold_penalty * clampf(loudness, 0.0, 1.0),
		0.0
	)


func _spawn(player: Node3D, camera: Camera3D) -> void:
	var pick := _pick_spawn_position(player, camera)
	if not pick["ok"]:
		# Nowhere legal right now - stay armed and try again shortly rather
		# than appearing somewhere the player could never look at. See
		# _pick_spawn_position()'s doc comment.
		phase = GhostPhase.WAITING
		_spawn_timer = blocked_spawn_retry_delay
		return
	var spawn_position: Vector3 = pick["position"]
	_rail_origin = player.global_position
	_rail_eye = camera.global_position if camera else player.global_position
	_rail_floor_y = _floor_y(player)
	var flat_offset := spawn_position - _rail_origin
	flat_offset.y = 0.0
	# The rail runs straight in from wherever the room allowed the ghost to
	# stand. There is no angular component: the lurches close distance, and
	# the bearing it arrived on is the bearing the player has to keep
	# checking for the rest of the encounter.
	_rail_far_distance = maxf(flat_offset.length(), contact_distance + 0.05)
	_rail_direction = (
		flat_offset.normalized()
		if not flat_offset.is_zero_approx()
		else -player.global_transform.basis.z
	)

	advance = _pending_start_advance
	step_index = floori(advance * float(maxi(steps_to_reach, 1)))
	spot_count = 0
	_spotted_this_cycle = false
	_stare_time = 0.0
	_expressed_advance = 0.0
	global_position = spawn_position
	_face_player(player)
	_active_player = player
	_apply_advance(player)
	visual.visible = true
	_set_presence(player, true)
	phase = GhostPhase.HOLDING
	_hold_timer = _next_hold_duration()
	_report_threat(player)
	_play_cue(0.0, 1.0)


## Places the ghost at the point on the rail its current advance names, and
## looms it.
##
## A rail position is only taken if the ghost would both fit there and be
## visible from where the player is sitting. The line-of-sight half is what
## keeps a lurch from putting it through a side wall or out of an open
## doorway - a ghost the player cannot see is a ghost they cannot catch, so
## the lurch stops short and the escalation continues on the looming axis.
## That is also the whole small-room story: the ghost that runs out of floor
## stops walking and starts leaning in, with no per-map measurement, markers
## or tuning.
func _apply_advance(player: Node3D) -> void:
	var distance := lerpf(_rail_far_distance, contact_distance, clampf(advance, 0.0, 1.0))
	var candidate := _rail_origin + _rail_direction * distance
	candidate.y = _rail_floor_y + spawn_clearance_radius + 0.02
	if _is_position_clear(candidate) \
			and not _is_path_blocked(_rail_eye, candidate + Vector3(0, head_height, 0), player):
		global_position = candidate
		_expressed_advance = advance
	if is_instance_valid(player):
		_face_player(player)
	_apply_lean()
	_report_threat(player)


## The looming axis. Driven by advance plus whatever advance the room refused
## to express as movement (see _apply_advance()), so a ghost pinned against a
## wall halfway in reads as advanced as one that had the floor to walk it.
## Clamped, so the two together can never over-rotate the model.
func _apply_lean() -> void:
	var blocked := maxf(advance - _expressed_advance, 0.0)
	var drive := clampf(advance + blocked, 0.0, 1.0)
	visual.rotation.x = -deg_to_rad(lean_max_degrees) * drive
	visual.position = Vector3(0.0, _visual_base_y + lift_max * drive, 0.0)


## Caught - either mid-lurch, or standing still with the last tally banked.
## Either way the encounter is over: it glitches, then vanishes, then forces
## the blink, then the loop re-arms.
func _on_caught(player: Node3D) -> void:
	phase = GhostPhase.STUTTER
	_stutter_timer = stutter_duration
	_clear_threat()
	_play_cue(0.0, 1.35)
	if is_instance_valid(player):
		_face_player(player)


## Mirrors the player's per-source threat entry to how far in the ghost has
## come, so the horror overlay swells as it closes. See THREAT_SOURCE.
func _report_threat(player: Node3D) -> void:
	if is_instance_valid(player) and player.has_method("set_threat_from"):
		player.call("set_threat_from", THREAT_SOURCE, clampf(advance, 0.0, 1.0))


## Drops this ghost's threat entry entirely (0.0 erases the source rather
## than pinning it at zero - see player.gd set_threat_from()). Every path
## that ends an encounter goes through here, so a cancelled session can
## never leave the overlay stuck red.
func _clear_threat() -> void:
	if is_instance_valid(_active_player) and _active_player.has_method("set_threat_from"):
		_active_player.call("set_threat_from", THREAT_SOURCE, 0.0)


func _set_presence(player: Node3D, present: bool) -> void:
	if is_instance_valid(player) and player.has_method("set_toilet_ghost_presence"):
		player.call("set_toilet_ghost_presence", present)


func _clear_presence() -> void:
	_set_presence(_active_player, false)


## One cue on the shared teleport player: used for arrival, acknowledgement,
## and the catch. Lurches deliberately stay silent, so sound cannot hand the
## player a free turn cue.
func _play_cue(volume_offset_db: float, pitch: float) -> void:
	teleport_audio.volume_db = _teleport_base_volume_db + volume_offset_db
	teleport_audio.pitch_scale = pitch
	teleport_audio.play()


## Faces the ghost toward the player, horizontally only (no pitch, so its
## own dramatic head tilt from the Sprint 3 model isn't compounded by
## looking up/down at a height difference) - duplicated from
## ghosts/statue_ghost.gd's own face_player_on_freeze idiom
## (rotation.y = atan2(-flat_target.x, -flat_target.z)) rather than shared,
## matching this file's existing convention. Re-applied on every lurch,
## since unlike a fixed-position spawn the ghost is now closing on the
## player rather than standing where it landed.
func _face_player(player: Node3D) -> void:
	var flat_target := player.global_position - global_position
	flat_target.y = 0.0
	if not flat_target.is_zero_approx():
		rotation.y = atan2(-flat_target.x, -flat_target.z)


## The point the player actually needs to look at - see head_height's doc
## comment. This is what every sighting is checked against, not the root.
func _head_position() -> Vector3:
	return global_position + Vector3(0, visual.position.y + head_height, 0)


## After the stutter: the ghost actually disappears, then the existing player
## blink API is forced so the beat reads as "I caught it, it glitched, I
## blinked, it's gone" rather than a silent pop. The reopen is scheduled on
## this node's own timer (see _finish_blink()) rather than left to the
## player's _physics_process, which minigames like the toilet's disable for
## their whole duration - see force_blink_now()'s doc comment in player.gd.
func _disappear() -> void:
	phase = GhostPhase.DISAPPEARING
	visual.visible = false
	_clear_presence()
	visual.rotation.x = 0.0
	visual.position = Vector3(0.0, _visual_base_y, 0.0)
	teleport_audio.stop()
	_blink_timer = _forced_blink_duration()
	if is_instance_valid(_active_player) and _active_player.has_method("force_blink_now"):
		_active_player.call("force_blink_now")


## Reopens the eyes closed by _disappear(), ends this encounter, and arms the
## next one - a banished ghost continues the spawn loop rather than ending it.
## Advance reaching 1.0 instead resolves into the owning minigame's stun path.
func _finish_blink() -> void:
	var resolved_player := _active_player
	if is_instance_valid(resolved_player) and resolved_player.has_method("end_forced_blink"):
		resolved_player.call("end_forced_blink")
	ghost_seen.emit()
	_arm_respawn()


## How long the forced blink stays closed before _finish_blink() reopens it.
## Reuses the player's own existing forced_blink_duration convention (the
## same value force_blink() defaults to) instead of inventing a second,
## redundant "how long is a blink" constant.
func _forced_blink_duration() -> float:
	if _active_player and "forced_blink_duration" in _active_player:
		return _active_player.forced_blink_duration
	return 0.22


## The last lurch landed on the player: steps_to_reach cycles went by without
## the player catching it. The owning ToiletMinigame turns this signal into a
## 3D scare plus a temporary stun; this ghost never kills the player directly.
func _resolve_failure() -> void:
	phase = GhostPhase.IDLE
	visual.visible = false
	visual.rotation.x = 0.0
	visual.position = Vector3(0.0, _visual_base_y, 0.0)
	teleport_audio.stop()
	_clear_threat()
	_clear_presence()
	_active_player = null
	advance = 0.0
	ghost_timed_out.emit()


## The camera's forward direction at the moment the toilet minigame started,
## reconstructed from its current orientation rather than tracked separately -
## ToiletMinigame's yaw clamp holds player.accumulated_yaw as exactly the
## rotation applied since that moment, so undoing it recovers the original
## direction regardless of how far the player has since turned. Spawns are
## sampled around this fixed reference, not the live camera direction: the
## camera's own reachable range is fixed for the whole session too (it's a
## clamp on accumulated_yaw, not a moving window), so using the live
## direction could place a candidate outside where the player could ever
## turn to, particularly once they're already turned close to one limit.
## Flattened to the horizontal plane: the toilet camera starts pitched down
## toward the bowl, and an unflattened forward vector drags that pitch into
## the spawn offset, foreshortening every distance by cos(pitch) - a 2.0 m
## roll landed the ghost 1.73 m away, under its own configured minimum.
## Spawn direction is a compass bearing; the height comes from the floor.
func _session_start_forward(camera: Camera3D, player: Node3D) -> Vector3:
	var current_forward := -camera.global_basis.z
	current_forward.y = 0.0
	if current_forward.is_zero_approx():
		current_forward = Vector3.FORWARD
	current_forward = current_forward.normalized()
	var accumulated: float = player.accumulated_yaw if "accumulated_yaw" in player else 0.0
	return current_forward.rotated(Vector3.UP, -accumulated)


## Yaw range [low, high] in degrees covered by one spawn zone. The zones tile
## the rear-left and rear-right diagonal bands
## [-spawn_yaw_range, -min_spawn_offset_angle] and
## [min_spawn_offset_angle, spawn_yaw_range]. Every valid angle is more than
## 90 degrees from the session-start facing, so the ghost is always behind.
func _zone_bounds(zone: int) -> Vector2:
	var band := maxf(spawn_yaw_range - min_spawn_offset_angle, 1.0)
	var width := band / float(SPAWN_ZONE_COUNT / 2)
	var per_side := SPAWN_ZONE_COUNT / 2
	if zone < per_side:
		# Rear-left band, outermost slice first, running inward.
		var low := -spawn_yaw_range + width * float(zone)
		return Vector2(low, low + width)
	var right_low := min_spawn_offset_angle + width * float(zone - per_side)
	return Vector2(right_low, right_low + width)


## Picks the direction of the next spawn as {zone, angle}. After the first
## spawn it must come from the rear side opposite the last one, forcing the
## player to check behind both shoulders. The arithmetic is settled here
## before physics work, so _pick_spawn_position() can never trade that rule
## away just to satisfy a clearance check.
func _next_zone_angle() -> Dictionary:
	var per_side := SPAWN_ZONE_COUNT / 2
	for attempt in max_spawn_attempts:
		var zone: int
		if _last_spawn_zone < 0:
			zone = _rng.randi_range(0, SPAWN_ZONE_COUNT - 1)
		elif _last_spawn_zone < per_side:
			zone = _rng.randi_range(per_side, SPAWN_ZONE_COUNT - 1)
		else:
			zone = _rng.randi_range(0, per_side - 1)
		var bounds := _zone_bounds(zone)
		var angle := _rng.randf_range(bounds.x, bounds.y)
		if _last_spawn_zone >= 0 and absf(angle - _last_spawn_angle) < min_spawn_angle_separation:
			continue
		return {"zone": zone, "angle": angle}
	return _furthest_zone_angle()


## Best-available pick once the random retries above are spent: the allowed
## opposite-side zone whose far edge sits furthest from the last angle.
func _furthest_zone_angle() -> Dictionary:
	if _last_spawn_zone < 0:
		var any_zone := _rng.randi_range(0, SPAWN_ZONE_COUNT - 1)
		var any_bounds := _zone_bounds(any_zone)
		return {"zone": any_zone, "angle": _rng.randf_range(any_bounds.x, any_bounds.y)}

	var best_zone := 0
	var best_angle := 0.0
	var best_gap := -1.0
	var per_side := SPAWN_ZONE_COUNT / 2
	for zone in SPAWN_ZONE_COUNT:
		if (_last_spawn_zone < per_side) == (zone < per_side):
			continue
		var bounds := _zone_bounds(zone)
		for edge in [bounds.x, bounds.y]:
			var gap: float = absf(edge - _last_spawn_angle)
			if gap > best_gap:
				best_gap = gap
				best_zone = zone
				best_angle = edge
	return {"zone": best_zone, "angle": best_angle}


func _record_spawn(zone: int, angle_deg: float) -> void:
	_last_spawn_zone = zone
	_last_spawn_angle = angle_deg


## Picks where the ghost appears, or reports that nowhere works.
##
## Returns {"ok": bool, "position": Vector3}. The direction comes from
## _next_zone_angle() (see there for the zone/separation rules); the
## *distance* is then measured rather than guessed - a ray down the chosen
## bearing says how much open floor is actually there, and the roll is
## clamped to that minus wall_margin. Guessing was the bug: House2's
## bathroom has 1.55 m of floor straight ahead and 2.00 m to the left, so a
## blind roll in [2, 4] m put nearly every candidate in those directions
## inside a wall, and the arc's whole left-hand side could only ever be
## satisfied by the old unvalidated fallback - which is how ghosts ended up
## outside the room where they could never be seen or caught.
##
## Candidates are still rejected if they overlap geometry or have no clear
## line from the player's eye (that check is at head height, not the
## floor-level candidate: checking the base point let a candidate pass with
## a clear view to its feet while its actual head - the point the live
## "seen" check raycasts to every frame - sat behind the toilet's own body,
## producing ghosts that could never be seen no matter how the player aimed).
##
## Deliberately does NOT require the spawn to be inside the camera's current
## frustum. The rear-left and rear-right zones are intentionally out of view;
## gating on the frustum would make the encounter impossible. The ghost is
## still within the camera's reachable yaw range and must be looked at before
## it counts as seen.
func _pick_spawn_position(player: Node3D, camera: Camera3D) -> Dictionary:
	var floor_y := _floor_y(player)
	var eye_position := camera.global_position if camera else player.global_position
	var reference_forward := _session_start_forward(camera, player) if camera else -player.global_transform.basis.z

	for i in spawn_sample_count:
		var pick := _next_zone_angle()
		var zone: int = pick["zone"]
		var angle_deg: float = pick["angle"]
		var direction := reference_forward.rotated(Vector3.UP, deg_to_rad(angle_deg))

		# How much room this bearing actually has. A bearing with nothing
		# behind it inside the sampled range is an opening rather than a
		# wall - a doorway - and the ghost is held at the minimum there so
		# it stays in the room with the player instead of drifting out
		# through it into the next one.
		var wall_distance := _free_distance_along(eye_position, direction, player)
		var available := (
			spawn_min_distance
			if wall_distance < 0.0
			else wall_distance - wall_margin
		)
		if available < spawn_min_distance:
			continue
		# The furthest this bearing allows, not a roll inside the range: the
		# ghost is supposed to arrive at the far edge of what the player can
		# still see, so its lurches have somewhere to come from. Variety
		# comes from which bearing it picks, not from how close it starts.
		var distance := minf(spawn_max_distance, available)
		var candidate := player.global_position + direction * distance
		# The clearance sphere below is spawn_clearance_radius wide, so its
		# center must clear the floor by more than that radius or it always
		# overlaps the floor slab itself and every candidate gets rejected.
		candidate.y = floor_y + spawn_clearance_radius + 0.02

		if not _is_position_clear(candidate):
			continue
		var candidate_head := candidate + Vector3(0, head_height, 0)
		if _is_path_blocked(eye_position, candidate_head, player):
			continue

		_record_spawn(zone, angle_deg)
		return {"ok": true, "position": candidate}

	# Nowhere in the whole arc can host the ghost right now. Say so instead
	# of forcing it: _spawn() re-arms a short retry, and the encounter simply
	# starts a beat later. Placing an unseeable ghost is strictly worse than
	# placing none - the player cannot catch what is inside a wall, so it
	# would just walk in unopposed.
	return {"ok": false, "position": Vector3.ZERO}


## Open floor along `direction` from the player's eye, or -1.0 if nothing is
## hit inside the range the ghost could spawn in at all. Cast at eye height
## because that is the height the live "seen" raycast has to travel later:
## a bearing that is clear down here but walled at head height would produce
## exactly the unseeable ghost this whole path exists to prevent.
func _free_distance_along(eye: Vector3, direction: Vector3, player: Node3D) -> float:
	var reach := spawn_max_distance + wall_margin
	var exclude: Array[RID] = []
	if player and player.has_method("get_rid"):
		exclude.append(player.get_rid())
	var query := PhysicsRayQueryParameters3D.create(
		eye,
		eye + direction * reach,
		spawn_blocking_mask,
		exclude
	)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return -1.0
	return eye.distance_to(hit["position"])


## The floor the ghost stands on, found by casting down from the player
## rather than assumed from the bottom of their capsule.
##
## The capsule cannot be used here: ToiletMinigame.start_session() seats
## the player about 0.3 m below standing height for the whole session, so
## the capsule bottom sits *under* the real floor. Deriving the floor from
## it put every spawn candidate inside the floor slab, which failed the
## clearance check on all of them and sent every single spawn through the
## fallback path - which is how ghosts ended up inside walls in House2's
## bathroom, where they could never be seen or caught.
func _floor_y(player: Node3D) -> float:
	var exclude: Array[RID] = []
	if player and player.has_method("get_rid"):
		exclude.append(player.get_rid())
	var origin := player.global_position
	var query := PhysicsRayQueryParameters3D.create(
		origin + Vector3(0, FLOOR_PROBE_UP, 0),
		origin - Vector3(0, FLOOR_PROBE_DOWN, 0),
		spawn_blocking_mask,
		exclude
	)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		return hit["position"].y
	# Nothing underfoot at all (a headless test scene with no ground, say).
	# Fall back to the old capsule estimate rather than to nothing.
	var shape_node := player.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node:
		var capsule := shape_node.shape as CapsuleShape3D
		if capsule:
			return shape_node.global_position.y - capsule.height * 0.5
	return player.global_position.y


func _is_position_clear(position: Vector3) -> bool:
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := SphereShape3D.new()
	shape.radius = spawn_clearance_radius
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, position)
	query.collision_mask = spawn_blocking_mask
	return space_state.intersect_shape(query, 1).is_empty()


func _is_path_blocked(from: Vector3, to: Vector3, player: Node3D) -> bool:
	var exclude: Array[RID] = []
	if player and player.has_method("get_rid"):
		exclude.append(player.get_rid())
	var query := PhysicsRayQueryParameters3D.create(from, to, spawn_blocking_mask, exclude)
	query.hit_from_inside = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty()


func _is_inside_camera_fov(camera: Camera3D, point: Vector3) -> bool:
	var offset := point - camera.global_position
	var distance := offset.length()
	if distance <= 0.01:
		return true
	var look_dot := (-camera.global_basis.z).dot(offset / distance)
	return look_dot >= cos(deg_to_rad(observation_half_angle))


## Duplicated from ghosts/statue_ghost.gd's _camera_can_see_point() by
## design - see the class doc comment.
func _camera_can_see_point(camera: Camera3D, player: Node3D, point: Vector3) -> bool:
	var offset := point - camera.global_position
	var distance := offset.length()
	if distance <= 0.01 or distance > maximum_observation_distance:
		return false

	var look_dot := (-camera.global_basis.z).dot(offset / distance)
	if look_dot < cos(deg_to_rad(observation_half_angle)):
		return false
	if not camera.is_position_in_frustum(point):
		return false

	var exclude: Array[RID] = []
	if player and player.has_method("get_rid"):
		exclude.append(player.get_rid())
	var query := PhysicsRayQueryParameters3D.create(
		camera.global_position,
		point,
		sight_blocking_mask,
		exclude
	)
	query.hit_from_inside = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty()


## Optional dev/testing hook, matching the existing per-ghost convention
## (statue/crawler/hunter all expose dev_force_spawn for DevTools/manual
## testing). Not wired into ui/dev_tools.gd in this sprint - that would
## touch an unrelated file - but kept available for the next sprint's
## manual playtest.
func dev_force_spawn(player: Node3D, camera: Camera3D) -> bool:
	if not is_instance_valid(player):
		return false
	_spawn(player, camera)
	return true
