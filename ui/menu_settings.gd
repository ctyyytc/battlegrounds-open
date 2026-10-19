extends CanvasLayer
## Persistent UI above choices. Its lifetime is independent of render_match().
const Preparation=preload("res://ui/match_preparation.gd")
var host
var preparation=Preparation.new()
var route="home"
var mode="all"
var settings_visible=false
var dialog_visible=false
var settings_source="home"
var focus_before: WeakRef
var root: Control
var gear: Button
var overlay: Control
var overlay_header: VBoxContainer
var overlay_footer: VBoxContainer
var settings_clock: Label
var preference_status: Label
var fast_select: OptionButton
var confirmation: CheckButton
var reduced: CheckButton
var busy_hint: Label
var scroll_positions={}
var hero_scroll: ScrollContainer
func _ready() -> void:
	name="MenuSettings";layer=50
	root=Control.new();root.name="PersistentUI";root.theme=host.theme;add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.mouse_filter=Control.MOUSE_FILTER_IGNORE
	gear=ui_button("⚙ 设置",open_settings,"SettingsGear");root.add_child(gear)
	gear.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	gear.offset_left=-360;gear.offset_right=-200;gear.offset_top=18;gear.offset_bottom=62
	get_tree().auto_accept_quit=false
	get_tree().root.close_requested.connect(request_quit)
func blocking() -> bool:
	return settings_visible or dialog_visible
func ui_button(caption: String,callback: Callable,node_name: String) -> Button:
	var b=Button.new();b.text=caption;b.name=node_name;b.custom_minimum_size=Vector2(0,44)
	b.pressed.connect(func():
		if is_instance_valid(b) and b.is_inside_tree() and not b.is_queued_for_deletion():callback.call())
	return b
func _input(event: InputEvent) -> void:
	if not blocking():return
	if event is InputEventKey and event.pressed and event.keycode==KEY_TAB:
		var controls=overlay.find_children("*","BaseButton",true,false).filter(func(c):return c.is_visible_in_tree() and not c.disabled and c.focus_mode!=Control.FOCUS_NONE)
		if not controls.is_empty():
			var index=controls.find(get_viewport().gui_get_focus_owner())
			controls[posmod(index+(-1 if event.shift_pressed else 1),controls.size())].grab_focus()
		get_viewport().set_input_as_handled();return
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		# Defer so every underlying _input sees the shield for this entire event.
		call_deferred("close_overlay")
func _process(_delta: float) -> void:
	gear.visible=host.in_match and not blocking()
	if settings_visible:
		settings_clock.text=stage_text()
		var busy=preferences_busy()
		fast_select.disabled=busy;confirmation.disabled=busy
		busy_hint.visible=busy
func stage_text() -> String:
	if not host.in_match or host.game==null:return "偏好跨启动保留"
	var state=host.game.state
	var phase={"recruit":"招募","combat":"战斗回放","finished":"对局结束","diagnostic":"规则诊断"}.get(state.phase,str(state.phase))
	var clock=" · "+host.timer_text() if state.phase=="recruit" else (" · 已暂停" if state.paused else " · 继续运行")
	return "第 %d 回合 · %s%s" % [int(state.round),phase,clock]
func preferences_busy() -> bool:
	if not host.in_match or host.game==null:return false
	var state=host.game.state
	return state.has("confirmation") or state.has("auto_chain") or not host.pending_play.is_empty() or host.selected_spell>=0 or host.placing_minion>=0 or host.power_target or host.activated_source>=0 or not state.players[0].choices.is_empty() or host.right_spell_intent>=0 or state.has("play_tail") or state.has("cast_tail") or state.has("devour_tail")
func page(title: String,subtitle: String="") -> VBoxContainer:
	host.clear_screen()
	var scroll=ScrollContainer.new();scroll.name="PageScroll";scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;host.screen.add_child(scroll)
	var column=VBoxContainer.new();column.size_flags_horizontal=Control.SIZE_EXPAND_FILL;column.add_theme_constant_override("separation",14);scroll.add_child(column)
	column.add_child(host.label(title,36,host.GOLD))
	if subtitle!="":column.add_child(wrapped(subtitle,17))
	return column
func wrapped(value: String,font_size: int=16) -> Label:
	var l=host.label(value,font_size);l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	return l
