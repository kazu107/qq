extends Control

const CONNECTION_PANEL_WIDTH: float = 500.0
const DECK_TILE_SIZE: Vector2 = Vector2(92.0, 92.0)

@export var online_mode: bool = false

var _name_edit: LineEdit
var _address_edit: LineEdit
var _port_spin: SpinBox
var _room_code_edit: LineEdit
var _lobby_target_wins_spin: SpinBox
var _automatic_upnp_check: CheckButton
var _host_button: Button
var _join_button: Button
var _discovered_list: ItemList
var _join_discovered_button: Button
var _status_label: Label
var _connection_panel: PanelContainer
var _lobby_panel: PanelContainer
var _invite_label: Label
var _ready_count_label: Label
var _players_box: VBoxContainer
var _starter_option: OptionButton
var _starter_ids: Array[String] = []
var _deck_panel: CardHandPanel
var _ready_button: Button
var _start_button: Button
var _leave_button: Button
var _result_label: Label
var _discovered_entries: Array[Dictionary] = []
var _developer_panel: DeveloperPanel
var _opening_battle: bool = false
var _connection_busy: bool = false
var _refreshing_rules: bool = false


func _ready() -> void:
	online_mode = true
	_build_ui()
	_connect_network_signals()
	_name_edit.text = Game.get_online_player_name()
	_address_edit.text = Game.get_online_last_address()
	_port_spin.value = float(Game.get_online_port())
	_room_code_edit.text = Game.get_online_room_code()
	_automatic_upnp_check.button_pressed = false
	_status_label.text = Localization.get_text("online.status.offline", "Create a room or join with a private room code.")
	_refresh_all()
	if not NetworkManager.is_session_connected():
		NetworkManager.start_online_room_directory()
	if Game.is_developer_mode_enabled():
		_build_developer_panel()
	if NetworkManager.is_lan_arena_session_active():
		if NetworkManager.has_active_match():
			call_deferred("_open_battle_scene")
		else:
			call_deferred("_open_arena_scene")


func _exit_tree() -> void:
	if not NetworkManager.is_session_connected():
		NetworkManager.stop_online_room_directory()


func _build_ui() -> void:
	var background: ColorRect = ColorRect.new()
	background.color = Color(0.008, 0.014, 0.021, 1.0)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 44)
	margin.add_theme_constant_override("margin_top", 36)
	margin.add_theme_constant_override("margin_right", 44)
	margin.add_theme_constant_override("margin_bottom", 36)
	add_child(margin)

	var root: VBoxContainer = VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 18)
	margin.add_child(root)

	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	root.add_child(header)

	var back_button: Button = Button.new()
	back_button.name = "LanBackButton"
	back_button.text = Localization.get_text("lan.back", "Back to Hub")
	back_button.custom_minimum_size = Vector2(150.0, 42.0)
	back_button.pressed.connect(_on_back_pressed)
	header.add_child(back_button)

	var title: Label = Label.new()
	title.text = Localization.get_text("online.title", "WEB MULTIPLAYER")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.72, 0.93, 1.0, 1.0))
	header.add_child(title)

	var protocol_label: Label = Label.new()
	protocol_label.text = "PROTO %d" % LanProtocol.PROTOCOL_VERSION
	protocol_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	protocol_label.add_theme_color_override("font_color", Color(0.48, 0.68, 0.76, 1.0))
	header.add_child(protocol_label)

	_status_label = Label.new()
	_status_label.name = "LanStatusLabel"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_color_override("font_color", Color(0.72, 0.82, 0.86, 1.0))
	root.add_child(_status_label)

	var body: HBoxContainer = HBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_theme_constant_override("separation", 18)
	root.add_child(body)

	_connection_panel = _make_panel("LanConnectionPanel")
	_connection_panel.custom_minimum_size = Vector2(CONNECTION_PANEL_WIDTH, 0.0)
	body.add_child(_connection_panel)
	_build_connection_panel(_connection_panel)

	_lobby_panel = _make_panel("LanLobbyPanel")
	_lobby_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(_lobby_panel)
	_build_lobby_panel(_lobby_panel)


