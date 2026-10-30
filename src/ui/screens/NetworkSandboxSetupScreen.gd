extends "res://src/ui/screens/SandboxSetupScreen.gd"

var _self_peer: int = 1
var _other_peer: int = -1
var _roster: RichTextLabel
var _sent: Dictionary = {}
var _dirty_since: int = -1
var _syncing: bool = false
var _awaiting_edit: bool = false


func _ready() -> void:
	if not NetworkManager.is_network_sandbox_active():SceneRouter.go_to_online_lobby();return
	SandboxSession.get_draft()
	_self_peer=multiplayer.get_unique_id()
	var configs: Dictionary=NetworkManager.get_sandbox_snapshot()["configs"]
	if not configs.has(str(_self_peer)):_self_peer=int(configs.keys()[0])
	for id: String in configs:
		if int(id)!=_self_peer:_other_peer=int(id);break
	data=_current_config()
	_build();_layout()
	for side: String in ["player","enemy"]:_refresh_deck(side);_refresh_relics(side)
	_refresh_presets();resized.connect(_layout)
	NetworkManager.arena_preparation_changed.connect(_on_state)
	NetworkManager.arena_action_result_received.connect(_on_action)
	NetworkManager.match_started.connect(_on_match)
	NetworkManager.session_ended.connect(func(_reason:String)->void:SceneRouter.go_to_online_lobby())
	NetworkManager.arena_session_finished.connect(func(_result:Dictionary)->void:SceneRouter.go_to_online_lobby())
	_sent=data.duplicate(true);_update_roster()
	SceneRouter.mark_ui_localized(self)


func _current_config() -> Dictionary:
	var snapshot: Dictionary=NetworkManager.get_sandbox_snapshot()
	var configs: Dictionary=snapshot["configs"]
	return NetworkSandboxConfig.match_config(configs.get(str(_self_peer),SandboxConfig.side_from_starter()),configs.get(str(_other_peer),SandboxConfig.side_from_starter()),snapshot["rules"])


func _build() -> void:
	super._build()
	var root: Node=(find_child("SandboxSetupScroll",true,false) as Control).get_parent()
	var row: HFlowContainer=HFlowContainer.new();row.name="NetworkSandboxParticipants";root.add_child(row);root.move_child(row,2)
	var choose: OptionButton=OptionButton.new();choose.name="SandboxViewOpponent";row.add_child(choose)
	for profile: Dictionary in NetworkManager.get_lobby_players():
		var id: int=int(profile.get("peer_id",-1))
		if id==_self_peer or not NetworkManager.get_sandbox_snapshot()["configs"].has(str(id)):continue
		choose.add_item(String(profile.get("name","Player")));choose.set_item_metadata(choose.item_count-1,id)
		if id==_other_peer:choose.select(choose.item_count-1)
	choose.item_selected.connect(func(index:int)->void:
		_flush_edits();_other_peer=int(choose.get_item_metadata(index));_replace_config(_current_config());_sent=data.duplicate(true))
	_roster=RichTextLabel.new();_roster.name="SandboxReadyRoster";_roster.bbcode_enabled=true;_roster.fit_content=true;_roster.scroll_active=false;root.add_child(_roster);root.move_child(_roster,3)
	var spectator: bool=NetworkManager.is_local_spectator()
	var editable_other: bool=NetworkManager.is_host() and bool(data["rules"].get("edit_opponents",false))
	_set_readonly(find_child("SandboxSide_player",true,false),spectator)
	_set_readonly(find_child("SandboxSide_enemy",true,false),not editable_other)
	for key: String in ["enemy_ai","player_ai","boss_passive"]:(find_child("SandboxRule_"+key,true,false) as Control).hide()
	var power: Control=find_child("SandboxRule_power",true,false) as Control
	power.get_parent().get_child(power.get_index()-1).hide();power.hide()
	if not NetworkManager.is_host():
		for control: Node in find_children("SandboxRule_*","",true,false):_set_readonly(control,true)
		(find_child("SandboxField",true,false) as OptionButton).disabled=true
	var edit: CheckButton=CheckButton.new();edit.name="SandboxRule_edit_opponents";edit.text=_t("ホストによる相手編成の編集","Host May Edit Opponents");edit.button_pressed=bool(data["rules"].get("edit_opponents",false));edit.disabled=not NetworkManager.is_host();row.add_child(edit)
	edit.toggled.connect(func(enabled:bool)->void:data["rules"]["edit_opponents"]=enabled;_set_readonly(find_child("SandboxSide_enemy",true,false),not enabled))
	(find_child("SandboxStart",true,false) as Button).visible=not spectator
	_status.text=_t("各自16枚・遺物8個まで。設定変更で準備完了が解除されます。進行データには加算しません。","Up to 16 cards and 8 relics each. Edits clear readiness. No progression credit.")
	_update_roster()


