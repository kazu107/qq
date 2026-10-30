extends Control

const DEBUG_CARD_SLOT_COUNT := 6
const LOGO: Texture2D = preload("res://assets/branding/queuequest-logo.svg")

var _info_label: Label
var _developer_panel: DeveloperPanel
var _debug_enemy_option: OptionButton
var _debug_starter_option: OptionButton
var _debug_card_options: Array[CardIconPicker] = []
var _debug_card_grade_options: Array[OptionButton] = []
var _version_history_overlay: ColorRect
var _version_history_content: RichTextLabel
var _account_button: Button
var _ranked_start_button: Button
var _ranking_status_label: Label
var _cloud_status_label: Label
var _settings_dialog: SettingsDialog
var _settings_language: String
var _settings_developer: bool
var _meta_snapshot: String
var _achievement_notification: Panel


func _ready() -> void:
	Game.stash_active_run_for_hub()
	AccountSession.changed.connect(_refresh_account_button)
	AccountSession.changed.connect(_refresh_ranking_access)
	RankedSession.changed.connect(_refresh_ranking_status)
	RankedSession.changed.connect(_refresh_ranking_access)
	CloudSession.changed.connect(_refresh_cloud_status)
	CloudSession.changed.connect(_refresh_achievement_notification)
	SaveManager.profile_saved.connect(_on_profile_saved)
	Game.meta_achievement_claimed.connect(_refresh_achievement_notification)
	_build_ui()
	AccountSession.refresh()


func _build_ui() -> void:
	_build_top_right_actions()
	var margin: MarginContainer = MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.offset_left = 80.0
	margin.offset_top = 110.0
	margin.offset_right = -80.0
	margin.offset_bottom = -60.0
	add_child(margin)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "HubContentScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var center: CenterContainer = CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var root: VBoxContainer = VBoxContainer.new()
	root.name = "HubModeSelection"
	root.custom_minimum_size = Vector2(1320.0, 0.0)
	root.add_theme_constant_override("separation", 24)
	center.add_child(root)
	var hero: HBoxContainer = HBoxContainer.new()
	hero.add_theme_constant_override("separation", 32)
	root.add_child(hero)
	var identity: VBoxContainer = VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.add_theme_constant_override("separation", 10)
	hero.add_child(identity)
	var logo: TextureRect = TextureRect.new()
	logo.name = "HubLogo"
	logo.texture = LOGO
	logo.custom_minimum_size = Vector2(520.0, 140.0)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	logo.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	identity.add_child(logo)

	_info_label = Label.new()
	_info_label.name = "HubMetaPoints"
	_info_label.add_theme_font_size_override("font_size", 24)
	_info_label.add_theme_color_override("font_color", UiTheme.ACCENT_GOLD)
	_info_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_info_label.text = Localization.get_textf("hub.meta_points", "Meta Points: {points}", {
		"points": Game.get_meta_points(),
	})
	_info_label.tooltip_text = _info_label.text
	_info_label.text = str(Game.get_meta_points())
	var points_row: HBoxContainer = HBoxContainer.new()
	points_row.name = "HubMetaPointBadge"
	points_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hero.add_child(points_row)
	var points_icon: TextureRect = TextureRect.new()
	points_icon.texture = StatIconFactory.get_icon("meta_points")
	points_icon.custom_minimum_size = Vector2(32, 32)
	points_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	points_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	points_icon.tooltip_text = UiIconHelper.get_hint("meta_points")
	points_row.add_child(points_icon)
	points_row.add_child(_info_label)
	if SaveManager.last_recovery_source != "":
		var recovery_label: Label = Label.new()
		recovery_label.name = "SaveRecoveryNotice"
		recovery_label.text = Localization.get_text(
			"save.recovered_notice",
			"The latest save could not be read. Progress was restored from a backup."
		)
		recovery_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		recovery_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		recovery_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.28))
		root.add_child(recovery_label)
		SaveManager.last_recovery_source = ""

	var modes: GridContainer = GridContainer.new()
	modes.name = "HubModeGrid"
	modes.columns = 3 if Game.WEB_MULTIPLAYER_ENABLED else 2
	modes.add_theme_constant_override("h_separation", 18)
	modes.add_theme_constant_override("v_separation", 18)
	root.add_child(modes)
	var normal: VBoxContainer = _build_mode_card(modes, "step", Localization.get_text("hub.run_start", "Run Start"), Localization.get_text("hub.mode.normal_detail", "Choose a route, gather cards and relics, and challenge the boss."), UiTheme.ACCENT_GOLD)
	_add_run_mode_row(normal, Game.RUN_SETUP_MODE_NORMAL)
	var arena: VBoxContainer = _build_mode_card(modes, "arena", Localization.get_text("hub.arena_start", "Arena Mode"), Localization.get_text("hub.mode.arena_detail", "Build your deck between matches. Every purchase shapes the next battle."), UiTheme.ACCENT_BLUE)
	_add_run_mode_row(arena, Game.RUN_SETUP_MODE_ARENA)

	if Game.WEB_MULTIPLAYER_ENABLED:
		var online: VBoxContainer = _build_mode_card(modes, "online", Localization.get_text("hub.web_multiplayer", "Web Multiplayer"), Localization.get_text("hub.mode.online_detail", "Create a room, invite friends, and compete or spectate together."), Color(0.35, 0.82, 0.70))
		var online_button: Button = Button.new()
		online_button.name = "WebMultiplayerButton"
		online_button.text = Localization.get_text("hub.open_rooms", "Open Rooms")
		online_button.custom_minimum_size.y = 54.0
		online_button.pressed.connect(func() -> void:
			Game.current_screen_hint = "online"
			SceneRouter.go_to_online_lobby()
		)
		online.add_child(online_button)

	if Game.is_infinite_mode_unlocked():
		var infinite: VBoxContainer = _build_mode_card(modes, "infinity", Localization.get_text("hub.infinite_mode", "Infinite Mode"), Localization.get_text("hub.mode.infinite_detail", "Push beyond the final step into an ever-growing challenge."), UiTheme.ACCENT_GOLD)
		var infinite_button: Button = Button.new()
		infinite_button.name = "InfiniteModeStartButton"
		infinite_button.text = Localization.get_text("hub.infinite_mode", "Infinite Mode")
		infinite_button.pressed.connect(_on_start_infinite_mode)
		infinite_button.custom_minimum_size.y = 54.0
		infinite.add_child(infinite_button)

	var navigation: HBoxContainer = HBoxContainer.new()
	navigation.name = "HubCollectionActions"
	navigation.add_theme_constant_override("separation", 18)
	root.add_child(navigation)
	var tutorial_button: Button = Button.new()
	tutorial_button.name = "BattleTutorialButton"
	tutorial_button.text = Localization.get_text("hub.tutorial", "Battle Tutorial")
	tutorial_button.pressed.connect(_on_open_battle_tutorial)
	_setup_navigation_button(navigation, tutorial_button, "tutorial")

	var meta_button: Button = Button.new()
	meta_button.name = "HubMetaProgressButton"
	meta_button.text = Localization.get_text("hub.meta_progress", "Meta Progress")
	meta_button.pressed.connect(_on_open_meta_progress)
	_setup_navigation_button(navigation, meta_button, "meta_points")
	_build_achievement_notification(meta_button)

	var library_button: Button = Button.new()
	library_button.name = "HubCardLibraryButton"
	library_button.text = Localization.get_text("hub.card_library", "Card & Relic Library")
	library_button.pressed.connect(_on_open_card_library)
	_setup_navigation_button(navigation, library_button, "card_owned")
	var sandbox_button: Button = Button.new()
	sandbox_button.name = "SandboxModeButton"
	sandbox_button.text = "サンドボックス" if Localization.get_language() == "ja" else "Sandbox"
	sandbox_button.disabled = NetworkManager.is_session_connected()
	sandbox_button.pressed.connect(SceneRouter.go_to_sandbox)
	_setup_navigation_button(navigation,sandbox_button,"arena")

	_build_version_history_overlay()
	_build_ranking_actions(root)

	if Game.is_developer_mode_enabled():
		_build_debug_battle_lab(root)
		_build_developer_panel()
		call_deferred("_warm_debug_card_pickers")
	_refresh_account_button()
	SceneRouter.mark_ui_localized(self)