func _build_connection_panel(panel: PanelContainer) -> void:
	var box: VBoxContainer = _add_panel_content(panel)

	var title: Label = _make_section_title(Localization.get_text("lan.connection", "CONNECTION"))
	box.add_child(title)
	_name_edit = LineEdit.new()
	_name_edit.name = "LanPlayerNameEdit"
	_name_edit.placeholder_text = Localization.get_text("lan.player_name", "Player name")
	_name_edit.max_length = LanProtocol.MAX_NAME_LENGTH
	box.add_child(_labeled_control(Localization.get_text("lan.player_name", "Player name"), _name_edit))

	_port_spin = SpinBox.new()
	_port_spin.name = "LanPortSpin"
	_port_spin.min_value = 1024.0
	_port_spin.max_value = 65535.0
	_port_spin.step = 1.0
	_port_spin.allow_greater = false
	_port_spin.allow_lesser = false
	var port_row: HBoxContainer = _labeled_control(Localization.get_text("lan.port", "UDP port"), _port_spin)
	port_row.visible = not online_mode
	box.add_child(port_row)

	_room_code_edit = LineEdit.new()
	_room_code_edit.name = "OnlineRoomCodeEdit"
	_room_code_edit.placeholder_text = Localization.get_text("online.room_code_auto", "Leave blank to generate")
	_room_code_edit.max_length = LanProtocol.ONLINE_ROOM_CODE_LENGTH
	_room_code_edit.visible = online_mode
	var room_code_row: HBoxContainer = _labeled_control(Localization.get_text("online.room_code", "Room code"), _room_code_edit)
	room_code_row.visible = online_mode
	box.add_child(room_code_row)

	_automatic_upnp_check = CheckButton.new()
	_automatic_upnp_check.name = "OnlineAutomaticUpnpCheck"
	_automatic_upnp_check.text = Localization.get_text("online.automatic_upnp", "Open UDP port automatically (UPnP)")
	_automatic_upnp_check.visible = false
	box.add_child(_automatic_upnp_check)

	_host_button = Button.new()
	_host_button.name = "LanHostButton"
	_host_button.text = Localization.get_text("online.host", "HOST WEB ROOM")
	_host_button.custom_minimum_size = Vector2(0.0, 46.0)
	_host_button.pressed.connect(_on_host_pressed)
	box.add_child(_host_button)

	var divider: HSeparator = HSeparator.new()
	box.add_child(divider)

	_address_edit = LineEdit.new()
	_address_edit.name = "LanAddressEdit"
	_address_edit.placeholder_text = "192.168.1.10"
	_address_edit.text_submitted.connect(func(_value: String) -> void: _on_join_pressed())
	var address_row: HBoxContainer = _labeled_control(
		Localization.get_text("online.host_address", "Public IP or hostname") if online_mode else Localization.get_text("lan.host_address", "Host address"),
		_address_edit
	)
	address_row.visible = not online_mode
	box.add_child(address_row)

	_join_button = Button.new()
	_join_button.name = "LanJoinButton"
	_join_button.text = Localization.get_text("online.join", "JOIN WEB ROOM")
	_join_button.custom_minimum_size = Vector2(0.0, 46.0)
	_join_button.pressed.connect(_on_join_pressed)
	box.add_child(_join_button)

	var discovered_title: Label = _make_section_title(
		Localization.get_text("online.rooms", "PUBLIC WEB ROOMS")
		if online_mode
		else Localization.get_text("lan.discovered", "DISCOVERED ON LAN")
	)
	box.add_child(discovered_title)
	_discovered_list = ItemList.new()
	_discovered_list.name = "LanDiscoveredList"
	_discovered_list.custom_minimum_size = Vector2(0.0, 180.0)
	_discovered_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_discovered_list.item_selected.connect(_on_discovered_selected)
	_discovered_list.item_activated.connect(_on_discovered_activated)
	_discovered_list.visible = true
	box.add_child(_discovered_list)

	_join_discovered_button = Button.new()
	_join_discovered_button.name = "LanJoinDiscoveredButton"
	_join_discovered_button.text = (
		Localization.get_text("online.join_selected", "JOIN SELECTED ROOM")
		if online_mode
		else Localization.get_text("lan.join_selected", "JOIN SELECTED HOST")
	)
	_join_discovered_button.disabled = true
	_join_discovered_button.visible = true
	_join_discovered_button.pressed.connect(_on_join_discovered_pressed)
	box.add_child(_join_discovered_button)


