class_name BreakerMinigame
extends CanvasLayer

## Timing-wheel repair fought at the main breaker after a full-house blackout.
##
## One repair is a countdown, not a score: `repair_duration` seconds of holding
## the wheel. A red needle sweeps a dial and the player presses SPACE while it
## covers the white mark. Every press flips the sweep direction, every resolved
## attempt makes the needle faster (up to `needle_max_speed`), and every miss
## adds `fail_penalty` seconds back onto the repair.
##
## Like ToiletMinigame this is owned per-object (a child of MainBreaker) and is
## started through Player.start_breaker_minigame(). It owns no power logic: the
## breaker listens for `repair_completed` and does the restore itself, exactly
## as it did when the interaction was instantaneous.

signal repair_completed
signal session_ended(success: bool)

@export_category("Repair")
## Seconds of clean play one repair costs. Progress survives a cancel, so
## leaving the breaker and coming back resumes rather than restarts.
@export var repair_duration: float = 10.0
## Added to the remaining repair time by each miss.
@export var fail_penalty: float = 1.5
## Hard ceiling on one repair, in both directions: failures stop adding time
## once the countdown reaches it, and this many seconds of actual play always
## finishes the repair whatever the countdown says. A bad run is bounded - it
## never becomes an endless wheel while the house stays dark.
@export var max_repair_seconds: float = 20.0

@export_category("Needle")
## Sweep speed at the start of a repair, in degrees per second.
@export var needle_start_speed: float = 150.0
## Added to the sweep speed by every resolved attempt, hit or miss - the wheel
## escalates over a session rather than rewarding or punishing accuracy twice.
@export var needle_speed_gain: float = 24.0
## The ceiling that keeps a long repair hard instead of impossible.
@export var needle_max_speed: float = 520.0
## Half-width of the white mark as it is drawn, in degrees.
@export var target_half_width: float = 16.0
## Extra degrees either side of the drawn mark that still count as a hit. The
## mark is what the player aims at; this is invisible slack so a press a shade
## early or late still lands. It also sets where an ignored mark finally counts
## as missed - the needle has to clear this window, not just the mark's centre.
@export var hit_forgiveness: float = 7.0
## Reaction time the next mark is placed at, in seconds of travel at the
## current speed. Expressed as time, not degrees, so a fast needle still gets
## a fair run-up instead of the mark landing under it immediately.
@export var target_lead_min_time: float = 0.45
@export var target_lead_max_time: float = 1.1
## Bounds on that lead once converted to degrees, so a slow needle is not
## given a trivially short arc and a fast one does not lap the dial.
@export var target_lead_min_degrees: float = 60.0
@export var target_lead_max_degrees: float = 330.0

@export_category("Presentation")
@export var dial_radius: float = 132.0
@export var feedback_hold: float = 0.55

@onready var dial: Control = $Root/Dial
@onready var timer_label: Label = $Root/Timer
@onready var feedback_label: Label = $Root/Feedback
@onready var hint_label: Label = $Root/Hint

var player: Node3D
var _breaker: Node
var _running: bool = false
## Kept between sessions: a cancelled repair (and every penalty earned in it)
## is still owed the next time the cabinet is opened.
var _remaining: float = -1.0
var _needle_angle: float = 0.0
var _target_angle: float = 90.0
var _direction: float = 1.0
var _speed: float = 0.0
var _hits: int = 0
var _misses: int = 0
## Seconds actually spent on the wheel, carried across a cancel like _remaining
## is. Once it reaches max_repair_seconds the repair completes regardless.
var _elapsed: float = 0.0
## What the countdown read when this session opened, so the progress ring fills
## across the session and visibly jumps back when a miss adds time.
var _countdown_span: float = 1.0
var _feedback_timer: float = 0.0
var _hit_flash: float = 0.0
## The E press that opened the cabinet is still travelling through the input
## tree; ignore it until released so it cannot instantly cancel the session.
var _wait_for_interact_release: bool = false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	dial.draw.connect(_draw_dial)
	visible = false
	set_process(false)