func home() -> void:
	route="home"
	var column=page("战棋开放工程","v"+str(ProjectSettings.get_setting("application/config/version"))+" · 外部图文资源模式")
	var center=CenterContainer.new();column.add_child(center)
	var card=host.panel(center);card.custom_minimum_size.x=460
	card.add_child(host.button("开始游戏",show_modes,"StartGame"))
	card.add_child(host.button("继续存档",host.load_game,"Load",not FileAccess.file_exists("user://open_save.json")))
	card.add_child(host.button("设置",open_settings,"MainSettings"))
	card.add_child(host.button("结束游戏",request_quit,"QuitGame"))
	var links=HFlowContainer.new();column.add_child(links)
	links.add_child(host.button("内容百科 · 实现状态",host.encyclopedia,"Encyclopedia"))
	links.add_child(host.button("资源包",host.resource_pack_menu,"ResourcePacks"))
	column.add_child(wrapped("选择开局模式后再选英雄。准备期间不会创建对局或覆盖存档。",16))
	if host.status_message!="":column.add_child(wrapped(host.status_message))
	column.add_child(wrapped("验证池包含已实现内容；完整内容尚未全部实装。",14))
func ensure_preparation() -> void:
	if preparation.epoch==0 or preparation.seed_value!=host.menu_seed:
		if host.menu_seed==0:host.menu_seed=randi_range(1,2147483646)
		preparation.prepare(host.registry,host.menu_seed)
	host.menu_tribes=preparation.tribes.duplicate()
func show_modes() -> void:
	ensure_preparation();route="modes"
	var column=page("开始游戏","选择英雄方式；两种模式使用本局同一合法英雄池。")
	column.add_child(host.button("全英雄手选",func():show_heroes("all"),"ModeAll"))
	column.add_child(wrapped("查看本局全部合法英雄，自由选择；原有英雄说明与开局流程保留。"))
	column.add_child(host.button("英雄三选一",func():show_heroes("three"),"ModeThree"))
	column.add_child(wrapped("从本局合法池均匀抽取最多3位互异英雄，由你选定后开始。"))
	column.add_child(host.button("设置",open_settings,"PreparationSettings"))
	column.add_child(host.button("返回主菜单",home,"BackHome"))
func remember_scroll() -> void:
	if is_instance_valid(hero_scroll):scroll_positions[mode]=hero_scroll.scroll_vertical
func reroll() -> void:
	host.menu_seed=randi_range(1,2147483646);preparation.prepare(host.registry,host.menu_seed);scroll_positions.clear();show_heroes(mode)
func set_seed(value: String) -> void:
	if not value.is_valid_int():return
	host.menu_seed=int(value);preparation.prepare(host.registry,host.menu_seed);scroll_positions.clear();show_heroes(mode)
func show_heroes(selected_mode: String) -> void:
	ensure_preparation();mode=selected_mode;route="heroes"
	var column=page("全英雄手选" if mode=="all" else "英雄三选一")
	hero_scroll=column.get_parent()
	column.add_child(wrapped("种子 %d · 本局登场：%s" % [preparation.seed_value,"、".join(host.ExternalText.terms_list(preparation.tribes))],18))
	var bar=HFlowContainer.new();column.add_child(bar)
	bar.add_child(host.button("返回模式选择",func():remember_scroll();show_modes(),"BackModes"))
	bar.add_child(host.button("设置",func():remember_scroll();open_settings(),"HeroSettings"))
	bar.add_child(host.button("重抽新局",reroll,"NewMatchRoll"))
	var seed=LineEdit.new();seed.name="Seed";seed.text=str(preparation.seed_value);seed.custom_minimum_size.x=270;seed.visible=false;bar.add_child(seed);host.seed_input=seed
	seed.text_submitted.connect(set_seed)
	bar.add_child(host.button("调试种子",func():seed.visible=not seed.visible,"DebugSeed"))
	bar.add_child(host.button("应用种子",func():set_seed(seed.text),"ApplySeed"))
	var ids=preparation.legal if mode=="all" else preparation.candidates
	if ids.size()<3:column.add_child(wrapped("本局只有%d位合法候选。%s" % [ids.size(),"可返回或重抽新局。" if ids.is_empty() else "不补入重复或非法英雄。"],18))
	var grid=GridContainer.new();grid.columns=clampi(int((host.size.x-40)/300),1,4);grid.add_theme_constant_override("h_separation",12);grid.add_theme_constant_override("v_separation",12);column.add_child(grid)
	var token=preparation.epoch
	for id in ids:
		var d=host.registry.get_def(id)
		var b=host.button("",func():choose_hero(id,token),"Hero_"+id)
		b.custom_minimum_size=Vector2(280,270);b.size_flags_horizontal=Control.SIZE_EXPAND_FILL;host.UISkin.button(b,"option_card");b.tooltip_text=d.text
		var v=VBoxContainer.new();v.mouse_filter=Control.MOUSE_FILTER_IGNORE;b.add_child(v);v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);v.offset_left=18;v.offset_right=-18;v.offset_top=18;v.offset_bottom=-18
		v.add_child(host.framed_portrait(id,Vector2(110,105)))
		v.add_child(wrapped(d.name,21));v.add_child(wrapped(d.text,14));v.add_child(host.label("生命 %d   护甲 %d" % [d.health,d.armor],14,host.MUTED))
		grid.add_child(b)
		var fit=func():b.custom_minimum_size.y=maxf(270,v.get_combined_minimum_size().y+36)
		v.minimum_size_changed.connect(fit);fit.call()
	if scroll_positions.has(mode):hero_scroll.set_deferred("scroll_vertical",int(scroll_positions[mode]))