func _button(parent: Node, text: String, id: String, action: Callable) -> Button:
	if id=="SandboxBack":
		text=_t("退室","Leave");action=func()->void:NetworkManager.leave_session();SceneRouter.go_to_online_lobby()
	return super._button(parent,text,id,action)


func _replace_config(raw: Dictionary) -> void:
	var shared: Dictionary=Dictionary(raw.get("rules",{})) if NetworkManager.is_host() else NetworkManager.get_sandbox_snapshot()["rules"]
	data=NetworkSandboxConfig.match_config(raw["player"],raw["enemy"],shared);_generation+=1
	if not NetworkManager.is_host() or not bool(shared.get("edit_opponents",false)):
		data["enemy"]=_current_config()["enemy"]
	for child: Node in get_children():remove_child(child);child.queue_free()
	_deck_grids.clear();_relic_rows.clear();_previews.clear();_card_widgets.clear();_stat_widgets.clear();_stat_grids.clear();_cost_labels.clear()
	_build();_layout()
	for side: String in ["player","enemy"]:_refresh_deck(side);_refresh_relics(side)
	_refresh_presets()


func _number(parent: Node, id: String, value: int, minimum: int, maximum: int) -> SpinBox:
	if id.ends_with("_max_hp") or id.ends_with("_hp"):maximum=mini(maximum,100000)
	if id.ends_with("_attack"):maximum=mini(maximum,10000)
	if id.ends_with("_slots"):maximum=mini(maximum,16)
	return super._number(parent,id,value,minimum,maximum)


func _add_card(id: String) -> void:
	if Array(data[_catalog_side]["cards"]).size()<NetworkSandboxConfig.MAX_CARDS:super._add_card(id)


func _add_relic(id: String) -> void:
	if Array(data[_catalog_side]["relics"]).size()<NetworkSandboxConfig.MAX_RELICS:super._add_relic(id)


func _set_readonly(node: Node, value: bool) -> void:
	if node is BaseButton:
		(node as BaseButton).disabled=value
		if value:(node as BaseButton).add_theme_color_override("font_disabled_color",Color(.72,.8,.85))
	if node is SpinBox:(node as SpinBox).editable=not value
	if node is LineEdit:
		(node as LineEdit).editable=not value
		if value:(node as LineEdit).add_theme_color_override("font_uneditable_color",Color(.72,.8,.85))
	for child: Node in node.get_children():_set_readonly(child,value)


func _process(_delta: float) -> void:
	if _syncing or not NetworkManager.is_network_sandbox_active():return
	if data!=_sent:
		if _dirty_since<0:_dirty_since=Time.get_ticks_msec()
		if Time.get_ticks_msec()-_dirty_since>=220:_flush_edits()
	else:_dirty_since=-1


func _flush_edits() -> bool:
	if _awaiting_edit:return false
	var snapshot: Dictionary=NetworkManager.get_sandbox_snapshot()
	var desired: Dictionary=NetworkSandboxConfig.side(data["player"])
	data["player"]=desired;data["enemy"]=NetworkSandboxConfig.side(data["enemy"])
	var shared: Dictionary=NetworkSandboxConfig.rules(data["rules"])
	var target: int=_self_peer
	if desired==snapshot["configs"].get(str(_self_peer),{}) and (not NetworkManager.is_host() or shared==snapshot["rules"]):
		if not NetworkManager.is_host() or not bool(snapshot["rules"].get("edit_opponents",false)) or NetworkSandboxConfig.side(data["enemy"])==snapshot["configs"].get(str(_other_peer),{}):
			_sent=data.duplicate(true);return true
		target=_other_peer;desired=NetworkSandboxConfig.side(data["enemy"])
	_awaiting_edit=true
	var accepted: bool=NetworkManager.submit_sandbox_setup(target,desired,shared if NetworkManager.is_host() else {})
	if not accepted:_awaiting_edit=false
	_dirty_since=-1
	return false