func _build_lobby_panel(panel: PanelContainer) -> void:
	var box: VBoxContainer = _add_panel_content(panel)
	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	box.add_child(header)
	header.add_child(_make_section_title(Localization.get_text("lan.lobby", "LOBBY")))

	_ready_count_label = Label.new()
	_ready_count_label.name = "OnlineLobbyReadyCount"
	_ready_count_label.add_theme_font_size_override("font_size", 18)
	_ready_count_label.add_theme_color_override("font_color", Color(0.45, 0.94, 0.72, 1.0))
	header.add_child(_ready_count_label)

	_invite_label = Label.new()
	_invite_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_invite_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_invite_label.add_theme_color_override("font_color", Color(0.46, 0.78, 0.86, 1.0))
	header.add_child(_invite_label)

	_result_label = Label.new()
	_result_label.name = "LanLastResultLabel"
	_result_label.visible = false
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.add_theme_font_size_override("font_size", 24)
	box.add_child(_result_label)

	_players_box = VBoxContainer.new()
	_players_box.name = "LanPlayersBox"
	_players_box.add_theme_constant_override("separation", 10)
	box.add_child(_players_box)

	var divider: HSeparator = HSeparator.new()
	box.add_child(divider)

	_lobby_target_wins_spin = _create_target_wins_control("OnlineLobbyTargetWinsSpin")
	_lobby_target_wins_spin.value_changed.connect(_on_lobby_target_wins_changed)
	box.add_child(_labeled_control(
		Localization.get_text("online.target_wins", "First to wins"),
		_lobby_target_wins_spin
	))

	_starter_option = OptionButton.new()
	_starter_option.name = "LanStarterOption"
	_starter_option.item_selected.connect(_on_starter_selected)
	for starter_data in Database.starters:
		var starter_id: String = String(starter_data.get("id", ""))
		if starter_id == "":
			continue
		_starter_ids.append(starter_id)
		_starter_option.add_item(String(starter_data.get("name", starter_id)))
	box.add_child(_labeled_control(Localization.get_text("lan.starter", "Starter deck"), _starter_option))

	var deck_title: Label = _make_section_title(Localization.get_text("lan.deck", "LOADOUT PREVIEW"))
	box.add_child(deck_title)
	var deck_scroll: ScrollContainer = ScrollContainer.new()
	deck_scroll.name = "LanDeckScroll"
	deck_scroll.custom_minimum_size = Vector2(0.0, 236.0)
	deck_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(deck_scroll)

	_deck_panel = CardHandPanel.new()
	_deck_panel.name = "LanDeckPreview"
	_deck_panel.set_interactive(false)
	_deck_panel.set_tile_size(DECK_TILE_SIZE)
	deck_scroll.add_child(_deck_panel)

	var actions: HBoxContainer = HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 10)
	box.add_child(actions)

	_ready_button = Button.new()
	_ready_button.name = "LanReadyButton"
	_ready_button.custom_minimum_size = Vector2(170.0, 48.0)
	_ready_button.pressed.connect(_on_ready_pressed)
	actions.add_child(_ready_button)

	_start_button = Button.new()
	_start_button.name = "LanStartMatchButton"
	_start_button.text = Localization.get_text("lan.start_arena", "START ARENA PREPARATION")
	_start_button.custom_minimum_size = Vector2(190.0, 48.0)
	_start_button.pressed.connect(_on_start_match_pressed)
	actions.add_child(_start_button)

	_leave_button = Button.new()
	_leave_button.name = "LanLeaveButton"
	_leave_button.text = Localization.get_text("lan.leave", "LEAVE LOBBY")
	_leave_button.custom_minimum_size = Vector2(160.0, 48.0)
	_leave_button.pressed.connect(_on_leave_pressed)
	actions.add_child(_leave_button)


