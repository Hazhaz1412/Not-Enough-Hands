class_name DoorGhost
extends Node3D

## The Midnight Grin biped standing outside an attacked defense door: the
## visual and hit-target half of the door encounter, and nothing else.
##
## It has no senses, no navigation and no attack of its own - every call here
## comes from minigames/door_ghost_minigame.gd, the same one-way arrangement
## ToiletMinigame already has with minigames/toilet_ghost.gd.
## ghosts/hunter_ghost.gd keeps the Huntsman's real behaviour and does not know
## this scene exists, so the encounter can never change how the Huntsman plays.
##
## ## The asset
##
## The body is ghosts/ghost_visual.tscn, which instances the Midnight Grin biped
## - the same one file the Huntsman wears, no copy of it. That wrapper owns the
## scale, the facing, the material override and the clip library; this script
## only says which pose the encounter is in.
##
## The clips named below are the baked ones GhostVisual loads from
## ghosts/ghost_animations.res; see that class and
## tools/build_ghost_animations.gd. They are rotation-only, which is why
## `_place_ghost()` in the encounter stays the only thing that moves this body.


enum Pose { IDLE, APPROACH, REACT, LUNGE }

## What each beat asks the body to play, matched to what the beat actually is:
## APPROACH is the slow creep across the threat window, so it walks rather than
## runs, and REACT is the recoil that turns into the retreat, so that one runs.
const POSE_CLIPS := {
	Pose.IDLE: &"Idle",
	Pose.APPROACH: &"Walk",
	Pose.REACT: &"Run",
	Pose.LUNGE: &"Skill 3",
}
## Poses that hold for as long as the encounter stays in them, so their clips
## are the ones that loop. The other two are one-shots that fall back to IDLE.
const HELD_POSES := [Pose.IDLE, Pose.APPROACH]

## Height above the ghost's feet that the flashlight is tested against, and that
## the occlusion ray is aimed at. Roughly sternum height on the 1.70 m model.
@export var chest_height: float = 1.15
## Playback speed at rest and at full approach pressure, applied to whichever
## clip is running. There are no separate "agitated" clips, so the escalation is
## carried by the rate of the same unsteady walk rather than by a new one.
@export var calm_speed_scale: float = 0.85
@export var agitated_speed_scale: float = 1.45
var _pose: Pose = Pose.IDLE

@onready var model: GhostVisual = $Model
@onready var hit_area: Area3D = $HitArea
@onready var _whisper: AudioStreamPlayer3D = $WhisperAudio


func _ready() -> void:
	visible = false
	if _whisper and _whisper.stream and "loop" in _whisper.stream:
		_whisper.stream.set("loop", true)


## Places the ghost's feet at `at` and shows it standing.
func appear(at: Vector3) -> void:
	global_position = at
	visible = true
	# Started directly rather than through set_pose(), which ignores a repeat:
	# `_pose` is already IDLE both on the first encounter and after a vanish, so
	# set_pose() would do nothing and the body would show its bare rest pose.
	_pose = Pose.IDLE
	if model:
		model.play_clip(POSE_CLIPS[Pose.IDLE], true)
	sync_collider()


## Pushes the hit volume's transform to the physics server now instead of on
## the next physics tick. The encounter moves the ghost and tests the beam
## against it inside the same _process() frame, so without this the collider
## the ray sees is one tick behind the model the player sees - which is exactly
## wrong on the frame the ghost jumps to a new position.
func sync_collider() -> void:
	if hit_area and hit_area.is_inside_tree():
		PhysicsServer3D.area_set_transform(hit_area.get_rid(), hit_area.global_transform)


func vanish() -> void:
	visible = false
	stop_whisper()
	if model:
		model.stop_clip()


## Its own whispering, positional so it doubles as the search cue: which
## shoulder the sound is over is a real hint about where it is standing.
func start_whisper(pitch: float = 1.0) -> void:
	if _whisper:
		_whisper.pitch_scale = pitch
		if not _whisper.playing:
			_whisper.play()


func set_whisper_pitch(pitch: float) -> void:
	if _whisper:
		_whisper.pitch_scale = pitch


func stop_whisper() -> void:
	if _whisper:
		_whisper.stop()


func set_audio_bus(bus: StringName) -> void:
	if _whisper:
		_whisper.bus = bus


## LUNGE is the one-shot: the final threat plays it once and the body falls
## back to idle, rather than looping an attack at the player.
func set_pose(pose: Pose) -> void:
	if pose == _pose:
		return
	_pose = pose
	if model:
		model.play_clip(POSE_CLIPS[pose], HELD_POSES.has(pose))


func get_pose() -> Pose:
	return _pose


## Turns to look at `point`, upright - the encounter only ever wants it facing
## the player, never leaning off its feet.
func face_point(point: Vector3) -> void:
	var to_target := point - global_position
	to_target.y = 0.0
	if to_target.length_squared() > 0.0001:
		global_basis = Basis.looking_at(to_target.normalized(), Vector3.UP)


## The point the flashlight has to actually reach for a hit to count.
func get_chest_point() -> Vector3:
	return global_position + Vector3.UP * chest_height


## True when `collider` is this ghost's own hit volume - what tells a ray that
## reached the ghost apart from one that stopped on a wall.
func owns_collider(collider: Object) -> bool:
	return collider != null and collider == hit_area


## Drives how fast it moves rather than what it does, because the library has no
## agitated variant of the walk.
func set_agitation(value: float) -> void:
	if model:
		var pressure := clampf(value, 0.0, 1.0)
		model.agitation = pressure
		model.locomotion_speed = lerpf(0.4, 1.3, pressure) if _pose == Pose.APPROACH else 0.0
		model.set_clip_speed(lerpf(calm_speed_scale, agitated_speed_scale, pressure))
		model.advance(get_process_delta_time())
