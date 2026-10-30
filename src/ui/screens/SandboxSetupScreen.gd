extends Control

var data: Dictionary = {}
var _side_grid: GridContainer
var _deck_grids: Dictionary = {}
var _relic_rows: Dictionary = {}
var _previews: Dictionary = {}
var _stat_widgets: Dictionary = {}
var _stat_grids: Dictionary = {}
var _card_widgets: Dictionary = {}
var _cost_labels: Dictionary = {}
var _status: Label
var _preset_name: LineEdit
var _presets: OptionButton
var _catalog_overlay: ColorRect
var _catalog_grid: GridContainer
var _catalog_search: LineEdit
var _catalog_rarity: OptionButton
var _catalog_tag: OptionButton
var _catalog_page: Label
var _catalog_kind: String
var _catalog_side: String
var _page: int = 0
var _generation: int = 0


func _t(ja: String, en: String) -> String:
	return ja if Localization.get_language() == "ja" else en


func _ready() -> void:
	data = SandboxSession.get_draft()
	_build()
	resized.connect(_layout)
	_layout()
	for side: String in ["player","enemy"]: _refresh_deck(side); _refresh_relics(side)
	_refresh_presets()
	SceneRouter.mark_ui_localized(self)


func _button(parent: Node, text: String, id: String, action: Callable) -> Button:
	var button: Button = Button.new(); button.name=id; button.text=text
	button.set_meta("skip_auto_icon", true)
	if text=="×": UiIconHelper.decorate_square(button,"close",36)
	button.custom_minimum_size.y=42; button.pressed.connect(action); parent.add_child(button)
	return button


func _build() -> void:
	var margin: MarginContainer=MarginContainer.new();margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left",32);margin.add_theme_constant_override("margin_right",32)
	margin.add_theme_constant_override("margin_top",24);margin.add_theme_constant_override("margin_bottom",24);add_child(margin)
	var root: VBoxContainer=VBoxContainer.new();root.add_theme_constant_override("separation",14);margin.add_child(root)
	var header: HBoxContainer=HBoxContainer.new();root.add_child(header)
	var title: Label=Label.new();title.text=_t("サンドボックス","Sandbox");title.add_theme_font_size_override("font_size",32);title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(title)
	title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_button(header,_t("ハブへ","Hub"),"SandboxBack",func()->void:SandboxSession.save_last(data);SceneRouter.go_to_hub())
	var start: Button=_button(header,_t("戦闘開始","Start Battle"),"SandboxStart",_start)
	start.theme_type_variation="PrimaryButton"
	var presets_row: HFlowContainer=HFlowContainer.new();presets_row.add_theme_constant_override("h_separation",8);root.add_child(presets_row)
	_preset_name=LineEdit.new();_preset_name.name="SandboxPresetName";_preset_name.placeholder_text=_t("設定の名前","Preset name");_preset_name.custom_minimum_size=Vector2(180,42);presets_row.add_child(_preset_name)
	_button(presets_row,_t("保存","Save"),"SandboxSavePreset",func()->void:
		var ok: bool=SandboxSession.save_preset(_preset_name.text,data)
		_status.text=_t("設定を保存しました。","Preset saved.") if ok else _t("名前を入力してください。保存は20件までです。","Enter a name; up to 20 presets.")
		_refresh_presets())
	_presets=OptionButton.new();_presets.name="SandboxPresets";_presets.custom_minimum_size=Vector2(180,42);presets_row.add_child(_presets)
	_button(presets_row,_t("読み込む","Load"),"SandboxLoadPreset",func()->void:
		if _presets.selected>=0:
			var title_text: String=_presets.get_item_text(_presets.selected)
			if SandboxSession.presets().has(title_text):_replace_config(SandboxSession.presets()[title_text]);_preset_name.text=title_text)
	_button(presets_row,_t("削除","Delete"),"SandboxDeletePreset",func()->void:
		if _presets.selected>=0:SandboxSession.delete_preset(_presets.get_item_text(_presets.selected));_refresh_presets())
	for entry: Array in [["dummy",_t("動かない標的","Dummy")],["boss",_t("高耐久ボス","Boss")],["regen",_t("リジェネ","Regen")],["echo",_t("反響","Echo")]]:
		_button(presets_row,String(entry[1]),"SandboxExample_"+String(entry[0]),_example.bind(String(entry[0])))
	_status=Label.new();_status.name="SandboxSetupStatus";_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_status.text=_t("設定だけを保存します。通常ラン・報酬・実績・ランキングには影響しません。","Only setup is saved. Normal runs, rewards, achievements and rankings are unaffected.");root.add_child(_status)
	var scroll: ScrollContainer=ScrollContainer.new();scroll.name="SandboxSetupScroll";scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;root.add_child(scroll)
	var body: VBoxContainer=VBoxContainer.new();body.size_flags_horizontal=Control.SIZE_EXPAND_FILL;body.add_theme_constant_override("separation",16);scroll.add_child(body)
	_side_grid=GridContainer.new();_side_grid.name="SandboxSides";_side_grid.columns=2;_side_grid.add_theme_constant_override("h_separation",16);_side_grid.add_theme_constant_override("v_separation",16);body.add_child(_side_grid)
	for side: String in ["player","enemy"]:_build_side(side)
	_build_rules(body)