## Called by Player.start_breaker_minigame(), mirroring ToiletMinigame.start().
func start(p_player: Node3D, breaker: Node) -> bool:
	if _running or not is_instance_valid(breaker) or not is_instance_valid(p_player):
		return false
	player = p_player
	_breaker = breaker
	_running = true
	_wait_for_interact_release = true
	if _remaining <= 0.0:
		_remaining = maxf(repair_duration, 0.1)
		_elapsed = 0.0
	_countdown_span = maxf(_effective_remaining(), 0.1)
	_needle_angle = _rng.randf_range(0.0, 360.0)
	_direction = 1.0 if _rng.randf() < 0.5 else -1.0
	_speed = maxf(needle_start_speed, 1.0)
	_hits = 0
	_misses = 0
	_feedback_timer = 0.0
	_hit_flash = 0.0
	_place_target()

	if player.has_method("set_physics_process"):
		player.set_physics_process(false)
	if player.has_method("set_held_item_visibility"):
		player.set_held_item_visibility(false)

	feedback_label.text = ""
	_update_labels()
	visible = true
	set_process(true)
	return true


func is_running() -> bool:
	return _running


## Seconds of repair still owed, used by MainBreaker for its own prompt text.
func get_repair_remaining() -> float:
	return maxf(_effective_remaining(), 0.0) if _remaining > 0.0 else maxf(repair_duration, 0.1)


## Called by MainBreaker once power is actually back, so the next outage starts
## a full-length repair instead of resuming a finished one.
func reset_progress() -> void:
	_remaining = -1.0
	_elapsed = 0.0


func cancel() -> void:
	if not _running:
		return
	_end_session(false)


func _process(delta: float) -> void:
	if not _running:
		return
	# A player who dies mid-repair must not stay pinned to the wheel with their
	# physics process switched off.
	if not is_instance_valid(player) or not is_instance_valid(_breaker) \
		or ("is_alive" in player and not player.is_alive):
		_end_session(false)
		return

	_feedback_timer = maxf(_feedback_timer - delta, 0.0)
	if _feedback_timer <= 0.0:
		feedback_label.text = ""
	_hit_flash = maxf(_hit_flash - delta * 3.0, 0.0)

	var step: float = _speed * _direction * delta
	# Resolve a mark the needle is about to sweep past before moving onto it,
	# so an ignored window is a miss rather than a free pass.
	if _sweep_passes_target(_needle_angle, step):
		_resolve_attempt(false, "TRƯỢT NHỊP! +%.1fs" % fail_penalty)
	_needle_angle = fposmod(_needle_angle + step, 360.0)

	_remaining -= delta
	_elapsed += delta
	# Two ways to finish: serve the countdown, or simply have spent
	# max_repair_seconds on the wheel. The second is the floor under a bad run.
	if _effective_remaining() <= 0.0:
		_remaining = 0.0
		_update_labels()
		dial.queue_redraw()
		repair_completed.emit()
		_end_session(true)
		return

	_update_labels()
	dial.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not _running:
		return
	if event.is_action_released("interact"):
		_wait_for_interact_release = false
		return
	if event.is_action_pressed("interact"):
		if not _wait_for_interact_release:
			cancel()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("jump") and not event.is_echo():
		press()
		get_viewport().set_input_as_handled()


## One SPACE press. Every press flips the sweep, whether or not it landed -
## reversing is the control, not the reward. Public so the smoke test can
## drive an attempt without synthesising input events.
func press() -> void:
	if not _running:
		return
	var hit := _needle_is_on_target()
	_direction = -_direction
	if hit:
		_resolve_attempt(true, "CHUẨN!")
	else:
		_resolve_attempt(false, "TRƯỢT! +%.1fs" % fail_penalty)


func _resolve_attempt(hit: bool, message: String) -> void:
	if hit:
		_hits += 1
		_hit_flash = 1.0
	else:
		_misses += 1
		_remaining = minf(_remaining + fail_penalty, maxf(max_repair_seconds, repair_duration))
	_speed = minf(_speed + needle_speed_gain, maxf(needle_max_speed, needle_start_speed))
	_place_target()
	feedback_label.text = message
	feedback_label.add_theme_color_override(
		"font_color", Color(0.55, 0.95, 0.6) if hit else Color(0.98, 0.45, 0.32)
	)
	_feedback_timer = feedback_hold