func _on_action(action: String, accepted: bool, _result: Dictionary) -> void:
	if action=="sandbox_edit":
		_awaiting_edit=false
		if not accepted:_status.text=_t("他の変更と重なりました。設定を再送します。","Concurrent edit; retrying the setup.")


func _on_state(_snapshot: Dictionary) -> void:
	_update_roster()
	if _awaiting_edit:return
	var incoming: Dictionary=_current_config()
	if data==_sent:
		if incoming!=data:
			if not _update_stats_only(incoming):_replace_config(incoming)
		_sent=data.duplicate(true)
	else:
		# Keep local typing while receiving other players' edits; retry against the new revision.
		if not NetworkManager.is_host() or not bool(incoming["rules"].get("edit_opponents",false)):
			var old: Dictionary=data["enemy"]
			data["enemy"]=incoming["enemy"].duplicate(true)
			for key: String in _stat_widgets["enemy"]:(_stat_widgets["enemy"][key] as SpinBox).set_value_no_signal(float(data["enemy"][key]))
			if old["cards"]!=data["enemy"]["cards"]:_refresh_deck("enemy")
			else:_refresh_card_previews("enemy")
			if old["relics"]!=data["enemy"]["relics"]:_refresh_relics("enemy")
			if old["visual"]!=data["enemy"]["visual"]:_show_model("enemy")
			_set_readonly(find_child("SandboxSide_enemy",true,false),true)
		if not NetworkManager.is_host() and data["rules"]!=incoming["rules"]:
			data["rules"]=incoming["rules"].duplicate(true)
			for key: String in data["rules"]:
				var toggle: CheckButton=find_child("SandboxRule_"+key,true,false) as CheckButton
				if toggle!=null:toggle.set_pressed_no_signal(bool(data["rules"][key]))
			(find_child("SandboxRule_seed",true,false) as SpinBox).set_value_no_signal(float(data["rules"]["seed"]))
			var fields: OptionButton=find_child("SandboxField",true,false) as OptionButton
			for index: int in fields.item_count:
				if fields.get_item_metadata(index)==data["rules"]["field"]:fields.select(index)
		if incoming["player"]==NetworkSandboxConfig.side(data["player"]) and incoming["enemy"]==NetworkSandboxConfig.side(data["enemy"]) and incoming["rules"]==NetworkSandboxConfig.rules(data["rules"]):
			data=incoming;_sent=data.duplicate(true)


func _update_stats_only(incoming: Dictionary) -> bool:
	if incoming["rules"]!=data["rules"]:return false
	for side: String in ["player","enemy"]:
		for key: String in ["cards","relics","visual"]:
			if incoming[side][key]!=data[side][key]:return false
	data=incoming.duplicate(true)
	for side: String in ["player","enemy"]:
		for key: String in _stat_widgets[side]:(_stat_widgets[side][key] as SpinBox).set_value_no_signal(float(data[side][key]))
		_refresh_card_previews(side)
	return true


func _update_roster() -> void:
	if _roster==null:return
	var ready: Dictionary=NetworkManager.get_sandbox_snapshot()["ready"]
	var lines: Array[String]=[]
	for profile: Dictionary in NetworkManager.get_lobby_players():
		var id: String=str(profile.get("peer_id",-1))
		if not ready.has(id):continue
		lines.append("[color=%s]%s  %s[/color]"%["#61f0a0" if ready[id] else "#f1bf54",String(profile.get("name","Player")).replace("[","[lb]"),_t("準備完了","Ready") if ready[id] else _t("準備中","Preparing")])
	_roster.text="  |  ".join(lines)
	var start: Button=find_child("SandboxStart",true,false) as Button
	if start!=null:start.text=_t("準備を取り消す","Cancel Ready") if bool(ready.get(str(multiplayer.get_unique_id()),false)) else _t("準備完了","Ready")


func _start() -> void:
	if not _flush_edits():
		_status.text=_t("設定の共有が終わってから準備完了を押してください。","Wait for setup synchronization, then press Ready.");return
	NetworkManager.set_sandbox_ready(not NetworkManager.is_local_arena_ready())


func _on_match(_payload: Dictionary) -> void:
	SceneRouter.go_to_battle()
