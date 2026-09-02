extends CharacterBody3D

## "Ma Dưới Sàn" / The Crawler.
##
## Designed as the exact inverse of the statue ghost, so the two can share a
## house without competing for the same fear:
##
##   statue: hunts by sight, freezes the moment you look at it, floor only,
##           teleports in for a scripted ambush, kills the moment you look away.
##   crawler: blind. Hunts by SOUND. Does not care that you can see it. Owns
##           the walls and the ceiling, so it ignores the floor plan entirely.
##
## The counterplay is therefore also inverted. Against the statue you keep your
## eyes on it; against this you go quiet - crouch, stop, and let it crawl over
## the ceiling above your head and away toward the last thing it heard.
##
## It runs on a fixed, announced hunt cycle rather than being a permanent
## threat, which is what keeps it survivable:
##
##   HIDDEN    it is not in the house at all. Nothing can hurt you.
##   OMEN      it appears and bolts across one player's view, far too fast to
##             catch and unable to kill during the dash. This is a warning, and
##             it is the only warning: a hunt has started.
##   PATROL    it sweeps a fixed route around the whole house, `patrol_laps`
##             times. This is the dangerous phase, but it is looking, not
##             tracking - a silent player is passed over.
##   HUNTING   a noise broke the patrol. It commits to that noise.
##   LEAVING   it has been on top of somebody for too long, or has just killed
##             them. It bolts for the far side of the house and is deaf on the
##             way, so a hunt always ends in the room being handed back.
##   RETREAT   it finished its laps without finding anyone: one scream, then it
##             is gone until the next cycle.
##
## The attic is its lair. Every cycle starts and ends there.

enum CrawlerState {
	DORMANT,
	HIDDEN,
	OMEN,
	PATROL,
	HUNTING,
	SEARCHING,
	POUNCE_WINDUP,
	POUNCING,
	RECOVERING,
	RETREATING,
	# Appended rather than slotted in beside RETREATING on purpose: this enum's
	# ordinal is what WorldReplicator ships to clients, so inserting a value in
	# the middle would renumber every state above it mid-session.
	LEAVING,
}

signal state_changed(new_state: CrawlerState)
signal noise_heard(position: Vector3, loudness: float)
signal surface_changed(new_normal: Vector3)
signal omen_started(player: Node3D, from: Vector3, to: Vector3)
signal patrol_lap_completed(lap: int)
signal pounce_started(target_point: Vector3)
signal pounce_missed()
signal killed_player(player: Node3D)
signal leaving_area(destination: Vector3)
signal retreated()
signal containment_recovered(escaped_position: Vector3, recovered_position: Vector3)

@export_category('Behavior')
@export var active: bool = true
## Patrol crawl. Deliberately crippling - less than half a walking player. It is
## not chasing anyone at this speed; it is dragging itself across the ceiling
## waiting to hear something, and it can be walked away from at leisure.
@export var crawl_speed: float = 1.45
## Closing speed once it has a fix but the noise is too far away to leap at. It
## is faster than a patrol and slower than a sprint, so distance still buys time.
@export var hunting_speed: float = 4.5
@export var acceleration: float = 26.0
@export var turn_speed: float = 7.5
## How fast the steering direction itself may swing, as distinct from how fast
## the body turns to face it. `acceleration` reaches full speed in about a
## twentieth of a second, so a steering vector that jumps between frames - and
## both the navigation path and the wedge probes below hand over vectors that
## jump - gets applied as a twitch. Easing the direction turns those into arcs.
@export var steer_smoothing: float = 6.0

@export_category('Hunt Cycle')
## Whether it runs the hidden/omen/patrol/retreat cycle at all. Off leaves a
## bare noise-hunter, which is the control the isolated smoke tests use.
@export var hunt_cycle_enabled: bool = true
@export var start_hidden: bool = true
@export var initial_hidden_delay_min: float = 35.0
@export var initial_hidden_delay_max: float = 60.0
## The quiet between hunts. This is most of the nerf: for minutes at a time the
## house simply does not contain it.
@export var hidden_delay_min: float = 95.0
@export var hidden_delay_max: float = 160.0
## Noise while it is hiding cannot summon it directly - the omen always plays
## first - but it does bring the next cycle forward by this fraction of the
## remaining wait, so a loud house is still a more dangerous house.
@export_range(0.0, 1.0) var noise_impatience: float = 0.2

@export_category('Omen')
## The announced fly-past that precedes every hunt. It cannot kill during this,
## and it makes no attempt to reach anyone.
@export var omen_enabled: bool = true
@export var omen_speed: float = 13.5
## How far in front of the chosen player it crosses. Far enough to read as a
## shape rather than a jumpscare, close enough that you cannot miss it.
@export var omen_distance_min: float = 5.5
@export var omen_distance_max: float = 9.0
## Half-width of the crossing, measured out from the player's sightline. The
## dash runs the full width, so it enters and leaves frame.
@export var omen_crossing_half_width: float = 4.5
@export var omen_max_duration: float = 2.2
@export_range(4, 32, 1) var omen_candidate_count: int = 14
## If no player can be given a clean fly-past, it screams from above the ceiling
## instead. The hunt is never unannounced.
@export var omen_audio_fallback: bool = true

@export_category('Adhesion')
## Whether it may leave the floor at all. Turning this off leaves a plain
## floor-bound crawler, which is what the isolated smoke tests use as a control.
@export var wall_crawling_enabled: bool = true
## Acceleration pulling the body into whatever surface it is currently gripping.
## This replaces gravity while clung, so it must comfortably exceed it or the
## crawler sags off ceilings.
@export var cling_force: float = 30.0
## Cap on the speed it may build up straight into the surface. Without this the
## adhesion accelerates forever and the body vibrates against the geometry.
@export var max_cling_speed: float = 2.2
## How far below the body a surface may be and still be grippable. Sphere radius
## is 0.34, so this allows a little clearance over uneven trim without letting
## it hover.
@export var cling_probe_distance: float = 0.55
## Reach used when feeling around a convex edge - the table lip, the top of a
## wall - for the face on the other side.
@export var edge_reach: float = 0.6
## How fast the body re-aligns to a newly gripped surface. Low values look like
## it is pouring around the corner; high values snap and read as a bug.
@export var surface_align_speed: float = 9.0
## A wall must be at least this far from the current surface plane before it
## counts as a new surface to climb rather than something to slide along.
@export_range(0.0, 1.0) var surface_change_threshold: float = 0.25
## Grace period after losing grip before it accepts that it is falling. Stops a
## single frame of bad geometry from dropping it off the ceiling.
@export var cling_lost_time: float = 0.18
## Minimum time between re-anchors. In a concave corner two or three faces are
## all in contact and all "more different" than the current one, so without this
## it swaps surface every frame and vibrates in place instead of turning.
@export var regrip_cooldown: float = 0.35
## How long it may be wedged before it simply lets go and drops. Nothing steers
## out of a ceiling corner reliably, but falling out of one always works, and a
## crawler losing its grip is in character.
@export var stuck_release_time: float = 1.4
## How long it may make no headway toward its goal before it stops shoving and
## tries sliding out sideways instead. Well under `stuck_release_time`, because
## a sidestep costs nothing while letting go of the ceiling costs the whole
## position - the cheap escape has to be the one that is tried first.
@export var wedge_probe_time: float = 0.45
## How long one sidestep is committed to. Long enough to actually clear a door
## reveal or the end of a run of furniture, short enough that it is back on the
## noise rather than wandering.
@export var wedge_escape_time: float = 0.8
## Reach of the feelers that choose which way to sidestep, and the width it
## treats as "open".
@export var wedge_probe_distance: float = 1.6
## How far it has to physically get from where it was before it counts as having
## gone anywhere. Roughly two body lengths: far enough that jittering in a
## corner cannot pass for travel, short enough that squeezing along a wall does.
@export var wedge_progress_distance: float = 0.75
@export_flags_3d_physics var surface_mask: int = 1

@export_category('Containment')
## Wall/ceiling locomotion intentionally ignores navigation. A level can enable
## this volume to stop a pounce, search point, or open doorway from carrying the
## crawler onto the outside face of the building.
@export var containment_enabled: bool = false
@export var containment_min: Vector3 = Vector3(-8.85, -3.2, -5.85)
@export var containment_max: Vector3 = Vector3(8.85, 9.4, 5.85)
## Recovery moves the sphere clear of the boundary before releasing its grip,
## otherwise the same outward velocity can cross the limit again next frame.
@export var containment_recovery_inset: float = 0.4

@export_category('Hearing')
## Distance a full-speed sprint carries to. Everything quieter scales down from
## here, so crouch-walking is audible only from a few metres. Roughly one floor
## of the house rather than the whole building: it has to physically patrol into
## your half of the map before your footsteps matter.
##
## This is the outer edge of hearing, not the edge of the charge. `reach` is
## this scaled by loudness, and `search_confidence` then splits what it hears in
## two at 80% of that reach: a walking player is run down inside 16 m and only
## groped around for between 16 and 20 m, which is the band where the creature
## is looking for you rather than coming for you.
@export var hearing_range: float = 20.0
## Player speed treated as maximum loudness. Slightly above the player's sprint
## speed so even sprinting is not quite a 1.0 - there is always a louder noise.
@export var loud_reference_speed: float = 3.9
@export_range(0.0, 1.0) var crouch_noise_multiplier: float = 0.3
## A landing thump is a single loud event no amount of crouching hides.
@export_range(0.0, 1.0) var landing_noise: float = 0.85
## Sound still reaches it through a wall, just muffled - which is why closing a
## door behind you helps but does not save you.
@export_range(0.0, 1.0) var wall_muffle: float = 0.55
## How fast its fix on the last noise rots. This is the whole stealth window:
## go silent and it keeps crawling to where you *were*.
@export var trail_decay: float = 0.12
## Below this confidence it stops committing to the trail and starts sweeping.
@export_range(0.0, 1.0) var search_confidence: float = 0.2
## It notices a body it physically crawls into, silent or not - but only while
## it is actually hunting. On patrol it can pass right over you.
@export var touch_detection_range: float = 0.8
## Loudness required to break off a patrol and commit to a hunt. A crouch-walk
## sits under this, so sneaking does not turn a sweep into a chase.
@export_range(0.0, 1.0) var patrol_alert_loudness: float = 0.35

@export_category('Patrol')
## Nodes in this group are the route, visited in tree order. With none present
## it falls back to sampling the navmesh around its lair.
@export var patrol_point_group: StringName = 'crawler_patrol_points'
## Nodes in this group mark where it lives and where every cycle begins. The
## attic, in this house. Falls back to wherever it was placed in the scene.
@export var lair_group: StringName = 'crawler_lair'
## Complete laps of the route before it gives up and goes home.
@export_range(1, 6, 1) var patrol_laps: int = 2
## A patrol point counts as visited from this far away; it is sweeping rooms,
## not touching markers.
@export var patrol_arrive_distance: float = 2.0
## Give up on a patrol point that will not resolve, so one unreachable marker
## cannot strand the whole cycle.
@export var patrol_point_timeout: float = 14.0
@export var patrol_chitter_interval_min: float = 5.0
@export var patrol_chitter_interval_max: float = 12.0
## While patrolling it steers this far above its route marker, which drives it
## up the nearest wall and onto the ceiling. It hunts from up there, which is
## why looking up is the counterplay to the omen. Applied only on genuinely flat
## floor - see `flat_floor_threshold`.
@export var patrol_climb_bias: float = 2.4
## How level a surface has to be before navigation is used to route across it.
##
## This must stay well below cos(45 degrees) = 0.707, because the house's
## authored stair ramps are exactly 45 degrees. At a 0.7 threshold the crawler
## flickered between "on ground, use the navmesh" and "on a wall, go straight
## and climb" on every single frame of every staircase, which is precisely why
## it could walk up a flight and then never get back down one.
@export_range(0.0, 1.0) var ground_surface_threshold: float = 0.45
## Separate, much stricter test for "standing on a level floor", used to decide
## whether to reach for the ceiling. A staircase is walkable ground but is not
## somewhere to start climbing from.
@export_range(0.0, 1.0) var flat_floor_threshold: float = 0.9
## Height difference under which a route marker counts as being on the crawler's
## own level. Floors here are 3 m apart, so this cleanly separates "same room"
## from "another storey".
@export var same_level_height: float = 1.5
## Consecutive failed attempts to shake itself loose before it gives up and
## relocates. Only ever used while no player can see it.
@export_range(1, 10, 1) var unstick_relocate_after: int = 3

