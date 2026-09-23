extends SceneTree

const TRAP_SCENE := preload("res://items/trap_item.tscn")
const STICK_SCENE := preload("res://items/stun_stick_item.tscn")


class FakePlayer extends Node3D:
	var released: Node = null

	func release_held_item(item: Node) -> bool:
		released = item
		return true

	func get_tactical_use_origin() -> Vector3:
		return global_position

	func get_tactical_use_direction() -> Vector3:
		return Vector3.FORWARD


class FakeCrawler extends Node3D:
	var stun_duration := 0.0

	func apply_stun(duration: float) -> bool:
		stun_duration = duration
		return true


class FakeHunter extends Node3D:
	var snare_duration := 0.0

	func apply_snare(duration: float) -> bool:
		snare_duration = duration
		return true


class FakeShadow extends Node3D:
	var stun_duration := 0.0

	func apply_stun(duration: float) -> bool:
		stun_duration = duration
		return true


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var player := FakePlayer.new()
	world.add_child(player)
	var crawler := FakeCrawler.new()
	crawler.add_to_group(&"hostile_ghosts")
	world.add_child(crawler)
	crawler.global_position = Vector3(0, 0, -1)
	var hunter := FakeHunter.new()
	hunter.add_to_group(&"hostile_ghosts")
	world.add_child(hunter)

	var trap := TRAP_SCENE.instantiate()
	world.add_child(trap)
	var stick := STICK_SCENE.instantiate()
	world.add_child(stick)
	assert(trap.collision_layer & 2 != 0, "Trap must be visible to the interaction ray")
	assert(stick.collision_layer & 2 != 0, "Stick must be visible to the interaction ray")
	trap.is_placed = true
	trap.is_armed = true
	trap._trigger(crawler)
	assert(trap.is_spent, "Trap must be spent after its first trigger")
	assert(crawler.stun_duration == 3.0, "Trap stun must last three seconds")
	assert(stick.use(player), "Stick should hit the Crawler in its short forward arc")
	assert(stick.durability == 2, "Crawler hit must cost one stick durability")
	assert(crawler.stun_duration == 1.5, "Stick stun must last 1.5 seconds")
	var shadow := FakeShadow.new()
	shadow.add_to_group(&"darkness_ghosts")
	world.add_child(shadow)
	crawler.global_position = Vector3(20, 0, 0)
	shadow.global_position = Vector3(0, 0, -1)
	assert(stick.use(player), "Stick should target a Darkness-group ghost")
	assert(shadow.stun_duration == 1.5, "Shadow stick stun must last 1.5 seconds")

	# Move the Crawler away so the next swing resolves against the Huntsman.
	shadow.global_position = Vector3(20, 0, 0)
	hunter.global_position = Vector3(0, 0, -1)
	assert(stick.use(player), "Stick should resolve a Huntsman strike")
	assert(player.released == stick, "Huntsman strike must destroy the stick immediately")

	print("Tactical tools smoke test passed.")
	quit()