func choose_hero(id: String,token: int) -> void:
	if host.in_match or blocking() or not preparation.accepts(id,token):return
	if mode=="three" and id not in preparation.candidates:return
	var commit=func():
		if not preparation.accepts(id,token) or host.in_match:return
		preparation.committed=true
		host.start_match(id)
	if FileAccess.file_exists("user://open_save.json"):
		confirm_dialog("开始新局？","现有单一存档将在新局开局选择完成后被覆盖。未选英雄的准备不会写盘。",commit,"确认开始新局")
	else:commit.call()
func open_settings() -> void:
	if blocking():return
	settings_source="match" if host.in_match else route
	var focus=get_viewport().gui_get_focus_owner();focus_before=weakref(focus) if focus else null
	var table=host.screen.get_node_or_null("TavernTable") if is_instance_valid(host.screen) else null
	if table:table.reset_drag();table.restore_positions();table.clear_hidden_inspection()
	get_viewport().gui_release_focus()
	settings_visible=true
	var v=make_overlay("设置","SettingsOverlay")
	settings_clock=wrapped(stage_text(),18);settings_clock.name="SettingsClock";overlay_header.add_child(settings_clock)
	v.add_child(wrapped("设置不会自动暂停或恢复对局；计时与回放按当前状态继续。",15))
	v.add_child(host.label("操作偏好",22,host.GOLD))
	fast_select=OptionButton.new();fast_select.name="SettingsFast";fast_select.custom_minimum_size.y=44
	for caption in ["快捷：关闭（0）","快捷：档位1","快捷：档位2"]:fast_select.add_item(caption)
	fast_select.select(host.fast_mode_level);v.add_child(fast_select)
	fast_select.item_selected.connect(func(index):
		if preferences_busy():fast_select.select(host.fast_mode_level);return
		host.set_fast_mode(index);preference_status.text=host.preference_message)
	v.add_child(wrapped("关闭：普通点击与拖拽。档位1：左键快捷使用，法术优先己方最左目标；右键出售场上随从。档位2：右键手牌随从打出后出售，法术优先右端目标；例外仍需手动。",15))
	confirmation=CheckButton.new();confirmation.name="SettingsConfirmation";confirmation.text="防误操作";confirmation.button_pressed=host.confirmation_enabled;v.add_child(confirmation)
	confirmation.toggled.connect(func(value):
		if preferences_busy():confirmation.set_pressed_no_signal(host.confirmation_enabled);return
		host.set_confirmation(value);preference_status.text=host.preference_message)
	v.add_child(wrapped("高风险出售或消灭前提示确认，普通目标和发现仍按原规则处理。",15))
	busy_hint=wrapped("当前有未完成的目标、选择、确认或操作链；完成后可修改快捷与防误操作。",15);busy_hint.name="SettingsBusy";v.add_child(busy_hint)
	v.add_child(host.label("动态表现",22,host.GOLD))
	reduced=CheckButton.new();reduced.name="SettingsReducedMotion";reduced.text="减少动态";reduced.button_pressed=host.reduced_motion_enabled;v.add_child(reduced)
	reduced.toggled.connect(func(value):host.set_reduced_motion(value);preference_status.text=host.preference_message)
	v.add_child(wrapped("简化轮盘、关键词及吞噬表现；待选饰品改用常亮边框和文字。跨启动保留，并应用于新局与读档。",15))
	v.add_child(host.label("操作帮助",22,host.GOLD))
	v.add_child(wrapped("保存：每回合开头强制选择完成后自动存一次；中途可手动保存，包括待选界面。继续存档恢复最近保存进度。\n撤销：最近3个完整招募操作，使用次数不限，不跨回合或读档。\n暂停在招募现场切换；战斗倍速与跳过留在战斗现场。隐藏选择不代表完成。\n资源包只在主菜单管理；数值不同的包不能继续原档。",15))
	preference_status=wrapped(host.preference_message,15);preference_status.name="PreferenceStatus";v.add_child(preference_status)
	var back=ui_button("返回游戏" if host.in_match else "返回英雄准备" if route=="heroes" else "返回模式选择" if route=="modes" else "返回主菜单",close_overlay,"SettingsBack");overlay_footer.add_child(back)
	if host.in_match:
		v.add_child(ui_button("返回主菜单…",func():close_overlay();request_menu(),"SettingsMenu"))
		v.add_child(ui_button("结束游戏…",func():close_overlay();request_quit(),"SettingsQuit"))
	if preferences_busy():reduced.grab_focus()
	else:fast_select.grab_focus()
