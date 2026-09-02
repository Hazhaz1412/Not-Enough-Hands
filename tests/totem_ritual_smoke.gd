extends SceneTree

## Covers the totem-burning objective end to end without a map: the 4:00 AM
## ceiling still carried by the clock's raw `skip_minutes()` jump, what a burn
## actually pays now (runway, not a jump), the two-handed carry rule, and the
## burn -> fire out -> firewood -> relight loop the brazier enforces.

var _root: Node3D
var _clock: NightClock
var _brazier: TotemBrazier
var _ritual: TotemRitual
var _player: CharacterBody3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not _check_clock_ceiling():
		return
	if not await _build_world():
		return
	if not _check_two_handed_carry():
		return
	if not await _check_burn_loop():
		return
	if not await _check_line_of_sight():
		return
	if not await _check_spawn_rules():
		return
	if not _check_per_player_pricing():
		return
	if not await _check_completion():
		return

	print(
		"Totem ritual smoke test passed: 4:00 AM ceiling, two-handed totem, "
		+ "burn/relight loop, wall-blocked seen glow, 77-second x-ray hint, five random totems, "
		+ "nine logs and nine batteries, three burns per player at "
		+ "every head count, an uncapped bank a whole team can cash into at once, "
		+ "every owed burn worth something including the clipped last one, and "
		+ "end-of-ritual cleanup."
	)
	quit()


## The clock's raw jump primitive, which burns no longer use - they pay through
## add_fuel() - but which test setup and any direct jump still do, ceiling and
## all. Nine 30-minute jumps is exactly 11:55 PM -> 4:00 AM, and the ninth is
## the one that gets clipped: 3:55 AM + 30 must land on 4:00 AM, not 4:25 AM.
func _check_clock_ceiling() -> bool:
	var clock := (load("res://ui/night_clock.tscn") as PackedScene).instantiate() as NightClock
	clock.pause_on_victory = false
	root.add_child(clock)
	clock.set_process(false)

	if clock.get_minutes_until_skip_limit() != 245:
		return _fail("11:55 PM to 4:00 AM should leave 245 skippable minutes, got %d." % clock.get_minutes_until_skip_limit())
	for i: int in 8:
		if clock.skip_minutes(30) != 30:
			return _fail("Burn %d should have granted a full 30 minutes." % (i + 1))
	if clock.get_formatted_time() != "3:55 AM":
		return _fail("Eight 30-minute burns should reach 3:55 AM, got %s." % clock.get_formatted_time())
	if clock.skip_minutes(30) != 5:
		return _fail("A burn at 3:55 AM should have been clipped to the 5 minutes left.")
	if clock.get_formatted_time() != "4:00 AM":
		return _fail("The clipped burn should land exactly on 4:00 AM, got %s." % clock.get_formatted_time())
	if clock.skip_minutes(30) != 0 or clock.get_minutes_until_skip_limit() != 0:
		return _fail("Nothing may be granted once the night is at 4:00 AM.")
	if clock.won:
		return _fail("Reaching the skip ceiling must not end the night early.")

	clock.free()
	return true


func _build_world() -> bool:
	_root = Node3D.new()
	root.add_child(_root)

	_clock = (load("res://ui/night_clock.tscn") as PackedScene).instantiate() as NightClock
	_clock.pause_on_victory = false
	_root.add_child(_clock)
	_clock.set_process(false)

	_brazier = (load("res://items/totem_brazier.tscn") as PackedScene).instantiate() as TotemBrazier
	_root.add_child(_brazier)

	_ritual = TotemRitual.new()
	# Restocking needs a map full of room markers. The burn-loop checks below hand
	# every item in by name, so this director cannot create its own population;
	# keeping the normal target also prevents its deferred burn restock from
	# treating the next test's manually created totem as surplus.
	# One fake player is in the group by now; the hard floor still keeps five.
	_ritual.firewood_in_world = 0
	_root.add_child(_ritual)
	await _ritual.begin()
	_ritual.set_process(false)

	_player = (load("res://player/player.tscn") as PackedScene).instantiate() as CharacterBody3D
	_root.add_child(_player)
	_player.set_physics_process(false)

	if _brazier.is_lit != true:
		return _fail("The brazier should start the night already lit.")
	return true


