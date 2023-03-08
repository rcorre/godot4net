extends Node

const LOBBY_MAX_MEMBERS := 10

func _ready() -> void:
	if not Steam.isSteamRunning():
		prints("Steam not running")
		return

	var res := Steam.steamInit()
	if res.status != 1:
		prints("Failed to initialize steam: %s" % res.verbal)
		set_physics_process(false)
		return

	prints("Steam initialized: %s" % res)

# Join an available lobby if there is one, else host a new one
# Returns the lobby ID async
func find_or_create_lobby(lobby_name: String) -> int:
	prints("Searching for lobbies")
	Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_DEFAULT)
	Steam.addRequestLobbyListStringFilter("name", lobby_name, Steam.LOBBY_COMPARISON_EQUAL)
	Steam.requestLobbyList()

	var lobbies: Array = await Steam.lobby_match_list
	if lobbies.is_empty():
		prints("No lobby named %s found, creating one" % lobby_name)
		return await create_lobby(lobby_name)
	var id: int = lobbies[0]
	prints("Found lobby %d" % id)
	return id

# Returns the ID of the created lobby, or 0 if it failed
func create_lobby(lobby_name: String) -> int:
	Steam.createLobby(Steam.LOBBY_TYPE_PUBLIC, LOBBY_MAX_MEMBERS)
	# res: [response, lobby_id]
	var res: Array = await Steam.lobby_created
	if res[0] != 1:
		prints("Failed to create steam lobby: %s" % Steam.getAPICallFailureReason())
		return 0
	var id: int = res[1]
	prints("Created steam lobby: %d" % id)
	Steam.setLobbyJoinable(id, true)
	Steam.setLobbyData(id, "name", lobby_name)
	if Steam.allowP2PPacketRelay(true):
		prints("Enabled steam relay backup")
	else:
		prints("Steam relay backup unavailable")
	return id

func _physics_process(_delta: float) -> void:
	Steam.run_callbacks()