func _build_achievement_notification(button: Button) -> void:
	_achievement_notification = Panel.new()
	_achievement_notification.name = "HubAchievementNotification"
	_achievement_notification.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_achievement_notification.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_achievement_notification.offset_left = -28.0
	_achievement_notification.offset_top = -5.0
	_achievement_notification.offset_right = -6.0
	_achievement_notification.offset_bottom = 17.0
	_achievement_notification.z_index = 2
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color("d3444f")
	style.border_color = Color("ffe6b6")
	style.set_border_width_all(2)
	style.set_corner_radius_all(11)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.4)
	style.shadow_size = 3
	_achievement_notification.add_theme_stylebox_override("panel", style)
	var mark: Label = Label.new()
	mark.text = "!"
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mark.add_theme_font_size_override("font_size", 14)
	mark.add_theme_color_override("font_color", Color.WHITE)
	_achievement_notification.add_child(mark)
	button.add_child(_achievement_notification)
	_refresh_achievement_notification()


func _refresh_achievement_notification() -> void:
	if not is_instance_valid(_achievement_notification): return
	var count: int = Game.get_claimable_achievement_count()
	_achievement_notification.visible = count > 0
	_achievement_notification.set_meta("claimable_count", count)
	var button: Button = _achievement_notification.get_parent() as Button
	button.tooltip_text = Localization.get_textf("hub.achievement_notification", "{count} achievements have rewards ready to claim.", {"count":count}) if count > 0 else ""


func _on_profile_saved(_profile: String) -> void:
	_refresh_achievement_notification()


