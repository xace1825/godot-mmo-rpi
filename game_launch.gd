extends Node

# Static launch configuration passed from main menu to main scene.

var mode: String = "client" # singleplayer | host | client
var server_ip: String = "127.0.0.1"
var server_port: int = 7777
var mode_set_by_cmdline: bool = false

func _ready():
	var args := OS.get_cmdline_args()
	for i in range(args.size()):
		if args[i] == "--mode" and i + 1 < args.size():
			mode = args[i + 1]
			mode_set_by_cmdline = true
		elif args[i] == "--server-ip" and i + 1 < args.size():
			server_ip = args[i + 1]
		elif args[i] == "--server-port" and i + 1 < args.size():
			server_port = int(args[i + 1])
	print("GameLaunch: mode=", mode, " server=", server_ip, ":", server_port)
