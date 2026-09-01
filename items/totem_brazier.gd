class_name TotemBrazier
extends StaticBody3D

## The one place in the house a totem can be burned.
##
## It owns the fire and the hold, and nothing else. How much night a burn is
## worth, how many totems exist and when the ritual is finished all belong to
## TotemRitual - the same split the breaker and its minigame use. The player is
## never reached into either: the brazier polls the `players` group the way a
## downed body polls for a rescuer, and asks the player itself to hand the item
## over via `release_held_item()`.
##
## The loop the fire enforces: burn a totem, the flames die with it, and the
## next totem cannot go in until somebody has carried firewood back here. A
## totem takes both hands, so that is always a second trip.

enum Use { BURN, RELIGHT }

@export_range(0.5, 10.0, 0.1) var interaction_range: float = 2.4
## Uninterrupted seconds of the interact key to feed a totem to the fire.
@export_range(0.5, 15.0, 0.1) var burn_hold_seconds: float = 3.0
@export_range(0.2, 15.0, 0.1) var relight_hold_seconds: float = 1.5
## How fast an abandoned hold drains, as a multiple of real time.
@export_range(0.1, 8.0, 0.1) var hold_decay_multiplier: float = 2.0
@export var starts_lit: bool = true

@onready var interactable: Interactable = $Interactable
@onready var flame: Node3D = get_node_or_null("Flame") as Node3D
@onready var flame_light: OmniLight3D = get_node_or_null("Flame/FlameLight") as OmniLight3D

var is_lit: bool = true
var hold_progress: float = 0.0

var _hold_player: Node = null
var _ritual_node: Node = null
var _flare: float = 0.0
var _flicker: float = 0.0
var _flame_base_scale: Vector3 = Vector3.ONE


func _ready() -> void:
	add_to_group(&"totem_braziers")
	interactable.interaction_range = interaction_range
	if flame:
		_flame_base_scale = flame.scale
	is_lit = starts_lit
	_apply_lit_visuals()
	_update_prompt({})


func _process(delta: float) -> void:
	var use := _find_user()
	# The hold is counted once, by the authority, off the interact every client
	# already streams to it. A client keeps drawing its prompt and its flame but
	# takes the bar and the fire from apply_network_state() - otherwise the same
	# totem would be worth thirty minutes of night on every machine at once.
	if not WorldNet.is_world_authority():
		_update_prompt(use)
		_animate_flame(delta)
		return
	if use.is_empty() or not bool(use["player"].call("is_holding_interact")):
		_hold_player = null
		hold_progress = maxf(hold_progress - delta * hold_decay_multiplier, 0.0)
	else:
		if use["player"] != _hold_player:
			_hold_player = use["player"]
			hold_progress = 0.0
		hold_progress += delta
		if hold_progress >= float(use["seconds"]):
			hold_progress = 0.0
			_hold_player = null
			if int(use["mode"]) == Use.BURN:
				burn_totem(use["player"], use["item"])
			else:
				relight(use["player"], use["item"])
			use = {}
	_update_prompt(use)
	_animate_flame(delta)


## Consumes `totem` out of `player`'s hands, banks the night it is worth
## through the ritual, and puts the fire out. Public because the hold is only
## the gate: the burn itself is one step the smoke test drives directly.
func burn_totem(player: Node, totem: Node3D) -> bool:
	if not is_lit or not _take_from(player, totem):
		return false
	totem.queue_free()
	_flare = 1.0
	_set_lit(false)
	var ritual := _ritual()
	if ritual:
		ritual.on_totem_burned()
	return true


## Spends a piece of firewood to bring the fire back, which is the only way a
## second totem ever goes in.
func relight(player: Node, fuel: Node3D) -> bool:
	if is_lit or not _take_from(player, fuel):
		return false
	fuel.queue_free()
	_flare = 0.6
	_set_lit(true)
	return true


## Takes the server's fire and its hold bar. The flare is re-derived rather than
## sent: which way the fire just changed is enough to know whether this was a
## totem going in or firewood bringing it back.
func apply_network_state(lit: bool, progress: float) -> void:
	hold_progress = progress
	if lit != is_lit:
		_flare = 0.6 if lit else 1.0
		_set_lit(lit)