func _build_side(side: String) -> void:
	var panel: PanelContainer=PanelContainer.new();panel.name="SandboxSide_"+side;panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_side_grid.add_child(panel)
	var margin: MarginContainer=MarginContainer.new();margin.add_theme_constant_override("margin_left",18);margin.add_theme_constant_override("margin_right",18);margin.add_theme_constant_override("margin_top",16);margin.add_theme_constant_override("margin_bottom",16);panel.add_child(margin)
	var root: VBoxContainer=VBoxContainer.new();root.add_theme_constant_override("separation",12);margin.add_child(root)
	var row: HFlowContainer=HFlowContainer.new();root.add_child(row)
	var title: Label=Label.new();title.text=_t("自分","Player") if side=="player" else _t("敵","Enemy");title.add_theme_font_size_override("font_size",24);row.add_child(title)
	var visual: OptionButton=OptionButton.new();visual.name="SandboxVisual_"+side;visual.custom_minimum_size=Vector2(230,42);row.add_child(visual)
	for profile: Dictionary in Database.get_all_battle_visual_profiles():
		var id: String=String(profile.get("id",""))
		if id.begins_with("default_"):continue
		var starter: Dictionary=Database.get_starter(id);var enemy: EnemyDef=Database.get_enemy(id)
		if starter.is_empty() and enemy==null:continue
		visual.add_item(enemy.name if enemy!=null else String(starter["name"]));visual.set_item_metadata(visual.item_count-1,id)
		if id==data[side]["visual"]:visual.select(visual.item_count-1)
	visual.item_selected.connect(func(index:int)->void:
		data[side]["visual"]=String(visual.get_item_metadata(index))
		if side=="enemy":data["enemy_id"]=data[side]["visual"] if Database.get_enemy(data[side]["visual"])!=null else "scout"
		_show_model(side))
	_button(row,_t("標準編成","Default Loadout"),"SandboxTemplate_"+side,func()->void:
		var id: String=String(data[side]["visual"])
		data[side]=SandboxConfig.side_from_enemy(id) if Database.get_enemy(id)!=null else SandboxConfig.side_from_starter(id)
		_replace_config(data))
	if side=="player":_button(row,_t("ランからコピー","Copy Run"),"SandboxCopyRun",_copy_run)
	var model: StarterModelPreview=StarterModelPreview.new();model.name="SandboxModel_"+side;model.custom_minimum_size=Vector2(0,180);root.add_child(model);_previews[side]=model;_show_model(side)
	model.name="SandboxModel_"+side
	var stats: GridContainer=GridContainer.new();stats.columns=4;stats.add_theme_constant_override("h_separation",12);root.add_child(stats)
	_stat_grids[side]=stats
	_stat_widgets[side]={}
	for entry: Array in [["max_hp",_t("最大HP","Max HP")],["hp",_t("開始HP","Start HP")],["attack",_t("攻撃","Attack")],["speed",_t("速度","Speed")],["shield",_t("シールド","Shield")],["slots",_t("スロット","Slots")],["loadout_limit",_t("コスト上限","Loadout Limit")]]:
		var key: String=String(entry[0]);var label: Label=Label.new();label.text=String(entry[1]);stats.add_child(label)
		var spin: SpinBox=_number(stats,"SandboxStat_"+side+"_"+key,int(data[side][key]),SandboxConfig.STAT_LIMITS[key][0],SandboxConfig.STAT_LIMITS[key][1])
		_stat_widgets[side][key]=spin
		spin.value_changed.connect(func(value:float)->void:
			data[side][key]=roundi(value)
			if key=="max_hp" and int(data[side]["hp"])>roundi(value):(_stat_widgets[side]["hp"] as SpinBox).value=value
			_refresh_card_previews(side))
	var actions: HFlowContainer=HFlowContainer.new();root.add_child(actions)
	_button(actions,_t("カードを追加","Add Card"),"SandboxAddCard_"+side,_open_catalog.bind(side,"card"))
	_button(actions,_t("カードを全て外す","Clear Cards"),"SandboxClearCards_"+side,func()->void:data[side]["cards"]=[];_refresh_deck(side))
	_button(actions,_t("遺物を追加","Add Relic"),"SandboxAddRelic_"+side,_open_catalog.bind(side,"relic"))
	var cost: Label=Label.new();cost.name="SandboxCost_"+side;root.add_child(cost);_cost_labels[side]=cost
	_deck_grids[side]=HFlowContainer.new();_deck_grids[side].name="SandboxDeck_"+side;_deck_grids[side].add_theme_constant_override("h_separation",12);_deck_grids[side].add_theme_constant_override("v_separation",12);root.add_child(_deck_grids[side])
	_relic_rows[side]=HFlowContainer.new();_relic_rows[side].name="SandboxRelics_"+side;root.add_child(_relic_rows[side])