func _check_two_handed_carry() -> bool:
	var totem := _spawn(&"res://items/totem.tscn")
	var firewood := _spawn(&"res://items/firewood.tscn")

	if PlayerEquipment.get_item_slot_cost(totem) != 2:
		return _fail("A totem must declare a two-slot carry cost.")
	if PlayerEquipment.get_item_slot_cost(firewood) != 1:
		return _fail("Firewood must stay a one-slot pickup.")
	if not _player.try_pick_up_item(totem):
		return _fail("A totem should be pickable with both hands free.")
	if _player.equipment.get_slot_item(0) != totem or _player.equipment.get_slot_item(1) != totem:
		return _fail("A totem should occupy both equipment slots.")
	if _player.try_pick_up_item(firewood):
		return _fail("Nothing else may be picked up while a totem fills both hands.")

	if not _player.release_held_item(totem):
		return _fail("release_held_item() should hand a carried totem back.")
	if not _player.equipment.is_slot_empty(0) or not _player.equipment.is_slot_empty(1):
		return _fail("Releasing a totem should clear both slots.")
	if not _player.try_pick_up_item(firewood):
		return _fail("Firewood should be pickable once the hands are free.")
	if not _player.equipment.is_slot_empty(1):
		return _fail("Firewood should take one slot, not both.")
	_player.release_held_item(firewood)
	firewood.queue_free()
	totem.queue_free()
	return true


func _check_burn_loop() -> bool:
	var totem := _spawn(&"res://items/totem.tscn")
	_player.try_pick_up_item(totem)
	if not _brazier.burn_totem(_player, totem):
		return _fail("Burning a totem at a lit brazier should succeed.")
	if _brazier.is_lit:
		return _fail("The fire must go out with the totem it consumed.")
	# A burn buys runway; it does not move the hands. The night advances only as
	# real time is spent against what the burn paid for, which is the whole
	# difference between this and the old skip_minutes() jump.
	if _clock.get_formatted_time() != "11:55 PM":
		return _fail("A burn moved the clock directly instead of paying runway, got %s." % _clock.get_formatted_time())
	# There is no bank ceiling any more, so a burn is worth its whole price on
	# top of whatever was already banked - never "up to the cap".
	var unit: int = _ritual.get_minutes_per_totem()
	if _clock.fuel_minutes != unit * 2:
		return _fail(
			"The opening tank plus one burn should be %d runway, got %d."
			% [unit * 2, _clock.fuel_minutes]
		)
	_clock.advance_real_seconds(30.0 * _clock.real_seconds_per_game_minute)
	if _clock.get_formatted_time() != "12:25 AM":
		return _fail("Runway bought by a burn did not run the night, got %s." % _clock.get_formatted_time())
	await process_frame

	var second := _spawn(&"res://items/totem.tscn")
	_player.try_pick_up_item(second)
	if _brazier.burn_totem(_player, second):
		return _fail("A dead fire must refuse a totem.")
	if _player.equipment.get_slot_item(0) != second:
		return _fail("A refused burn must leave the totem in the player's hands.")

	var firewood := _spawn(&"res://items/firewood.tscn")
	if _player.try_pick_up_item(firewood):
		return _fail("Firewood cannot be carried in the same trip as a totem.")
	_player.release_held_item(second)
	_player.try_pick_up_item(firewood)
	if not _brazier.relight(_player, firewood):
		return _fail("Firewood should bring the fire back.")
	if not _brazier.is_lit:
		return _fail("The brazier should be lit again after being fed firewood.")

	_player.try_pick_up_item(second)
	if not _brazier.burn_totem(_player, second):
		return _fail("The relit fire should accept the next totem.")
	# Thirty minutes were spent above, so the second burn adds a whole unit on
	# top of what was left rather than being clipped: runway accumulates, and a
	# team that burns before it is empty keeps every minute of the difference.
	if _clock.fuel_minutes != unit * 3 - 30:
		return _fail(
			"The second burn should have brought the runway to %d, got %d."
			% [unit * 3 - 30, _clock.fuel_minutes]
		)
	_clock.advance_real_seconds(30.0 * _clock.real_seconds_per_game_minute)
	if _clock.get_formatted_time() != "12:55 AM":
		return _fail("The second burn's runway should reach 12:55 AM, got %s." % _clock.get_formatted_time())
	return true