func _build_ranking_actions(parent: Control) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.name = "HubRankingActions"
	row.add_theme_constant_override("separation", 14)
	parent.add_child(row)
	var view: Button = Button.new()
	view.name = "HubRankingsButton"
	view.text = "無限ランキング" if Localization.get_language() == "ja" else "Infinite Rankings"
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.custom_minimum_size.y = 50
	view.pressed.connect(RankedSession.open_board)
	row.add_child(view)
	var start: Button = Button.new()
	_ranked_start_button = start
	start.name = "HubRankedStartButton"
	start.text = "ランキングに挑戦" if Localization.get_language() == "ja" else "Ranked Infinite"
	start.tooltip_text = "ログインが必要です。永続強化なし・全カードと遺物共通。"
	start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start.disabled = not RankedSession.is_supported() or not AccountSession.is_supported() or not bool(AccountSession.snapshot.get("authenticated", false)) or bool(AccountSession.snapshot.get("needsUsername", false))
	start.pressed.connect(func() -> void:
		SceneRouter.go_to_run_setup(Game.RUN_SETUP_MODE_RANKED)
	)
	row.add_child(start)
	if Game.has_suspended_run(Game.RUN_SETUP_MODE_RANKED):
		var resume: Button = Button.new()
		resume.name = "HubRankedResumeButton"
		resume.text = "ランキングの続き" if Localization.get_language() == "ja" else "Continue Ranked"
		resume.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		resume.pressed.connect(func() -> void:
			if await RankedSession.resume_saved(): SceneRouter.go_to_continue_target()
		)
		row.add_child(resume)
		var retire: Button = Button.new()
		retire.name = "HubRankedRetireButton"
		retire.text = "挑戦を終了・送信" if Localization.get_language() == "ja" else "Finish & Submit"
		retire.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		retire.pressed.connect(func() -> void:
			if not await RankedSession.resume_saved(): return
			if RankedSession.engine != null:
				RankedSession.status_text = "戦闘を完了してから記録を確定してください"
				SceneRouter.go_to_continue_target()
				return
			Game.current_run.run_complete = true
			RankedSession.finish()
			SceneRouter.go_to_result()
		)
		row.add_child(retire)
	var status: Label = Label.new()
	_ranking_status_label = status
	status.name = "RankingSyncStatus"
	status.text = RankedSession.status_text
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(status)
	_refresh_ranking_status()
	RankedSession.refresh_availability.call_deferred()
	_refresh_ranking_access()
	_cloud_status_label = Label.new()
	_cloud_status_label.name = "CloudSaveStatus"
	_cloud_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cloud_status_label.add_theme_font_size_override("font_size", 16)
	parent.add_child(_cloud_status_label)
	_refresh_cloud_status()


func _refresh_cloud_status() -> void:
	if not is_instance_valid(_cloud_status_label): return
	_cloud_status_label.visible = CloudSession.initialized
	var ja: bool = Localization.get_language() == "ja"
	var dirty: bool = bool(SaveManager.profile_meta.get("dirty", false))
	var message: String = "クラウド同期済み" if ja else "Cloud synchronized"
	if CloudSession.state == "guest": message = "ゲストの進行はこの端末のみ" if ja else "Guest progress is saved on this device only"
	elif CloudSession.state == "offline": message = "オフライン・進行は端末に保留中" if ja else "Offline; changes retained on this device"
	elif CloudSession.state != "ready": message = "アカウント画面で保存データを確認してください" if ja else "Check save data in your account panel"
	elif dirty: message = "クラウドへ送信待ち" if ja else "Cloud upload pending"
	_cloud_status_label.text = message
	_cloud_status_label.modulate = UiTheme.ACCENT_GOLD if dirty or CloudSession.state != "ready" else Color(0.4, 0.88, 0.7)


func _refresh_ranking_access() -> void:
	if is_instance_valid(_ranked_start_button):
		_ranked_start_button.disabled = RankedSession.availability_status != "active" or not RankedSession.is_supported() or not AccountSession.is_supported() or not bool(AccountSession.snapshot.get("authenticated", false)) or bool(AccountSession.snapshot.get("needsUsername", false))
		_ranked_start_button.text = ("ランキング準備中" if Localization.get_language() == "ja" else "Rankings Preparing") if RankedSession.availability_status == "preparing" else ("ランキングに挑戦" if Localization.get_language() == "ja" else "Ranked Infinite")
	for name_text: String in ["HubRankedResumeButton", "HubRankedRetireButton"]:
		var button: Button = find_child(name_text, true, false) as Button
		if button != null: button.disabled = RankedSession.availability_status != "active"


func _refresh_ranking_status() -> void:
	if not is_instance_valid(_ranking_status_label): return
	if RankedSession.availability_status == "preparing":
		_ranking_status_label.text = "ランキング準備中 / シーズン1は未開始" if Localization.get_language() == "ja" else "Rankings preparing / Season 1 has not started"
	else:
		_ranking_status_label.text = RankedSession.status_text


