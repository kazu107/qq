extends PanelContainer
class_name SandboxBattleDock

var battle: Control
var engine: RealtimeBattleEngine
var paused: bool = false
var speed: float = 1.0
var _body: VBoxContainer
var _pause: Button
var _enemy_card: OptionButton
var _status: Label
var _player_ai: EnemyAI = EnemyAI.new()
var _expanded: bool = false


func _t(ja: String, en: String) -> String:
	return ja if Localization.get_language()=="ja" else en


func _button(parent: Node, text: String, id: String, action: Callable) -> Button:
	var button: Button=Button.new();button.name=id;button.text=text;button.set_meta("skip_auto_icon",true);button.custom_minimum_size.y=36;button.pressed.connect(action);parent.add_child(button);return button


func configure(screen: Control, value: RealtimeBattleEngine) -> void:
	battle=screen;engine=value;_player_ai.side="player"
	name="SandboxBattleDock";z_index=90
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left=-390;offset_right=-18;offset_top=74
	var style: StyleBoxFlat=StyleBoxFlat.new();style.bg_color=Color(.025,.045,.065,.97);style.border_color=UiTheme.ACCENT_BLUE;style.set_border_width_all(2);style.set_corner_radius_all(12);style.set_content_margin_all(12);add_theme_stylebox_override("panel",style)
	var root: VBoxContainer=VBoxContainer.new();add_child(root)
	var header: HBoxContainer=HBoxContainer.new();root.add_child(header)
	var title: Label=Label.new();title.text=_t("サンドボックス","Sandbox");title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(title)
	var toggle: Button=_button(header,"+","SandboxDockToggle",func()->void:
		_expanded=not _expanded;_body.visible=_expanded
		(header.get_node("SandboxDockToggle") as Button).text="-" if _expanded else "+"
		reset_size())
	toggle.custom_minimum_size=Vector2(32,32)
	_body=VBoxContainer.new();_body.visible=false;root.add_child(_body)
	_status=Label.new();_status.name="SandboxSafetyStatus";_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_status.text=_t("保存・報酬・実績への加算なし","No progress, rewards or achievement credit");_body.add_child(_status)
	var time_row: HFlowContainer=HFlowContainer.new();_body.add_child(time_row)
	_pause=_button(time_row,_t("一時停止","Pause"),"SandboxPause",func()->void:paused=not paused;_sync_pause())
	for entry: Array in [[.1,"+0.1s"],[1.0,"+1s"]]:
		_button(time_row,String(entry[1]),"SandboxStep_"+str(entry[0]).replace(".","_"),advance.bind(float(entry[0])))
	var speeds: OptionButton=OptionButton.new();speeds.name="SandboxSpeed";time_row.add_child(speeds)
	for value_speed: float in [.25,.5,1.0,2.0,4.0]:
		speeds.add_item("x"+str(value_speed));speeds.set_item_metadata(speeds.item_count-1,value_speed)
	speeds.select(2);speeds.item_selected.connect(func(index:int)->void:speed=float(speeds.get_item_metadata(index));_sync_pause())
	for side: String in ["player","enemy"]:
		var row: HFlowContainer=HFlowContainer.new();_body.add_child(row)
		var label: Label=Label.new();label.text=_t("自分","Player") if side=="player" else _t("敵","Enemy");row.add_child(label)
		_button(row,_t("HP全快","Full HP"),"SandboxHeal_"+side,func()->void:engine.battle_state.get_unit(side).hp=engine.battle_state.get_unit(side).max_hp;_refresh())
		_button(row,_t("状態解除","Clear Status"),"SandboxClearStatus_"+side,func()->void:
			var unit: UnitState=engine.battle_state.get_unit(side)
			unit.statuses.clear();unit.card_reservations.clear();unit.repeat_charges=0;unit.next_attack_multiplier=1.0;_refresh())
		_button(row,_t("再使用リセット","Reset Recast"),"SandboxResetRecast_"+side,func()->void:
			for runtime: CardRuntimeState in engine.battle_state.get_unit(side).card_runtime_states:
				if runtime.state==CardRuntimeState.CardState.COOLDOWN:runtime.set_cooldown_remaining(0.0)
			_refresh())
		_button(row,_t("シールド解除","Clear Shield"),"SandboxClearShield_"+side,func()->void:engine.battle_state.get_unit(side).shield=0;_refresh())
	var ai_row: HFlowContainer=HFlowContainer.new();_body.add_child(ai_row)
	for side: String in ["player","enemy"]:
		var ai: CheckButton=CheckButton.new();ai.name="SandboxLiveAI_"+side;ai.text=_t("自分AI","Player AI") if side=="player" else _t("敵AI","Enemy AI");ai.button_pressed=bool(engine.sandbox_options[side+"_ai"]);ai_row.add_child(ai)
		ai.toggled.connect(func(enabled:bool)->void:
			engine.sandbox_options[side+"_ai"]=enabled
			if side=="enemy":engine.set_enemy_ai_enabled(enabled))
	_enemy_card=OptionButton.new();_enemy_card.name="SandboxEnemyCard";_body.add_child(_enemy_card)
	for runtime: CardRuntimeState in engine.battle_state.enemy.card_runtime_states:
		var card: CardDef=engine._get_card_def("enemy",runtime.card_id,runtime.runtime_id)
		_enemy_card.add_item(card.name);_enemy_card.set_item_metadata(_enemy_card.item_count-1,runtime.runtime_id)
	_button(_body,_t("敵カードを登録","Queue Enemy Card"),"SandboxQueueEnemy",func()->void:
		if _enemy_card.selected>=0:engine.request_use_card("enemy",String(_enemy_card.get_selected_metadata()));_refresh())
	var bottom: HFlowContainer=HFlowContainer.new();_body.add_child(bottom)
	_button(bottom,_t("統計","Statistics"),"SandboxStatistics",func()->void:
		paused=true;_sync_pause()
		(battle.get("_analysis_panel") as BattleResultAnalysisPanel).show_details(engine.build_summary(),"player"))
	_button(bottom,_t("同条件で再戦","Restart"),"SandboxRestart",func()->void:SceneRouter.start_sandbox(SandboxSession.config))
	_button(bottom,_t("設定へ","Setup"),"SandboxBattleBack",SceneRouter.go_to_sandbox)
	custom_minimum_size=Vector2(360,0);reset_size()