## Seconds of repair still owed, taking both limits into account: the countdown
## itself, and how much of max_repair_seconds is left to spend.
func _effective_remaining() -> float:
	return minf(_remaining, maxf(max_repair_seconds, repair_duration) - _elapsed)


func _hit_window() -> float:
	return target_half_width + maxf(hit_forgiveness, 0.0)


func _needle_is_on_target() -> bool:
	return absf(_signed_delta(_target_angle, _needle_angle)) <= _hit_window()


## Places the next mark ahead of the needle along the current sweep direction,
## far enough away to still be reactable at the current speed.
func _place_target() -> void:
	var lead: float = _speed * _rng.randf_range(target_lead_min_time, target_lead_max_time)
	lead = clampf(lead, target_lead_min_degrees, target_lead_max_degrees)
	_target_angle = fposmod(_needle_angle + _direction * lead, 360.0)


## True when sweeping `step` degrees from `from` carries the needle out the far
## side of the live mark's hit window. Measured at the window's exit edge, not
## the mark's centre, so the forgiveness slack is real on the late side too - a
## press just after the mark still lands rather than being pre-empted by a miss.
func _sweep_passes_target(from: float, step: float) -> bool:
	if is_zero_approx(step):
		return false
	var exit_angle: float = fposmod(_target_angle + signf(step) * _hit_window(), 360.0)
	var ahead: float = fposmod((exit_angle - from) * signf(step), 360.0)
	return ahead <= absf(step)


## Shortest signed distance from `b` to `a`, in degrees, within (-180, 180].
func _signed_delta(a: float, b: float) -> float:
	return fposmod(a - b + 180.0, 360.0) - 180.0


func _update_labels() -> void:
	timer_label.text = "CÒN LẠI %.1fs" % maxf(_effective_remaining(), 0.0)
	hint_label.text = "SPACE khi kim đỏ chạm vạch trắng  •  E: rời cầu dao  •  Trượt +%.1fs (tối đa %.0fs)" % [fail_penalty, max_repair_seconds]


func _end_session(success: bool) -> void:
	_running = false
	set_process(false)
	visible = false
	_wait_for_interact_release = false
	if is_instance_valid(player):
		if player.has_method("set_physics_process"):
			player.set_physics_process(true)
		if player.has_method("set_held_item_visibility"):
			player.set_held_item_visibility(true)
	player = null
	_breaker = null
	session_ended.emit(success)


func _draw_dial() -> void:
	var centre := dial.size * 0.5
	var radius := dial_radius

	dial.draw_circle(centre, radius + 16.0, Color(0.02, 0.02, 0.03, 0.85))
	dial.draw_arc(centre, radius, 0.0, TAU, 96, Color(0.26, 0.28, 0.32), 4.0, true)

	# Repair progress: the outer ring fills as the countdown drains, so a run
	# of misses is visibly pushing the finish line back.
	var progress := clampf(1.0 - _effective_remaining() / _countdown_span, 0.0, 1.0)
	if progress > 0.0:
		dial.draw_arc(
			centre, radius + 12.0, _to_screen(0.0), _to_screen(360.0 * progress),
			72, Color(0.35, 0.85, 0.95, 0.9), 5.0, true
		)

	# The white mark the needle has to be inside when SPACE is pressed.
	dial.draw_arc(
		centre, radius,
		_to_screen(_target_angle - target_half_width),
		_to_screen(_target_angle + target_half_width),
		16, Color(1.0, 1.0, 1.0, 0.95), 13.0, true
	)

	var needle_dir := Vector2(
		cos(_to_screen(_needle_angle)), sin(_to_screen(_needle_angle))
	)
	var needle_colour := Color(1.0, 0.24, 0.14).lerp(Color(1.0, 0.95, 0.6), _hit_flash)
	dial.draw_line(
		centre + needle_dir * 34.0, centre + needle_dir * (radius + 6.0), needle_colour, 5.0, true
	)
	dial.draw_circle(centre, 9.0, needle_colour)


## Dial angles are degrees clockwise from the top; Godot's draw_* calls take
## radians measured from the +X axis.
func _to_screen(degrees: float) -> float:
	return deg_to_rad(degrees - 90.0)