func _build_mode_card(parent: GridContainer, icon_id: String, title_text: String, description: String, accent: Color) -> VBoxContainer:
	var box: VBoxContainer = UiTheme.add_section(parent, "")
	var panel: PanelContainer = box.get_parent() as PanelContainer
	panel.custom_minimum_size = Vector2(410.0, 180.0)
	panel.tooltip_text = description
	var style: StyleBoxFlat = UiTheme.get_game_theme().get_stylebox("panel", "SectionPanel").duplicate() as StyleBoxFlat
	style.border_color = Color(accent, 0.55)
	style.border_width_top = 3
	panel.add_theme_stylebox_override("panel", style)
	var header: HBoxContainer = HBoxContainer.new()
	box.add_child(header)
	var icon: TextureRect = TextureRect.new()
	icon.texture = StatIconFactory.get_icon(icon_id)
	icon.custom_minimum_size = Vector2(38.0, 38.0)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	header.add_child(icon)
	var title: Label = Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", accent)
	header.add_child(title)
	return box


func _setup_navigation_button(parent: Control, button: Button, icon_id: String) -> void:
	button.custom_minimum_size.y = 66.0
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.icon = StatIconFactory.get_icon(icon_id)
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 24)
	parent.add_child(button)


func _build_top_right_actions() -> void:
	var actions: HBoxContainer = HBoxContainer.new()
	actions.name = "HubTopActions"
	actions.anchor_left = 1.0
	actions.anchor_top = 0.0
	actions.anchor_right = 1.0
	actions.anchor_bottom = 0.0
	actions.offset_left = -700.0
	actions.offset_top = 22.0
	actions.offset_right = -22.0
	actions.offset_bottom = 76.0
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 10)
	actions.z_index = 40
	add_child(actions)
	_account_button = Button.new()
	_account_button.name = "HubAccountButton"
	_account_button.custom_minimum_size = Vector2(300.0, 54.0)
	_account_button.icon = StatIconFactory.get_icon("online")
	_account_button.expand_icon = true
	_account_button.add_theme_constant_override("icon_max_width", 24)
	_account_button.pressed.connect(_open_account)
	actions.add_child(_account_button)

	var history_button: Button = Button.new()
	history_button.name = "VersionHistoryButton"
	history_button.custom_minimum_size = Vector2(270.0, 54.0)
	history_button.text = Localization.get_textf(
		"hub.version_history.button",
		"Version History {version}",
		{"version": GameVersion.get_current_version()}
	)
	history_button.tooltip_text = Localization.get_text(
		"hub.version_history.tooltip",
		"Open version history"
	)
	history_button.icon = StatIconFactory.get_icon("version_history")
	history_button.expand_icon = true
	history_button.pressed.connect(_open_version_history)
	actions.add_child(history_button)

	var settings_button: Button = Button.new()
	settings_button.name = "OpenSettingsButton"
	settings_button.custom_minimum_size = Vector2(58.0, 54.0)
	settings_button.tooltip_text = Localization.get_text("hub.settings.tooltip", "Open settings")
	settings_button.icon = StatIconFactory.get_icon("settings")
	settings_button.expand_icon = true
	settings_button.pressed.connect(_open_settings)
	actions.add_child(settings_button)


func _refresh_account_button() -> void:
	if not is_instance_valid(_account_button): return
	var data: Dictionary = AccountSession.snapshot
	_account_button.text = Localization.get_text("account.register_name", "Set username") if data.get("needsUsername", false) else Localization.get_text("account.signed_in", "Account: signed in") if data.get("authenticated", false) else Localization.get_text("account.open", "Sign in / Register")
	_account_button.disabled = not AccountSession.is_supported()
	if is_instance_valid(_settings_dialog) and _settings_dialog.visible: return
	var lab: Control = find_child("DebugBattleLab", true, false) as Control
	if lab != null: lab.visible = Game.is_developer_mode_enabled()
	elif Game.is_developer_mode_enabled():
		var root: Control = find_child("HubModeSelection", true, false) as Control
		if root != null:
			_build_debug_battle_lab(root)
			_build_developer_panel()
			call_deferred("_warm_debug_card_pickers")
	_account_button.tooltip_text = Localization.get_text("account.open_hint", "Open your account and cloud-save controls inside the game.") if AccountSession.is_supported() else Localization.get_text("account.web_only", "Account sign-in is available in the Web edition. Local play does not require an account.")


func _open_account() -> void:
	SaveManager.flush_requested_save()
	if AccountSession.open_account(Localization.get_language()): return
	var notice: AcceptDialog = AcceptDialog.new()
	notice.dialog_text = Localization.get_text("account.popup_blocked", "Allow pop-ups for this site, then open your account again.")
	notice.confirmed.connect(notice.queue_free)
	notice.canceled.connect(notice.queue_free)
	add_child(notice)
	notice.popup_centered()


