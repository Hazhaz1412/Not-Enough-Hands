extends Control

## The one settings screen, shown from the main menu and from the in-game pause
## menu. It owns no option of its own: every row reads and writes `GameSettings`,
## which is what applies and persists the value, so a setting changed mid-run
## takes effect without this scene knowing what it drives.

signal closed()

const SENSITIVITY_DISPLAY_SCALE := 1000.0

@onready var tabs: TabContainer = %Tabs
@onready var display_rows: VBoxContainer = %DisplayRows
@onready var audio_rows: VBoxContainer = %AudioRows
@onready var control_rows: VBoxContainer = %ControlRows
@onready var game_rows: VBoxContainer = %GameRows
@onready var status_label: Label = %StatusLabel
@onready var reset_button: Button = %ResetButton
@onready var close_button: Button = %CloseButton

var _awaiting_action: StringName = &""
var _awaiting_button: Button


func _ready() -> void:
	# The pause menu pauses the tree in single player; a settings screen that
	# stopped processing there would be drawn but dead.
	process_mode = Node.PROCESS_MODE_ALWAYS
	tabs.set_tab_title(0, "HÌNH ẢNH")
	tabs.set_tab_title(1, "ÂM THANH")
	tabs.set_tab_title(2, "ĐIỀU KHIỂN")
	tabs.set_tab_title(3, "TRÒ CHƠI")
	reset_button.pressed.connect(_on_reset_pressed)
	close_button.pressed.connect(_on_close_pressed)
	GameSettings.binds_changed.connect(_refresh_bind_labels)
	_rebuild()


func open() -> void:
	visible = true
	_rebuild()
	close_button.grab_focus()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if _awaiting_action == &"":
		if event.is_action_pressed("ui_cancel"):
			get_viewport().set_input_as_handled()
			_on_close_pressed()
		return

	var key_event := event as InputEventKey
	if key_event and key_event.pressed and not key_event.echo:
		get_viewport().set_input_as_handled()
		if key_event.keycode == KEY_ESCAPE:
			_cancel_capture("Đã huỷ đổi phím.")
		else:
			_finish_capture(key_event)
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event and mouse_event.pressed:
		get_viewport().set_input_as_handled()
		_finish_capture(mouse_event)


func _rebuild() -> void:
	for rows: VBoxContainer in [display_rows, audio_rows, control_rows, game_rows]:
		for child: Node in rows.get_children():
			rows.remove_child(child)
			child.queue_free()
	_cancel_capture("")
	_build_display_rows()
	_build_audio_rows()
	_build_control_rows()
	_build_game_rows()


func _build_display_rows() -> void:
	_add_choice(
		display_rows,
		"Chế độ cửa sổ",
		"display/window_mode",
		["Cửa sổ", "Toàn màn hình", "Toàn màn hình độc quyền"],
		[
			GameSettings.WINDOW_MODE_WINDOWED,
			GameSettings.WINDOW_MODE_FULLSCREEN,
			GameSettings.WINDOW_MODE_EXCLUSIVE,
		]
	)
	_add_toggle(display_rows, "Đồng bộ dọc (VSync)", "display/vsync")
	_add_choice(
		display_rows,
		"Giới hạn FPS",
		"display/max_fps",
		["Không giới hạn", "60", "120", "144", "240"],
		[0, 60, 120, 144, 240]
	)
	_add_slider(
		display_rows,
		"Tỉ lệ dựng hình 3D",
		"display/render_scale",
		0.5,
		1.0,
		0.05,
		func(value: float) -> String: return "%d%%" % roundi(value * 100.0)
	)
	_add_note(
		display_rows,
		"Hạ tỉ lệ dựng hình giúp máy yếu chạy mượt hơn; giao diện vẫn nét."
	)


func _build_audio_rows() -> void:
	_add_slider(
		audio_rows,
		"Âm lượng tổng",
		"audio/master_volume",
		0.0,
		1.0,
		0.01,
		func(value: float) -> String: return "%d%%" % roundi(value * 100.0)
	)
	_add_toggle(audio_rows, "Tắt tiếng", "audio/muted")
	_add_note(
		audio_rows,
		"Trò chơi này nghe là chính: con Bò Sát mù hoàn toàn và chỉ săn theo tiếng động."
	)


func _build_control_rows() -> void:
	_add_slider(
		control_rows,
		"Độ nhạy chuột",
		"controls/mouse_sensitivity",
		0.0005,
		0.006,
		0.0001,
		func(value: float) -> String:
			return "%.1f" % (value * SENSITIVITY_DISPLAY_SCALE)
	)
	_add_toggle(control_rows, "Đảo trục dọc", "controls/invert_look_y")
	_add_note(control_rows, "Bấm vào một phím tắt rồi nhấn phím mới. ESC để huỷ.")
	for action: StringName in GameSettings.REBINDABLE_ACTIONS:
		if not InputMap.has_action(action):
			continue
		_add_bind_row(action)