## The highlight is a "you can see it" hint, so a wall has to switch it off and
## so does simply not looking at it.
func _check_line_of_sight() -> bool:
	var camera := Camera3D.new()
	_root.add_child(camera)
	camera.global_position = Vector3(0, 1.6, 0)
	camera.look_at(Vector3(0, 1.6, -6), Vector3.UP)
	camera.current = true

	var totem := _spawn(&"res://items/totem.tscn")
	totem.global_position = Vector3(0, 1.4, -4)
	await physics_frame
	if not totem.is_seen_by_camera():
		return _fail("A totem in the open, in front of the camera, should be seen.")

	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6, 4, 0.4)
	shape.shape = box
	wall.add_child(shape)
	_root.add_child(wall)
	wall.global_position = Vector3(0, 1.6, -2)
	await physics_frame
	if totem.is_seen_by_camera():
		return _fail("A wall between the camera and a totem must switch the highlight off.")

	wall.queue_free()
	totem.global_position = Vector3(0, 1.4, 4)
	await physics_frame
	if totem.is_seen_by_camera():
		return _fail("A totem behind the camera is out of frustum and must not glow.")

	totem.queue_free()
	camera.queue_free()
	return true


## Restocking on a stage of its own: two rooms, one under the players' feet and
## one 120 m away, so "at least 70 m from everybody" has exactly one answer.
func _check_spawn_rules() -> bool:
	# The burn-loop player is done with; it would otherwise count towards the
	# population this stage is measuring. One frame flushes it and every item
	# queued for deletion above.
	_player.free()
	await process_frame
	var stage := Node3D.new()
	root.add_child(stage)
	var near_room := _fake_room(stage, Vector3(0, 0, 0))
	var far_room := _fake_room(stage, Vector3(120, 0, 0))
	var first := _fake_player(stage, Vector3(2, 0, 0))

	var director := TotemRitual.new()
	# An emptied table must still leave something findable rather than nothing:
	# the runtime floor is what upgrades it.
	director.totems_by_player_count = PackedInt32Array()
	director.min_spawn_distance = 70.0
	stage.add_child(director)
	await director.begin()

	if get_nodes_in_group(&"totems").size() != TotemRitual.MIN_TOTEMS_IN_WORLD:
		return _fail("An empty population table should fall back to the floor of five.")
	# Logs are a flat population, not one per player: the fire needs one after
	# every burn, so the map always carries a handful of them.
	if get_nodes_in_group(&"fire_fuel").size() != director.firewood_in_world:
		return _fail(
			"The map should always carry %d logs, found %d."
			% [director.firewood_in_world, get_nodes_in_group(&"fire_fuel").size()]
		)
	if director.firewood_in_world != 9 or director.batteries_in_world != 9:
		return _fail("The expanded item supply must keep nine logs and nine batteries in the map.")
	for item: Node in get_nodes_in_group(&"totems") + get_nodes_in_group(&"fire_fuel"):
		var spawned := item as Node3D
		if spawned.global_position.distance_to(first.global_position) < 70.0:
			return _fail("An item was dropped %.1f m from a player, under the 70 m rule." % spawned.global_position.distance_to(first.global_position))

	# Batteries are the one population that is not the objective, and they are
	# held to their own much smaller radius on purpose - the 70 m rule above is
	# what makes a totem a trip, and applying it to the thing that lets you see
	# would make every trip worse rather than longer.
	var batteries := get_nodes_in_group(&"flashlight_batteries")
	if batteries.size() != director.batteries_in_world:
		return _fail(
			"The map should carry %d torch batteries, found %d."
			% [director.batteries_in_world, batteries.size()]
		)
	for item: Node in batteries:
		var cell := item as Node3D
		var gap := cell.global_position.distance_to(first.global_position)
		if gap < director.battery_spawn_distance:
			return _fail("A battery landed %.1f m from a player, inside its own radius." % gap)

	# The authority starts one shared objective beacon every 77 seconds. Calling
	# the same process step the runtime uses proves the interval and one-at-a-time
	# rule without making the smoke actually wait 77 real seconds.
	for item: Node in get_nodes_in_group(&"totems"):
		item.call(&"clear_guidance_highlight")
	director._totem_hint_timer = 0.01
	director._process(0.02)
	var hinted := 0
	for item: Node in get_nodes_in_group(&"totems"):
		if bool(item.call(&"is_guidance_highlight_active")):
			hinted += 1
	if hinted != 1:
		return _fail("A 77-second hint tick must highlight exactly one loose totem, got %d." % hinted)
	if not is_equal_approx(director._totem_hint_timer, 77.0):
		return _fail("The totem hint timer did not reset to 77 seconds.")

	var second := _fake_player(stage, Vector3(0, 0, 4))
	director.restock()
	if get_nodes_in_group(&"totems").size() != TotemRitual.MIN_TOTEMS_IN_WORLD:
		return _fail("Adding a player changed the fixed five-totem population.")

	second.queue_free()
	await process_frame
	director.restock()
	await process_frame
	if get_nodes_in_group(&"totems").size() != TotemRitual.MIN_TOTEMS_IN_WORLD:
		return _fail("Losing a player changed the fixed five-totem population.")

	# Nothing on this stage is 500 m from anybody, so the rule has to fall back
	# to the farthest room there is rather than give up or drop it underfoot.
	director.min_spawn_distance = 500.0
	for item: Node in get_nodes_in_group(&"totems"):
		item.free()
	director.restock()
	var totems := get_nodes_in_group(&"totems")
	if totems.size() != TotemRitual.MIN_TOTEMS_IN_WORLD:
		return _fail("An impossible distance rule must still restock, not stall.")
	for node: Node in totems:
		if (node as Node3D).global_position.distance_to(far_room.global_position) > 3.0:
			return _fail("With no room 500 m away the farthest room should have been used.")

	# Burning one queues it out of the world and asks the authority to replace it.
	# The count returns to five without waiting for the periodic restock timer.
	var old_ids: Array[int] = []
	for node: Node in totems:
		old_ids.append(node.get_instance_id())
	(totems[0] as Node).queue_free()
	director.on_totem_burned()
	await process_frame
	await process_frame
	var replacements := get_nodes_in_group(&"totems")
	if replacements.size() != TotemRitual.MIN_TOTEMS_IN_WORLD:
		return _fail("Burning one totem did not immediately restore the population.")
	var found_new := false
	for node: Node in replacements:
		if not old_ids.has(node.get_instance_id()):
			found_new = true
			break
	if not found_new:
		return _fail("Totem restock did not create a new random replacement instance.")

	stage.free()
	await process_frame
	return true