func _number(parent: Node, id: String, value: int, minimum: int, maximum: int) -> SpinBox:
	var spin: SpinBox=SpinBox.new();spin.name=id;spin.min_value=minimum;spin.max_value=maximum;spin.value=value;spin.custom_minimum_size=Vector2(115,40);parent.add_child(spin)
	var line: LineEdit=spin.get_line_edit()
	line.text_changed.connect(func(text:String)->void:
		if not text.is_valid_float():return
		var number: float=float(text)
		if not is_finite(number) or number<spin.min_value or number>spin.max_value:return
		var caret: int=line.caret_column;var previous: float=spin.value
		spin.set_value_no_signal(number);spin.apply();line.text=text;line.caret_column=caret
		if not is_equal_approx(previous,spin.value):spin.value_changed.emit(spin.value))
	return spin


func _show_model(side: String) -> void:
	if not _previews.has(side):return
	var id: String=String(data[side]["visual"])
	if Database.get_enemy(id)!=null:(_previews[side] as StarterModelPreview).show_enemy(id)
	else:(_previews[side] as StarterModelPreview).show_starter(id)
	(_previews[side] as StarterModelPreview).set_auto_frame(true)
	SceneRouter.schedule_battle_visuals(String(data["player"]["visual"]),String(data["enemy"]["visual"]))


func _refresh_deck(side: String) -> void:
	var grid: Control=_deck_grids[side]
	for child: Node in grid.get_children():grid.remove_child(child);child.queue_free()
	_card_widgets[side]=[]
	for index: int in Array(data[side]["cards"]).size():
		var group: VBoxContainer=VBoxContainer.new();group.custom_minimum_size.x=120;grid.add_child(group)
		var card: CardButton=CardButton.new();card.name="SandboxCard_"+side+"_"+str(index);card.set_tile_size(Vector2(100,100));group.add_child(card)
		var controls: HBoxContainer=HBoxContainer.new();group.add_child(controls)
		var grade: OptionButton=OptionButton.new();grade.name="SandboxGrade_"+side+"_"+str(index)
		for tier: int in range(6):grade.add_item(_t("基本","Base") if tier==0 else "+"+str(tier))
		grade.select(int(data[side]["cards"][index]["tier"]));controls.add_child(grade)
		grade.item_selected.connect(func(tier:int)->void:data[side]["cards"][index]["tier"]=tier;_refresh_card_previews(side))
		var remove: Button=_button(controls,"×","SandboxRemove_"+side+"_"+str(index),func()->void:data[side]["cards"].remove_at(index);_refresh_deck(side))
		remove.custom_minimum_size=Vector2(36,36)
		_card_widgets[side].append(card)
	_refresh_card_previews(side)


