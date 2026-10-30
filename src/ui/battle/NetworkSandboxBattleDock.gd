extends PanelContainer
class_name NetworkSandboxBattleDock

var _battle: Control
var _body: VBoxContainer
var _matches: OptionButton
var _status: Label


func _t(ja: String,en: String) -> String:
	return ja if Localization.get_language()=="ja" else en


func _button(parent: Node,text: String,id: String,callback: Callable) -> void:
	var button: Button=Button.new();button.name=id;button.text=text;button.set_meta("skip_auto_icon",true);button.custom_minimum_size.y=36;button.pressed.connect(callback);parent.add_child(button)


func configure(battle: Control) -> void:
	_battle=battle;name="NetworkSandboxDock";z_index=90
	set_anchors_preset(Control.PRESET_TOP_RIGHT);offset_left=-390;offset_right=-18;offset_top=74
	var style: StyleBoxFlat=StyleBoxFlat.new();style.bg_color=Color(.02,.04,.06,.97);style.border_color=UiTheme.ACCENT_BLUE;style.set_border_width_all(2);style.set_content_margin_all(12);style.set_corner_radius_all(12);add_theme_stylebox_override("panel",style)
	var root: VBoxContainer=VBoxContainer.new();add_child(root)
	_button(root,_t("サンドボックス操作 +","Sandbox Controls +"),"NetworkSandboxToggle",func()->void:_body.visible=not _body.visible;reset_size())
	_body=VBoxContainer.new();_body.hide();root.add_child(_body)
	_status=Label.new();_status.name="NetworkSandboxStatus";_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_body.add_child(_status)
	_matches=OptionButton.new();_matches.name="NetworkSandboxMatch";_body.add_child(_matches)
	_refresh_matches(NetworkManager.get_arena_round_results_snapshot())
	NetworkManager.arena_round_results_changed.connect(_refresh_matches)
	if NetworkManager.is_local_spectator():_button(_body,_t("この試合を観戦","Watch Match"),"NetworkSandboxWatch",func()->void:NetworkManager.request_sandbox_spectate(_match_id()))
	if NetworkManager.is_host():
		var row: HFlowContainer=HFlowContainer.new();_body.add_child(row)
		_button(row,_t("停止","Pause"),"NetworkSandboxPause",_control.bind("pause",1.0))
		_button(row,_t("再開","Resume"),"NetworkSandboxResume",_control.bind("pause",0.0))
		_button(row,"+0.1s","NetworkSandboxStepSmall",_control.bind("step",.1))
		_button(row,"+1s","NetworkSandboxStepLarge",_control.bind("step",1.0))
		var speed: OptionButton=OptionButton.new();speed.name="NetworkSandboxSpeed";_body.add_child(speed)
		for value: float in [.25,.5,1.0,2.0,4.0]:speed.add_item("x"+str(value));speed.set_item_metadata(speed.item_count-1,value)
		speed.select(2);speed.item_selected.connect(func(index:int)->void:_control("speed",float(speed.get_item_metadata(index))))
		for side: String in ["player","enemy"]:
			var label: Label=Label.new();label.text=_t("青側","Blue Side") if side=="player" else _t("赤側","Red Side");_body.add_child(label)
			var actions: HFlowContainer=HFlowContainer.new();_body.add_child(actions)
			for entry: Array in [["heal",_t("HP全快","Full HP")],["clear_status",_t("状態解除","Clear Status")],["clear_shield",_t("シールド解除","Clear Shield")],["reset_recast",_t("再使用リセット","Reset Recast")]]:
				_button(actions,String(entry[1]),"NetworkSandbox_"+String(entry[0])+"_"+side,func()->void:NetworkManager.sandbox_match_control(String(entry[0]),_match_id(),0,side))
			var queue: HBoxContainer=HBoxContainer.new();_body.add_child(queue)
			var number: SpinBox=SpinBox.new();number.min_value=1;number.max_value=NetworkSandboxConfig.MAX_CARDS;number.custom_minimum_size.x=70;queue.add_child(number)
			_button(queue,_t("枚目を登録","Queue Card #"),"NetworkSandboxQueue_"+side,func()->void:NetworkManager.sandbox_match_control("queue_card",_match_id(),number.value-1,side))
		_button(_body,_t("この試合をリセット","Reset This Match"),"NetworkSandboxRestart",_control.bind("restart",0.0))
		_button(_body,_t("全試合を終了 / 編成へ","End All / Edit Setup"),"NetworkSandboxEditSetup",NetworkManager.sandbox_return_to_setup)
	_button(_body,_t("バトルの詳細","Battle Details"),"NetworkSandboxStatistics",func()->void:
		if NetworkManager.is_host():_control("pause",1)
		NetworkManager.request_sandbox_statistics(_match_id() if NetworkManager.is_host() else String(NetworkManager.get_match_payload().get("match_id",""))))
	NetworkManager.sandbox_statistics_received.connect(func(summary:Dictionary)->void:(_battle.get("_analysis_panel") as BattleResultAnalysisPanel).show_details(summary,String(_battle.get("_local_side"))))
	custom_minimum_size=Vector2(360,0);reset_size()


func _match_id() -> String:
	return String(_matches.get_selected_metadata()) if _matches.selected>=0 else String(NetworkManager.get_match_payload().get("match_id",""))


func _refresh_matches(snapshot: Dictionary) -> void:
	var previous: String=_match_id()
	_matches.clear()
	for result: Dictionary in snapshot.get("results",[]):
		_matches.add_item(String(result.get("player_name","Player"))+" vs "+String(result.get("enemy_name","Enemy")))
		_matches.set_item_metadata(_matches.item_count-1,String(result["match_id"]))
		if String(result["match_id"])==previous:_matches.select(_matches.item_count-1)


func _control(action: String,value: float) -> void:
	NetworkManager.sandbox_match_control(action,_match_id(),value)


func _process(_delta: float) -> void:
	var state: Dictionary=NetworkManager.get_sandbox_match_control(_match_id())
	_status.text=_t("安全上限に到達・停止中","Safety Limit: Paused") if state.get("safety",false) else (_t("停止中","Paused") if state.get("paused",false) else _t("進行中","Running"))