@export_category('Leaving')
## How close to a living player counts as being on top of them.
@export var loiter_radius: float = 7.0
## How long it may stay that close before it gives the room back. It creeps,
## it listens, and then it goes: without this it has nowhere else to be and
## simply orbits whoever it last heard for the rest of the hunt, which reads as
## a stuck creature rather than a hunting one.
@export var loiter_tolerance: float = 4.5
## The bolt out. Well above hunting_speed on purpose - leaving has to read as a
## decision rather than as the same crawl it arrived with, and it has to clear
## the room fast enough that the player gets a real all-clear out of it.
@export var leave_speed: float = 9.0
## How far from every living player it has to get before it resumes the sweep.
@export var leave_distance: float = 22.0
## Hard ceiling on one retreat, so an unreachable far corner cannot strand it
## out here for the rest of the cycle.
@export var leave_timeout: float = 8.0

@export_category('Retreat')
## The scream that ends a failed hunt. It vanishes when this finishes.
@export var retreat_scream_duration: float = 1.6

@export_category('Search')
@export var arrive_distance: float = 1.2
## Shorter than a patrol leg on purpose: losing the trail should drop it back
## to sweeping rather than leave it circling one room.
@export var search_duration: float = 7.0
@export var search_radius: float = 5.0
@export var search_point_interval: float = 2.2

@export_category('Pounce')
## The entire attack. It creeps at `crawl_speed` and then covers this whole
## distance in one launch, so range is what you manage, not speed: make a sound
## anywhere inside this and it is already on you. Outside it there is no leap at
## all - it simply walks the noise down, which is what makes this a line the
## player can actually feel rather than a number.
@export var pounce_range: float = 10.0
@export var pounce_min_range: float = 1.4
## Short, because the leap is the threat and a long tell would defuse it - but
## not zero: this plus the scream is the only frame in which it can be dodged.
@export var pounce_windup: float = 0.3
## Deliberately left where it was when the crawl/hunt paces were raised: the
## leap is a fixed reaction test, and speeding it up shortens a dodge window
## measured in human reflexes rather than in metres of map.
@export var pounce_speed: float = 21.0
@export var pounce_arc: float = 0.22
## How far ahead of a moving target it aims. It is blind, so this is guesswork
## and it can be dodged by changing direction during the windup.
@export var pounce_lead_time: float = 0.22
@export var pounce_kill_radius: float = 1.05
@export var pounce_max_air_time: float = 1.4
## The window a missed pounce hands back to the player. Without this it is
## simply unsurvivable in a corridor, and it is long enough here to actually
## clear a room and put a door between you.
@export var pounce_recovery: float = 2.6
## Minimum gap between leaps. It has one attack, so this is the whole attack
## rate: after a leap it has to creep and listen again before trying another.
@export var pounce_cooldown: float = 7.0
@export_range(0.0, 1.0) var pounce_min_confidence: float = 0.25
## Being technically inside the edge of the camera for one frame is not enough
## warning. After this much unobstructed view the player knows the Crawler is in
## the area, and that knowledge lasts until it retreats and hides again.
@export var minimum_visible_before_awareness: float = 0.35
## Audio near its maximum attenuation edge can be technically playing but too
## faint to read as a warning. Only this inner portion grants awareness.
@export_range(0.1, 1.0) var audio_awareness_distance_multiplier: float = 0.65
## How near its noise fix a player has to be before it is willing to leap at
## them. It is blind: it lunges at a sound, not at a body, so a player who is
## simply nearby while something else made the noise is not a target.
@export var pounce_fix_tolerance: float = 2.5

@export_category('Presentation')
@export var crawl_animation_speed: float = 9.0
## Distance at which the flesh flushes and the breathing becomes audible.
@export var dread_radius: float = 9.0
@export var crawl_audio_min_speed: float = 0.35

var state: CrawlerState = CrawlerState.PATROL
var surface_normal: Vector3 = Vector3.UP
var has_surface: bool = false
var airborne_time: float = 0.0
var facing_direction: Vector3 = Vector3.FORWARD

var last_noise_position: Vector3
var noise_confidence: float = 0.0
var noise_source: CharacterBody3D
var has_noise_fix: bool = false

var search_timer: float = 0.0
var search_point_timer: float = 0.0
var search_point: Vector3
var hidden_timer: float = 0.0
var omen_timer: float = 0.0
var omen_target_point: Vector3
var patrol_index: int = 0
var patrol_lap: int = 0
var patrol_point_timer: float = 0.0
var patrol_chitter_timer: float = 0.0
var retreat_timer: float = 0.0
var loiter_timer: float = 0.0
var leave_timer: float = 0.0
var leave_target: Vector3
var leave_origin: Vector3
var manifested: bool = true
var lair_position: Vector3
var patrol_points: Array[Vector3] = []
var normal_collision_layer: int
var normal_collision_mask: int
var pounce_timer: float = 0.0
var pounce_cooldown_timer: float = 0.0
var pounce_air_time: float = 0.0
## The noise-making target selected after the encounter was announced. Kept
## apart from noise_source because a newer sound during the windup must not
## redirect an already committed attack onto a bystander.
var pounce_target: CharacterBody3D
var player_visibility_times: Dictionary = {}
var aware_player_ids: Dictionary = {}
## Team-wide permission for this manifestation. One player receiving a fair
## warning announces the Crawler to the whole room; from then on any player who
## gives it a valid noise fix can be attacked.
var attack_announced: bool = false
var dev_attack_suspended: bool = false
## The game director's own hold, kept apart from the flag above because that one
## is not a dev flag at all: player.gd refcounts it as the minigame safety lock.
## A director sharing it would release somebody's lock mid-encounter.
var director_attacks_suspended: bool = false
var attack_resume_grace_remaining: float = 0.0
var recovery_timer: float = 0.0
var regrip_cooldown_timer: float = 0.0
var steering_goal: Vector3
var no_progress_time: float = 0.0
## Where it was when it was last credited with having got somewhere, and how
## long ago that was. Together these are the whole wedge detector.
var wedge_anchor: Vector3
## Whether it is currently trying to travel at all. A crawler holding still at a
## search point to listen is not stuck, and must not be treated as if it were.
var steering_active: bool = false
var failed_releases: int = 0
var steer_direction: Vector3 = Vector3.ZERO
var wedge_escape_direction: Vector3 = Vector3.ZERO
var wedge_escape_timer: float = 0.0
var last_contained_position: Vector3
var has_contained_position: bool = false

var crawl_phase: float = 0.0
var agitation: float = 0.0
var breath: float = 0.0
var jaw_open: float = 0.0
var presentation_time: float = 0.0
var flesh_material: ShaderMaterial

var gravity: float = ProjectSettings.get_setting('physics/3d/default_gravity')
## Bodies the surface probes must ignore: itself, plus every player. Players
## share the world collision layer, so without this the crawler will happily
## decide a player standing beside it is a wall and try to climb them.
var _cling_exclusions: Array[RID] = []
## Per-player airborne memory, keyed by instance id, used to turn a landing into
## a single loud thump instead of a continuous noise while falling.
var _player_airborne: Dictionary = {}

@onready var visual_root: Node3D = $VisualRoot
@onready var body_pivot: Node3D = $VisualRoot/BodyPivot
@onready var neck_pivot: Node3D = $VisualRoot/BodyPivot/NeckPivot
@onready var head_pivot: Node3D = $VisualRoot/BodyPivot/NeckPivot/HeadPivot
@onready var jaw_pivot: Node3D = $VisualRoot/BodyPivot/NeckPivot/HeadPivot/JawPivot
@onready var tail_pivot: Node3D = $VisualRoot/BodyPivot/TailPivot
@onready var tail_tip_pivot: Node3D = $VisualRoot/BodyPivot/TailPivot/TailTipPivot
@onready var skull: MeshInstance3D = $VisualRoot/BodyPivot/NeckPivot/HeadPivot/Skull
@onready var drip: GPUParticles3D = $VisualRoot/Drip
## The imported body's own walk cycle. It ships exactly one clip, so the gait is
## carried by its rate rather than by clip selection - see _animate_crawl().
@onready var model_animation: AnimationPlayer = get_node_or_null(
	^"VisualRoot/BodyPivot/Model/AnimationPlayer"
) as AnimationPlayer
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var crawl_audio: AudioStreamPlayer3D = $CrawlAudio
@onready var chitter_audio: AudioStreamPlayer3D = $ChitterAudio
@onready var breath_audio: AudioStreamPlayer3D = $BreathAudio
@onready var scream_audio: AudioStreamPlayer3D = $ScreamAudio
@onready var bone_audio: AudioStreamPlayer3D = $BoneAudio

## Limb chains, in the order they are driven: the two diagonal pairs are
## (front-left, back-right) and (front-right, back-left).
@onready var limb_roots: Array[Node3D] = [
	$VisualRoot/BodyPivot/Limbs/FrontLeft,
	$VisualRoot/BodyPivot/Limbs/BackRight,
	$VisualRoot/BodyPivot/Limbs/FrontRight,
	$VisualRoot/BodyPivot/Limbs/BackLeft,
]
var limb_lowers: Array[Node3D] = []
var limb_hands: Array[Node3D] = []

# Rest pose of one limb, in degrees, authored here rather than in the scene so
# the animation code is the single source of truth for the silhouette.
#
# The whole read of this creature comes from two deliberate anatomical errors:
#   1. the upper limb is rotated past horizontal, so the elbow/knee rides ABOVE
#      the spine instead of below it, and
#   2. the second joint folds the wrong way, so the forearm comes back down to
#      the surface from the outside like a spider's leg, not a human's.
#
# Limb segments hang down local -Y, and a rotation of t about local +Z sends
# that to (sin t, -cos t, 0). So the left limb (side -1) opens to -118 degrees:
# out to its own side and 28 degrees ABOVE horizontal, which is the raised
# elbow. The forearm then adds +91, landing at a net -27 degrees - back down
# onto the surface from outside the shoulder. Both numbers mirror through
# `side`, and `lift` always increases the fold so the hand peels off the
# surface on the recovery half of the stride.
const LIMB_UPPER_SPLAY := 118.0
const LIMB_UPPER_PITCH := 22.0
const LIMB_LOWER_FOLD := -91.0
const LIMB_HAND_FLAT := 46.0
const LIMB_SIDE_SIGNS: Array[float] = [-1.0, 1.0, 1.0, -1.0]
const LIMB_FRONT_SIGNS: Array[float] = [1.0, -1.0, 1.0, -1.0]


func _ready() -> void:
	add_to_group('crawler_ghosts')
	add_to_group('hostile_ghosts')
	normal_collision_layer = collision_layer
	normal_collision_mask = collision_mask
	wedge_anchor = global_position
	last_contained_position = global_position
	has_contained_position = _is_inside_containment(global_position)
	last_noise_position = global_position
	search_point = global_position
	lair_position = global_position
	surface_normal = Vector3.UP
	facing_direction = -global_basis.z
	patrol_chitter_timer = randf_range(patrol_chitter_interval_min, patrol_chitter_interval_max)
	for limb: Node3D in limb_roots:
		var lower := limb.get_node('LowerPivot') as Node3D
		limb_lowers.append(lower)
		limb_hands.append(lower.get_node('HandPivot') as Node3D)
	_prepare_materials()
	_start_model_animation()
	_apply_rest_pose()
	# Route markers are ordinary scene nodes, so they only exist once the rest of
	# the level has entered the tree.
	_resolve_route.call_deferred()

	if not active:
		_set_state(CrawlerState.DORMANT)
	elif hunt_cycle_enabled and start_hidden:
		_enter_hidden(randf_range(initial_hidden_delay_min, initial_hidden_delay_max))
	else:
		_begin_patrol()


## Reads the lair and the patrol route out of the scene. Keeping these in groups
## rather than as coordinates in this script means the route belongs to the
## level, and the creature works unchanged in a test box with neither.
func _resolve_route() -> void:
	if not is_inside_tree():
		return
	patrol_points.clear()
	for node: Node in get_tree().get_nodes_in_group(patrol_point_group):
		var marker := node as Node3D
		if marker:
			patrol_points.append(marker.global_position)

	for node: Node in get_tree().get_nodes_in_group(lair_group):
		var marker := node as Node3D
		if marker:
			lair_position = marker.global_position
			break


