extends Node
var peer = ENetMultiplayerPeer.new()
var connected := false
var done := false
func _ready():
	Network.full_sync.connect(_on_full_sync)
	peer.create_client("127.0.0.1", 7777)
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(func(): connected = true)
func _physics_process(_delta):
	if not connected or done:
		return
func _on_full_sync(data: Dictionary):
	var b = data.get("buildings", {})
	var v = data.get("villagers", {})
	var r = data.get("resources", {})
	print("LOAD-CHECK buildings=", b.size(), " villagers=", v.size(), " wood=", r.get("wood", 0))
	if b.size() >= 1 and v.size() >= 1 and r.get("wood", 0) >= 490:
		print("TEST PASS: world loaded")
		get_tree().quit(0)
	else:
		print("TEST FAIL: world not loaded")
		get_tree().quit(1)
	done = true