func _refresh_card_previews(side: String) -> void:
	if not _card_widgets.has(side):return
	var run: RunState=SandboxConfig.make_run(SandboxConfig.normalize(data),side)
	var unit: UnitState=UnitState.new();unit.attack=run.attack;unit.speed=run.speed;unit.hp=run.player_hp;unit.max_hp=run.max_hp
	RelicService.new().apply_battle_modifiers(unit,run)
	(_cost_labels[side] as Label).text=_t("ロードアウトコスト","Loadout Cost")+" %d / %d"%[SandboxConfig.loadout_cost(data,side),int(data[side]["loadout_limit"])]
	for index: int in Array(_card_widgets[side]).size():
		var item: Dictionary=data[side]["cards"][index]
		var runtime_id: String="preview_"+str(index);unit.sandbox_card_tiers[runtime_id]=int(item["tier"])
		var context: Dictionary=CardTooltipResolver.build_context(String(item["id"]),run,unit,runtime_id)
		(_card_widgets[side][index] as CardButton).bind_preview(context["card"],String(item["id"]),false,"",context.get("comparison"))


func _refresh_relics(side: String) -> void:
	var row: Control=_relic_rows[side]
	for child: Node in row.get_children():row.remove_child(child);child.queue_free()
	for id: String in Array(data[side]["relics"]):
		var group: HBoxContainer=HBoxContainer.new();row.add_child(group)
		var icon: RelicIcon=RelicIcon.new();icon.set_icon_size(Vector2(48,48));group.add_child(icon);icon.bind_relic_id(id)
		_button(group,"×","SandboxRemoveRelic_"+side+"_"+id,func()->void:data[side]["relics"].erase(id);_refresh_relics(side))
	_refresh_card_previews(side)


func _build_rules(parent: Node) -> void:
	var panel: PanelContainer=PanelContainer.new();parent.add_child(panel)
	var root: VBoxContainer=VBoxContainer.new();panel.add_child(root)
	var row: HFlowContainer=HFlowContainer.new();root.add_child(row)
	for entry: Array in [["ignore_cost",_t("コスト制限なし","Ignore Loadout Cost")],["fatigue",_t("疲労あり","Fatigue")],["enemy_ai",_t("敵AI","Enemy AI")],["player_ai",_t("自分もAI操作","Player AI")],["boss_passive",_t("ボスの固有行動","Boss Behavior")],["immortal_player",_t("自分は倒れない","Player Immortal")],["immortal_enemy",_t("敵は倒れない","Enemy Immortal")]]:
		var key: String=String(entry[0]);var toggle: CheckButton=CheckButton.new();toggle.name="SandboxRule_"+key;toggle.text=String(entry[1]);toggle.button_pressed=bool(data["rules"][key]);row.add_child(toggle)
		toggle.toggled.connect(func(value:bool)->void:data["rules"][key]=value)
	var numeric: HFlowContainer=HFlowContainer.new();root.add_child(numeric)
	for entry: Array in [["power",_t("無限強化（0で無効）","Infinite Power (0 = off)"),0,100],["seed","Seed",1,2147483647]]:
		var label: Label=Label.new();label.text=String(entry[1]);numeric.add_child(label)
		var key: String=String(entry[0]);var spin: SpinBox=_number(numeric,"SandboxRule_"+key,int(data["rules"][key]),int(entry[2]),int(entry[3]))
		if key=="power":spin.tooltip_text=_t("敵のHP・攻撃・速度とカードGradeに強化を適用します。上の数値は強化前です。","Scale enemy HP, attack, speed and card Grades. The editor shows values before scaling.")
		spin.value_changed.connect(func(value:float)->void:data["rules"][key]=roundi(value))
	var fields: OptionButton=OptionButton.new();fields.name="SandboxField";numeric.add_child(fields)
	for field: Dictionary in BattleEnvironmentArt.FIELDS:
		fields.add_item(String(field["ja"] if Localization.get_language()=="ja" else field["en"]));fields.set_item_metadata(fields.item_count-1,field["id"])
		if field["id"]==data["rules"]["field"]:fields.select(fields.item_count-1)
	fields.item_selected.connect(func(index:int)->void:data["rules"]["field"]=fields.get_item_metadata(index))


