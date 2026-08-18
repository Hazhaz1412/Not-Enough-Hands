extends CharacterBody3D

@export var walk_speed: float = 5.0
@export var crouch_speed: float = 2.5
@export var jump_velocity: float = 4.5
@export var crouch_height: float = 1.0
@export var standing_height: float = 2.0
@export var crouch_camera_height: float = -0.2
@export var standing_camera_height: float = 0.8
@export var crouch_transition_speed: float = 10.0

var is_crouching: bool = false
@export var max_stamina: float = 100.0

var yaw_clamp_active: bool = false
var yaw_clamp_min: float = 0.0
var yaw_clamp_max: float = 0.0
var accumulated_yaw: float = 0.0
var pitch_clamp_min: float = -PI/2
var pitch_clamp_max: float = PI/2
@export var sprint_stamina_drain: float = 20.0
@export var stamina_regen_idle: float = 20.0
@export var stamina_regen_moving: float = 5.0

signal interact_target_changed(interactable: Interactable3D)
var current_interactable: Interactable3D = null

var current_stamina: float = max_stamina
@export var max_health: float = 100.0
var current_health: float = max_health

signal health_changed(current: float, max: float)

@export var mouse_sensitivity: float = 0.002
@export var max_interaction_range: float = 10.0

@onready var camera_pivot: Node3D = $CameraPivot
@onready var interact_ray: RayCast3D = $CameraPivot/Camera3D/InteractRay
@onready var first_person_holder: Node3D = $CameraPivot/Camera3D/FirstPersonItemHolder
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var bladder: BladderComponent = $BladderComponent
@onready var carry_slots: CarrySlotsComponent = $CarrySlotsComponent

var current_held_node: Node3D = null
var is_held_item_hidden: bool = false

func set_held_item_visibility(visible: bool) -> void:
	is_held_item_hidden = not visible
	if current_held_node:
		current_held_node.visible = visible

# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready() -> void:
	current_stamina = max_stamina
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if interact_ray:
		interact_ray.target_position = Vector3(0, 0, -max_interaction_range)
		
	if carry_slots:
		carry_slots.selected_slot_changed.connect(_on_selected_slot_changed)
		carry_slots.slots_changed.connect(_update_held_item)
		# Delay first update slightly so ready calls finish
		call_deferred("_update_held_item")

func _on_selected_slot_changed(_idx: int) -> void:
	_update_held_item()

func _update_held_item() -> void:
	if current_held_node:
		current_held_node.queue_free()
		current_held_node = null
		
	if not carry_slots: return
	var item = carry_slots.get_selected_item()
	if not item: return
	
	if item.held_scene:
		current_held_node = item.held_scene.instantiate()
		first_person_holder.add_child(current_held_node)
	else:
		var mesh_inst = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(0.1, 0.1, 0.2)
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.5, 0.0)
		box.material = mat
		mesh_inst.mesh = box
		current_held_node = mesh_inst
		first_person_holder.add_child(current_held_node)
		
	current_held_node.visible = not is_held_item_hidden

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		# Rotate player horizontally
		var yaw_delta = -event.relative.x * mouse_sensitivity
		if yaw_clamp_active:
			var new_yaw = clamp(accumulated_yaw + yaw_delta, yaw_clamp_min, yaw_clamp_max)
			yaw_delta = new_yaw - accumulated_yaw
			accumulated_yaw = new_yaw
		rotate_y(yaw_delta)
		
		# Rotate camera vertically
		camera_pivot.rotate_x(-event.relative.y * mouse_sensitivity)
		
		# Clamp vertical rotation
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, pitch_clamp_min, pitch_clamp_max)
		
	if event.is_action_pressed("interact"):
		if current_interactable:
			current_interactable.interact(self)
			
	if carry_slots:
		if event.is_action_pressed("select_slot_1"):
			carry_slots.select_slot(0)
		elif event.is_action_pressed("select_slot_2"):
			carry_slots.select_slot(1)
		elif event.is_action_pressed("quick_slot_next"):
			carry_slots.next_slot()
		elif event.is_action_pressed("quick_slot_previous"):
			carry_slots.previous_slot()
		elif event.is_action_pressed("drop_item"):
			if not is_held_item_hidden:
				carry_slots.drop_selected()

