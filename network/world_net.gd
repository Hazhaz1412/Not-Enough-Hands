class_name WorldNet
extends RefCounted

## The seam every world system talks to the network through.
##
## Ghosts, defense doors, the power manager, the totem ritual and the night
## clock all have to ask one question - "am I the one simulating this?" - and
## two of them also have to create things that must exist on every peer. Those
## are the only three calls here.
##
## ## Why this is a class and not the autoload
##
## `NetworkManager` and `WorldReplicator` are autoloads, and an autoload's name
## is only a resolvable identifier when the project's main loop is running. The
## smoke tests under `tests/` are `SceneTree` scripts launched with
## `godot --headless --script`, which has no autoloads at all: a world script
## naming `NetworkManager` directly stops compiling the moment a test pulls it
## in as a dependency. `player/player.gd` already sidesteps that with a runtime
## `get_node_or_null("/root/NetworkManager")`; this is the same trick, in one
## place, so the ten scripts that need it do not each repeat it.
##
## ## Degrading
##
## Every call answers sensibly when there is no network layer at all - which is
## the case in the smoke tests, in the `tools/` scripts, and in single-player:
## authority is *true* (simulate normally) and `spawn()` is a plain
## `add_child()`. So the guards these calls sit behind change nothing outside a
## hosted session, which is what keeps House2 and every existing test working.

const MANAGER_PATH := ^"/root/NetworkManager"
const REPLICATOR_PATH := ^"/root/WorldReplicator"


## True where world simulation is allowed to run: single-player, the server of a
## network session, and anywhere the network layer is absent entirely. False
## only on a client, which must take the world from the server instead of
## running a second, divergent copy of it.
static func is_world_authority() -> bool:
	var manager := _node(MANAGER_PATH)
	if manager == null:
		return true
	if not bool(manager.get("session_active")):
		return true
	var tree := _tree()
	return tree != null and tree.get_multiplayer().is_server()


## The mirror of is_world_authority(): a peer that has to be told what the world
## is doing.
static func is_network_client() -> bool:
	return not is_world_authority()


## Creates something that has to exist on every peer - a dropped totem, the
## brazier, a huntsman coming through a breach - and returns it, or null on a
## client, where the node arrives from the server instead.
##
## The transform is passed in rather than set by the caller afterwards so the
## very first packet already places the thing correctly.
static func spawn(
	scene: PackedScene,
	parent: Node,
	position: Vector3 = Vector3.ZERO,
	rotation_y: float = 0.0,
	node_name: String = ""
) -> Node:
	var replicator := _node(REPLICATOR_PATH)
	if replicator != null and replicator.has_method(&"spawn"):
		return replicator.call(&"spawn", scene, parent, position, rotation_y, "", node_name)
	# No network layer: behave exactly as the plain add_child this replaced.
	if scene == null or parent == null or not is_world_authority():
		return null
	var node := scene.instantiate()
	if not node_name.is_empty():
		node.name = node_name
	parent.add_child(node)
	var node_3d := node as Node3D
	if node_3d:
		node_3d.global_position = position
		node_3d.rotation.y = rotation_y
	return node


## Tells the other peers whose hands `item` is in now, or that it is loose
## again. A no-op without a network layer.
static func report_holder(item: Node, peer_id: int) -> void:
	var replicator := _node(REPLICATOR_PATH)
	if replicator != null and replicator.has_method(&"report_holder"):
		replicator.call(&"report_holder", item, peer_id)


static func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


static func _node(path: NodePath) -> Node:
	var tree := _tree()
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(path)