func _open_catalog(side: String, kind: String) -> void:
	_catalog_side=side;_catalog_kind=kind;_page=0
	_catalog_overlay=ColorRect.new();_catalog_overlay.name="SandboxCatalog";_catalog_overlay.color=Color(0.0,0.01,0.02,.85);_catalog_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);_catalog_overlay.z_index=100;add_child(_catalog_overlay)
	var panel: PanelContainer=PanelContainer.new();panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);panel.offset_left=40;panel.offset_top=40;panel.offset_right=-40;panel.offset_bottom=-40;_catalog_overlay.add_child(panel)
	var root: VBoxContainer=VBoxContainer.new();panel.add_child(root)
	var filters: HFlowContainer=HFlowContainer.new();root.add_child(filters)
	_catalog_search=LineEdit.new();_catalog_search.name="SandboxCatalogSearch";_catalog_search.placeholder_text=_t("名前・IDで検索","Search name / ID");_catalog_search.custom_minimum_size=Vector2(260,42);filters.add_child(_catalog_search)
	_catalog_search.text_changed.connect(func(_text:String)->void:_page=0;_catalog_refresh())
	_catalog_rarity=OptionButton.new();_catalog_rarity.name="SandboxCatalogRarity";filters.add_child(_catalog_rarity)
	for rarity: String in ["","common","rare","epic","legendary"]:_catalog_rarity.add_item(_t("全レア度","All Rarities") if rarity=="" else rarity);_catalog_rarity.set_item_metadata(_catalog_rarity.item_count-1,rarity)
	_catalog_rarity.item_selected.connect(func(_index:int)->void:_page=0;_catalog_refresh())
	_catalog_tag=OptionButton.new();_catalog_tag.name="SandboxCatalogTag";filters.add_child(_catalog_tag)
	for tag: String in ["","attack","shield","heal","regen","support","time","special"]:_catalog_tag.add_item(_t("全種類","All Types") if tag=="" else tag);_catalog_tag.set_item_metadata(_catalog_tag.item_count-1,tag)
	_catalog_tag.item_selected.connect(func(_index:int)->void:_page=0;_catalog_refresh())
	_button(filters,_t("閉じる","Close"),"SandboxCatalogClose",_close_catalog)
	var scroll: ScrollContainer=ScrollContainer.new();scroll.name="SandboxCatalogScroll";scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;root.add_child(scroll)
	_catalog_grid=GridContainer.new();_catalog_grid.columns=maxi(1,mini(8,int((size.x-160)/150)));_catalog_grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_catalog_grid.add_theme_constant_override("h_separation",16);_catalog_grid.add_theme_constant_override("v_separation",16);scroll.add_child(_catalog_grid)
	var pages: HBoxContainer=HBoxContainer.new();root.add_child(pages)
	_button(pages,"<","SandboxCatalogPrevious",func()->void:_page=maxi(0,_page-1);_catalog_refresh())
	_catalog_page=Label.new();pages.add_child(_catalog_page)
	_button(pages,">","SandboxCatalogNext",func()->void:_page+=1;_catalog_refresh())
	_catalog_refresh()


func _catalog_refresh() -> void:
	_generation+=1;var generation: int=_generation
	for child: Node in _catalog_grid.get_children():_catalog_grid.remove_child(child);child.queue_free()
	var entries: Array[Dictionary]=[]
	var query: String=_catalog_search.text.strip_edges().to_lower()
	var rarity: String=String(_catalog_rarity.get_selected_metadata());var tag: String=String(_catalog_tag.get_selected_metadata())
	for entry: Dictionary in SandboxConfig.catalog(_catalog_kind):
		if query!="" and not (String(entry["id"])+" "+String(entry["name"])).to_lower().contains(query):continue
		if rarity!="" and entry["rarity"]!=rarity:continue
		if tag!="" and not Array(entry["tags"]).has(tag):continue
		entries.append(entry)
	var pages: int=maxi(1,ceili(entries.size()/48.0));_page=clampi(_page,0,pages-1)
	_catalog_page.text="%d / %d  (%d)"%[_page+1,pages,entries.size()]
	for index: int in range(_page*48,mini(entries.size(),(_page+1)*48)):
		if generation!=_generation or not is_instance_valid(_catalog_overlay):return
		var id: String=String(entries[index]["id"])
		var tile: VBoxContainer=VBoxContainer.new();tile.custom_minimum_size.x=120;_catalog_grid.add_child(tile)
		if _catalog_kind=="card":
			var card: CardButton=CardButton.new();card.name="SandboxPick_"+id;card.set_tile_size(Vector2(100,100));tile.add_child(card);card.bind_preview(Database.get_card(id),id,true,"")
			card.card_requested.connect(_add_card)
		else:
			var relic: RelicIcon=RelicIcon.new();relic.set_icon_size(Vector2(64,64));tile.add_child(relic);relic.bind_relic_id(id)
			_button(tile,String(entries[index]["name"]),"SandboxPick_"+id,_add_relic.bind(id))
		if index%4==3:await get_tree().process_frame