func _build_version_history_overlay() -> void:
	_version_history_overlay = ColorRect.new()
	_version_history_overlay.name = "VersionHistoryOverlay"
	_version_history_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_version_history_overlay.color = Color(0.01, 0.02, 0.035, 0.88)
	_version_history_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_version_history_overlay.z_index = 120
	_version_history_overlay.visible = false
	add_child(_version_history_overlay)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_left = 28.0
	center.offset_top = 28.0
	center.offset_right = -28.0
	center.offset_bottom = -28.0
	_version_history_overlay.add_child(center)

	var modal: PanelContainer = PanelContainer.new()
	modal.name = "VersionHistoryModal"
	modal.custom_minimum_size = Vector2(900.0, 700.0)
	center.add_child(modal)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_bottom", 24)
	modal.add_child(margin)

	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)

	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 18)
	root.add_child(header)

	var title: Label = Label.new()
	title.name = "VersionHistoryTitle"
	title.text = Localization.get_text("hub.version_history.title", "Version History")
	title.tooltip_text = GameVersion.get_history_note(Game.get_language())
	title.add_theme_font_size_override("font_size", 30)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var current_version: Label = Label.new()
	current_version.name = "CurrentVersionLabel"
	current_version.text = Localization.get_textf(
		"hub.version_history.current",
		"Current: {version}",
		{"version": GameVersion.get_current_version()}
	)
	current_version.add_theme_font_size_override("font_size", 20)
	current_version.add_theme_color_override("font_color", Color(0.46, 0.88, 1.0))
	current_version.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	current_version.tooltip_text = Localization.get_textf(
		"hub.version_history.scheme",
		"Version scheme: {scheme}",
		{"scheme": GameVersion.get_scheme()}
	)
	header.add_child(current_version)
	root.add_child(HSeparator.new())

	_version_history_content = RichTextLabel.new()
	_version_history_content.name = "VersionHistoryContent"
	_version_history_content.bbcode_enabled = true
	_version_history_content.fit_content = false
	_version_history_content.scroll_active = true
	_version_history_content.selection_enabled = true
	_version_history_content.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_version_history_content.custom_minimum_size = Vector2(820.0, 470.0)
	_version_history_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_version_history_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_version_history_content)

	var footer: HBoxContainer = HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(footer)

	var close_button: Button = Button.new()
	close_button.name = "VersionHistoryCloseButton"
	close_button.custom_minimum_size = Vector2(220.0, 48.0)
	close_button.text = Localization.get_text("hub.version_history.close", "Close")
	close_button.pressed.connect(_close_version_history)
	footer.add_child(close_button)

	_refresh_version_history_content()


func _refresh_version_history_content() -> void:
	if _version_history_content == null:
		return
	var language_suffix: String = "ja" if Game.get_language() == "ja" else "en"
	_version_history_content.language = language_suffix
	var lines: PackedStringArray = []
	for release: Dictionary in GameVersion.get_releases():
		var version: String = String(release.get("version", ""))
		var date: String = String(release.get("date", ""))
		var title: String = String(release.get("title_%s" % language_suffix, release.get("title_en", "")))
		var estimated_badge: String = ""
		if bool(release.get("estimated", false)):
			estimated_badge = "  [color=#c8ad72](%s)[/color]" % Localization.get_text("hub.version_history.estimated", "Estimated")
		lines.append("[font_size=24][color=#f4c85c][b]%s[/b][/color]  [color=#7fdcff]%s[/color]%s[/font_size]" % [version, date, estimated_badge])
		lines.append("[font_size=20][b]%s[/b][/font_size]" % title)
		var raw_changes: Variant = release.get("changes_%s" % language_suffix, release.get("changes_en", []))
		if raw_changes is Array:
			var cells: PackedStringArray = []
			for raw_change: Variant in raw_changes:
				cells.append("[cell expand=0 padding=0,0,10,6]-[/cell][cell expand=1 padding=0,0,0,6]%s[/cell]" % String(raw_change))
			lines.append("[color=#c9d7e2][table=2]%s[/table][/color]" % "".join(cells))
		lines.append("")
	_version_history_content.text = "\n".join(lines)
	_version_history_content.scroll_to_line(0)


func _open_version_history() -> void:
	if SceneRouter.is_battle_tutorial_dialog_open(): return
	if _version_history_overlay == null:
		return
	_refresh_version_history_content()
	_version_history_overlay.visible = true
	AudioManager.play_sfx("ui_toggle")


func _close_version_history() -> void:
	if _version_history_overlay == null:
		return
	_version_history_overlay.visible = false
	AudioManager.play_sfx("ui_toggle")


func _open_settings() -> void:
	if SceneRouter.is_battle_tutorial_dialog_open(): return
	if SceneRouter.is_meta_progress_dialog_open(): return
	if is_instance_valid(_settings_dialog) and _settings_dialog.visible: return
	if _version_history_overlay != null and _version_history_overlay.visible: _close_version_history()
	if not is_instance_valid(_settings_dialog):
		_settings_dialog = SettingsDialog.new()
		add_child(_settings_dialog)
		_settings_dialog.dismissed.connect(_on_settings_closed)
	_settings_language = Game.get_language()
	_settings_developer = Game.is_developer_mode_enabled()
	_settings_dialog.open()


func _on_settings_closed() -> void:
	if Game.get_language() == _settings_language and Game.is_developer_mode_enabled() == _settings_developer: return
	_rebuild_menu("OpenSettingsButton")