func _physics_process(delta: float) -> void:
	# See hunter_ghost.gd: on a client this body is placed and animated by
	# WorldReplicator, never simulated here.
	if not WorldNet.is_world_authority():
		return
	attack_resume_grace_remaining = maxf(attack_resume_grace_remaining - delta, 0.0)
	if not active:
		velocity = Vector3.ZERO
		return

	if state == CrawlerState.HIDDEN:
		velocity = Vector3.ZERO
		_update_hidden(delta)
		_update_player_threat()
		return

	if _is_inside_containment(global_position):
		last_contained_position = global_position
		has_contained_position = true

	regrip_cooldown_timer = maxf(regrip_cooldown_timer - delta, 0.0)
	wedge_escape_timer = maxf(wedge_escape_timer - delta, 0.0)
	_refresh_cling_exclusions()
	_listen(delta)
	_update_surface(delta)
	_update_player_awareness(delta)
	_track_loiter(delta)

	match state:
		CrawlerState.OMEN:
			_update_omen(delta)
		CrawlerState.PATROL:
			_update_patrol(delta)
		CrawlerState.HUNTING:
			_update_hunting(delta)
		CrawlerState.SEARCHING:
			_update_searching(delta)
		CrawlerState.POUNCE_WINDUP:
			_update_pounce_windup(delta)
		CrawlerState.POUNCING:
			_update_pouncing(delta)
		CrawlerState.RECOVERING:
			_update_recovering(delta)
		CrawlerState.LEAVING:
			_update_leaving(delta)
		CrawlerState.RETREATING:
			_update_retreating(delta)
		CrawlerState.DORMANT:
			velocity = Vector3.ZERO

	_apply_adhesion(delta)
	move_and_slide()
	if not _recover_inside_containment():
		_resolve_wall_transition()
	_update_stuck_state(delta)
	_update_orientation(delta)
	_update_player_threat()
	_update_presentation(delta)


func set_dev_attack_suspended(suspended: bool) -> void:
	_set_attack_suspension(suspended, director_attacks_suspended)


## The director's hold on this ghost's attacks. Held separately from the lock
## above so the two cannot overwrite each other: either one alone blocks, and
## attacks only resume once both have let go.
func set_director_attacks_suspended(suspended: bool) -> void:
	_set_attack_suspension(dev_attack_suspended, suspended)


## True while this ghost is a live threat the director has to count against its
## concurrency budget. Patrolling counts here, unlike the huntsman's: the
## crawler is only ever on patrol during a hunt, and is absent between them.
func is_engaged() -> bool:
	return state in [
		CrawlerState.OMEN,
		CrawlerState.PATROL,
		CrawlerState.HUNTING,
		CrawlerState.SEARCHING,
		CrawlerState.POUNCE_WINDUP,
		CrawlerState.POUNCING,
	]


## Director hook: brings the next hunt forward without starting one. It only
## ever shortens a wait that is already running, so a cycle already underway is
## left alone - the director changes the schedule, never a live encounter.
func request_hunt_soon(within_seconds: float) -> bool:
	if not active or not hunt_cycle_enabled or state != CrawlerState.HIDDEN:
		return false
	hidden_timer = minf(hidden_timer, maxf(within_seconds, 0.0))
	return true


func _set_attack_suspension(dev_held: bool, director_held: bool) -> void:
	var was_blocked := dev_attack_suspended or director_attacks_suspended
	dev_attack_suspended = dev_held
	director_attacks_suspended = director_held
	var is_blocked := dev_held or director_held
	if is_blocked == was_blocked:
		return
	if is_blocked:
		attack_resume_grace_remaining = 0.0
		if state == CrawlerState.POUNCE_WINDUP or state == CrawlerState.POUNCING:
			WorldNet.stop_shared(scream_audio)
			pounce_timer = 0.0
			pounce_air_time = 0.0
			_brake(1.0)
			_set_state(CrawlerState.RECOVERING)
	else:
		attack_resume_grace_remaining = maxf(
			attack_resume_grace_remaining,
			pounce_cooldown
		)
		pounce_cooldown_timer = maxf(pounce_cooldown_timer, pounce_cooldown)
	_update_player_threat()


func _attacks_blocked() -> bool:
	return dev_attack_suspended \
		or director_attacks_suspended \
		or attack_resume_grace_remaining > 0.0


## Forces the existing crawler instance into the world near the chosen player.
## It resumes its authored patrol instead of waiting for the next hidden cycle.
func dev_force_spawn(target: CharacterBody3D = null) -> bool:
	active = true
	var spawn_position := lair_position
	if is_instance_valid(target):
		var camera := target.get_node_or_null("CameraPivot/Camera3D") as Camera3D
		var forward := -target.global_basis.z
		if camera:
			forward = -camera.global_basis.z
		forward.y = 0.0
		if forward.length_squared() > 0.0001:
			forward = forward.normalized()
			var candidate := _standable_point(target.global_position + forward * 5.5)
			if candidate != Vector3.INF:
				spawn_position = candidate

	spawn_position = _clamp_to_containment(spawn_position, containment_recovery_inset)
	global_position = spawn_position
	last_contained_position = spawn_position
	has_contained_position = true
	velocity = Vector3.ZERO
	surface_normal = Vector3.UP
	has_surface = false
	steer_direction = Vector3.ZERO
	wedge_escape_timer = 0.0
	has_noise_fix = false
	noise_confidence = 0.0
	noise_source = null
	pounce_timer = 0.0
	pounce_air_time = 0.0
	pounce_cooldown_timer = 0.0
	_begin_patrol()
	WorldNet.play_shared(chitter_audio)
	return true


# --- Level containment --------------------------------------------------------


func _is_inside_containment(point: Vector3) -> bool:
	if not containment_enabled:
		return true
	return point.x >= containment_min.x and point.x <= containment_max.x \
		and point.y >= containment_min.y and point.y <= containment_max.y \
		and point.z >= containment_min.z and point.z <= containment_max.z


func _clamp_to_containment(point: Vector3, inset: float = 0.0) -> Vector3:
	if not containment_enabled:
		return point
	var size := containment_max - containment_min
	var safe_inset := clampf(
		inset,
		0.0,
		maxf(minf(size.x, minf(size.y, size.z)) * 0.49, 0.0)
	)
	var lower := containment_min + Vector3.ONE * safe_inset
	var upper := containment_max - Vector3.ONE * safe_inset
	return Vector3(
		clampf(point.x, lower.x, upper.x),
		clampf(point.y, lower.y, upper.y),
		clampf(point.z, lower.z, upper.z)
	)


## Restores the previous valid frame rather than teleporting to an unrelated
## patrol marker. The inset puts the body back on the interior side of the wall,
## then the lost noise fix prevents it from immediately charging outside again.
func _recover_inside_containment() -> bool:
	if _is_inside_containment(global_position):
		last_contained_position = global_position
		has_contained_position = true
		return false

	var escaped_position := global_position
	var recovery_position := last_contained_position if has_contained_position else lair_position
	if not _is_inside_containment(recovery_position):
		recovery_position = (containment_min + containment_max) * 0.5
	recovery_position = _clamp_to_containment(recovery_position, containment_recovery_inset)

	var interrupted_pounce := state == CrawlerState.POUNCE_WINDUP \
		or state == CrawlerState.POUNCING
	global_position = recovery_position
	last_contained_position = recovery_position
	has_contained_position = true
	velocity = Vector3.ZERO
	up_direction = Vector3.UP
	surface_normal = Vector3.UP
	has_surface = false
	airborne_time = cling_lost_time
	regrip_cooldown_timer = regrip_cooldown
	no_progress_time = 0.0
	wedge_anchor = recovery_position
	failed_releases = 0
	pounce_timer = 0.0
	pounce_air_time = 0.0
	pounce_cooldown_timer = maxf(pounce_cooldown_timer, pounce_cooldown)
	has_noise_fix = false
	noise_confidence = 0.0
	noise_source = null
	last_noise_position = recovery_position
	search_point = recovery_position
	steering_goal = recovery_position
	steer_direction = Vector3.ZERO
	wedge_escape_timer = 0.0
	if state != CrawlerState.HIDDEN and state != CrawlerState.DORMANT:
		_set_state(CrawlerState.PATROL if not patrol_points.is_empty() else CrawlerState.SEARCHING)
	if interrupted_pounce:
		pounce_missed.emit()
	_play_bone_snap()
	containment_recovered.emit(escaped_position, recovery_position)
	return true


# --- Hearing ------------------------------------------------------------------


## Public noise channel. Anything in the world that makes a sound can call this
## (doors do), and so can a test that needs a deterministic stimulus instead of
## having to physically walk a player around.
func report_noise(position: Vector3, loudness: float, source: Node = null) -> void:
	if not active or state == CrawlerState.DORMANT:
		return
	if not _is_inside_containment(position):
		return
	var clamped := clampf(loudness, 0.0, 1.0)
	if clamped <= 0.0:
		return

	# While it is hidden it cannot be called: a noise only makes it impatient,
	# and the omen still has to play before anything can hurt anyone. Skipping
	# straight to a hunt here is exactly the un-announced ambush this cycle
	# exists to remove.
	if state == CrawlerState.HIDDEN:
		hidden_timer -= hidden_timer * noise_impatience * clamped
		return
	# During the fly-past it is deaf. It is a scripted crossing, and letting a
	# noise redirect it mid-dash turns the warning back into an attack. Leaving
	# is deaf for the same reason: it is walking away from a player who is very
	# probably still making noise, and hearing them would just turn it round.
	if state == CrawlerState.OMEN \
		or state == CrawlerState.RETREATING \
		or state == CrawlerState.LEAVING:
		return

	var distance := global_position.distance_to(position)
	var reach := clamped * hearing_range
	if _is_occluded(position, source):
		reach *= wall_muffle
	if distance > reach or reach <= 0.001:
		return

	# Nearer and louder wins. A quiet noise right beside it still beats a distant
	# sprint, which is what lets a player draw it away with a thrown-sounding
	# event on the far side of a room.
	var confidence := clampf(1.0 - distance / reach, 0.0, 1.0) * clamped
	if confidence < noise_confidence and has_noise_fix:
		return

	last_noise_position = position
	noise_confidence = confidence
	has_noise_fix = true
	noise_source = source as CharacterBody3D
	noise_heard.emit(position, clamped)

	if state == CrawlerState.PATROL and clamped >= patrol_alert_loudness:
		# Only a real noise breaks the sweep. A crouch-walk registers as a fix -
		# so it will drift your way - without turning the patrol into a chase.
		_set_state(CrawlerState.HUNTING)
	elif state == CrawlerState.SEARCHING and distance > arrive_distance:
		# Only a noise it has somewhere to go to pulls it back out of a sweep.
		# Without the distance test, a player making noise right where it is
		# already standing flips it between hunting and searching every frame.
		_set_state(CrawlerState.HUNTING)


func _refresh_cling_exclusions() -> void:
	_cling_exclusions.clear()
	_cling_exclusions.append(get_rid())
	for node: Node in get_tree().get_nodes_in_group('players'):
		var body := node as CollisionObject3D
		if body:
			_cling_exclusions.append(body.get_rid())


func _listen(delta: float) -> void:
	noise_confidence = maxf(noise_confidence - trail_decay * delta, 0.0)
	if noise_confidence <= 0.0:
		has_noise_fix = false

	for player: CharacterBody3D in _living_players():
		var loudness := _player_loudness(player)
		if loudness > 0.0:
			report_noise(player.global_position, loudness, player)

		# Contact overrides silence entirely: it has just put a hand on you.
		# Patrol is excluded - a slow sweep passing over a player who is holding
		# still is the payoff for holding still, and it must not be a death.
		if state != CrawlerState.PATROL \
			and global_position.distance_to(player.global_position) <= touch_detection_range:
			last_noise_position = player.global_position
			noise_confidence = 1.0
			has_noise_fix = true
			noise_source = player
			if state == CrawlerState.SEARCHING:
				_set_state(CrawlerState.HUNTING)


## Converts what a player is physically doing into a 0..1 loudness. Standing
## still is genuinely zero - that is the entire stealth mechanic, so it must not
## be fudged with a floor value.
func _player_loudness(player: CharacterBody3D) -> float:
	var key := player.get_instance_id()
	var on_floor := player.is_on_floor()
	var was_airborne: bool = _player_airborne.get(key, false)
	_player_airborne[key] = not on_floor

	if on_floor and was_airborne:
		return landing_noise

	if not on_floor:
		return 0.0

	var real_velocity := player.get_real_velocity()
	var horizontal_speed := Vector2(real_velocity.x, real_velocity.z).length()
	var loudness := clampf(horizontal_speed / maxf(loud_reference_speed, 0.01), 0.0, 1.0)
	if 'is_crouching' in player and player.is_crouching:
		loudness *= crouch_noise_multiplier
	# Footfalls, not a siren: below a slow creep there is nothing to hear.
	return loudness if loudness > 0.06 else 0.0