func _fake_room(stage: Node3D, point: Vector3) -> Marker3D:
	var room := Marker3D.new()
	room.add_to_group(&"house2_rooms")
	room.set_meta(&"room_size", Vector3(4, 3, 4))
	stage.add_child(room)
	room.global_position = point
	return room


## The night costs the same amount of night whoever is carrying it: three burns
## per head, each worth proportionally less, so a full room does not finish in
## three trips and a solo player is not asked for twelve. The arithmetic that
## has to hold at every head count is "the burns owed, plus the free opening
## tank, add up to at least the whole night" - a run priced a minute short is a
## run nobody can finish.
func _check_per_player_pricing() -> bool:
	var stage := Node3D.new()
	root.add_child(stage)
	var ritual := TotemRitual.new()
	var clock := (load("res://ui/night_clock.tscn") as PackedScene).instantiate() as NightClock
	clock.set_process(false)
	root.add_child(clock)
	stage.add_child(ritual)
	ritual._clock = clock
	var night := clock.get_total_night_minutes()

	for heads: int in [1, 2, 3, 4]:
		while stage.get_child_count() - 1 < heads:
			_fake_player(stage, Vector3(float(stage.get_child_count()) * 2.0, 0.0, 0.0))
		var burns := ritual.get_burns_required()
		if burns != ritual.burns_per_player * heads:
			stage.free()
			clock.free()
			return _fail(
				"%d player(s) should owe %d burns, got %d."
				% [heads, ritual.burns_per_player * heads, burns]
			)
		var unit := ritual.get_minutes_per_totem()
		# The arithmetic being right is not the same as the clock being told. It
		# was not: the clock resets with the solo tank before this node counts
		# the room, add_fuel() can only add, and a two-player night therefore
		# opened 39 minutes over-fuelled and finished in fewer burns than it
		# owed. Assert the tank the night actually starts with, not the formula.
		ritual._sync_runway_pricing()
		if clock.fuel_minutes != unit or clock.max_fuel_minutes != night:
			stage.free()
			clock.free()
			return _fail(
				"%d player(s) should open on %d runway under a %d ceiling, got %d under %d."
				% [heads, unit, night, clock.fuel_minutes, clock.max_fuel_minutes]
			)
		# A round of trips finished together, which is how a team actually plays:
		# from an empty tank every player's burn has to land whole. Against the
		# old two-unit ceiling the third and fourth of them were granted
		# nothing - a totem carried across the villa for zero minutes of night.
		# The bank has no ceiling at all now, so a whole team's worth of burns
		# banked at once is still worth every minute of itself.
		clock.set_opening_runway(0)
		for _burn: int in heads:
			if clock.add_fuel(unit) != unit:
				stage.free()
				clock.free()
				return _fail(
					"%d player(s) burning together lost a burn to the bank." % heads
				)
		clock.set_opening_runway(unit)

		# Burning is never blocked - a team is free to spend a trip on a totem
		# that buys nothing, and the runway bar is what they judge that on. What
		# must hold is that the burns they owe are all still worth something: the
		# last one is clipped by design (the burns plus the free tank overshoot
		# the night), so a rule that refused clipped burns refused the winning
		# one every time, at two totems for a solo player.
		clock.set_opening_runway(unit)
		for burn: int in burns:
			var granted := clock.add_fuel(unit)
			if granted <= 0:
				stage.free()
				clock.free()
				return _fail(
					"%d player(s): burn %d of %d bought no night at all."
					% [heads, burn + 1, burns]
				)
		if clock.fuel_minutes != clock.get_minutes_remaining():
			stage.free()
			clock.free()
			return _fail(
				"%d player(s): every owed burn should leave the night paid to dawn, got %d of %d."
				% [heads, clock.fuel_minutes, clock.get_minutes_remaining()]
			)
		# And past that point a burn is simply worth nothing, rather than an
		# error or a negative: their gamble, cleanly lost.
		if clock.add_fuel(unit) != 0:
			stage.free()
			clock.free()
			return _fail("%d player(s): a burn past dawn's worth still paid out." % heads)
		clock.set_opening_runway(unit)

		var bought := unit * burns + unit
		if bought < night:
			stage.free()
			clock.free()
			return _fail(
				"%d player(s) burning %d totems buy %d of a %d-minute night - unfinishable."
				% [heads, burns, bought, night]
			)
		# And not so generous that the night is over before the burns are.
		if unit * burns > night:
			stage.free()
			clock.free()
			return _fail(
				"%d player(s) reach dawn on %d burns without spending the free tank."
				% [heads, burns]
			)

	stage.free()
	clock.free()
	return true