func _add_card(id: String) -> void:
	if Array(data[_catalog_side]["cards"]).size()>=SandboxConfig.MAX_CARDS:_status.text=_t("カードは片側64枚までです。","Up to 64 cards per side.");return
	data[_catalog_side]["cards"].append({"id":id,"tier":0});_refresh_deck(_catalog_side)


func _add_relic(id: String) -> void:
	if Array(data[_catalog_side]["relics"]).size()>=SandboxConfig.MAX_RELICS:return
	if not data[_catalog_side]["relics"].has(id):data[_catalog_side]["relics"].append(id)
	_refresh_relics(_catalog_side)


func _close_catalog() -> void:
	_generation+=1
	if is_instance_valid(_catalog_overlay):remove_child(_catalog_overlay);_catalog_overlay.queue_free()
	_catalog_overlay=null


func _refresh_presets() -> void:
	_presets.clear()
	for title: String in SandboxSession.presets():_presets.add_item(title)


func _replace_config(raw: Dictionary) -> void:
	data=SandboxConfig.normalize(raw);_generation+=1
	for child: Node in get_children():remove_child(child);child.queue_free()
	_deck_grids.clear();_relic_rows.clear();_previews.clear();_card_widgets.clear();_stat_widgets.clear()
	_stat_grids.clear()
	_cost_labels.clear()
	_build();_layout()
	for side: String in ["player","enemy"]:_refresh_deck(side);_refresh_relics(side)
	_refresh_presets()


func _example(id: String) -> void:
	var config: Dictionary=SandboxConfig.defaults()
	if id=="dummy":config["enemy"]["max_hp"]=1000000;config["enemy"]["hp"]=1000000;config["rules"]["enemy_ai"]=false;config["rules"]["immortal_enemy"]=true;config["rules"]["fatigue"]=false
	elif id=="boss":config["enemy_id"]="boss_timekeeper";config["enemy"]=SandboxConfig.side_from_enemy("boss_timekeeper");config["rules"]["field"]="timekeeper_engine"
	elif id=="regen":config["player"]["hp"]=12;config["player"]["cards"]=[{"id":"regen_patch","tier":0},{"id":"regen_salve","tier":0},{"id":"regen_burst","tier":0}];config["rules"]["enemy_ai"]=false
	elif id=="echo":config["player"]["cards"]=[{"id":"reserve_focus","tier":0},{"id":"echo_cast","tier":0},{"id":"quick_slash","tier":0}];config["enemy"]["max_hp"]=500;config["enemy"]["hp"]=500;config["rules"]["enemy_ai"]=false
	_replace_config(config)


func _copy_run() -> void:
	var run: RunState=Game.current_run
	if run==null:
		var saved: Dictionary=Dictionary(Game.suspended_runs.get(Game.RUN_SETUP_MODE_NORMAL,{})).get("run",{})
		if not saved.is_empty():run=RunState.from_dict(saved)
	if run==null:_status.text=_t("コピーできるランがありません。","No run to copy.");return
	var copied: Dictionary=data.duplicate(true)
	copied["player"].merge({"visual":run.starter_id,"max_hp":run.max_hp,"hp":run.player_hp,"attack":run.attack,"speed":run.speed,"loadout_limit":run.loadout_limit,"cards":[],"relics":run.relics.duplicate()},true)
	for id: String in run.equipped_cards:copied["player"]["cards"].append({"id":id,"tier":int(run.card_upgrades.get(id,0))})
	_replace_config(copied)


func _start() -> void:
	var normalized: Dictionary=SandboxConfig.normalize(data)
	if not SandboxConfig.errors(normalized).is_empty():_status.text=_t("各陣営に1枚以上のカードを設定し、コスト上限を確認してください。","Give both sides at least one card and check loadout costs.");return
	SandboxSession.save_last(normalized)
	SceneRouter.start_sandbox(normalized)


func _layout() -> void:
	if _side_grid!=null:_side_grid.columns=2 if size.x>=1180 else 1
	for grid: GridContainer in _stat_grids.values():grid.columns=2 if size.x<700 else 4
	if is_instance_valid(_catalog_overlay) and is_instance_valid(_catalog_grid):_catalog_grid.columns=maxi(1,mini(8,int((size.x-160)/150)))


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and is_instance_valid(_catalog_overlay):_close_catalog();get_viewport().set_input_as_handled()
