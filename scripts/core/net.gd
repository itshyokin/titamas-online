extends Node
## Autoload "Net": co-op over the network (Godot's ENet, direct IP for now).
##
## One player hosts; their game runs the world (enemies, their AI and health, respawns).
## Friends join with their own character from their own save. Each game moves its own
## player and sends where it is and what it's doing; the others show it as a
## RemotePlayer. On joining games, enemies are puppets that copy the host.
##
## Fights:
## - A joined player hits an enemy → the hit goes to the host, which applies it (the
##   attacker is that player's RemotePlayer there) and tells everyone the damage.
## - The host's enemy hits a RemotePlayer → the attack goes to that player's game, which
##   works it out on the real player (their block, dodge and armour count).
## - An enemy dies → every game drops its own loot (personal loot).
## Hit-stop and slow motion are off in co-op (they'd slow everyone's game).

signal peers_changed
signal connected_to_host
signal connection_failed(reason: String)
signal host_left
## A chat line from another player.
signal chat_received(who: String, text: String)

const DEFAULT_PORT := 24565
const MAX_PLAYERS := 10
const STATE_RATE := 20.0  # player states per second
const ENEMY_RATE := 10.0  # enemy states per second (host)

## True while hosting or joined.
var active := false
var is_host := false
## Everyone else: peer id -> {name, look, class, level, equipment}
var peers := {}

var _peer: ENetMultiplayerPeer
var _state_timer := 0.0
var _enemy_timer := 0.0
var _anim_seq := 0
var _last_anim := ""
var _last_anim_pos := 0.0
var _hooked_scene: Node = null


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func() -> void:
		leave()
		connection_failed.emit("Couldn't reach the host."))
	multiplayer.server_disconnected.connect(func() -> void:
		leave()
		host_left.emit())


func is_client() -> bool:
	return active and not is_host


## Starts hosting. The level should be started (GameSession.start_game) right after.
func host_game(port := DEFAULT_PORT) -> Error:
	leave()
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		_peer = null
		return err
	multiplayer.multiplayer_peer = _peer
	active = true
	is_host = true
	return OK


## Connects to a host. connected_to_host fires once the host has sent its world.
func join_game(address: String, port := DEFAULT_PORT) -> Error:
	leave()
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(address, port)
	if err != OK:
		_peer = null
		return err
	multiplayer.multiplayer_peer = _peer
	active = true
	is_host = false
	return OK


func leave() -> void:
	if _peer:
		_peer.close()
	_peer = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	active = false
	is_host = false
	for id in peers.keys():
		_remove_remote(id)
	peers.clear()
	_hooked_scene = null
	peers_changed.emit()


## This machine's addresses on the local network (to tell friends what to join).
func local_addresses() -> Array[String]:
	var out: Array[String] = []
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."):
			out.append(a)
	return out


## What other games need to show this player.
func my_info() -> Dictionary:
	var d: Dictionary = GameSession.data
	var inv: Dictionary = d.get("inventory", {})
	var player := _local_player()
	if player:
		var inventory := player.get_node_or_null("Inventory")
		if inventory:
			inv = inventory.call("to_dict")
	return {"name": d.get("name", "Adventurer"), "look": d.get("look", {}), "class": d.get("class", "fighter"),
		"level": int(d.get("level", 1)), "equipment": inv.get("equipped", {})}


# --- Connecting ---------------------------------------------------------------------

func _on_connected() -> void:
	_hello.rpc_id(1, my_info())


func _on_peer_connected(_id: int) -> void:
	pass  # the joining game introduces itself with _hello


func _on_peer_disconnected(id: int) -> void:
	if peers.has(id):
		GameLog.post("%s left the game." % peers[id].get("name", "A player"), Color(0.6, 0.9, 1.0))
	_remove_remote(id)
	peers.erase(id)
	peers_changed.emit()