func _sync_pause() -> void:
	_pause.text=_t("再開","Resume") if paused else _t("一時停止","Pause")
	var stage: BattleStage3D=battle.get("_battle_stage") as BattleStage3D
	if stage!=null:stage.set_playback_speed(0.0 if paused else minf(2.0,speed))


func _refresh() -> void:
	battle.call("_refresh_ui",1.0)


func advance(seconds: float) -> void:
	paused=true;_sync_pause();engine.start_battle();step_time(seconds);_refresh()


func step_time(seconds: float) -> void:
	var remaining: float=minf(2.0,maxf(0.0,seconds))
	while remaining>.000001 and engine.battle_state.winner=="":
		var step: float=minf(.05,remaining)
		if engine.has_battle_started() and bool(engine.sandbox_options.get("player_ai",false)):_player_ai.update(engine,step)
		engine.update(step);remaining-=step
		var unsafe: bool=engine.balance_limit_reached or engine.battle_state.active_instances.size()>=SandboxConfig.MAX_ACTIVE
		for side: String in ["player","enemy"]:
			var unit: UnitState=engine.battle_state.get_unit(side)
			if unit.next_attack_multiplier>1000000.0 or unit.attack>1000000000 or unit.shield>1000000000:unsafe=true
		if unsafe:
			paused=true;_sync_pause();_status.text=_t("安全上限で停止しました。再戦か設定変更で再開してください。","Safety limit reached. Restart or change the setup.");break


func process_battle(delta: float) -> void:
	if NetworkManager.is_session_connected():SceneRouter.go_to_hub();return
	if not paused:step_time(minf(.25,delta)*speed)
