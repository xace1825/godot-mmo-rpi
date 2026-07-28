extends Node

# PlayerManager tracks connected human players and their cursors/positions.
# Networking is handled by Network.gd via RPC; this file only stores state and emits signals.

signal player_joined(id: int, data: Dictionary)
signal player_left(id: int)
signal player_moved(id: int, pos: Vector2)
signal chat_message(id: int, text: String)

# player_id (multiplayer peer id) -> { name: String, color: Color, pos: Vector2 }
var players: Dictionary = {}

# Client-side: our own peer id
var my_id: int = 0

const PLAYER_COLORS: Array[Color] = [
	Color.RED,
	Color.GREEN,
	Color.BLUE,
	Color.YELLOW,
	Color.CYAN,
	Color.MAGENTA,
	Color.ORANGE,
	Color.PURPLE
]

func _ready():
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func _on_connected_to_server():
	my_id = multiplayer.get_unique_id()

func _on_peer_disconnected(id: int):
	if players.has(id):
		players.erase(id)
		player_left.emit(id)

func register_player(id: int, name: String, color: Color, pos: Vector2) -> void:
	var data := {"name": name, "color": color, "pos": pos}
	players[id] = data
	player_joined.emit(id, data)

func unregister_player(id: int) -> void:
	if players.has(id):
		players.erase(id)
		player_left.emit(id)

func update_player_position(id: int, pos: Vector2) -> void:
	if players.has(id):
		players[id]["pos"] = pos
		player_moved.emit(id, pos)

func get_player_name(id: int) -> String:
	if players.has(id):
		return players[id].get("name", "Player %d" % id)
	return "Player %d" % id

func next_player_color() -> Color:
	return PLAYER_COLORS[players.size() % PLAYER_COLORS.size()]

func update_my_position(pos: Vector2):
	if my_id == 0:
		return
	if multiplayer.is_server():
		if players.has(my_id):
			players[my_id]["pos"] = pos
			Network.broadcast_player_position(my_id, pos)
	else:
		Network.ask_report_position(pos)

func send_chat(text: String):
	if text.strip_edges() == "":
		return
	if multiplayer.is_server():
		Network.broadcast_chat(my_id, text)
	else:
		Network.ask_chat(text)

func receive_chat(id: int, text: String):
	chat_message.emit(id, text)