## Joining game → host: who I am. The host answers with its level and where to stand.
@rpc("any_peer", "reliable")
func _hello(info: Dictionary) -> void:
	if not is_host:
		return
	var id := multiplayer.get_remote_sender_id()
	peers[id] = info
	var host_player := _local_player()
	var spot := host_player.global_position + Vector3(1.5, 0.5, 1.5) if host_player else Vector3.ZERO
	var others := {1: my_info()}
	for other in peers:
		if other != id:
			others[other] = peers[other]
	var scene := get_tree().current_scene
	_welcome.rpc_id(id, scene.scene_file_path if scene else GameSession.START_SCENE, [spot.x, spot.y, spot.z], others)
	_peer_joined.rpc(id, info)
	_spawn_remote(id, info)
	GameLog.post("%s joined the game." % info.get("name", "A player"), Color(0.6, 0.9, 1.0))
	peers_changed.emit()


## Host → joining game: the level, a spot next to the host, and who's already playing.
@rpc("authority", "reliable")
func _welcome(scene_path: String, spot: Array, others: Dictionary) -> void:
	peers.clear()
	for id in others:
		peers[int(id)] = others[id]
	GameSession.data["scene"] = scene_path
	GameSession.data["position"] = spot
	connected_to_host.emit()
	peers_changed.emit()


@rpc("authority", "reliable")
func _peer_joined(id: int, info: Dictionary) -> void:
	if id == multiplayer.get_unique_id():
		return
	peers[id] = info
	_spawn_remote(id, info)
	GameLog.post("%s joined the game." % info.get("name", "A player"), Color(0.6, 0.9, 1.0))
	peers_changed.emit()


## A player's gear or level changed.
@rpc("any_peer", "reliable")
func _info_changed(info: Dictionary) -> void:
	var id := multiplayer.get_remote_sender_id()
	peers[id] = info
	var remote := _remote(id)
	if remote:
		remote.apply_info(info)


func send_info() -> void:
	if active:
		_info_changed.rpc(my_info())


# --- Chat --------------------------------------------------------------------------

func send_chat(who: String, text: String) -> void:
	if active:
		_chat.rpc(who, text.left(200))


@rpc("any_peer", "reliable")
func _chat(who: String, text: String) -> void:
	chat_received.emit(who, text)


# --- Every frame --------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not active or get_tree().current_scene == null:
		return
	var scene := get_tree().current_scene
	if scene != _hooked_scene and _local_player():
		_hook_scene(scene)
	_state_timer -= delta
	if _state_timer <= 0.0:
		_state_timer = 1.0 / STATE_RATE
		_send_player_state()
	if is_host:
		_enemy_timer -= delta
		if _enemy_timer <= 0.0:
			_enemy_timer = 1.0 / ENEMY_RATE
			_send_enemy_states()


## A new level is up: spawn everyone's RemotePlayer and listen to the enemies.
func _hook_scene(scene: Node) -> void:
	_hooked_scene = scene
	for id in peers:
		_spawn_remote(id, peers[id])
	var inventory := _local_player().get_node_or_null("Inventory")
	if inventory and not inventory.is_connected("equipment_changed", send_info):
		inventory.connect("equipment_changed", send_info)
	if is_host:
		for enemy in _enemies():
			var path := scene.get_path_to(enemy)
			enemy.stats.damaged.connect(func(amount: float, _source: Node, crit: bool) -> void:
				if active:
					_enemy_damaged.rpc(path, amount, crit))
			enemy.stats.died.connect(func() -> void:
				if active:
					_enemy_died.rpc(path))


func _send_player_state() -> void:
	var player := _local_player()
	if player == null:
		return
	var character: CharacterModel = player.get_node("Model/Character")
	var anim := character.current_animation()
	var pos := character.animation_position()
	if anim != _last_anim or pos < _last_anim_pos - 0.05:
		_anim_seq += 1  # changed or restarted (a combo swing)
	_last_anim = anim
	_last_anim_pos = pos
	var stats: Stats = player.get_node("Stats")
	var combat := player.get_node_or_null("PlayerCombat")
	var drawn := 0
	if combat and combat.get("in_combat"):
		drawn = 1 if combat.call("active_slot") == "primary" else 2
	var p := player.global_position
	var model := player.get_node("Model") as Node3D
	_player_state.rpc([p.x, p.y, p.z, model.rotation.y, anim, _anim_seq, pos, character.get_speed(),
		stats.health, stats.max_health, drawn])