func get_hold_ratio(seconds: float) -> float:
	return clampf(hold_progress / maxf(seconds, 0.01), 0.0, 1.0)


## The player this brazier would serve right now, whether or not they are
## already holding the key: {player, item, mode, seconds}, or {} for nobody.
## Mirrors Player._find_reviver() - written from this side so the outcome does
## not depend on which node _process happens to reach first.
func _find_user() -> Dictionary:
	if _ritual_is_complete():
		return {}
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		if not _player_can_use(node):
			continue
		var wanted: StringName = &"totems" if is_lit else &"fire_fuel"
		var item := _carried_item(node, wanted)
		if item == null:
			continue
		return {
			"player": node,
			"item": item,
			"mode": Use.BURN if is_lit else Use.RELIGHT,
			"seconds": burn_hold_seconds if is_lit else relight_hold_seconds,
		}
	return {}


func _player_can_use(player: Node) -> bool:
	if not is_instance_valid(player) or not player.has_method("get_interaction_target"):
		return false
	if "is_alive" in player and not bool(player.get("is_alive")):
		return false
	if "is_downed" in player and bool(player.get("is_downed")):
		return false
	if "is_spectator" in player and bool(player.get("is_spectator")):
		return false
	return (
		player.call("get_interaction_target") == interactable
		and bool(player.call("can_interact_with", interactable))
	)


func _carried_item(player: Node, group: StringName) -> Node3D:
	if not ("equipment" in player):
		return null
	var equipment: PlayerEquipment = player.get("equipment")
	if equipment == null:
		return null
	for index: int in PlayerEquipment.SLOT_COUNT:
		var item := equipment.get_slot_item(index) as Node3D
		if item and item.is_in_group(group):
			return item
	return null


func _take_from(player: Node, item: Node3D) -> bool:
	if not is_instance_valid(player) or not is_instance_valid(item):
		return false
	if not player.has_method("release_held_item"):
		return false
	return bool(player.call("release_held_item", item))


func _set_lit(lit: bool) -> void:
	if is_lit == lit:
		return
	is_lit = lit
	_apply_lit_visuals()


func _apply_lit_visuals() -> void:
	if flame:
		flame.visible = is_lit or _flare > 0.0


func _animate_flame(delta: float) -> void:
	_flare = maxf(_flare - delta * 1.6, 0.0)
	_flicker += delta * 7.0
	if flame:
		flame.visible = is_lit or _flare > 0.0
		if not flame.visible:
			return
	var level := (1.0 if is_lit else 0.0) + _flare * 1.8
	var wobble := 0.9 + 0.1 * sin(_flicker) + 0.06 * sin(_flicker * 2.7)
	if flame_light:
		flame_light.light_energy = level * 2.2 * wobble
	if flame:
		flame.scale = _flame_base_scale * (0.85 + 0.35 * level) * wobble


## The prompt is the whole HUD for this interaction: the interaction prompt UI
## reads it off the Interactable, so the hold percentage is written into
## `prompt_text` rather than drawn anywhere of our own.
func _update_prompt(use: Dictionary) -> void:
	var text := ""
	if _ritual_is_complete():
		text = "NGHI LỄ ĐÃ HOÀN TẤT"
	elif use.is_empty():
		text = "CẦN MANG TOTEM TỚI ĐÂY" if is_lit else "LỬA ĐÃ TẮT - CẦN CỦI MỒI"
	else:
		var ratio := get_hold_ratio(float(use["seconds"]))
		var verb := "ĐỐT TOTEM" if int(use["mode"]) == Use.BURN else "NHÓM LỬA"
		if ratio > 0.0:
			text = "GIỮ ĐỂ %s  %d%%" % [verb, roundi(ratio * 100.0)]
		else:
			text = "GIỮ ĐỂ " + verb
	interactable.prompt_text = text


## Resolved lazily rather than in _ready(): a map is free to add the brazier to
## the tree before the ritual director.
func _ritual() -> Node:
	if not is_instance_valid(_ritual_node):
		_ritual_node = get_tree().get_first_node_in_group(&"totem_ritual")
	return _ritual_node


func _ritual_is_complete() -> bool:
	var ritual := _ritual()
	return ritual != null and bool(ritual.get("is_complete"))
