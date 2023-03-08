extends MultiplayerPeerExtension
class_name MultiplayerPeerSteam

const MAX_PACKETS_READ_PER_POLL := 16

class Packet:
	var sender: int
	var data: PackedByteArray

var _lobby_id: int
var _status: ConnectionStatus
var _packets: Array[Packet]

var _transfer_mode: TransferMode
var _transfer_channel: int
var _target_peer: int
var _refuse_new_connections: bool

var _steam_id_to_peer_id := {}
var _peer_id_to_steam_id := {}

func _init() -> void:
	Steam.connect("p2p_session_request", Callable(self, "_on_p2p_session_request"))
	Steam.connect("p2p_session_connect_fail", Callable(self, "_on_p2p_session_fail"))
	Steam.connect("lobby_chat_update", Callable(self, "_on_lobby_chat_update"))

func _on_p2p_session_request(id: int):
	if _refuse_new_connections:
		prints("Refusing P2P session request from %d" % id)
	else:
		prints("Accepting P2P session request from %d" % id)
		Steam.acceptP2PSessionWithUser(id)

func _on_p2p_session_fail(id: int, _err: int):
	prints("P2P session with %d failed: %s" % [id, Steam.getAPICallFailureReason()])

func _on_lobby_chat_update(lobby_id: int, steam_id: int, _making_change_id: int, chat_state: int) -> void:
	if lobby_id != _lobby_id:
		prints("Lobby change notification for lobby %d (my lobby is %d)" % [lobby_id, _lobby_id])
		return
	var peer_id := _convert_steam_to_peer_id(steam_id)
	_steam_id_to_peer_id[steam_id] = peer_id
	_peer_id_to_steam_id[peer_id] = steam_id
	match chat_state:
		Steam.CHAT_MEMBER_STATE_CHANGE_ENTERED:
			emit_signal("peer_connected", peer_id)
		Steam.CHAT_MEMBER_STATE_CHANGE_DISCONNECTED:
			emit_signal("peer_disconnected", peer_id)
		Steam.CHAT_MEMBER_STATE_CHANGE_LEFT:
			emit_signal("peer_disconnected", peer_id)
		Steam.CHAT_MEMBER_STATE_CHANGE_KICKED:
			emit_signal("peer_disconnected", peer_id)

func _convert_steam_to_peer_id(steam_id: int) -> int:
	# Assume the lobby owner is the host
	if steam_id == Steam.getLobbyOwner(_lobby_id):
		return TARGET_PEER_SERVER
	# Steam IDs are uint64s, but godot peer IDs must be >0 and <2147483647 (positive int32)
	# We add 2 to avoid assigning 1 to anyone who is not the host
	# There is, of course, as small chance of a collision with this scheme
	# A more clever implementation could have the server assign and distribute truly unique IDs
	return 2 + (steam_id % 2147483647)

func join_lobby(lobby_id: int):
	_status = CONNECTION_CONNECTING
	Steam.joinLobby(lobby_id)
	# res: [lobby_id, permissions, locked, response]
	var res: Array = await Steam.lobby_joined
	if res[3] != 1:
		_status = CONNECTION_DISCONNECTED
		push_error("Failed to join steam lobby %d: %s" % [lobby_id, Steam.getAPICallFailureReason()])
		return
	_lobby_id = res[0]
	prints("My ID %d Lobby owner %d" % [Steam.getSteamID(), Steam.getLobbyOwner(lobby_id)])
	_status = CONNECTION_CONNECTED
	prints("Connected to steam lobby %d" % _lobby_id)
	for i in Steam.getNumLobbyMembers(_lobby_id):
		var steam_id := Steam.getLobbyMemberByIndex(_lobby_id, i)
		if steam_id != Steam.getSteamID():
			var peer_id: int = _steam_id_to_peer_id[steam_id]
			emit_signal("peer_connected", peer_id)

func _close() ->  void:
	pass

func _disconnect_peer(_p_peer: int, _p_force: bool) ->  void:
	pass

func _get_available_packet_count() ->  int:
	return _packets.size()

func _get_connection_status() ->  ConnectionStatus:
	return _status

func _get_max_packet_size() ->  int:
	return 4096

func _get_packet_peer() ->  int:
	return _packets.front().size()

func _get_packet_script() ->  PackedByteArray:
	var data := _packets[0].data
	_packets.pop_front()
	return data

func _get_transfer_channel() ->  int:
	return _transfer_channel

func _get_transfer_mode() ->  TransferMode:
	return _transfer_mode

func _get_unique_id() ->  int:
	return _steam_id_to_peer_id[Steam.getSteamID()]

func _is_refusing_new_connections() ->  bool:
	return false

func _is_server() ->  bool:
	return Steam.getSteamID() == Steam.getLobbyOwner(_lobby_id)

func _poll() ->  void:
	for _i in range(MAX_PACKETS_READ_PER_POLL):
		var size := Steam.getAvailableP2PPacketSize()
		if size <= 0:
			break
		var packet := Packet.new()
		var packet_info := Steam.readP2PPacket(size)
		packet.peer_id = _steam_id_to_peer_id[packet_info.steam_id_remote]
		packet.data = packet_info.data
		_packets.push_back(packet)

func _put_packet_script(p_buffer : PackedByteArray) ->  Error:
	var mode := Steam.P2P_SEND_RELIABLE if _transfer_mode == TRANSFER_MODE_RELIABLE else Steam.P2P_SEND_UNRELIABLE
	if _target_peer == TARGET_PEER_BROADCAST:
		for i in range(Steam.getNumLobbyMembers(_lobby_id)):
			var steam_id := Steam.getLobbyMemberByIndex(_lobby_id, i)
			Steam.sendP2PPacket(steam_id, p_buffer, mode)
	else:
		var steam_id: int = _steam_id_to_peer_id[_target_peer]
		Steam.sendP2PPacket(steam_id, p_buffer, mode)

	return OK

func _set_refuse_new_connections(p_enable : bool) ->  void:
	_refuse_new_connections = p_enable

func _set_target_peer(p_peer: int) ->  void:
	_target_peer = p_peer

func _set_transfer_channel(p_channel: int) ->  void:
	_transfer_channel = p_channel

func _set_transfer_mode(p_mode: TransferMode) -> void:
	_transfer_mode = p_mode