func _connect_network_signals() -> void:
	if not NetworkManager.connection_state_changed.is_connected(_on_connection_state_changed):
		NetworkManager.connection_state_changed.connect(_on_connection_state_changed)
	if not NetworkManager.lobby_changed.is_connected(_on_lobby_changed):
		NetworkManager.lobby_changed.connect(_on_lobby_changed)
	if not NetworkManager.discovery_changed.is_connected(_refresh_discovered_hosts):
		NetworkManager.discovery_changed.connect(_refresh_discovered_hosts)
	if not NetworkManager.online_rooms_changed.is_connected(_refresh_online_rooms):
		NetworkManager.online_rooms_changed.connect(_refresh_online_rooms)
	if not NetworkManager.network_error.is_connected(_on_network_error):
		NetworkManager.network_error.connect(_on_network_error)
	if not NetworkManager.match_started.is_connected(_on_match_started):
		NetworkManager.match_started.connect(_on_match_started)
	if not NetworkManager.arena_preparation_started.is_connected(_on_arena_preparation_started):
		NetworkManager.arena_preparation_started.connect(_on_arena_preparation_started)
	if not NetworkManager.match_finished.is_connected(_on_match_finished):
		NetworkManager.match_finished.connect(_on_match_finished)
	if not NetworkManager.session_ended.is_connected(_on_session_ended):
		NetworkManager.session_ended.connect(_on_session_ended)
	if not NetworkManager.online_host_status_changed.is_connected(_on_online_host_status_changed):
		NetworkManager.online_host_status_changed.connect(_on_online_host_status_changed)


func _refresh_all() -> void:
	var connected: bool = NetworkManager.is_session_connected()
	_connection_panel.visible = not connected
	_lobby_panel.visible = connected
	if not connected:
		_refresh_online_rooms(NetworkManager.get_online_rooms())
		if _status_label.text == "":
			_status_label.text = Localization.get_text("online.status.offline", "Create a room or join with a private room code.")
		return

	var profiles: Array[Dictionary] = NetworkManager.get_lobby_players()
	_refresh_player_slots(profiles)
	_refresh_local_profile_controls()
	_refresh_online_invite()
	_ready_count_label.text = Localization.get_textf("network.ready_count", "READY {ready}/{total}", {
		"ready": NetworkManager.get_lobby_ready_count(),
		"total": LanProtocol.MAX_PLAYERS,
	})
	_refreshing_rules = true
	_lobby_target_wins_spin.set_value_no_signal(float(NetworkManager.get_online_target_wins()))
	_lobby_target_wins_spin.editable = NetworkManager.is_host()
	_refreshing_rules = false
	_start_button.visible = NetworkManager.is_host()
	_start_button.disabled = not NetworkManager.can_start_match()
	_ready_button.disabled = NetworkManager.has_active_match()
	_refresh_last_result()


func _refresh_player_slots(players: Array[Dictionary]) -> void:
	for child in _players_box.get_children():
		_players_box.remove_child(child)
		child.queue_free()
	for slot_index in range(LanProtocol.MAX_PLAYERS):
		var player_data: Dictionary = players[slot_index] if slot_index < players.size() else {}
		_players_box.add_child(_build_player_slot(slot_index, player_data))


func _build_player_slot(slot_index: int, player_data: Dictionary) -> PanelContainer:
	var frame: PanelContainer = PanelContainer.new()
	frame.name = "LanPlayerSlot%d" % (slot_index + 1)
	frame.custom_minimum_size = Vector2(0.0, 82.0)
	frame.add_theme_stylebox_override("panel", _make_panel_style(
		Color(0.035, 0.055, 0.071, 0.94),
		Color(0.24, 0.53, 0.64, 0.80) if not player_data.is_empty() else Color(0.18, 0.25, 0.29, 0.70)
	))
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 10)
	frame.add_child(margin)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)
	var slot_label: Label = Label.new()
	slot_label.text = "P%d" % (slot_index + 1)
	slot_label.custom_minimum_size = Vector2(44.0, 0.0)
	slot_label.add_theme_font_size_override("font_size", 22)
	slot_label.add_theme_color_override("font_color", Color(0.42, 0.84, 0.95, 1.0))
	row.add_child(slot_label)
	var info: VBoxContainer = VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var name_label: Label = Label.new()
	if player_data.is_empty():
		name_label.text = Localization.get_text("lan.waiting_player", "Waiting for player...")
		name_label.add_theme_color_override("font_color", Color(0.48, 0.54, 0.58, 1.0))
	else:
		name_label.text = String(player_data.get("name", "Player"))
	name_label.add_theme_font_size_override("font_size", 19)
	info.add_child(name_label)
	var detail_label: Label = Label.new()
	if not player_data.is_empty():
		var starter_data: Dictionary = Database.get_starter(String(player_data.get("starter_id", "")))
		detail_label.text = Localization.get_textf("lan.player_detail", "{starter} | {cards} cards | {ping} ms", {
			"starter": String(starter_data.get("name", player_data.get("starter_id", ""))),
			"cards": int(player_data.get("deck_count", 0)),
			"ping": int(player_data.get("ping_ms", 0)),
		})
	detail_label.add_theme_color_override("font_color", Color(0.62, 0.71, 0.75, 1.0))
	info.add_child(detail_label)
	var ready_label: Label = Label.new()
	ready_label.custom_minimum_size = Vector2(120.0, 0.0)
	ready_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ready_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if player_data.is_empty():
		ready_label.text = "---"
	elif bool(player_data.get("ready", false)):
		ready_label.text = Localization.get_text("lan.ready", "READY")
		ready_label.add_theme_color_override("font_color", Color(0.30, 1.0, 0.62, 1.0))
	else:
		ready_label.text = Localization.get_text("lan.not_ready", "NOT READY")
		ready_label.add_theme_color_override("font_color", Color(1.0, 0.64, 0.30, 1.0))
	row.add_child(ready_label)
	return frame