func _rebuild_menu(focus_name: String) -> void:
	var old_scroll: ScrollContainer = find_child("HubContentScroll", true, false) as ScrollContainer
	var scroll_position: int = old_scroll.scroll_vertical if old_scroll != null else 0
	# Rebuild localized menu controls, not the scene or the saved run. Keep the cached dialog.
	for child: Node in get_children():
		if child == _settings_dialog or child.name == UiTheme.BACKGROUND_NODE_NAME: continue
		remove_child(child)
		child.queue_free()
	_developer_panel = null
	_debug_enemy_option = null
	_debug_starter_option = null
	_debug_card_options.clear()
	_debug_card_grade_options.clear()
	_build_ui()
	var scroll: ScrollContainer = find_child("HubContentScroll", true, false) as ScrollContainer
	if scroll != null: scroll.set_deferred("scroll_vertical", scroll_position)
	var focus_button: Button = find_child(focus_name, true, false) as Button
	if focus_button != null: focus_button.call_deferred("grab_focus")


func _unhandled_input(event: InputEvent) -> void:
	if _version_history_overlay != null and _version_history_overlay.visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close_version_history()


func _add_run_mode_row(parent: VBoxContainer, mode: String) -> void:
	var is_arena: bool = mode == Game.RUN_SETUP_MODE_ARENA
	var row: HBoxContainer = HBoxContainer.new()
	row.name = "ArenaModeButtonRow" if is_arena else "NormalModeButtonRow"
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)

	var start_button: Button = Button.new()
	start_button.name = "ArenaStartButton" if is_arena else "RunStartButton"
	start_button.text = Localization.get_text(
		"hub.new_run",
		"New Game"
	)
	start_button.custom_minimum_size.y = 54.0
	start_button.theme_type_variation = "PrimaryButton" if not is_arena else "Button"
	start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start_button.pressed.connect(func() -> void:
		SceneRouter.go_to_run_setup(mode)
	)
	row.add_child(start_button)

	if not Game.has_suspended_run(mode):
		return
	var continue_button: Button = Button.new()
	continue_button.name = "ContinueArenaRunButton" if is_arena else "ContinueNormalRunButton"
	continue_button.text = Localization.get_text(
		"hub.continue_arena" if is_arena else "hub.continue_normal",
		"Continue Arena" if is_arena else "Continue Run"
	)
	continue_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	continue_button.custom_minimum_size.y = 54.0
	continue_button.pressed.connect(SceneRouter.continue_suspended_run.bind(mode))
	row.add_child(continue_button)


func _build_debug_battle_lab(parent: Control) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.name = "DebugBattleLab"
	panel.custom_minimum_size = Vector2(620.0, 0.0)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	parent.add_child(panel)

	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var title: Label = Label.new()
	title.text = Localization.get_text("hub.debug_battle_lab", "Debug Battle Lab")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	_debug_enemy_option = _create_debug_option(
		"DebugEnemyOption",
		Game.get_debug_battle_enemy_entries(),
		"scout",
		false
	)
	_add_option_row(box, Localization.get_text("hub.debug_enemy", "Enemy"), _debug_enemy_option)

	_debug_starter_option = _create_debug_option(
		"DebugStarterOption",
		Game.get_debug_battle_starter_entries(),
		"balanced",
		false
	)
	_add_option_row(box, Localization.get_text("hub.debug_starter", "Starter"), _debug_starter_option)

	var cards_label: Label = Label.new()
	cards_label.text = Localization.get_text("hub.debug_loadout", "Loadout")
	box.add_child(cards_label)
	var presets: DeckPresetBar = DeckPresetBar.new()
	presets.max_cards = DEBUG_CARD_SLOT_COUNT
	presets.get_cards = func() -> Array[String]:
		var cards: Array[String] = []
		for picker in _debug_card_options:
			if picker.get_selected_card_id() != "":
				cards.append(picker.get_selected_card_id())
		return cards
	presets.apply_requested.connect(func(cards: Array[String]) -> void:
		for i in range(_debug_card_options.size()):
			_debug_card_options[i].set_selected_card_id(cards[i] if i < cards.size() else "")
	)
	box.add_child(presets)

	var card_grid: GridContainer = GridContainer.new()
	card_grid.name = "DebugCardSlotGrid"
	card_grid.columns = 3
	card_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_grid.add_theme_constant_override("h_separation", 10)
	card_grid.add_theme_constant_override("v_separation", 10)
	box.add_child(card_grid)

	var card_entries: Array[Dictionary] = Game.get_debug_battle_card_entries()
	var default_cards: Array[String] = ["quick_slash", "strike", "guard", "heavy_swing", "delay_step", "reload"]
	_debug_card_options.clear()
	_debug_card_grade_options.clear()
	for slot_index in range(DEBUG_CARD_SLOT_COUNT):
		var default_card_id: String = default_cards[slot_index] if slot_index < default_cards.size() else "quick_slash"
		var option: CardIconPicker = _create_debug_card_picker(
			"DebugCardSlot%d" % slot_index,
			card_entries,
			default_card_id,
			true
		)
		var grade_option: OptionButton = _create_debug_grade_option("DebugCardGradeSlot%d" % slot_index)
		_debug_card_options.append(option)
		_debug_card_grade_options.append(grade_option)
		_add_card_slot_row(
			card_grid,
			Localization.get_textf("hub.debug_card_slot", "Card {index}", {"index": slot_index + 1}),
			option,
			grade_option
		)

	var start_button: Button = Button.new()
	start_button.name = "DevCustomBattleStart"
	start_button.text = Localization.get_text("hub.debug_start_custom_battle", "Start Custom Battle")
	start_button.pressed.connect(_on_dev_start_custom_battle)
	box.add_child(start_button)