func _physics_process(delta: float) -> void:
	_update_interact_target()
	
	# Add the gravity.
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Handle Jump
	if Input.is_action_just_pressed("jump") and is_on_floor():
		if is_crouching:
			if _can_stand():
				_stand_up()
				velocity.y = jump_velocity
		else:
			velocity.y = jump_velocity

	# Handle Crouch
	if Input.is_action_pressed("crouch"):
		if not is_crouching:
			_crouch()
	else:
		if is_crouching:
			if _can_stand():
				_stand_up()

	# Smooth Camera Transition
	var target_cam_y = crouch_camera_height if is_crouching else standing_camera_height
	camera_pivot.position.y = lerp(camera_pivot.position.y, target_cam_y, crouch_transition_speed * delta)

	# Get the input direction and handle the movement/deceleration.
	# Input.get_vector automatically normalizes diagonal input
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	var is_sprinting = false
	if direction != Vector3.ZERO and Input.is_action_pressed("run") and current_stamina > 0.0 and not is_crouching:
		is_sprinting = true

	var current_speed = walk_speed
	
	if is_sprinting:
		current_speed = walk_speed * 1.3
		current_stamina -= sprint_stamina_drain * delta
	else:
		if is_crouching:
			current_speed = crouch_speed
			
		if direction == Vector3.ZERO:
			current_stamina += stamina_regen_idle * delta
		else:
			current_stamina += stamina_regen_moving * delta
			
	current_stamina = clamp(current_stamina, 0.0, max_stamina)

	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)

	move_and_slide()

func _crouch() -> void:
	is_crouching = true
	var shape = collision_shape.shape as CapsuleShape3D
	shape.height = crouch_height
	collision_shape.position.y = (standing_height - crouch_height) / -2.0

func _stand_up() -> void:
	is_crouching = false
	var shape = collision_shape.shape as CapsuleShape3D
	shape.height = standing_height
	collision_shape.position.y = 0.0

func _can_stand() -> bool:
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsShapeQueryParameters3D.new()
	
	var shape = CapsuleShape3D.new()
	shape.radius = (collision_shape.shape as CapsuleShape3D).radius
	shape.height = standing_height
	
	query.shape = shape
	query.transform = global_transform
	query.exclude = [get_rid()]
	query.collision_mask = collision_mask
	
	var result = space_state.intersect_shape(query)
	return result.is_empty()

func _update_interact_target() -> void:
	if not interact_ray: return
	
	var new_target: Interactable3D = null
	
	if interact_ray.is_colliding():
		var collider = interact_ray.get_collider()
		var candidate = _resolve_interactable(collider)
		if candidate:
			var dist = global_position.distance_to(candidate.global_position)
			if dist <= candidate.interaction_range:
				new_target = candidate
				
	if new_target != current_interactable:
		current_interactable = new_target
		interact_target_changed.emit(current_interactable)

func _resolve_interactable(node: Node) -> Interactable3D:
	if not node: return null
	
	if node is Interactable3D:
		return node
		
	for child in node.get_children():
		if child is Interactable3D:
			return child
			
	var parent = node.get_parent()
	if parent:
		if parent is Interactable3D:
			return parent
		for child in parent.get_children():
			if child is Interactable3D:
				return child
				
	return null

func take_damage(amount: float) -> void:
	if amount <= 0: return
	current_health = clamp(current_health - amount, 0.0, max_health)
	health_changed.emit(current_health, max_health)
	
	if current_health <= 0:
		# Very minimal placeholder for death
		print("Player has died!")