func _refresh_local_profile_controls() -> void:
	var profile: Dictionary = NetworkManager.get_local_profile()
	var starter_id: String = String(profile.get("starter_id", ""))
	for index in range(_starter_ids.size()):
		if _starter_ids[index] == starter_id:
			_starter_option.select(index)
			break
	var is_ready: bool = NetworkManager.is_local_ready()
	_starter_option.disabled = is_ready
	_ready_button.text = Localization.get_text("lan.cancel_ready", "CANCEL READY") if is_ready else Localization.get_text("lan.ready_up", "READY UP")
	var deck: Array[String] = []
	for raw_card_id in Array(profile.get("deck", [])):
		deck.append(String(raw_card_id))
	var run_state: RunState = LanProtocol.profile_to_run(profile, 1)
	_deck_panel.refresh_card_ids(deck, false, "WEB", run_state)


func _refresh_last_result() -> void:
	var result: Dictionary = NetworkManager.get_last_match_result()
	_result_label.visible = not result.is_empty()
	if result.is_empty():
		return
	var winner: String = String(result.get("winner", "draw"))
	if winner == "draw":
		_result_label.text = Localization.get_text("lan.result.draw", "LAST MATCH: DRAW")
		_result_label.add_theme_color_override("font_color", Color(0.84, 0.86, 0.88, 1.0))
	elif winner == NetworkManager.get_local_side():
		_result_label.text = Localization.get_text("lan.result.win", "LAST MATCH: VICTORY")
		_result_label.add_theme_color_override("font_color", Color(0.32, 1.0, 0.64, 1.0))
	else:
		_result_label.text = Localization.get_text("lan.result.loss", "LAST MATCH: DEFEAT")
		_result_label.add_theme_color_override("font_color", Color(1.0, 0.42, 0.34, 1.0))


func _refresh_discovered_hosts(hosts: Array[Dictionary]) -> void:
	if online_mode:
		return
	_discovered_entries = hosts.duplicate(true)
	_discovered_list.clear()
	for host_data in _discovered_entries:
		_discovered_list.add_item("%s   %d/%d   %s:%d" % [
			String(host_data.get("name", "LAN Host")),
			int(host_data.get("players", 1)),
			int(host_data.get("max_players", 2)),
			String(host_data.get("address", "")),
			int(host_data.get("port", LanProtocol.DEFAULT_PORT)),
		])
	_join_discovered_button.disabled = _discovered_entries.is_empty()


func _refresh_online_rooms(rooms: Array[Dictionary]) -> void:
	if not online_mode:
		return
	_discovered_entries = rooms.duplicate(true)
	_discovered_list.clear()
	if _discovered_entries.is_empty():
		_discovered_list.add_item(Localization.get_text("online.rooms.empty", "No compatible rooms are open."))
		_discovered_list.set_item_disabled(0, true)
		_join_discovered_button.disabled = true
		return
	for room_data in _discovered_entries:
		var joinable: bool = bool(room_data.get("joinable", false))
		var room_text: String = Localization.get_textf(
			"online.room.entry",
			"{host} | {players}/{max_players} | First to {target} | {code}",
			{
				"host": String(room_data.get("hostName", "Web Host")),
				"players": int(room_data.get("players", 1)),
				"max_players": int(room_data.get("maxPlayers", LanProtocol.MAX_PLAYERS)),
				"target": int(room_data.get("targetWins", ArenaService.TARGET_WINS)),
				"code": String(room_data.get("code", "")),
			}
		)
		if not joinable:
			room_text += " | %s" % Localization.get_text("online.room.full", "FULL")
		_discovered_list.add_item(room_text)
		_discovered_list.set_item_disabled(_discovered_list.item_count - 1, not joinable)
	_join_discovered_button.disabled = true