func _add_option_row(parent: Control, label_text: String, option: OptionButton) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var label: Label = Label.new()
	label.custom_minimum_size = Vector2(120.0, 0.0)
	label.text = label_text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)

	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(option)


func _add_card_slot_row(parent: Control, label_text: String, card_option: CardIconPicker, grade_option: OptionButton) -> void:
	var slot_box: VBoxContainer = VBoxContainer.new()
	slot_box.name = "DebugCardSlotCell_%s" % card_option.name
	slot_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot_box.add_theme_constant_override("separation", 5)
	parent.add_child(slot_box)

	var label: Label = Label.new()
	label.text = label_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slot_box.add_child(label)

	card_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot_box.add_child(card_option)

	var grade_row: HBoxContainer = HBoxContainer.new()
	grade_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grade_row.add_theme_constant_override("separation", 6)
	slot_box.add_child(grade_row)

	var grade_label: Label = Label.new()
	grade_label.text = Localization.get_text("hub.debug_grade", "Grade")
	grade_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	grade_row.add_child(grade_label)

	grade_option.custom_minimum_size = Vector2(86.0, 0.0)
	grade_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grade_row.add_child(grade_option)


func _create_debug_option(name: String, entries: Array[Dictionary], default_id: String, include_empty: bool) -> OptionButton:
	var option: OptionButton = OptionButton.new()
	option.name = name
	if include_empty:
		option.add_item(Localization.get_text("hub.debug_empty_slot", "Empty"))
		option.set_item_metadata(option.item_count - 1, "")
	for entry in entries:
		var entry_id: String = String(entry.get("id", ""))
		if entry_id == "":
			continue
		option.add_item("%s [%s]" % [String(entry.get("name", entry_id)), entry_id])
		option.set_item_metadata(option.item_count - 1, entry_id)
	_select_option_by_metadata(option, default_id)
	return option


func _create_debug_card_picker(name: String, entries: Array[Dictionary], default_id: String, include_empty: bool) -> CardIconPicker:
	var picker: CardIconPicker = CardIconPicker.new()
	picker.name = name
	picker.setup(entries, default_id, include_empty)
	return picker


func _create_debug_grade_option(name: String, default_tier: int = 0) -> OptionButton:
	var option: OptionButton = OptionButton.new()
	option.name = name
	for tier in range(CardUpgradeResolver.MAX_TIER + 1):
		option.add_item(CardInfoFormatter.format_grade_label(tier))
		option.set_item_metadata(option.item_count - 1, tier)
	option.select(clampi(default_tier, 0, CardUpgradeResolver.MAX_TIER))
	return option


func _warm_debug_card_pickers() -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if not is_inside_tree():
		return
	for picker in _debug_card_options:
		if picker == null or not is_instance_valid(picker):
			continue
		picker.warm_popup_choices()
		if not is_inside_tree():
			return
		await get_tree().process_frame


func _select_option_by_metadata(option: OptionButton, target_id: String) -> void:
	for index in range(option.item_count):
		if String(option.get_item_metadata(index)) == target_id:
			option.select(index)
			return
	if option.item_count > 0:
		option.select(0)


func _on_dev_start_custom_battle() -> void:
	var enemy_id: String = _get_selected_option_id(_debug_enemy_option)
	var starter_id: String = _get_selected_option_id(_debug_starter_option)
	var card_ids: Array[String] = []
	var card_tiers: Dictionary = {}
	for slot_index in range(_debug_card_options.size()):
		var option: CardIconPicker = _debug_card_options[slot_index]
		var card_id: String = option.get_selected_card_id()
		if card_id != "":
			card_ids.append(card_id)
			var selected_tier: int = _get_selected_grade(_debug_card_grade_options[slot_index])
			card_tiers[card_id] = maxi(int(card_tiers.get(card_id, 0)), selected_tier)
	Game.developer_open_custom_battle(enemy_id, starter_id, card_ids, card_tiers)
	SceneRouter.go_to_battle()


func _get_selected_option_id(option: OptionButton) -> String:
	if option == null or option.item_count == 0:
		return ""
	var selected_index: int = option.selected
	if selected_index < 0 or selected_index >= option.item_count:
		return ""
	return String(option.get_item_metadata(selected_index))


func _get_selected_grade(option: OptionButton) -> int:
	if option == null or option.item_count == 0:
		return 0
	var selected_index: int = option.selected
	if selected_index < 0 or selected_index >= option.item_count:
		return 0
	return clampi(int(option.get_item_metadata(selected_index)), 0, CardUpgradeResolver.MAX_TIER)


