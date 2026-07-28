extends Control

# Main menu for Fantasy Settlement MMO.
# Allows singleplayer, host dedicated server, join by IP, or exit.

const DEFAULT_PORT: int = 7777

@onready var singleplayer_button: Button = $VBoxContainer/SingleplayerButton
@onready var host_button: Button = $VBoxContainer/HostButton
@onready var join_button: Button = $VBoxContainer/JoinButton
@onready var join_ip_input: LineEdit = $VBoxContainer/JoinIPInput
@onready var join_port_input: LineEdit = $VBoxContainer/JoinPortInput
@onready var exit_button: Button = $VBoxContainer/ExitButton
@onready var status_label: Label = $VBoxContainer/StatusLabel

func _ready():
	join_ip_input.text = GameLaunch.server_ip if GameLaunch.server_ip != "" else "127.0.0.1"
	join_port_input.text = str(GameLaunch.server_port)
	status_label.text = ""

func _set_status(msg: String):
	status_label.text = msg
	print("MainMenu: ", msg)

func _on_singleplayer():
	_set_status("Starting singleplayer...")
	GameLaunch.mode = "singleplayer"
	GameLaunch.server_ip = ""
	GameLaunch.server_port = DEFAULT_PORT
	get_tree().change_scene_to_file("res://main.tscn")

func _on_host():
	_set_status("Starting host server...")
	GameLaunch.mode = "host"
	GameLaunch.server_ip = ""
	GameLaunch.server_port = DEFAULT_PORT
	get_tree().change_scene_to_file("res://main.tscn")

func _on_join():
	var ip := join_ip_input.text.strip_edges()
	if ip == "":
		_set_status("Enter server IP")
		return
	var port_str := join_port_input.text.strip_edges()
	var port := DEFAULT_PORT
	if port_str != "":
		port = int(port_str)
	_set_status("Joining %s:%d..." % [ip, port])
	GameLaunch.mode = "client"
	GameLaunch.server_ip = ip
	GameLaunch.server_port = port
	get_tree().change_scene_to_file("res://main.tscn")

func _on_exit():
	get_tree().quit()