func _on_host_pressed() -> void:
	if _connection_busy:
		return
	_set_connection_busy(true)
	_save_preferences()
	_status_label.text = Localization.get_text("online.status.hosting", "Opening Web room...")
	var hosted: bool = NetworkManager.host_online_lobby(
		_name_edit.text,
		_default_starter_id(),
		_room_code_edit.text,
		int(_port_spin.value),
		false
	)
	if hosted:
		_room_code_edit.text = NetworkManager.get_online_room_code()
	if not hosted:
		AudioManager.play_sfx("ui_error")
	_set_connection_busy(false)
	_refresh_all()


func _on_join_pressed() -> void:
	if _connection_busy:
		return
	_set_connection_busy(true)
	_save_preferences()
	_status_label.text = Localization.get_text("online.status.connecting", "Joining Web room...")
	var joined: bool = NetworkManager.join_online_lobby(
		"",
		_name_edit.text,
		_default_starter_id(),
		_room_code_edit.text,
		int(_port_spin.value)
	)
	if not joined:
		AudioManager.play_sfx("ui_error")
	_set_connection_busy(false)
	_refresh_all()


func _on_discovered_selected(index: int) -> void:
	if index < 0 or index >= _discovered_entries.size():
		return
	var host_data: Dictionary = _discovered_entries[index]
	if online_mode:
		_room_code_edit.text = String(host_data.get("code", ""))
		_join_discovered_button.disabled = not bool(host_data.get("joinable", false))
		return
	_address_edit.text = String(host_data.get("address", "127.0.0.1"))
	_port_spin.value = float(host_data.get("port", LanProtocol.DEFAULT_PORT))
	_join_discovered_button.disabled = false


func _on_discovered_activated(index: int) -> void:
	if index < 0 or index >= _discovered_entries.size():
		return
	if online_mode and not bool(_discovered_entries[index].get("joinable", false)):
		return
	_on_discovered_selected(index)
	_on_join_pressed()


func _on_join_discovered_pressed() -> void:
	var selected: PackedInt32Array = _discovered_list.get_selected_items()
	if selected.is_empty():
		return
	_on_discovered_selected(int(selected[0]))
	_on_join_pressed()


func _on_starter_selected(index: int) -> void:
	if index < 0 or index >= _starter_ids.size():
		return
	NetworkManager.set_local_starter(_starter_ids[index])
	_refresh_all()


func _on_lobby_target_wins_changed(value: float) -> void:
	if _refreshing_rules or not NetworkManager.is_host():
		return
	NetworkManager.set_online_target_wins(int(value))
	_refresh_all()


func _on_ready_pressed() -> void:
	NetworkManager.set_local_ready(not NetworkManager.is_local_ready())
	_refresh_all()


func _on_start_match_pressed() -> void:
	if not NetworkManager.start_lan_arena_preparation():
		AudioManager.play_sfx("ui_error")


func _on_leave_pressed() -> void:
	NetworkManager.leave_session("left_lobby")
	_refresh_all()


func _on_back_pressed() -> void:
	if NetworkManager.is_session_connected():
		NetworkManager.leave_session("returned_to_hub")
	SceneRouter.go_to_hub()


func _on_connection_state_changed(_state: int, message: String) -> void:
	_status_label.text = message
	_refresh_all()
	if not NetworkManager.is_session_connected() and NetworkManager.get_connection_state() == NetworkManager.ConnectionState.OFFLINE:
		call_deferred("_restart_online_directory")


func _on_lobby_changed(_snapshot: Dictionary) -> void:
	_refresh_all()


func _on_network_error(_code: String, message: String) -> void:
	_status_label.text = message
	_status_label.add_theme_color_override("font_color", Color(1.0, 0.44, 0.36, 1.0))
	AudioManager.play_sfx("ui_error")
	_refresh_all()
	call_deferred("_restart_online_directory")


func _on_match_started(_payload: Dictionary) -> void:
	if _opening_battle:
		return
	_opening_battle = true
	call_deferred("_open_battle_scene")