func _build_developer_panel() -> void:
	_developer_panel = DeveloperPanel.new()
	add_child(_developer_panel)
	_developer_panel.pin_top_right(92.0)
	_developer_panel.configure(
		Localization.get_text("developer.title", "Developer Mode"),
		[
			{"id": "DevStartRun", "label": Localization.get_text("hub.dev.quick_run", "Quick Run"), "callback": Callable(self, "_on_dev_quick_run")},
			{"id": "DevStartArena", "label": Localization.get_text("hub.dev.quick_arena", "Quick Arena"), "callback": Callable(self, "_on_dev_quick_arena")},
			{"id": "DevOpenBattle", "label": Localization.get_text("hub.dev.open_battle", "Open Battle"), "callback": Callable(self, "_on_dev_open_battle")},
			{"id": "DevOpenReward", "label": Localization.get_text("hub.dev.open_reward", "Open Reward"), "callback": Callable(self, "_on_dev_open_reward")},
			{"id": "DevOpenResult", "label": Localization.get_text("hub.dev.open_result", "Open Result"), "callback": Callable(self, "_on_dev_open_result")},
			{"id": "DevInfiniteScorePreview", "label": Localization.get_text("result.infinite.dev_preview", "Infinite Score Preview"), "callback": Callable(self, "_on_dev_infinite_result")},
			{"id": "DevAddPoints", "label": Localization.get_text("hub.dev.add_points", "Add 5 Points"), "callback": Callable(self, "_on_dev_add_points")},
			{"id": "DevUnlockAll", "label": Localization.get_text("hub.dev.unlock_all", "Unlock All Meta"), "callback": Callable(self, "_on_dev_unlock_all")},
			{"id": "DevResetMeta", "label": Localization.get_text("hub.dev.reset_meta", "Reset Meta"), "callback": Callable(self, "_on_dev_reset_meta")},
			{"id": "DevToggleOff", "label": Localization.get_text("hub.dev.turn_off", "Turn Off"), "callback": Callable(self, "_on_dev_turn_off")},
		],
		Localization.get_text("hub.dev.summary", "Quick scene access and meta control for manual testing.")
	)


func _on_dev_quick_run() -> void:
	Game.developer_start_run("balanced")
	SceneRouter.go_to_map()


func _on_dev_quick_arena() -> void:
	Game.developer_start_arena("balanced")
	SceneRouter.go_to_arena()


func _on_dev_open_battle() -> void:
	Game.developer_open_battle("scout")
	SceneRouter.go_to_battle()


func _on_dev_open_reward() -> void:
	Game.developer_open_reward()
	SceneRouter.go_to_reward()


func _on_dev_open_result() -> void:
	Game.developer_open_result()
	SceneRouter.go_to_result()


func _on_dev_infinite_result() -> void:
	Game.developer_open_infinite_result()
	SceneRouter.go_to_result()


func _on_dev_add_points() -> void:
	Game.developer_add_points(5)
	_info_label.text = str(Game.get_meta_points())
	_info_label.tooltip_text = Localization.get_textf("hub.meta_points", "Meta Points: {points}", {
		"points": Game.get_meta_points(),
	})


func _on_dev_unlock_all() -> void:
	Game.developer_unlock_all_meta()
	_info_label.text = Localization.get_text("hub.meta_unlocked_all", "Unlocked all meta entries.")


func _on_dev_reset_meta() -> void:
	Game.developer_reset_meta_progress()
	_info_label.text = Localization.get_text("hub.meta_reset", "Meta progress reset.")


func _on_dev_turn_off() -> void:
	Game.set_developer_mode_enabled(false)
	SceneRouter.go_to_hub()


func _on_open_meta_progress() -> void:
	if SceneRouter.is_battle_tutorial_dialog_open(): return
	if is_instance_valid(_settings_dialog) and _settings_dialog.visible: return
	if _version_history_overlay != null and _version_history_overlay.visible: _close_version_history()
	var dialog: MetaProgressDialog = SceneRouter.get_meta_progress_dialog()
	if dialog.visible: return
	if not dialog.dismissed.is_connected(_on_meta_closed): dialog.dismissed.connect(_on_meta_closed)
	_meta_snapshot = JSON.stringify(Game.meta_progress)
	dialog.open()


func _on_open_battle_tutorial() -> void:
	if NetworkManager.is_session_connected() or SceneRouter.is_meta_progress_dialog_open(): return
	if is_instance_valid(_settings_dialog) and _settings_dialog.visible: return
	if _version_history_overlay != null and _version_history_overlay.visible: _close_version_history()
	Game.clear_battle_tutorial()
	SceneRouter.get_battle_tutorial_dialog().open()


func _on_meta_closed() -> void:
	_refresh_achievement_notification()
	if JSON.stringify(Game.meta_progress) != _meta_snapshot: _rebuild_menu("HubMetaProgressButton")


func _on_open_card_library() -> void:
	Game.current_screen_hint = "library"
	SaveManager.request_save("library")
	SceneRouter.go_to_card_library()


func _on_start_infinite_mode() -> void:
	if Game.start_infinite_run():
		SceneRouter.go_to_map()
