extends VBoxContainer

@export var player_path: NodePath
var player: Node3D
var bladder: BladderComponent
var tween: Tween

@onready var label: RichTextLabel = $Label
@onready var warning_label: RichTextLabel = $WarningLabel
@onready var progress_bar: ProgressBar = $ProgressBar

const COLOR_NORMAL = "#b2cccc"
const COLOR_WARNING = "#ffaa00"
const COLOR_CRITICAL = "#ff5500"
const COLOR_FULL = "#ff0000"
var current_color_hex = COLOR_NORMAL

func _ready() -> void:
	if not player_path.is_empty():
		player = get_node(player_path)
		if player:
			bladder = player.get_node_or_null("BladderComponent")
			if bladder:
				bladder.value_changed.connect(_on_value_changed)
				bladder.threshold_changed.connect(_on_threshold_changed)
				bladder.max_reached.connect(_on_max_reached)
				
				# Initial state
				progress_bar.max_value = bladder.max_value
				progress_bar.value = bladder.get_value()
				_apply_threshold_state(bladder.get_threshold_state())
				_update_label(bladder.get_value(), bladder.max_value)

func _on_value_changed(val: float, max_val: float) -> void:
	if tween and tween.is_running():
		tween.kill()
		
	tween = create_tween().set_trans(Tween.TRANS_LINEAR)
	tween.tween_property(progress_bar, "value", val, 0.1)
	
	_update_label(val, max_val)

func _on_threshold_changed(_old_state, new_state) -> void:
	_apply_threshold_state(new_state)

func _on_max_reached() -> void:
	pass

func _apply_threshold_state(state) -> void:
	if state == BladderComponent.ThresholdState.NORMAL:
		current_color_hex = COLOR_NORMAL
		warning_label.text = ""
	elif state == BladderComponent.ThresholdState.WARNING:
		current_color_hex = COLOR_WARNING
		warning_label.text = "[center][color=" + current_color_hex + "]WARNING[/color][/center]"
	elif state == BladderComponent.ThresholdState.CRITICAL:
		current_color_hex = COLOR_CRITICAL
		warning_label.text = "[center][b][color=" + current_color_hex + "]CRITICAL[/color][/b][/center]"
	elif state == BladderComponent.ThresholdState.FULL:
		current_color_hex = COLOR_FULL
		warning_label.text = "[center][b][color=" + current_color_hex + "]FULL![/color][/b][/center]"
		
	if bladder:
		_update_label(bladder.get_value(), bladder.max_value)
		
	var fill_style = StyleBoxFlat.new()
	fill_style.bg_color = Color(current_color_hex)
	progress_bar.add_theme_stylebox_override("fill", fill_style)
	
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.1, 0.1, 0.1, 0.6)
	progress_bar.add_theme_stylebox_override("background", bg_style)

func _update_label(val: float, max_val: float) -> void:
	var percentage = 0.0
	if max_val > 0:
		percentage = (val / max_val) * 100.0
		
	var text = "[center][b][color=" + current_color_hex + "]BLADDER: " + str(int(percentage)) + "%[/color][/b][/center]"
	label.text = text