func _build_game_rows() -> void:
	_add_slider(
		game_rows,
		"Góc nhìn (FOV)",
		"gameplay/field_of_view",
		60.0,
		110.0,
		1.0,
		func(value: float) -> String: return "%d°" % roundi(value)
	)
	_add_slider(
		game_rows,
		"Lắc đầu khi đi",
		"gameplay/head_bob",
		0.0,
		1.5,
		0.05,
		func(value: float) -> String: return "%d%%" % roundi(value * 100.0)
	)
	_add_name_row()
	_add_note(
		game_rows,
		"Tên hiển thị dùng cho phòng chơi mạng và bảng tên trên đầu nhân vật."
	)


func _add_row(parent: VBoxContainer, label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.custom_minimum_size = Vector2(240, 34)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	parent.add_child(row)
	return row


func _add_note(parent: VBoxContainer, text: String) -> void:
	var note := Label.new()
	note.text = text
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", Color(0.42, 0.55, 0.57))
	note.custom_minimum_size = Vector2(420, 0)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(note)


func _add_toggle(parent: VBoxContainer, label_text: String, key: String) -> void:
	var row := _add_row(parent, label_text)
	var toggle := CheckButton.new()
	toggle.button_pressed = GameSettings.get_flag(key)
	toggle.toggled.connect(func(pressed: bool) -> void: GameSettings.set_setting(key, pressed))
	row.add_child(toggle)


func _add_choice(
	parent: VBoxContainer,
	label_text: String,
	key: String,
	labels: Array,
	values: Array
) -> void:
	var row := _add_row(parent, label_text)
	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(260, 34)
	for index: int in labels.size():
		option.add_item(str(labels[index]), index)
	var current: Variant = GameSettings.get_setting(key)
	option.selected = maxi(values.find(current), 0)
	option.item_selected.connect(
		func(index: int) -> void: GameSettings.set_setting(key, values[index])
	)
	row.add_child(option)


func _add_slider(
	parent: VBoxContainer,
	label_text: String,
	key: String,
	minimum: float,
	maximum: float,
	step: float,
	formatter: Callable
) -> void:
	var row := _add_row(parent, label_text)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = GameSettings.get_number(key)
	slider.custom_minimum_size = Vector2(200, 34)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(64, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.text = formatter.call(slider.value)
	slider.value_changed.connect(
		func(value: float) -> void:
			value_label.text = formatter.call(value)
			GameSettings.set_setting(key, value)
	)
	row.add_child(slider)
	row.add_child(value_label)


func _add_name_row() -> void:
	var row := _add_row(game_rows, "Tên hiển thị")
	var edit := LineEdit.new()
	edit.max_length = 24
	edit.custom_minimum_size = Vector2(260, 34)
	edit.text = str(GameSettings.get_setting("player/name"))
	edit.text_changed.connect(
		func(value: String) -> void:
			var cleaned := value.strip_edges()
			GameSettings.set_setting("player/name", cleaned if not cleaned.is_empty() else "Player")
	)
	row.add_child(edit)


func _add_bind_row(action: StringName) -> void:
	var row := _add_row(control_rows, str(GameSettings.ACTION_LABELS.get(action, action)))
	var button := Button.new()
	button.custom_minimum_size = Vector2(260, 34)
	button.text = GameSettings.get_bind_text(action)
	button.set_meta(&"action", action)
	button.pressed.connect(_begin_capture.bind(action, button))
	row.add_child(button)


func _begin_capture(action: StringName, button: Button) -> void:
	_cancel_capture("")
	_awaiting_action = action
	_awaiting_button = button
	button.text = "… nhấn phím mới"
	status_label.text = "Đang chờ phím cho \"%s\". ESC để huỷ." % str(
		GameSettings.ACTION_LABELS.get(action, action)
	)


func _finish_capture(event: InputEvent) -> void:
	var action := _awaiting_action
	if not GameSettings.set_bind(action, event):
		_cancel_capture("Phím này không dùng được.")
		return
	_awaiting_action = &""
	_awaiting_button = null
	_refresh_bind_labels()
	status_label.text = "Đã đổi \"%s\" thành %s." % [
		str(GameSettings.ACTION_LABELS.get(action, action)),
		GameSettings.get_bind_text(action),
	]


func _cancel_capture(message: String) -> void:
	if _awaiting_button and is_instance_valid(_awaiting_button):
		var action: StringName = _awaiting_button.get_meta(&"action", &"")
		_awaiting_button.text = GameSettings.get_bind_text(action)
	_awaiting_action = &""
	_awaiting_button = null
	if not message.is_empty():
		status_label.text = message


func _refresh_bind_labels() -> void:
	for row: Node in control_rows.get_children():
		for child: Node in row.get_children():
			var button := child as Button
			if button and button.has_meta(&"action"):
				button.text = GameSettings.get_bind_text(button.get_meta(&"action"))


func _on_reset_pressed() -> void:
	GameSettings.reset_to_defaults()
	_rebuild()
	status_label.text = "Đã khôi phục toàn bộ cài đặt mặc định."


func _on_close_pressed() -> void:
	_cancel_capture("")
	visible = false
	closed.emit()
