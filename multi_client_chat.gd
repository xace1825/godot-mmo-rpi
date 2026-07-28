extends Node

# Multi-client chat + player sync test.
# Usage:
#   godot --headless --path . --scene multi_client_chat.tscn --client-index 0
# Server must be running on 127.0.0.1:7777.

const DEFAULT_SERVER_IP: String = "127.0.0.1"
const DEFAULT_SERVER_PORT: int = 7777

const BASE_POSITIONS: Array = [Vector2i(60, 60), Vector2i(80, 80)]

var client_index: int = 0
var connected := false
var full_sync_received := false
var saw_other_player := false
var saw_chat_from_other := false
var saw_own_chat_echo := false
var sent_chat := false
var phase: String = "connect"
var phase_entered: bool = false
var phase_start_time: int = 0
var _finished: bool = false
var _base_settled: bool = false

func _ready():
	var args := OS.get_cmdline_args()
	for i in range(args.size()):
		if args[i] == "--client-index" and i + 1 < args.size():
			client_index = args[i + 1].to_int()
	print("Chat test client ", client_index, " starting")
	Network.full_sync.connect(func(_d): full_sync_received = true)
	Network.player_joined.connect(_on_player_joined)
	Network.chat_message.connect(_on_chat)
	Network.base_settled_at.connect(_on_base_settled)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func(): _fail("connection failed"))
	Network.start_client(DEFAULT_SERVER_IP, DEFAULT_SERVER_PORT)
	phase_start_time = Time.get_ticks_msec()

func _on_connected():
	connected = true
	print("Chat client ", client_index, " connected, my id=", multiplayer.get_unique_id())

func _on_base_settled(pos: Vector2i):
	_base_settled = true
	print("Chat client ", client_index, " base settled at ", pos)

func _settle_if_needed():
	if _base_settled:
		return
	var pos: Vector2i = BASE_POSITIONS[client_index % BASE_POSITIONS.size()]
	print("Chat client ", client_index, " requesting settle at ", pos)
	Network.ask_settle_base(pos)

func _on_player_joined(id: int, data: Dictionary):
	if id == multiplayer.get_unique_id():
		return
	saw_other_player = true
	print("Chat client ", client_index, " saw player ", id, " name=", data.get("name", ""))

func _on_chat(id: int, text: String):
	if id == multiplayer.get_unique_id():
		saw_own_chat_echo = true
		print("Chat client ", client_index, " saw own chat echo: ", text)
	else:
		saw_chat_from_other = true
		print("Chat client ", client_index, " received chat from ", id, ": ", text)

func _physics_process(_delta: float):
	var elapsed: float = (Time.get_ticks_msec() - phase_start_time) / 1000.0
	if not connected or not full_sync_received:
		if elapsed > 20.0:
			_fail("timeout waiting for connection/full sync")
		return
	if not _base_settled:
		if elapsed > 30.0:
			_fail("timeout waiting for base settlement")
		if (Time.get_ticks_msec() % 1000) < 50:
			_settle_if_needed()
		return
	match phase:
		"connect":
			phase = "wait" if client_index == 1 else "send"
			phase_entered = false
			phase_start_time = Time.get_ticks_msec()
		"wait":
			if saw_chat_from_other:
				_finish()
			elif elapsed > 30.0:
				_fail("client 1 did not receive chat")
		"send":
			if not phase_entered:
				phase_entered = true
				print("Chat client 0 waiting for client 1...")
			if saw_other_player and not sent_chat:
				sent_chat = true
				Network.ask_chat("hello from client 0")
				print("Chat client 0 sent message")
			if saw_chat_from_other or saw_own_chat_echo:
				_finish()
			elif elapsed > 30.0:
				_fail("client 0 did not see chat echo")

func _fail(msg: String):
	if _finished:
		return
	print("TEST FAIL chat client ", client_index, ": ", msg)
	get_tree().quit(1)

func _finish():
	if _finished:
		return
	_finished = true
	print("TEST PASS chat client ", client_index, ": other_player=", saw_other_player, " chat_from_other=", saw_chat_from_other, " own_echo=", saw_own_chat_echo)
	get_tree().quit(0)