## Is there architecture between the crawler and a point? `subject` must be
## excluded whenever the point is a body's own position, or its own collider is
## the first thing the ray finds and it reports itself as behind a wall - which
## silently makes both the pounce and the hearing muffle permanent.
func _is_occluded(point: Vector3, subject: Node = null) -> bool:
	var excluded: Array[RID] = [get_rid()]
	var subject_body := subject as CollisionObject3D
	if subject_body:
		excluded.append(subject_body.get_rid())
	var query := PhysicsRayQueryParameters3D.create(
		global_position,
		point,
		surface_mask,
		excluded
	)
	query.hit_from_inside = true
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()


# --- Surface adhesion ---------------------------------------------------------


## Finds the surface the body should be gripping this frame and eases the local
## "up" onto it. Three probes, in priority order:
##
##   1. straight under the belly     - stay on the plane we are already on
##   2. ahead, along the same plane  - the plane continues past the lip
##   3. around a convex edge         - the plane has ended; feel for the face on
##                                     the far side of the corner and pour onto it
##
## Concave corners (crawling into a wall, or into the wall/ceiling join) are not
## probed for here at all - move_and_slide reports those as real collisions, and
## _resolve_wall_transition re-anchors from the collision normal, which is both
## cheaper and more reliable than guessing with a ray.
func _update_surface(delta: float) -> void:
	if state == CrawlerState.POUNCING:
		has_surface = false
		# Mid-leap it is a normal falling body, so its local up has to unwind
		# back to world up - otherwise a leap launched off a ceiling keeps
		# probing upward and mistakes the ceiling it just left for a landing.
		surface_normal = _ease_normal(surface_normal, Vector3.UP, surface_align_speed * delta)
		return

	var forward := facing_direction
	if velocity.length_squared() > 0.04:
		var tangent := velocity - surface_normal * velocity.dot(surface_normal)
		if tangent.length_squared() > 0.01:
			forward = tangent.normalized()

	var found_normal := _probe_cling_normal(forward)
	if found_normal == Vector3.ZERO:
		airborne_time += delta
		if airborne_time >= cling_lost_time:
			has_surface = false
			# Falling with a stale ceiling normal aims every probe at the sky,
			# so it can never find the floor it is about to land on. Rolling the
			# local up back toward world up while airborne is what lets a
			# dropped or missed-pounce crawler re-grip on impact.
			surface_normal = _ease_normal(
				surface_normal,
				Vector3.UP,
				surface_align_speed * 0.5 * delta
			)
		return

	airborne_time = 0.0
	if not has_surface:
		has_surface = true
	_align_surface(found_normal, delta)


func _probe_cling_normal(forward: Vector3) -> Vector3:
	# The fly-past is a flat sprint across a doorway at 13 m/s. Left to grip
	# whatever it brushes at that speed it ends the dash hanging off a ceiling,
	# and the patrol then starts from up there instead of from the floor.
	if not wall_crawling_enabled or state == CrawlerState.OMEN:
		# Floor-only control mode: only ever accept ground under the belly.
		var ground := _cast_surface(global_position, Vector3.DOWN, cling_probe_distance)
		return ground if ground.dot(Vector3.UP) > 0.5 else Vector3.ZERO

	var under_belly := _cast_surface(global_position, -surface_normal, cling_probe_distance)
	if under_belly != Vector3.ZERO:
		return under_belly

	var ahead := global_position + forward * edge_reach
	var ahead_hit := _cast_surface(ahead, -surface_normal, cling_probe_distance + edge_reach)
	if ahead_hit != Vector3.ZERO:
		return ahead_hit

	# Convex wrap: stand off past the edge and below the old plane, then feel
	# backwards for the face we just crawled over the top of.
	var wrap_origin := ahead - surface_normal * edge_reach
	var wrap_hit := _cast_surface(wrap_origin, -forward, edge_reach * 1.8)
	if wrap_hit != Vector3.ZERO:
		return wrap_hit

	# Last resort, and the one that catches a landing: real ground, straight
	# down in world space, regardless of what plane it thinks it is on.
	var ground := _cast_surface(global_position, Vector3.DOWN, cling_probe_distance)
	if ground != Vector3.ZERO and ground.dot(Vector3.UP) > 0.5:
		return ground

	return Vector3.ZERO


func _cast_surface(origin: Vector3, direction: Vector3, distance: float) -> Vector3:
	if direction.is_zero_approx() or distance <= 0.0:
		return Vector3.ZERO
	var query := PhysicsRayQueryParameters3D.create(
		origin,
		origin + direction.normalized() * distance,
		surface_mask,
		_cling_exclusions
	)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return Vector3.ZERO
	var normal: Vector3 = hit['normal']
	return normal.normalized() if not normal.is_zero_approx() else Vector3.ZERO


func _align_surface(new_normal: Vector3, delta: float) -> void:
	# Both sides are re-normalized here rather than trusted. Vector3.slerp builds
	# an axis-angle rotation and hard-errors on a non-unit input, and normals
	# coming off the house's generated trimesh colliders are routinely a
	# thousandth short of unit length.
	var target := new_normal.normalized()
	if target.is_zero_approx():
		return
	var current := surface_normal.normalized()
	if target.distance_to(current) > surface_change_threshold:
		# Every re-grip pops the joints. This is the sound that tells a player
		# in the next room that it has just left the floor for the wall.
		_play_bone_snap()
		surface_changed.emit(target)
	surface_normal = _ease_normal(current, target, surface_align_speed * delta)


## Eases one surface normal toward another, avoiding the numerical trap in
## slerping two vectors that are already all but identical.
##
## Vector3.slerp rotates about the cross product of its two arguments, and for a
## converged alignment - which is most frames, since the crawler holds one
## surface for seconds at a time - that cross product is entirely floating point
## noise. Godot rejects the non-unit axis it normalizes to and hands back a zero
## vector, which lands in `surface_normal`: one frame with no adhesion and no
## usable local up, and a spurious re-grip, bone snap and `surface_changed` on
## the frame after, because a zero normal is a long way from every real one.
##
## There is nothing left to interpolate that close in, so it snaps instead.
func _ease_normal(current: Vector3, target: Vector3, weight: float) -> Vector3:
	var to := target.normalized()
	if to.is_zero_approx():
		return current
	var from := current.normalized()
	if from.is_zero_approx() or from.dot(to) > 0.9999:
		return to
	return from.slerp(to, clampf(weight, 0.0, 1.0)).normalized()


func _apply_adhesion(delta: float) -> void:
	if has_surface and state != CrawlerState.POUNCING:
		up_direction = surface_normal
		var inward_speed := velocity.dot(-surface_normal)
		if inward_speed < max_cling_speed:
			velocity += -surface_normal * cling_force * delta
			inward_speed = velocity.dot(-surface_normal)
		if inward_speed > max_cling_speed:
			velocity += surface_normal * (inward_speed - max_cling_speed)
		return

	up_direction = Vector3.UP
	velocity.y -= gravity * delta


## Re-anchors onto a wall the body has just run into. Only a surface meaningfully
## tilted away from the current one counts - otherwise it would re-anchor to
## every scrap of trim it brushes and jitter along a flat floor.
func _resolve_wall_transition() -> void:
	if not wall_crawling_enabled \
		or state == CrawlerState.POUNCING \
		or state == CrawlerState.OMEN:
		return
	if regrip_cooldown_timer > 0.0 and has_surface:
		return

	# While airborne any contact is worth gripping, so the threshold drops to
	# zero - that is how a fall or a spent leap re-attaches on impact.
	var best_normal := Vector3.ZERO
	var best_difference := surface_change_threshold if has_surface else -1.0
	for index: int in get_slide_collision_count():
		var collision := get_slide_collision(index)
		var normal := collision.get_normal()
		var difference := normal.distance_to(surface_normal)
		if difference > best_difference:
			best_difference = difference
			best_normal = normal

	if best_normal == Vector3.ZERO:
		return
	# Never re-anchor to a surface we would immediately fall off: the new normal
	# has to actually support the body from the side it hit.
	if best_normal.dot(velocity.normalized()) > 0.35:
		return

	has_surface = true
	airborne_time = 0.0
	regrip_cooldown_timer = regrip_cooldown
	_play_bone_snap()
	surface_changed.emit(best_normal)
	surface_normal = best_normal.normalized()


func _update_orientation(delta: float) -> void:
	var tangent := velocity - surface_normal * velocity.dot(surface_normal)
	if tangent.length_squared() > 0.02:
		facing_direction = tangent.normalized()

	# Normalized rather than trusted: Basis.slerp requires an orthonormal basis
	# and a column that is a thousandth off unit length is enough to trip it.
	var up := surface_normal.normalized()
	var forward := facing_direction - up * facing_direction.dot(up)
	if forward.length_squared() < 0.0001:
		forward = -global_basis.z - up * (-global_basis.z).dot(up)
	if forward.length_squared() < 0.0001:
		return
	forward = forward.normalized()

	var back := -forward
	var right := up.cross(back)
	if right.length_squared() < 0.0001:
		return
	var target_basis := Basis(right.normalized(), up, back).orthonormalized()
	global_basis = global_basis.slerp(target_basis, minf(turn_speed * delta, 1.0)).orthonormalized()


# --- States -------------------------------------------------------------------


func _set_state(new_state: CrawlerState) -> void:
	if state == new_state:
		return
	state = new_state
	if new_state != CrawlerState.POUNCE_WINDUP and new_state != CrawlerState.POUNCING:
		pounce_target = null
	match new_state:
		CrawlerState.SEARCHING:
			search_timer = search_duration
			search_point_timer = 0.0
		CrawlerState.RECOVERING:
			recovery_timer = pounce_recovery
	state_changed.emit(new_state)


# --- Hunt cycle ---------------------------------------------------------------


## Out of play entirely: no body, no collision, nothing to be killed by. This is
## where it spends most of the game.
func _enter_hidden(delay: float) -> void:
	hidden_timer = maxf(delay, 0.0)
	velocity = Vector3.ZERO
	has_noise_fix = false
	noise_confidence = 0.0
	noise_source = null
	pounce_target = null
	player_visibility_times.clear()
	aware_player_ids.clear()
	attack_announced = false
	pounce_cooldown_timer = 0.0
	global_position = lair_position
	surface_normal = Vector3.UP
	has_surface = false
	_set_manifested(false)
	_set_state(CrawlerState.HIDDEN)


func _set_manifested(is_manifested: bool) -> void:
	manifested = is_manifested
	visual_root.visible = is_manifested
	drip.emitting = is_manifested
	collision_layer = normal_collision_layer if is_manifested else 0
	collision_mask = normal_collision_mask if is_manifested else 0
	if not is_manifested:
		crawl_audio.stop()
		breath_audio.stop()


func _update_hidden(delta: float) -> void:
	hidden_timer -= delta
	if hidden_timer > 0.0:
		return
	if _living_players().is_empty():
		hidden_timer = 2.0
		return
	_begin_omen()


## The fly-past. It materialises to one side of a player's view, bolts across
## it far too fast to react to, and is gone - then the real hunt starts. This is
## the single most important thing the creature does, because it converts an
## ambush into an announced threat the player can prepare for.
func _begin_omen() -> void:
	if not omen_enabled:
		_begin_patrol()
		return

	var crossing := _find_omen_crossing()
	if crossing.is_empty():
		# Nobody could be shown a clean pass. Announce it anyway - an unheralded
		# hunt is exactly what this cycle exists to prevent.
		if omen_audio_fallback:
			global_position = _overhead_announce_position()
			WorldNet.play_shared(scream_audio)
		_begin_patrol()
		return

	global_position = crossing['from']
	omen_target_point = crossing['to']
	surface_normal = Vector3.UP
	has_surface = false
	omen_timer = omen_max_duration
	velocity = (omen_target_point - global_position).normalized() * omen_speed
	facing_direction = velocity.normalized()
	_set_manifested(true)
	WorldNet.play_shared(chitter_audio)
	_set_state(CrawlerState.OMEN)
	_mark_player_aware(crossing['player'] as CharacterBody3D)
	omen_started.emit(crossing['player'], crossing['from'], crossing['to'])


func _update_omen(delta: float) -> void:
	omen_timer -= delta
	var to_target := omen_target_point - global_position
	to_target.y = 0.0
	if omen_timer <= 0.0 or to_target.length() <= 0.6:
		_begin_patrol()
		return

	# Straight, flat and flat out. No steering, no navigation, no attacking:
	# for these two seconds it is a shape crossing a doorway, nothing more.
	var direction := to_target.normalized()
	var vertical := velocity.y
	velocity = direction * omen_speed
	velocity.y = vertical
	facing_direction = direction


