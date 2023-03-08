extends Node

const MAX_PLAYERS := 2

func host():
	prints("Hosting")
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(43523, MAX_PLAYERS)
	if err != OK:
		push_error("Failed to host")
		return
	get_tree().get_multiplayer().set_multiplayer_peer(peer)

func join():
	prints("Joining")
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client("127.0.0.1", 43523)
	if err:
		push_error("Failed to join")
		return
	get_tree().get_multiplayer().set_multiplayer_peer(peer)

@rpc("any_peer") func hello(msg: String):
	prints(multiplayer.get_unique_id(), "got", msg, "from", multiplayer.get_remote_sender_id())

class QuitHandler:
	extends Node

	func _unhandled_key_input(event: InputEvent) -> void:
		if event and event.keycode == KEY_ESCAPE:
			get_tree().quit()

func _ready():
	var args := OS.get_cmdline_args()
	if len(args) < 2:
		push_error("Usage: godot QuickStart.tscn host [mode] [level]|join")
		get_tree().quit()
		return

	match args[1]:
		"steam":
			var lobby_id := await SteamAPI.find_or_create_lobby("RRC Test Lobby")
			var peer := MultiplayerPeerSteam.new()
			peer.join_lobby(lobby_id)
			get_tree().get_multiplayer().set_multiplayer_peer(peer)
		"host":
			host()
			prints("Hosted, waiting for client")
		"join":
			join()
			await multiplayer.connected_to_server
			prints("Server connected, starting game")
			rpc_id(1, "hello", "hello")
		_:
			push_error("Usage: godot QuickStart.tscn host|join")
			get_tree().quit()

	multiplayer.connect("peer_connected", func(id): prints(multiplayer.get_unique_id(), ": got connection from: ", id))
	multiplayer.connect("peer_disconnected", func(id): prints(multiplayer.get_unique_id(), ": got disconnect from: ", id))

	await get_tree().process_frame
	get_tree().root.add_child(QuitHandler.new())