@rpc("any_peer", "unreliable_ordered")
func _player_state(state: Array) -> void:
	var remote := _remote(multiplayer.get_remote_sender_id())
	if remote:
		remote.apply_state(state)


# --- Enemies (the host runs them) ----------------------------------------------------

func _enemies() -> Array:
	return get_tree().get_nodes_in_group(Combat.GROUP).filter(func(n: Node) -> bool: return n is Enemy)


func _send_enemy_states() -> void:
	if peers.is_empty():
		return
	var scene := get_tree().current_scene
	var states := []
	for enemy: Enemy in _enemies():
		states.append(enemy.net_state(scene.get_path_to(enemy)))
	_enemy_states.rpc(states)


@rpc("authority", "unreliable_ordered")
func _enemy_states(states: Array) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	for s: Array in states:
		var enemy := scene.get_node_or_null(NodePath(s[0])) as Enemy
		if enemy:
			enemy.apply_net_state(s)


@rpc("authority", "reliable")
func _enemy_damaged(path: NodePath, amount: float, crit: bool) -> void:
	var enemy := _node(path) as Enemy
	if enemy:
		FloatingText.spawn(enemy, ("%d!" % amount) if crit else str(int(amount)), Color(1.0, 0.85, 0.3), 1.4 if crit else 1.0)


@rpc("authority", "reliable")
func _enemy_died(path: NodePath) -> void:
	var enemy := _node(path) as Enemy
	var player := _local_player()
	if enemy and player and enemy.global_position.distance_to(player.global_position) < 40.0:
		# Everyone gets their own loot.
		LootBag.drop_for(Database.enemy(enemy.enemy_id), Combat.world_root(enemy), enemy.global_position, enemy)
	if enemy:
		enemy.credit_kill()  # experience, if this game's player fought it


## Joined game: my player hit an enemy (the host works out the damage).
func request_hit(enemy: Node, power: float, stagger: bool, knockback: float) -> void:
	_hit_enemy.rpc_id(1, get_tree().current_scene.get_path_to(enemy), power, stagger, knockback)


@rpc("any_peer", "reliable")
func _hit_enemy(path: NodePath, power: float, stagger: bool, knockback: float) -> void:
	if not is_host:
		return
	var enemy := _node(path) as Node3D
	var attacker := _remote(multiplayer.get_remote_sender_id())
	if enemy and attacker:
		Combat.hit(attacker, enemy, power, stagger, knockback)


## Host: an enemy's swing reached a RemotePlayer; that player's game works it out.
func forward_attack(peer_id: int, enemy: Node, power: float, stagger: bool, knockback: float) -> void:
	_enemy_attack.rpc_id(peer_id, get_tree().current_scene.get_path_to(enemy), power, stagger, knockback)


@rpc("authority", "reliable")
func _enemy_attack(path: NodePath, power: float, stagger: bool, knockback: float) -> void:
	var enemy := _node(path) as Node3D
	var player := _local_player()
	if enemy and player:
		Combat.hit(enemy, player, power, stagger, knockback)


# --- Helpers -------------------------------------------------------------------------

func _node(path: NodePath) -> Node:
	var scene := get_tree().current_scene
	return scene.get_node_or_null(path) if scene else null


func _local_player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D


func _remote(id: int) -> RemotePlayer:
	var scene := get_tree().current_scene
	return scene.get_node_or_null("RemotePlayers/%d" % id) as RemotePlayer if scene else null


func _spawn_remote(id: int, info: Dictionary) -> void:
	var scene := get_tree().current_scene
	if scene == null or _local_player() == null or _remote(id):
		return
	var holder := scene.get_node_or_null("RemotePlayers")
	if holder == null:
		holder = Node3D.new()
		holder.name = "RemotePlayers"
		scene.add_child(holder)
	var remote := RemotePlayer.create(id, info)
	holder.add_child(remote)
	remote.global_position = _local_player().global_position + Vector3(2, 0, 2)


func _remove_remote(id: int) -> void:
	var remote := _remote(id)
	if remote:
		remote.queue_free()