## Picks a player and a line across their view to bolt along. Both ends are
## snapped to real standable ground so it does not sprint through a wall, and
## the near end is pushed outside the view cone so it enters frame rather than
## popping into existence in the middle of it.
func _find_omen_crossing() -> Dictionary:
	var players: Array[CharacterBody3D] = []
	for candidate: CharacterBody3D in _living_players():
		if _is_inside_containment(candidate.global_position):
			players.append(candidate)
	if players.is_empty():
		return {}
	var player: CharacterBody3D = players[randi() % players.size()]
	var camera := player.get_node_or_null('CameraPivot/Camera3D') as Camera3D
	var forward := -player.global_basis.z
	if camera:
		forward = -camera.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return {}
	forward = forward.normalized()
	var sideways := Vector3.UP.cross(forward).normalized()

	for attempt: int in omen_candidate_count:
		var distance := randf_range(omen_distance_min, omen_distance_max)
		var side := 1.0 if attempt % 2 == 0 else -1.0
		var centre := player.global_position + forward * distance
		var from := _standable_point(centre + sideways * omen_crossing_half_width * side)
		var to := _standable_point(centre - sideways * omen_crossing_half_width * side)
		if from == Vector3.INF or to == Vector3.INF:
			continue
		if not _is_inside_containment(from) or not _is_inside_containment(to):
			continue
		if from.distance_to(to) < omen_crossing_half_width:
			continue
		# Both ends on the player's own floor, or it crosses a room they cannot
		# see into.
		if absf(from.y - to.y) > 0.8 or absf(from.y - player.global_position.y) > 2.0:
			continue
		return {'player': player, 'from': from, 'to': to}
	return {}


## Nearest point the creature could actually sit on, using the navmesh when the
## level has one and a downward probe when it does not.
func _standable_point(near: Vector3) -> Vector3:
	if _has_navigation():
		var map_rid := nav_agent.get_navigation_map()
		var nav_point := NavigationServer3D.map_get_closest_point(map_rid, near)
		if nav_point.distance_to(near) > 3.0:
			return Vector3.INF
		return nav_point + Vector3.UP * 0.35

	var query := PhysicsRayQueryParameters3D.create(
		near + Vector3.UP * 1.5,
		near + Vector3.DOWN * 3.0,
		surface_mask,
		_cling_exclusions
	)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return Vector3.INF
	return (hit['position'] as Vector3) + Vector3.UP * 0.35


func _overhead_announce_position() -> Vector3:
	var players: Array[CharacterBody3D] = []
	for candidate: CharacterBody3D in _living_players():
		if _is_inside_containment(candidate.global_position):
			players.append(candidate)
	if players.is_empty():
		return lair_position
	var player: CharacterBody3D = players[randi() % players.size()]
	return player.global_position + Vector3.UP * 3.2


func _begin_patrol() -> void:
	_set_manifested(true)
	patrol_lap = 0
	patrol_index = 0
	patrol_point_timer = patrol_point_timeout
	patrol_chitter_timer = randf_range(patrol_chitter_interval_min, patrol_chitter_interval_max)
	_set_state(CrawlerState.PATROL)


## The slow sweep. It drags itself along the route at a crawl, biased upward so
## it spends the patrol on walls and ceilings, listening. Finding nobody after
## `patrol_laps` sends it home.
func _update_patrol(delta: float) -> void:
	patrol_chitter_timer -= delta
	if patrol_chitter_timer <= 0.0:
		patrol_chitter_timer = randf_range(patrol_chitter_interval_min, patrol_chitter_interval_max)
		if not chitter_audio.playing:
			WorldNet.play_shared(chitter_audio)

	if patrol_points.is_empty():
		# No route authored. Sweep around the lair rather than standing still.
		_set_state(CrawlerState.SEARCHING)
		last_noise_position = lair_position
		return

	var target: Vector3 = patrol_points[patrol_index % patrol_points.size()]
	patrol_point_timer -= delta
	if global_position.distance_to(target) <= patrol_arrive_distance or patrol_point_timer <= 0.0:
		_advance_patrol_point()
		return

	# Aim above the marker so the route pulls it up the walls and onto the
	# ceiling of the room it is crossing. Three conditions, all of them learned
	# the hard way:
	#   - only from level floor, never from a staircase,
	#   - only when the marker is on this level. Adding 2 m of climb to a marker
	#     that is already a storey up aims it at a point inside the building's
	#     structure, and it climbs into the stairwell shaft and wedges there
	#     instead of simply taking the stairs, and
	#   - only as far as the real headroom allows (see _effective_climb_bias).
	# Cross-floor legs are pure navigation, which is what knows about stairs.
	var level := absf(target.y - global_position.y) <= same_level_height
	var on_ground := surface_normal.dot(Vector3.UP) > ground_surface_threshold

	# Changing floors is done on the stairs, like everything else in the house.
	# Navigation is only consulted from walkable ground, so hanging off a ceiling
	# with a target one storey down leaves it steering by straight line into the
	# floor slab - it has to come down first.
	if not level and not on_ground and has_surface:
		_drop_to_floor()
		return

	# Aimed above the marker both while it is starting the climb from flat floor
	# and while it is already up a wall or across a ceiling. Dropping the bias
	# the moment it left the floor was the other half of why it never crossed a
	# ceiling: the raw line to a marker standing on the floor points straight
	# back down, so it would climb a wall and immediately pour off it again.
	var flat := surface_normal.dot(Vector3.UP) > flat_floor_threshold
	var clinging := has_surface and surface_normal.dot(Vector3.UP) <= ground_surface_threshold
	var climb := _effective_climb_bias(target) if (level and (flat or clinging)) else 0.0
	_crawl_toward(delta, target, crawl_speed, climb)


## Climb bias, clipped to whatever headroom actually exists. The raw bias aims
## at a point metres overhead; under a low slab that is a point inside solid
## geometry, and steering at it drove the crawler up into the 0.75 m void under
## the second floor and wedged it there, oscillating between the void's floor
## and its ceiling until the route timeout fired. Aiming just below the real
## ceiling gets the same behaviour - up the wall, across the ceiling - in rooms
## that have the room for it, and no behaviour at all in the ones that do not.
func _effective_climb_bias(target: Vector3) -> float:
	if patrol_climb_bias <= 0.0:
		return 0.0
	# Probed from wherever the climb is actually being started. On the floor that
	# is the crawler itself, and clipping to its own headroom is what stops it
	# steering up into the void under the second storey. Once it is on a wall or
	# a ceiling its own headroom is the slab it is holding onto, so measuring
	# there would retract the bias at exactly the moment the bias is producing
	# the behaviour it exists for; what matters then is how much open air stands
	# over the marker it is crossing toward.
	var on_floor := surface_normal.dot(Vector3.UP) > flat_floor_threshold
	var origin := global_position if on_floor else target + Vector3.UP * 0.1
	var probe := patrol_climb_bias + 0.5
	var query := PhysicsRayQueryParameters3D.create(
		origin,
		origin + Vector3.UP * probe,
		surface_mask,
		_cling_exclusions
	)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return patrol_climb_bias
	var headroom := origin.distance_to(hit['position'])
	return maxf(headroom - 0.7, 0.0)


func _advance_patrol_point() -> void:
	patrol_index += 1
	patrol_point_timer = patrol_point_timeout
	if patrol_index < patrol_points.size():
		return

	patrol_index = 0
	patrol_lap += 1
	patrol_lap_completed.emit(patrol_lap)
	if hunt_cycle_enabled and patrol_lap >= patrol_laps:
		_begin_retreat()


## The loiter watchdog. Anything that leaves it hovering around one player -
## an unreachable noise fix, a body it cannot get past, a leap it is not
## allowed to take - ends the same way: it gives the room back instead of
## grinding there. Only the phases where it is actually hunting are watched;
## a leap or the recovery after one is supposed to happen up close.
func _track_loiter(delta: float) -> void:
	if state != CrawlerState.PATROL \
		and state != CrawlerState.HUNTING \
		and state != CrawlerState.SEARCHING:
		# Cleared rather than paused, so a hidden/omen/leap phase never hands
		# the next patrol a timer that is already most of the way to expiry.
		loiter_timer = 0.0
		return
	var nearest := _closest_living_player()
	if not nearest \
		or global_position.distance_to(nearest.global_position) > loiter_radius:
		loiter_timer = 0.0
		return
	loiter_timer += delta
	if loiter_timer >= loiter_tolerance:
		_begin_leaving()


## Hands the area back. Used both by the loiter watchdog and by a kill - a
## corpse is the one thing guaranteed to still be inside loiter_radius, and
## standing on it was how the creature used to wedge itself after a hunt.
func _begin_leaving() -> void:
	loiter_timer = 0.0
	leave_timer = leave_timeout
	leave_target = _farthest_point_from_players()
	leave_origin = global_position
	# Leaving is a fresh route, not the tail end of the hunt's steering. Keeping
	# an in-progress wedge sidestep (or the smoothed direction into the player)
	# makes the first part of the retreat curl around the room instead of reading
	# as a clean turn away.
	wedge_anchor = global_position
	no_progress_time = 0.0
	wedge_escape_timer = 0.0
	wedge_escape_direction = Vector3.ZERO
	steer_direction = Vector3.ZERO
	_set_state(CrawlerState.LEAVING)
	leaving_area.emit(leave_target)


## The bolt out, at leave_speed and deaf (see report_noise). It ends on
## whichever comes first: real distance from where it turned round, arrival, or
## the timeout that stops one bad destination eating the rest of the cycle.
##
## Distance is measured from `leave_origin` rather than from the nearest living
## player on purpose. After a kill there may be no living player left to measure
## against at all, and the body it has to get off is lying exactly where it
## started - so "how far have I come" is the question that answers both cases.
func _update_leaving(delta: float) -> void:
	leave_timer -= delta
	if global_position.distance_to(leave_origin) >= leave_distance \
		or leave_timer <= 0.0 \
		or global_position.distance_to(leave_target) <= arrive_distance:
		# Straight back onto the sweep rather than into a hunt: it left with a
		# noise fix it deliberately ignored, and re-entering HUNTING here would
		# turn it round on the spot and undo the whole retreat.
		patrol_point_timer = patrol_point_timeout
		_set_state(CrawlerState.PATROL if not patrol_points.is_empty() else CrawlerState.SEARCHING)
		return
	_crawl_toward(delta, leave_target, leave_speed)


## Somewhere else. Every authored patrol marker plus the lair is scored by how
## far it is from the nearest living player - or, once there is no living player
## left to measure against, by how far it is from here - and the best one wins.
##
## A destination that is not actually further away than where it already stands
## is no destination at all: the lair is often the room it is standing in, and a
## fixture with no authored route has nothing but the lair. In that case it just
## heads away from whoever it was on top of, which is the whole point.
func _farthest_point_from_players() -> Vector3:
	var players := _living_players()
	var candidates := patrol_points.duplicate()
	candidates.append(lair_position)
	var best := global_position
	var best_distance := -INF
	for point: Vector3 in candidates:
		var score := global_position.distance_to(point)
		for player: CharacterBody3D in players:
			score = minf(score, point.distance_to(player.global_position))
		if score > best_distance:
			best_distance = score
			best = point
	if best_distance >= leave_distance:
		return _clamp_to_containment(best)
	return _clamp_to_containment(global_position + _away_from_players() * leave_distance)


## Straight out, away from the nearest living player. Falls back to whichever
## way it is already facing when there is nobody left to run from.
func _away_from_players() -> Vector3:
	var nearest := _closest_living_player()
	var away := facing_direction
	if nearest:
		away = global_position - nearest.global_position
	away.y = 0.0
	if away.length_squared() <= 0.001:
		return Vector3.FORWARD
	return away.normalized()


## Gave up. One scream, loud enough to be heard through the whole house, and
## then it is gone - which is also the all-clear the player needs.
func _begin_retreat() -> void:
	retreat_timer = retreat_scream_duration
	WorldNet.play_shared(scream_audio)
	_set_state(CrawlerState.RETREATING)


func _update_retreating(delta: float) -> void:
	_brake(delta)
	retreat_timer -= delta
	if retreat_timer > 0.0:
		return
	retreated.emit()
	_enter_hidden(randf_range(hidden_delay_min, hidden_delay_max))