func _fake_player(stage: Node3D, point: Vector3) -> CharacterBody3D:
	var player := CharacterBody3D.new()
	player.add_to_group(&"players")
	stage.add_child(player)
	player.global_position = point
	return player


## The ritual now ends with the night, not at the old 4:00 AM ceiling: it is what
## reaches dawn, so a finish line short of dawn would strand the run. The ceiling
## is lifted here only to drive the clock there in one jump.
func _check_completion() -> bool:
	var leftover := _spawn(&"res://items/totem.tscn")
	_clock.skip_limit_hour = 6
	_clock.skip_limit_minute = 0
	_clock.skip_minutes(600)
	if _clock.get_formatted_time() != "6:00 AM":
		return _fail("The night should have run out at 6:00 AM, got %s." % _clock.get_formatted_time())
	if _ritual.is_complete != true:
		return _fail("The ritual should have completed when the night reached dawn.")
	await process_frame
	if is_instance_valid(leftover):
		return _fail("Totems left in the world should be cleared once the ritual is over.")
	# process_frame fires just *before* the nodes tick, so the brazier needs one
	# more frame to have rewritten its prompt.
	await process_frame
	if _brazier.interactable.prompt_text != "NGHI LỄ ĐÃ HOÀN TẤT":
		return _fail("A finished ritual should say so on the brazier prompt, got %s." % _brazier.interactable.prompt_text)
	return true


func _spawn(path: StringName) -> Node3D:
	var item := (load(path) as PackedScene).instantiate() as Node3D
	_root.add_child(item)
	item.set_process(false)
	return item


func _fail(message: String) -> bool:
	push_error(message)
	quit(1)
	return false