func _on_arena_preparation_started(_snapshot: Dictionary) -> void:
	if _opening_battle:
		return
	_opening_battle = true
	call_deferred("_open_arena_scene")


func _open_battle_scene() -> void:
	SceneRouter.go_to_battle()


func _open_arena_scene() -> void:
	SceneRouter.go_to_arena()


func _on_match_finished(_result: Dictionary) -> void:
	_refresh_all()


func _on_session_ended(_reason: String) -> void:
	_opening_battle = false
	_refresh_all()
	call_deferred("_restart_online_directory")


func _save_preferences() -> void:
	Game.set_online_preferences(
		_name_edit.text,
		"",
		_room_code_edit.text,
		int(_port_spin.value),
		false
	)


func _on_online_host_status_changed(status: Dictionary) -> void:
	if not online_mode or not NetworkManager.is_host():
		return
	var state: String = String(status.get("state", ""))
	match state:
		"relay":
			_status_label.text = Localization.get_text("online.status.relay", "Web room is ready. Share the room code privately.")
		"opening":
			_status_label.text = Localization.get_text("online.status.upnp_opening", "Opening the router's UDP port with UPnP...")
		"open":
			_status_label.text = Localization.get_text("online.status.ready", "UPnP port mapping succeeded. Share the address and room code privately, then verify the connection from another network.")
		"manual":
			_status_label.text = Localization.get_text("online.status.manual", "Forward the selected UDP port on your router, then share your public IP and room code.")
		"failed":
			_status_label.text = Localization.get_text("online.status.upnp_failed", "Automatic port forwarding failed. Forward the selected UDP port manually; CGNAT connections require a relay or public IPv6.")
	_refresh_online_invite()


func _refresh_online_invite() -> void:
	if _invite_label == null:
		return
	_invite_label.text = Localization.get_textf("online.invite", "WEB ROOM | Code {code}", {
		"code": NetworkManager.get_online_room_code(),
	})


func _set_connection_busy(busy: bool) -> void:
	_connection_busy = busy
	_host_button.disabled = busy
	_join_button.disabled = busy
	_room_code_edit.editable = not busy


func _restart_online_directory() -> void:
	if online_mode and not NetworkManager.is_session_connected():
		NetworkManager.start_online_room_directory()


func _create_target_wins_control(control_name: String) -> SpinBox:
	var spin: SpinBox = SpinBox.new()
	spin.name = control_name
	spin.min_value = NetworkManager.ONLINE_MIN_TARGET_WINS
	spin.max_value = NetworkManager.ONLINE_MAX_TARGET_WINS
	spin.step = 1.0
	spin.value = ArenaService.TARGET_WINS
	spin.allow_greater = false
	spin.allow_lesser = false
	return spin


func _default_starter_id() -> String:
	if not _starter_ids.is_empty():
		return _starter_ids[0]
	return "balanced"


func _build_developer_panel() -> void:
	_developer_panel = DeveloperPanel.new()
	add_child(_developer_panel)
	_developer_panel.pin_top_right()
	_developer_panel.configure(
		Localization.get_text("developer.title", "Developer Mode"),
		[
			{"id": "DevWebDisconnect", "label": Localization.get_text("lan.dev.disconnect", "Drop remote peer"), "callback": Callable(self, "_on_dev_disconnect")},
			{"id": "DevWebLeave", "label": Localization.get_text("lan.leave", "Leave lobby"), "callback": Callable(self, "_on_leave_pressed")},
		],
		Localization.get_text("online.dev.summary", "WebRTC connection test controls.")
	)


func _on_dev_disconnect() -> void:
	if not NetworkManager.developer_disconnect_peer():
		AudioManager.play_sfx("ui_error")


func _make_panel(node_name: String) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.name = node_name
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(
		Color(0.018, 0.029, 0.039, 0.96),
		Color(0.20, 0.45, 0.56, 0.78)
	))
	return panel


func _add_panel_content(panel: PanelContainer) -> VBoxContainer:
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var box: VBoxContainer = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	scroll.add_child(box)
	return box


func _labeled_control(label_text: String, control: Control) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var label: Label = Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(130.0, 0.0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


func _make_section_title(text_value: String) -> Label:
	var label: Label = Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(0.58, 0.86, 0.94, 1.0))
	return label


func _make_panel_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(16)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.36)
	style.shadow_size = 10
	style.shadow_offset = Vector2(0.0, 4.0)
	return style
