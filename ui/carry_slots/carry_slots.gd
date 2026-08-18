extends MarginContainer

@export var player_path: NodePath
var carry_slots: CarrySlotsComponent

@onready var slot0_panel: PanelContainer = $HBoxContainer/Slot0Wrapper/Slot0
@onready var slot0_name: Label = $HBoxContainer/Slot0Wrapper/Slot0/VBoxContainer/ItemName
@onready var slot0_icon: TextureRect = $HBoxContainer/Slot0Wrapper/Slot0/VBoxContainer/ItemIcon

@onready var slot1_panel: PanelContainer = $HBoxContainer/Slot1Wrapper/Slot1
@onready var slot1_name: Label = $HBoxContainer/Slot1Wrapper/Slot1/VBoxContainer/ItemName
@onready var slot1_icon: TextureRect = $HBoxContainer/Slot1Wrapper/Slot1/VBoxContainer/ItemIcon

@export var active_scale: Vector2 = Vector2(1.0, 1.0)
@export var inactive_scale: Vector2 = Vector2(0.75, 0.75)

var style_selected: StyleBox
var style_normal: StyleBox

func _ready() -> void:
	style_selected = slot0_panel.get("theme_override_styles/panel")
	style_normal = slot1_panel.get("theme_override_styles/panel")
	
	# Set pivot offsets to center for scaling (minimum size is 80x80)
	slot0_panel.pivot_offset = Vector2(40, 40)
	slot1_panel.pivot_offset = Vector2(40, 40)
	
	if not player_path.is_empty():
		var player = get_node_or_null(player_path)
		if player:
			carry_slots = player.get_node_or_null("CarrySlotsComponent")
			if carry_slots:
				carry_slots.slots_changed.connect(_on_slots_changed)
				carry_slots.selected_slot_changed.connect(_on_selected_slot_changed)
				_full_update()

func _on_slots_changed() -> void:
	_full_update()

func _on_selected_slot_changed(_slot_index: int) -> void:
	update_inventory_slot_visuals()

func _full_update() -> void:
	if not carry_slots: return
	
	var item0 = carry_slots.get_slot_item(0)
	if item0:
		slot0_name.text = item0.display_name
		slot0_icon.texture = item0.icon
		slot0_icon.visible = item0.icon != null
	else:
		slot0_name.text = "EMPTY"
		slot0_icon.texture = null
		slot0_icon.visible = false
		
	var item1 = carry_slots.get_slot_item(1)
	if item1:
		slot1_name.text = item1.display_name
		slot1_icon.texture = item1.icon
		slot1_icon.visible = item1.icon != null
	else:
		slot1_name.text = "EMPTY"
		slot1_icon.texture = null
		slot1_icon.visible = false
		
	update_inventory_slot_visuals()

func update_inventory_slot_visuals() -> void:
	if not carry_slots: return
	var selected = carry_slots.get_selected_slot()
	
	if selected == 0:
		slot0_panel.add_theme_stylebox_override("panel", style_selected)
		slot1_panel.add_theme_stylebox_override("panel", style_normal)
		slot0_panel.scale = active_scale
		slot1_panel.scale = inactive_scale
	else:
		slot0_panel.add_theme_stylebox_override("panel", style_normal)
		slot1_panel.add_theme_stylebox_override("panel", style_selected)
		slot0_panel.scale = inactive_scale
		slot1_panel.scale = active_scale