func make_overlay(title: String,node_name: String) -> VBoxContainer:
	overlay=Control.new();overlay.name=node_name;root.add_child(overlay);overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);overlay.mouse_filter=Control.MOUSE_FILTER_STOP
	var dim=ColorRect.new();dim.color=Color(0,0,0,0.86);overlay.add_child(dim);dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center=CenterContainer.new();overlay.add_child(center);center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var frame=PanelContainer.new();frame.name="SettingsWindow";center.add_child(frame);host.UISkin.panel(frame,"window")
	var shell=VBoxContainer.new();shell.add_theme_constant_override("separation",10);frame.add_child(shell)
	overlay_header=VBoxContainer.new();shell.add_child(overlay_header);overlay_header.add_child(host.label(title,28,host.GOLD))
	var scroll=ScrollContainer.new();scroll.name="SettingsScroll";scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;shell.add_child(scroll)
	scroll.custom_minimum_size=Vector2(minf(760,host.size.x-100),minf(580,host.size.y-260))
	var resize_overlay=func():
		if is_instance_valid(scroll):scroll.custom_minimum_size=Vector2(minf(760,host.size.x-100),minf(580,host.size.y-260))
	host.resized.connect(resize_overlay)
	overlay.tree_exiting.connect(func():if host.resized.is_connected(resize_overlay):host.resized.disconnect(resize_overlay))
	var v=VBoxContainer.new();v.size_flags_horizontal=Control.SIZE_EXPAND_FILL;v.add_theme_constant_override("separation",10);scroll.add_child(v)
	overlay_footer=VBoxContainer.new();shell.add_child(overlay_footer)
	return v
func close_overlay() -> void:
	if not blocking():return
	var was_settings=settings_visible
	settings_visible=false;dialog_visible=false
	if is_instance_valid(overlay):root.remove_child(overlay);overlay.queue_free()
	overlay=null
	if was_settings and host.in_match:host.render_match()
	if focus_before:
		var focus=focus_before.get_ref()
		if is_instance_valid(focus) and focus.is_inside_tree() and focus.is_visible_in_tree():focus.grab_focus()
	focus_before=null
	if host.in_match and get_viewport().gui_get_focus_owner()==null:gear.grab_focus()
	elif not host.in_match and get_viewport().gui_get_focus_owner()==null:
		var target=host.find_child("HeroSettings" if route=="heroes" else "PreparationSettings" if route=="modes" else "MainSettings",true,false)
		if target:target.grab_focus()
func confirm_dialog(title: String,message: String,callback: Callable,accept_text: String,with_save: bool=false) -> void:
	if blocking():return
	dialog_visible=true
	var v=make_overlay(title,"LeaveConfirmation")
	v.add_child(wrapped(message,18))
	if with_save:
		v.add_child(ui_button("手动保存并离开",func():
			host.save_game()
			if host.last_save_error==OK:close_overlay();callback.call()
			else:v.add_child(wrapped(host.status_message)),"SaveAndLeave"))
	v.add_child(ui_button(accept_text,func():close_overlay();callback.call(),"ConfirmLeave"))
	var cancel=ui_button("取消 · 返回游戏" if host.in_match else "取消 · 返回准备",close_overlay,"CancelLeave");v.add_child(cancel);cancel.grab_focus()
func request_menu() -> void:
	if blocking():return
	if not host.in_match:host.menu();return
	confirm_dialog("离开当前对局？","只保留最近存点；本轮尚未保存的操作会丢失。可先手动保存，或确认放弃未保存进度。",host.menu,"放弃未保存进度并返回菜单",true)
func request_quit() -> void:
	if settings_visible:close_overlay()
	if dialog_visible:return
	if not host.in_match:get_tree().quit();return
	confirm_dialog("结束游戏？","只保留最近存点；本轮尚未保存的操作会丢失。可先手动保存，或确认放弃未保存进度。",func():get_tree().quit(),"放弃未保存进度并退出",true)
