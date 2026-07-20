extends Node

var peer = ENetMultiplayerPeer.new()
var connected := false
var full_sync_received := false
var start_time := 0

var start_hour: float = -1.0
var start_day: int = -1
var saw_night := false
var saw_day := false

func _ready():
	Network.full_sync.connect(_on_full_sync)
	Network.day_night_sync.connect(_on_day_night_sync)
	peer.create_client("127.0.0.1", 7777)
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(func(): connected = true)
	multiplayer.connection_failed.connect(func(): _fail("connection failed"))
	start_time = Time.get_ticks_msec()

func _physics_process(_delta):
	var elapsed: float = (Time.get_ticks_msec() - start_time) / 1000.0
	if not connected or not full_sync_received:
		if elapsed > 20.0:
			_fail("connection or full sync timeout")
		return
	# At time_scale=5.0 and 10 real seconds per game hour, one game hour passes every 2 real seconds.
	# We expect at least one full day-night cycle in 60 real seconds.
	if saw_night and saw_day:
		print("TEST PASS: day-night cycle observed (day=", start_day, " -> ", Network.last_full_sync.get("day_count", start_day), " hour=", start_hour, " -> night -> day)")
		get_tree().quit(0)
	if elapsed > 60.0:
		_fail("day-night cycle timeout (saw_night=" + str(saw_night) + " saw_day=" + str(saw_day) + ")")

func _on_full_sync(data: Dictionary):
	full_sync_received = true
	if start_hour < 0:
		start_hour = data.get("time_of_day", 6.0)
		start_day = data.get("day_count", 1)

func _on_day_night_sync(time_of_day: float, day_count: int):
	if time_of_day >= 22.0 or time_of_day <= 2.0:
		saw_night = true
	if time_of_day >= 8.0 and time_of_day <= 16.0 and saw_night:
		saw_day = true
	print("TEST: time_of_day=", time_of_day, " day=", day_count, " saw_night=", saw_night, " saw_day=", saw_day)

func _fail(msg: String):
	print("TEST FAIL: " + msg)
	get_tree().quit(1)