func _update_hunting(delta: float) -> void:
	if not has_noise_fix:
		_set_state(CrawlerState.SEARCHING)
		return

	if _maul_contact():
		return

	pounce_cooldown_timer = maxf(pounce_cooldown_timer - delta, 0.0)
	var pounce_target := _pounce_candidate()
	if pounce_target:
		_begin_pounce(pounce_target)
		return

	# Dead band closer. A leap needs `pounce_min_range` of run-up and a maul
	# needs `touch_detection_range` of contact, and the gap between the two used
	# to be a safe pocket: make a noise with the crawler already a metre away and
	# it would arrive at the sound, decide it had arrived, and wander off into a
	# search sweep without ever touching you. Inside the leap's minimum it walks
	# the last stretch in by hand. This still needs a live fix, so it is not a
	# way of finding a player who is standing still.
	var closing_target := _closest_living_player()
	if closing_target \
		and noise_confidence >= pounce_min_confidence \
		and global_position.distance_to(closing_target.global_position) < pounce_min_range:
		_crawl_toward(delta, closing_target.global_position, hunting_speed)
		return

	var to_noise := last_noise_position - global_position
	if to_noise.length() <= arrive_distance:
		_set_state(CrawlerState.SEARCHING)
		_brake(delta)
		return

	if noise_confidence < search_confidence:
		_set_state(CrawlerState.SEARCHING)
		return

	_crawl_toward(delta, last_noise_position, hunting_speed)


## Arrived where the sound was and found nothing. It sweeps the area, pausing on
## whatever surface it is on to listen - which is when a player pinned behind a
## sofa gets to watch it pass overhead.
func _update_searching(delta: float) -> void:
	if _maul_contact():
		return

	pounce_cooldown_timer = maxf(pounce_cooldown_timer - delta, 0.0)
	var pounce_target := _pounce_candidate()
	if pounce_target:
		_begin_pounce(pounce_target)
		return

	search_timer -= delta
	if search_timer <= 0.0:
		# Lost them. Rejoin the sweep where it left off rather than giving up on
		# the whole cycle - the lap counter is what ends a hunt, not one failure.
		if hunt_cycle_enabled or not patrol_points.is_empty():
			_set_state(CrawlerState.PATROL)
		return

	search_point_timer -= delta
	if search_point_timer <= 0.0:
		search_point_timer = search_point_interval
		search_point = _pick_search_point()
		if not chitter_audio.playing and randf() < 0.4:
			WorldNet.play_shared(chitter_audio)

	if global_position.distance_to(search_point) <= arrive_distance:
		_brake(delta)
		return
	_crawl_toward(delta, search_point, crawl_speed)


## Picks somewhere worth sweeping to rather than anywhere at all.
##
## This used to be one random point on a flat disc around the noise, clamped to
## the containment box and nothing else, so it regularly landed inside a wall or
## in the next room - and a point inside a wall is one the crawler grinds at for
## the full `search_point_interval` before it is handed another. Two cheap
## filters remove nearly all of those.
func _pick_search_point() -> Vector3:
	for _attempt: int in 6:
		var angle := randf() * TAU
		var radius := randf_range(search_radius * 0.35, search_radius)
		var candidate := _clamp_to_containment(
			last_noise_position + Vector3(cos(angle), 0.0, sin(angle)) * radius
		)
		var settled := _settle_search_point(candidate)
		if settled != Vector3.INF:
			return settled
	return _clamp_to_containment(last_noise_position)


## Pulls a candidate back to the near side of anything between it and the noise,
## then onto the navigation mesh where the level has one. Returns INF for a
## candidate not worth keeping: one walled off almost immediately, or one whose
## nearest walkable point is a whole search radius away, which means it was
## never in this room to begin with.
func _settle_search_point(candidate: Vector3) -> Vector3:
	var origin := last_noise_position
	var query := PhysicsRayQueryParameters3D.create(
		origin,
		candidate,
		surface_mask,
		_cling_exclusions
	)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var blocked: Vector3 = hit['position']
		if origin.distance_to(blocked) < search_radius * 0.35:
			return Vector3.INF
		candidate = blocked + (origin - blocked).normalized() * 0.6

	if not _has_navigation():
		return candidate
	var snapped := NavigationServer3D.map_get_closest_point(
		nav_agent.get_navigation_map(),
		candidate
	)
	if snapped.distance_to(candidate) > search_radius:
		return Vector3.INF
	return snapped


func _update_pounce_windup(delta: float) -> void:
	if _attacks_blocked():
		WorldNet.stop_shared(scream_audio)
		pounce_timer = 0.0
		_set_state(CrawlerState.RECOVERING)
		return
	_brake(delta)
	pounce_timer -= delta
	if pounce_timer > 0.0:
		return

	var target := pounce_target
	if not is_instance_valid(target):
		_set_state(CrawlerState.RECOVERING)
		return

	# Aim where the target will be, not where it is. It is blind and committed
	# from this moment - breaking your line during the windup is the dodge.
	var aim := target.global_position + target.velocity * pounce_lead_time
	var launch := aim - global_position
	var distance := launch.length()
	if distance < 0.01:
		_set_state(CrawlerState.RECOVERING)
		return

	has_surface = false
	airborne_time = cling_lost_time
	pounce_air_time = 0.0
	velocity = launch.normalized() * pounce_speed
	# Arc over the gap only when the target is not below it. Leaping off a
	# ceiling is a dive, and adding lift there sends it into the plaster instead
	# of onto the player - which is most of what this creature does now that it
	# patrols overhead.
	if aim.y >= global_position.y - 0.5:
		velocity += Vector3.UP * (distance * pounce_arc)
	WorldNet.play_shared(scream_audio)
	_set_state(CrawlerState.POUNCING)
	pounce_started.emit(aim)


func _update_pouncing(delta: float) -> void:
	pounce_air_time += delta

	var victim := _pounce_contact()
	if victim:
		_kill(victim)
		return

	# A short blind window so the launch frame's own contact with the surface it
	# pushed off does not immediately count as landing.
	if pounce_air_time < 0.12:
		return
	# Hit something, or ran out of air. Either way the leap is spent, and
	# _resolve_wall_transition re-grips from the impact on the same frame.
	var struck := get_slide_collision_count() > 0 or is_on_floor() or is_on_wall()
	if struck or pounce_air_time >= pounce_max_air_time:
		pounce_missed.emit()
		pounce_cooldown_timer = pounce_cooldown
		_set_state(CrawlerState.RECOVERING)


## The gap a player has to break away in. It is face down on the ground with its
## limbs folded the wrong way, and it takes a moment to get them back under it.
func _update_recovering(delta: float) -> void:
	_brake(delta)
	recovery_timer -= delta
	if recovery_timer <= 0.0:
		_set_state(CrawlerState.HUNTING if has_noise_fix else CrawlerState.SEARCHING)


func _begin_pounce(target: CharacterBody3D) -> void:
	if _attacks_blocked() or not attack_announced:
		return
	pounce_target = target
	pounce_timer = pounce_windup
	_brake(1.0)
	_set_state(CrawlerState.POUNCE_WINDUP)


## A pounce needs a live fix, not just a body in range: a player who has gone
## completely silent is not pounced on even from two metres away. That is the
## reward for holding still, and it is why this checks confidence rather than
## distance alone.
##
## The candidate also has to line up with the fix. Without that, a blind hunter
## sent after a noise on the far side of a room will instead throw itself at
## whatever silent player happens to be standing near it, over and over, and
## never reach the sound it was chasing.
func _pounce_candidate() -> CharacterBody3D:
	if _attacks_blocked() \
		or pounce_cooldown_timer > 0.0 \
		or noise_confidence < pounce_min_confidence \
		or not attack_announced:
		return null
	for player: CharacterBody3D in _living_players():
		if not _is_inside_containment(player.global_position):
			continue
		var distance := global_position.distance_to(player.global_position)
		if distance > pounce_range or distance < pounce_min_range:
			continue
		# Purely positional on purpose. Matching on `noise_source` instead would
		# keep a player targetable long after they went quiet and walked away,
		# which is the one thing going quiet is supposed to buy.
		if player.global_position.distance_to(last_noise_position) > pounce_fix_tolerance:
			continue
		if _is_occluded(player.global_position, player):
			continue
		return player
	return null


## Anything it is physically touching, it kills - no pounce required. A pounce
## has a minimum range, so without this the creature is completely harmless once
## it is close enough to reach out, which is the exact opposite of what a player
## watching it crawl toward them expects. Deliberately not checked while it is
## recovering from a miss: that window has to stay survivable even if the player
## is still lying underneath it.
func _maul_contact() -> bool:
	if _attacks_blocked() or not attack_announced:
		return false
	for player: CharacterBody3D in _living_players():
		if global_position.distance_to(player.global_position) > touch_detection_range:
			continue
		if _is_occluded(player.global_position, player):
			continue
		WorldNet.play_shared(scream_audio)
		_kill(player)
		return true
	return false


func _pounce_contact() -> CharacterBody3D:
	if _attacks_blocked():
		return null
	# A leap is committed to the noisy player who triggered it. Do not turn an
	# announced dodge test into collateral damage on somebody else.
	var player := pounce_target
	if not is_instance_valid(player):
		return null
	if "is_alive" in player and not bool(player.get("is_alive")):
		return null
	if global_position.distance_to(player.global_position) > pounce_kill_radius:
		return null
	# Occlusion still matters at contact range: without it a pounce that lands
	# on the floor above kills the intended player standing underneath it.
	if _is_occluded(player.global_position, player):
		return null
	return player


func _kill(player: CharacterBody3D) -> void:
	if _attacks_blocked():
		return
	if player.has_method('kill_by_ghost'):
		player.kill_by_ghost(self)
	killed_player.emit(player)
	pounce_cooldown_timer = pounce_cooldown
	# It leaves over the body rather than folding up on top of it. RECOVERING is
	# the fair-play window a *missed* leap owes the player; after a kill there is
	# nobody left to owe it to, and staying put wedged the creature against the
	# corpse it had just landed on.
	_begin_leaving()


# --- Locomotion ---------------------------------------------------------------


func _crawl_toward(delta: float, point: Vector3, speed: float, climb_bias: float = 0.0) -> void:
	steering_goal = point
	steering_active = true

	var direction := _steering_direction(point, climb_bias)
	if direction.is_zero_approx():
		_brake(delta)
		return

	var tangent_direction := direction - surface_normal * direction.dot(surface_normal)
	if tangent_direction.length_squared() < 0.0001:
		# Target is straight through the surface we are stuck to. Keep crawling
		# along the current facing so it slides off the edge and finds the way.
		tangent_direction = facing_direction - surface_normal * facing_direction.dot(surface_normal)
		if tangent_direction.length_squared() < 0.0001:
			_brake(delta)
			return
	tangent_direction = _smooth_steering(tangent_direction.normalized(), delta)

	var normal_speed := velocity.dot(surface_normal)
	var tangent_velocity := velocity - surface_normal * normal_speed
	tangent_velocity = tangent_velocity.move_toward(
		tangent_direction * speed,
		acceleration * delta
	)
	velocity = tangent_velocity + surface_normal * normal_speed


## While it is on a floor it routes with the navmesh like anything else. The
## moment it is on a wall or a ceiling it drops navigation entirely and takes the
## straight line, climbing whatever is in the way. That switch is the character:
## the house's floor plan stops applying to it.
##
## Being stuck deliberately does NOT switch it to direct steering. It used to,
## and that produced a deadlock: standing on the ground floor directly above a
## basement route point, the direct vector pointed straight down through the
## floor, it stopped moving, being stopped kept navigation switched off, and it
## ground against the same spot until the route timeout rescued it twenty
## seconds later. Navigation is exactly what knows where the stairs are.
## Genuine wedging is handled by _release_grip instead.
func _steering_direction(point: Vector3, climb_bias: float = 0.0) -> Vector3:
	# A sidestep in progress outranks the goal for its commitment window: the
	# only reason one was ever started is that steering at the goal had stopped
	# getting anywhere.
	if wedge_escape_timer > 0.0 and not wedge_escape_direction.is_zero_approx():
		return wedge_escape_direction.normalized()

	var direct := point - global_position
	if direct.length_squared() < 0.0001:
		return Vector3.ZERO

	# A live climb bias means the caller has already cleared it to go up here and
	# now - level floor, marker on this storey, real headroom over it - and going
	# up is not something a floor plan has an opinion about.
	#
	# Consulting navigation at that moment threw the bias away entirely, because
	# the bias is only ever added to the straight line. That is why a crawler in
	# a house with a baked navmesh spent every patrol on the floor while the
	# same crawler in a bare test box climbed exactly as designed: the behaviour
	# was never broken, it was unreachable in the only place it mattered.
	#
	# The bias still must not be handed to the agent. Feeding it a point metres
	# above the floor snaps the destination to whatever navmesh polygon happens
	# to be nearest that empty air, which routes it somewhere else entirely.
	var on_ground := surface_normal.dot(Vector3.UP) > ground_surface_threshold
	if not on_ground or climb_bias > 0.0 or not _has_navigation():
		return (direct + Vector3.UP * climb_bias).normalized()

	if nav_agent.target_position.distance_squared_to(point) > 0.04:
		nav_agent.target_position = point
	var next_point := nav_agent.get_next_path_position()
	var to_next := next_point - global_position
	if nav_agent.get_current_navigation_path().size() > 1 and to_next.length_squared() > 0.0001:
		return to_next.normalized()
	return direct.normalized()


