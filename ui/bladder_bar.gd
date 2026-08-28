extends ProgressBar

## Bottom-right bladder meter, next to ui/stamina_bar.gd. Unlike that bar,
## this one smooths its displayed value toward the authoritative one instead
## of copying it every frame, and reacts to PlayerBladder's own threshold
## state (read from its exported thresholds, not recomputed independently)
## for its warning/full visual - it never writes back to the bladder.

@export var player_path: NodePath
@export var display_smoothing: float = 6.0

var _bladder: PlayerBladder
var _displayed_value: float = 0.0
var _pulse_time: float = 0.0
var _is_warning: bool = false
var _is_full: bool = false

var _style_normal_fill: StyleBoxFlat
var _style_warning_fill: StyleBoxFlat
var _style_full_fill: StyleBoxFlat


func _ready() -> void:
	_style_normal_fill = get_theme_stylebox("fill").duplicate()
	_style_warning_fill = _style_normal_fill.duplicate()
	_style_warning_fill.bg_color = Color(0.82, 0.66, 0.24, 0.96)
	_style_full_fill = _style_normal_fill.duplicate()
	_style_full_fill.bg_color = Color(0.85, 0.28, 0.24, 0.98)
	# Player is our ancestor, so its _ready() (and the @onready `bladder` it
	# assigns) runs *after* ours - defer the bind, same fix as equipment_ui.gd.
	call_deferred("_bind_to_player")


func _bind_to_player() -> void:
	var player := get_node_or_null(player_path)
	if not player or not ("bladder" in player):
		return
	_bladder = player.bladder
	if not _bladder:
		return
	max_value = _bladder.bladder_max
	_displayed_value = _bladder.get_bladder()
	value = _displayed_value
	_bladder.bladder_changed.connect(_on_bladder_changed)
	_update_visual_state(_bladder.get_bladder())


func _process(delta: float) -> void:
	if not _bladder:
		return
	var blend := minf(display_smoothing * delta, 1.0)
	_displayed_value = lerpf(_displayed_value, _bladder.get_bladder(), blend)
	value = _displayed_value
	_update_pulse(delta)


func _on_bladder_changed(current: float, max_val: float) -> void:
	max_value = max_val
	_update_visual_state(current)


func _update_visual_state(current: float) -> void:
	_is_warning = current >= _bladder.bladder_warning_threshold
	_is_full = current >= _bladder.bladder_full_threshold
	if _is_full:
		add_theme_stylebox_override("fill", _style_full_fill)
	elif _is_warning:
		add_theme_stylebox_override("fill", _style_warning_fill)
	else:
		add_theme_stylebox_override("fill", _style_normal_fill)


## A quiet brightness pulse while warning/full, nothing while normal - the
## meter should stay visually silent until there's something to say.
func _update_pulse(delta: float) -> void:
	if not (_is_warning or _is_full):
		modulate = Color.WHITE
		return
	_pulse_time += delta
	var speed := 4.0 if _is_full else 2.2
	var strength := 0.18 if _is_full else 0.1
	var pulse := 1.0 + sin(_pulse_time * speed) * strength
	modulate = Color(pulse, pulse, pulse, 1.0)
