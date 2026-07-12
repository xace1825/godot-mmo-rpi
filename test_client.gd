extends Node

func _ready():
	print("Test client starting...")
	Network.start_client("127.0.0.1", 7777)
	multiplayer.connected_to_server.connect(func(): print("Connected to server!"); _run_tests())
	multiplayer.connection_failed.connect(func(): print("Connection failed"); get_tree().quit())
	await get_tree().create_timer(5.0).timeout
	print("Test timeout")
	get_tree().quit()

func _run_tests():
	print("Running tests...")
	await get_tree().create_timer(0.5).timeout
	print("Requesting build at 5,5")
	Network.ask_build(Vector2i(5, 5))
	await get_tree().create_timer(0.5).timeout
	print("Requesting build at 6,5")
	Network.ask_build(Vector2i(6, 5))
	await get_tree().create_timer(0.5).timeout
	print("Requesting duplicate build at 5,5")
	Network.ask_build(Vector2i(5, 5)) # duplicate
	await get_tree().create_timer(1.0).timeout
	print("Test actions complete")
	get_tree().quit()

func _exit_tree():
	print("Exiting test client")