## Eases the steering direction instead of snapping to it, and keeps the result
## on the surface. Interpolating two directions across a curved surface leaves
## the result tilted into it, which reads as the body ducking at every corner,
## so the eased vector is flattened back onto the tangent plane before use.
func _smooth_steering(target: Vector3, delta: float) -> Vector3:
	var previous := steer_direction - surface_normal * steer_direction.dot(surface_normal)
	if steer_smoothing <= 0.0 or previous.length_squared() < 0.0001:
		steer_direction = target
		return target

	var eased := previous.normalized().lerp(target, minf(steer_smoothing * delta, 1.0))
	eased -= surface_normal * eased.dot(surface_normal)
	# An exact reversal interpolates through zero, which would leave it facing
	# nowhere for a frame. Turning on the spot is the honest answer there.
	if eased.length_squared() < 0.0001:
		eased = target
	steer_direction = eased.normalized()
	return steer_direction


## How far the body could travel in `direction`, starting `offset` from where it
## is now, before something stops it. The origin lifts clear of the plane it is
## gripping so that plane is not itself the first thing every probe hits.
func _surface_clearance(direction: Vector3, offset: Vector3 = Vector3.ZERO) -> float:
	if direction.is_zero_approx():
		return 0.0
	var origin := global_position + offset + surface_normal * 0.12
	var query := PhysicsRayQueryParameters3D.create(
		origin,
		origin + direction.normalized() * wedge_probe_distance,
		surface_mask,
		_cling_exclusions
	)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return wedge_probe_distance
	var blocked: Vector3 = hit['position']
	return origin.distance_to(blocked)


func _has_navigation() -> bool:
	var map_rid := nav_agent.get_navigation_map()
	return map_rid.is_valid() \
		and NavigationServer3D.map_get_iteration_id(map_rid) > 0 \
		and not NavigationServer3D.map_get_regions(map_rid).is_empty()


func _brake(delta: float) -> void:
	steering_active = false
	var normal_speed := velocity.dot(surface_normal)
	var tangent_velocity := velocity - surface_normal * normal_speed
	tangent_velocity = tangent_velocity.move_toward(Vector3.ZERO, acceleration * delta * 2.0)
	velocity = tangent_velocity + surface_normal * normal_speed


## Wedged against something the navmesh thinks is passable, or against something
## no navmesh has an opinion about because the crawler is up a wall.
##
## What counts as progress here is net displacement over a window - where it
## physically is against where it physically was - and not, as it used to be,
## how much nearer the goal it has got. The goal is the wrong yardstick twice
## over:
##
##   - during a hunt the goal IS the player, so it moves several times a second,
##     and the old code rebased the whole detector every time it did. A crawler
##     wedged on the ceiling with a player walking about on the far side of a
##     wall therefore never registered as stuck at any point, and shoved into
##     the same corner for as long as the player kept moving. That is the exact
##     failure this rewrite exists for.
##   - a crawler skating back and forth in a corner is moving constantly and
##     getting nowhere, which the frame-to-frame movement check also misses.
##
## Displacement from an anchor answers both, and needs no goal at all.
func _update_stuck_state(delta: float) -> void:

	var should_be_moving := steering_active \
		and (state == CrawlerState.HUNTING
			or state == CrawlerState.SEARCHING
			or state == CrawlerState.PATROL
			or state == CrawlerState.LEAVING)
	if not should_be_moving:
		# Holding still on purpose - arrived, listening, braked - is not being
		# stuck, and letting it accumulate here is what used to drop a crawler
		# off the ceiling for the crime of waiting quietly.
		wedge_anchor = global_position
		no_progress_time = 0.0
		return

	if global_position.distance_to(wedge_anchor) > wedge_progress_distance:
		wedge_anchor = global_position
		no_progress_time = 0.0
		failed_releases = 0
		return

	no_progress_time += delta
	if wedge_escape_timer <= 0.0 and no_progress_time >= wedge_probe_time:
		_begin_wedge_escape()
	if wedge_escape_timer > 0.0:
		# A committed sidestep is a detour, and a detour by definition covers no
		# ground toward anywhere. Feeding that back into the release timer would
		# time out every escape a fraction of a second before it finished.
		return
	if no_progress_time >= stuck_release_time:
		# Sideways did not work either, so it lets go. Off a ceiling or a wall
		# this is the important one: it puts the creature back on the floor,
		# where navigation applies and the way round the wall is a door rather
		# than a straight line through it.
		no_progress_time = 0.0
		wedge_anchor = global_position
		_release_grip()


## Feels along the surface for the open side and commits to it for a moment.
##
## Crawling into a wall is not a fault in this creature - it is how it gets onto
## the wall - so nothing here fires until that has demonstrably stopped paying:
## `wedge_probe_time` of getting no nearer the goal. What it fixes is the case
## climbing cannot, the door reveal or the alcove where the face in front is
## grippable and so are the two beside it, every re-grip picks a different one,
## and the straight line to the goal points into all three. Sliding out sideways
## is the only exit, and it is one direct steering can never find on its own.
func _begin_wedge_escape() -> void:
	var goal_direction := steering_goal - global_position
	goal_direction -= surface_normal * goal_direction.dot(surface_normal)
	if goal_direction.length_squared() < 0.0001:
		goal_direction = facing_direction - surface_normal * facing_direction.dot(surface_normal)
	if goal_direction.length_squared() < 0.0001:
		return
	goal_direction = goal_direction.normalized()

	# Only ever an answer to something physically in the way. Stalling for any
	# other reason - braked at a search point, held off by a pounce cooldown -
	# must not send it wandering off sideways.
	if _surface_clearance(goal_direction) > wedge_probe_distance * 0.6:
		return

	var side := surface_normal.cross(goal_direction)
	if side.length_squared() < 0.0001:
		return
	side = side.normalized()

	var min_room := wedge_probe_distance * 0.5
	var left_room := _surface_clearance(side)
	var right_room := _surface_clearance(-side)
	if maxf(left_room, right_room) < min_room:
		# Boxed in on both sides too. There is nothing to slide to, so leave it
		# to the blunter drop below, which is what that exists for.
		return

	# Which side is open is the wrong question: standing in front of a flat
	# panel both sides are equally open, and choosing on that alone is a coin
	# flip that sends it along the length of the obstruction as often as around
	# the end of it. The question is which side has the GOAL open once it gets
	# there, so the forward probe is repeated from a step out to either hand.
	var left_gain := _surface_clearance(goal_direction, side * left_room * 0.9) 		if left_room >= min_room else -1.0
	var right_gain := _surface_clearance(goal_direction, -side * right_room * 0.9) 		if right_room >= min_room else -1.0
	if maxf(left_gain, right_gain) <= 0.0:
		return
	wedge_escape_direction = side if left_gain >= right_gain else -side
	wedge_escape_timer = wedge_escape_time


## Lets go on purpose. Used when it has wedged itself somewhere no amount of
## steering resolves - typically the corner where two walls meet a ceiling,
## where every face is in contact and each one looks like a better surface than
## the last. Dropping out of it costs a second and usually works.
func _release_grip() -> void:
	_drop_to_floor()
	failed_releases += 1
	if failed_releases >= unstick_relocate_after:
		_relocate_after_wedging()


## Deliberately lets go and falls. Distinct from _release_grip because it is
## also used as ordinary navigation - dropping off a ceiling to take the stairs
## is not a failure and must not count toward relocating.
func _drop_to_floor() -> void:
	wedge_escape_timer = 0.0
	steer_direction = Vector3.ZERO
	has_surface = false
	airborne_time = cling_lost_time
	regrip_cooldown_timer = regrip_cooldown
	velocity += -surface_normal * 1.4 + Vector3.DOWN * 1.2
	surface_normal = Vector3.UP
	_play_bone_snap()


## Last resort. A building assembled from modular panels has slots a 0.68 m
## sphere can enter and not steer out of, and no amount of local escape logic
## fixes all of them. Rather than let one of those strand the patrol - the
## symptom being a crawler that walks up a staircase and never comes back down -
## it relocates to its next route marker.
##
## Only ever while unobserved, so a player never sees it blink across a room.
## If it is being watched it just keeps struggling, which is at least honest.
func _relocate_after_wedging() -> void:
	if _is_visible_to_any_player():
		return

	var destination := lair_position
	if not patrol_points.is_empty():
		destination = patrol_points[patrol_index % patrol_points.size()]
	var landing := _standable_point(destination)
	if landing == Vector3.INF:
		landing = destination

	failed_releases = 0
	no_progress_time = 0.0
	wedge_anchor = landing
	steer_direction = Vector3.ZERO
	wedge_escape_timer = 0.0
	patrol_point_timer = patrol_point_timeout
	global_position = landing
	velocity = Vector3.ZERO
	surface_normal = Vector3.UP
	has_surface = false
	airborne_time = 0.0


func _is_visible_to_any_player() -> bool:
	for player: CharacterBody3D in _living_players():
		if _player_can_see_crawler(player):
			return true
	return false


## Fairness gate for both attacks. The Crawler can still locate anybody by
## sound, but may not commit until at least one player has learned that it is
## present during this manifestation. That announcement is team-wide: once one
## person saw or heard it, anybody who keeps making noise is taking an informed
## risk even if that particular player never looked at the Crawler.
func _update_player_awareness(delta: float) -> void:
	var living_ids: Dictionary = {}
	for player: CharacterBody3D in _living_players():
		var player_id := player.get_instance_id()
		living_ids[player_id] = true
		if aware_player_ids.has(player_id):
			continue

		if _player_can_see_crawler(player):
			var visible_time := float(player_visibility_times.get(player_id, 0.0)) + delta
			player_visibility_times[player_id] = visible_time
			if visible_time >= maxf(minimum_visible_before_awareness, 0.0):
				_mark_player_aware(player)
				continue
		else:
			player_visibility_times[player_id] = 0.0

		if _player_can_hear_crawler(player):
			_mark_player_aware(player)

	for player_id: Variant in player_visibility_times.keys():
		if not living_ids.has(player_id):
			player_visibility_times.erase(player_id)
	for player_id: Variant in aware_player_ids.keys():
		if not living_ids.has(player_id):
			aware_player_ids.erase(player_id)


func _mark_player_aware(player: CharacterBody3D) -> void:
	if not is_instance_valid(player):
		return
	aware_player_ids[player.get_instance_id()] = true
	attack_announced = true


func _player_is_aware(player: CharacterBody3D) -> bool:
	return is_instance_valid(player) and aware_player_ids.has(player.get_instance_id())


func _player_can_see_crawler(player: CharacterBody3D) -> bool:
	if not is_instance_valid(player) or not manifested:
		return false
	var camera := player.get_node_or_null('CameraPivot/Camera3D') as Camera3D
	if not camera or not camera.is_position_in_frustum(global_position):
		return false
	var query := PhysicsRayQueryParameters3D.create(
		camera.global_position,
		global_position,
		surface_mask,
		[player.get_rid(), get_rid()]
	)
	query.hit_from_inside = true
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _player_can_hear_crawler(player: CharacterBody3D) -> bool:
	if not is_instance_valid(player) or not manifested:
		return false
	var distance := global_position.distance_to(player.global_position)
	var occluded := _is_occluded(player.global_position, player)
	for audio: AudioStreamPlayer3D in [
		crawl_audio,
		chitter_audio,
		breath_audio,
		scream_audio,
		bone_audio,
	]:
		if not audio.playing:
			continue
		var audible_distance := audio.max_distance * audio_awareness_distance_multiplier
		if occluded:
			audible_distance *= wall_muffle
		if distance <= audible_distance:
			return true
	return false


func _closest_living_player() -> CharacterBody3D:
	var closest: CharacterBody3D
	var closest_distance := INF
	for player: CharacterBody3D in _living_players():
		if not _is_inside_containment(player.global_position):
			continue
		var distance := global_position.distance_squared_to(player.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest = player
	return closest


func _living_players() -> Array[CharacterBody3D]:
	var players: Array[CharacterBody3D] = []
	for node: Node in get_tree().get_nodes_in_group('players'):
		var player := node as CharacterBody3D
		if not player:
			continue
		if 'is_alive' in player and not player.is_alive:
			continue
		if player.has_method('can_be_targeted_by_ghosts') \
			and not bool(player.call('can_be_targeted_by_ghosts')):
			continue
		players.append(player)
	return players


func _update_player_threat() -> void:
	# Hidden means genuinely gone: the overlay has to go fully clear, or the
	# player never gets the relief that makes the next omen land.
	var threatening := not _attacks_blocked() \
		and state != CrawlerState.DORMANT \
		and state != CrawlerState.HIDDEN
	for node: Node in get_tree().get_nodes_in_group('players'):
		var player := node as CharacterBody3D
		if not player:
			continue
		var amount := 0.0
		if threatening:
			var distance := global_position.distance_to(player.global_position)
			amount = clampf(1.0 - distance / maxf(dread_radius, 0.01), 0.0, 1.0)
			if state == CrawlerState.POUNCE_WINDUP or state == CrawlerState.POUNCING:
				amount = maxf(amount, 0.85)
			elif state == CrawlerState.OMEN or state == CrawlerState.RETREATING:
				amount = maxf(amount, 0.6)
		if player.has_method('set_threat_from'):
			player.set_threat_from('crawler', amount)
		elif player.has_method('set_statue_threat'):
			player.set_statue_threat(amount)


# --- Presentation -------------------------------------------------------------


func _prepare_materials() -> void:
	var source := _primitive_material(skull)
	if source is ShaderMaterial:
		flesh_material = (source as ShaderMaterial).duplicate()
	if not flesh_material:
		return
	for node: Node in visual_root.find_children('*', 'MeshInstance3D', true, false):
		var mesh_instance := node as MeshInstance3D
		if _primitive_material(mesh_instance) == source:
			mesh_instance.material_override = flesh_material


func _primitive_material(mesh_instance: MeshInstance3D) -> Material:
	var primitive := mesh_instance.mesh as PrimitiveMesh
	return primitive.material if primitive else null


func _play_bone_snap() -> void:
	bone_audio.pitch_scale = randf_range(0.82, 1.15)
	WorldNet.play_shared(bone_audio)


func _update_presentation(delta: float) -> void:
	presentation_time += delta

	var tangent_speed := (velocity - surface_normal * velocity.dot(surface_normal)).length()
	var speed_scale := tangent_speed / maxf(crawl_speed, 0.1)

	match state:
		CrawlerState.POUNCE_WINDUP:
			_animate_coil(delta, 1.0 - clampf(pounce_timer / maxf(pounce_windup, 0.01), 0.0, 1.0))
		CrawlerState.POUNCING:
			_animate_coil(delta, 1.0)
		CrawlerState.RECOVERING:
			_animate_collapse(delta)
		_:
			_animate_crawl(delta, speed_scale)

	_update_head_tracking(delta)
	_update_audio(tangent_speed)

	var proximity := 0.0
	for player: CharacterBody3D in _living_players():
		var distance := global_position.distance_to(player.global_position)
		proximity = maxf(proximity, clampf(1.0 - distance / maxf(dread_radius, 0.01), 0.0, 1.0))

	var target_agitation := 0.0
	match state:
		CrawlerState.PATROL:
			# Almost inert on the sweep. The flush going out of it is what makes
			# the change when it finally hears you read at a glance.
			target_agitation = maxf(proximity * 0.5, 0.12)
		CrawlerState.OMEN:
			target_agitation = 1.0
		CrawlerState.HUNTING:
			target_agitation = maxf(proximity, 0.45)
		CrawlerState.SEARCHING:
			target_agitation = maxf(proximity * 0.8, 0.2)
		CrawlerState.POUNCE_WINDUP, CrawlerState.POUNCING:
			target_agitation = 1.0
		CrawlerState.RECOVERING:
			target_agitation = 0.7
		CrawlerState.LEAVING:
			target_agitation = 0.8
		CrawlerState.RETREATING:
			target_agitation = 0.9
	agitation = move_toward(agitation, target_agitation, delta * 3.0)

	# Breathing is fast and shallow when it is hunting, deep and slow on patrol -
	# the ribcage is the only part of it that moves when it is barely crawling.
	var breath_rate := lerpf(0.7, 4.2, agitation)
	breath = sin(presentation_time * breath_rate) * 0.5 + 0.5

	if flesh_material:
		flesh_material.set_shader_parameter('agitation', agitation)
		flesh_material.set_shader_parameter('breath', breath)

	drip.emitting = manifested and state != CrawlerState.DORMANT
	drip.amount_ratio = lerpf(drip.amount_ratio, lerpf(0.25, 1.0, agitation), minf(delta * 3.0, 1.0))


func _update_audio(tangent_speed: float) -> void:
	var crawling := tangent_speed > crawl_audio_min_speed and state != CrawlerState.POUNCING
	if crawling:
		crawl_audio.pitch_scale = clampf(0.7 + tangent_speed * 0.16, 0.7, 1.6)
		if not crawl_audio.playing:
			crawl_audio.play(randf_range(0.0, 1.5))
	elif crawl_audio.playing:
		crawl_audio.stop()

	# Audible breathing is the last warning before it is on top of you.
	var closest := INF
	for player: CharacterBody3D in _living_players():
		closest = minf(closest, global_position.distance_to(player.global_position))
	var should_breathe := closest < dread_radius * 0.45 and manifested
	if should_breathe and not breath_audio.playing:
		breath_audio.play()
	elif not should_breathe and breath_audio.playing:
		breath_audio.stop()


## The head is the only part that aims: it is blind, so it points its face at
## the sound like a dish, and holds there even after the sound stops.
func _update_head_tracking(delta: float) -> void:
	var blend := minf(delta * 6.0, 1.0)
	if not has_noise_fix:
		neck_pivot.rotation.y = lerp_angle(neck_pivot.rotation.y, 0.0, blend)
		return

	var local_target := to_local(last_noise_position)
	var yaw := atan2(-local_target.x, -local_target.z)
	neck_pivot.rotation.y = lerp_angle(
		neck_pivot.rotation.y,
		clampf(wrapf(yaw, -PI, PI), deg_to_rad(-95.0), deg_to_rad(95.0)),
		blend
	)
	var pitch := clampf(atan2(local_target.y, Vector2(local_target.x, local_target.z).length()), -1.1, 1.1)
	head_pivot.rotation.x = lerpf(head_pivot.rotation.x, deg_to_rad(18.0) + pitch, blend)


## The body GLB carries a single looping walk. Started once here rather than
## re-issued per frame, because AnimationPlayer.play() restarts a clip.
func _start_model_animation() -> void:
	if model_animation == null:
		return
	var clips := model_animation.get_animation_list()
	if clips.is_empty():
		return
	var clip := StringName(clips[0])
	model_animation.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	model_animation.play(clip)


func _apply_rest_pose() -> void:
	for index: int in limb_roots.size():
		_pose_limb(index, 0.0, 0.0)
	body_pivot.rotation = Vector3.ZERO
	neck_pivot.rotation = Vector3.ZERO
	head_pivot.rotation = Vector3(deg_to_rad(18.0), 0.0, 0.0)
	tail_pivot.rotation = Vector3.ZERO
	tail_tip_pivot.rotation = Vector3.ZERO
	jaw_open = 0.15
	_apply_jaw()


func _animate_crawl(delta: float, raw_speed_scale: float) -> void:
	# Capped because the gait is measured against the patrol crawl, and the omen
	# dash is more than ten times that - uncapped, the limbs blur into a solid.
	var speed_scale := clampf(raw_speed_scale, 0.12, 3.0)
	crawl_phase += delta * crawl_animation_speed * speed_scale

	# The two diagonal pairs alternate. limb_roots is ordered so index 0/1 are
	# one diagonal and 2/3 the other, which is why the offset is just index >= 2.
	for index: int in limb_roots.size():
		var phase := crawl_phase + (PI if index >= 2 else 0.0)
		_pose_limb(index, phase, speed_scale)

	var stride := sin(crawl_phase)
	var counter := sin(crawl_phase + PI)
	# The spine works side to side like something dragging itself, not up and
	# down like something walking.
	# The body's own legs are skinned now, so the gait reads off the clip's rate.
	# The spine/tail/jaw motion below still layers on top of it.
	if model_animation:
		model_animation.speed_scale = speed_scale
	body_pivot.rotation.y = stride * 0.14 * speed_scale
	body_pivot.rotation.z = counter * 0.09 * speed_scale
	body_pivot.position.y = absf(sin(crawl_phase * 2.0)) * 0.025 * speed_scale

	tail_pivot.rotation.y = -stride * 0.3 * speed_scale
	tail_pivot.rotation.x = deg_to_rad(-6.0) + counter * 0.08
	tail_tip_pivot.rotation.y = -counter * 0.42 * speed_scale

	head_pivot.rotation.z = sin(crawl_phase * 1.7) * 0.08
	jaw_open = lerpf(jaw_open, 0.2 + breath * 0.35 + agitation * 0.3, minf(delta * 5.0, 1.0))
	_apply_jaw()


## One limb of the four. `phase` runs the reach/plant cycle; `speed_scale` fades
## the whole motion out so a stationary crawler settles rather than treading.
func _pose_limb(index: int, phase: float, speed_scale: float) -> void:
	var limb := limb_roots[index]
	var lower := limb_lowers[index]
	var hand := limb_hands[index]
	var side := LIMB_SIDE_SIGNS[index]
	var front := LIMB_FRONT_SIGNS[index]

	var reach := sin(phase) * speed_scale
	# Only the recovery half of the cycle lifts the hand off the surface; the
	# other half is the power stroke and stays planted.
	var lift := maxf(sin(phase + PI * 0.5), 0.0) * speed_scale

	limb.rotation.z = deg_to_rad(side * (LIMB_UPPER_SPLAY + lift * 14.0))
	limb.rotation.x = deg_to_rad(LIMB_UPPER_PITCH * front + reach * 26.0)
	limb.rotation.y = deg_to_rad(-side * reach * 12.0)

	lower.rotation.z = deg_to_rad(side * (LIMB_LOWER_FOLD + lift * 22.0))
	lower.rotation.x = deg_to_rad(-reach * 20.0 - lift * 26.0)

	hand.rotation.x = deg_to_rad(LIMB_HAND_FLAT - lift * 34.0)
	hand.rotation.z = deg_to_rad(-side * 12.0)


## Windup and leap: everything folds in under the body, then the spine whips
## straight as it launches.
func _animate_coil(delta: float, progress: float) -> void:
	var blend := minf(delta * 12.0, 1.0)
	var coil := ease(clampf(progress, 0.0, 1.0), 0.6)
	for index: int in limb_roots.size():
		var limb := limb_roots[index]
		var lower := limb_lowers[index]
		var side := LIMB_SIDE_SIGNS[index]
		var front := LIMB_FRONT_SIGNS[index]
		limb.rotation.z = lerpf(limb.rotation.z, deg_to_rad(side * (LIMB_UPPER_SPLAY + 26.0)), blend)
		limb.rotation.x = lerpf(limb.rotation.x, deg_to_rad(front * 46.0), blend)
		lower.rotation.z = lerpf(lower.rotation.z, deg_to_rad(side * (LIMB_LOWER_FOLD + 34.0)), blend)

	body_pivot.rotation.x = lerpf(body_pivot.rotation.x, deg_to_rad(-14.0 * coil), blend)
	body_pivot.position.y = lerpf(body_pivot.position.y, -0.05 * (1.0 - coil), blend)
	head_pivot.rotation.x = lerpf(head_pivot.rotation.x, deg_to_rad(-32.0), blend)
	jaw_open = maxf(jaw_open, coil)
	_apply_jaw()


## Face down with its limbs still folded backwards, getting them under itself
## again. This is the visual tell for the window the player has to run.
func _animate_collapse(delta: float) -> void:
	var blend := minf(delta * 7.0, 1.0)
	for index: int in limb_roots.size():
		var limb := limb_roots[index]
		var lower := limb_lowers[index]
		var side := LIMB_SIDE_SIGNS[index]
		limb.rotation.z = lerpf(limb.rotation.z, deg_to_rad(side * 148.0), blend)
		limb.rotation.x = lerpf(limb.rotation.x, deg_to_rad(sin(presentation_time * 9.0) * 8.0), blend)
		lower.rotation.z = lerpf(lower.rotation.z, deg_to_rad(side * -46.0), blend)

	body_pivot.rotation.x = lerpf(body_pivot.rotation.x, deg_to_rad(4.0), blend)
	body_pivot.rotation.z = lerpf(body_pivot.rotation.z, sin(presentation_time * 6.0) * 0.05, blend)
	body_pivot.position.y = lerpf(body_pivot.position.y, -0.06, blend)
	head_pivot.rotation.x = lerpf(head_pivot.rotation.x, deg_to_rad(34.0), blend)
	jaw_open = lerpf(jaw_open, 0.85, blend)
	_apply_jaw()


func _apply_jaw() -> void:
	jaw_pivot.rotation.x = deg_to_rad(jaw_open * 42.0)
