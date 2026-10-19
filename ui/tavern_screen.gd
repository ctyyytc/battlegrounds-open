extends Control
const ExternalText = preload("res://domain/resources/external_content.gd")
const UISkin=preload("res://ui/round143_skin.gd")
const BTheme=preload("res://ui/round142_theme.gd")
const PackStore=preload("res://domain/resources/resource_pack_store.gd")
const R134Wheel=preload("res://ui/round134_wheel.gd")
const R133View=preload("res://ui/round133_presentation.gd")
const Presentation=preload("res://ui/card_presentation.gd")
const SpellText=preload("res://ui/spell_presentation.gd")
const TavernTable=preload("res://ui/tavern_table.gd")
const SpellHistoryPanel=preload("res://ui/spell_history_panel.gd")
const KeywordFX=preload("res://ui/keyword_fx.gd")
var keyword_fx=preload("res://ui/keyword_fx_timeline.gd").new()
var history_open=false
var history_page=0
var history_selected_seq=-1
var history_cutoff=0
const GoldenText=preload("res://ui/golden_ability_text.gd")
const Registry=preload("res://domain/rules/content_registry.gd")
const MatchEngine=preload("res://domain/rules/match_engine.gd")
const Special=preload("res://domain/rules/special_rules.gd")
const ActionAvailability=preload("res://domain/rules/action_availability.gd")
const Selection=preload("res://domain/rules/selection_service.gd")
var autosave_enabled: bool=true
var last_save_error=OK
var fast_mode_enabled: bool=false
var fast_mode_level: int=0
var confirmation_enabled: bool=true
var reduced_motion_enabled: bool=false
var preference_message: String=""
var menu_ui
var registry
var game
var screen: Control
var ui_generation: int=0
var toast: Label
var timer_label: Label
var menu_seed: int=0
var menu_tribes: Array=[]
var activated_ability: String="native"
var seed_input: LineEdit
var selected_board: int=-1
var selected_spell: int=-1
var right_spell_intent: int=-1
var placing_minion: int=-1
var pending_play: Dictionary={}
var timing_enabled: bool=false
var activated_source: int=-1
var power_target: bool=false
var selected_power_slot: int=0
var tick_accumulator: float=0.0
var frame_accumulator: float=0.0
var frame_index: int=0
var combat_presentation: Dictionary={}
var playback_skipped: bool=false
var battle_speed: float=1.0
var in_match: bool=false
var active_choice: String=""
var choice_view_key: String=""
var choice_view_hidden: bool=false
var texture_cache: Dictionary={}
var status_message: String=""
const GOLD=Color("#d7b77a")
const TEXT=Color("#eee6d7")
const MUTED=Color("#adbac1")
const INK=Color("#101923")
const PANEL=Color("#202c38")
class ChoiceShield extends Control:
	var host
	func _get_tooltip(at_position: Vector2) -> String:
		return host.choice_hover_text(get_global_transform_with_canvas()*at_position)
	func _make_custom_tooltip(value: String) -> Object:
		if value.is_empty():return null
		var info=host.rich_label(value,15)
		info.custom_minimum_size.x=390;info.mouse_filter=Control.MOUSE_FILTER_IGNORE
		return info
func choice_hover_text(point: Vector2) -> String:
	if not choice_view_is_hidden() or not is_instance_valid(screen):return ""
	var table=screen.get_node_or_null("TavernTable")
	return table.inspection_text_at(point) if table!=null else ""
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var t=Theme.new()
	t.default_font_size=17
	var font=SystemFont.new()
	font.font_names=PackedStringArray(["Microsoft YaHei UI","Microsoft YaHei","Noto Sans CJK SC"])
	t.default_font=font
	t.set_color("font_color","Label",TEXT)
	t.set_color("font_color","Button",TEXT)
	t.set_color("font_hover_color","Button",Color.WHITE)
	t.set_color("font_disabled_color","Button",Color("#607582"))
	t.set_stylebox("normal","Button",box(PANEL,Color("#657780"),8))
	t.set_stylebox("hover","Button",box(Color("#344757"),GOLD,8))
	t.set_stylebox("pressed","Button",box(Color("#43505a"),GOLD,8))
	t.set_stylebox("disabled","Button",box(Color("#17232e"),Color("#33404a"),8))
	t.set_stylebox("normal","LineEdit",box(INK,Color("#657780"),6))
	t.set_color("font_color","LineEdit",TEXT)
	UISkin.install_theme(t)
	theme=t
	resized.connect(_on_view_resize)
	registry=Registry.new()
	load_preferences()
	menu()
func _on_view_resize() -> void:
	queue_redraw()
	if in_match and game!=null and game.state.phase in ["recruit","combat"]:call_deferred("render_match")
	elif is_instance_valid(menu_ui) and menu_ui.route=="heroes":menu_ui.remember_scroll();menu_ui.call_deferred("show_heroes",menu_ui.mode)
func box(color: Color,border: Color=Color.TRANSPARENT,radius: int=10) -> StyleBoxFlat:
	var s=StyleBoxFlat.new(); s.bg_color=color
	s.border_color=border; s.set_border_width_all(1); s.set_corner_radius_all(radius)
	s.content_margin_left=12; s.content_margin_right=12; s.content_margin_top=8; s.content_margin_bottom=8
	return s
func clear_screen() -> void:
	ui_generation+=1
	if not in_match:choice_view_key="";choice_view_hidden=false
	var old_wheel=get_node_or_null("Round134Wheel")
	if old_wheel:remove_child(old_wheel);old_wheel.queue_free()
	var old_history=get_node_or_null("SpellHistoryOverlay")
	if old_history:remove_child(old_history);old_history.queue_free()
	var old_overlay=get_node_or_null("ChoiceOverlay")
	if old_overlay:
		remove_child(old_overlay); old_overlay.queue_free()
	if is_instance_valid(screen):
		var old_table=screen.get_node_or_null("TavernTable")
		if old_table: old_table.retire()
		remove_child(screen); screen.queue_free()
	screen=MarginContainer.new(); add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]: screen.add_theme_constant_override("margin_"+side,18)
	queue_redraw()
func _draw() -> void:
	var background=BTheme.texture("arcane_slate_background")
	if background:
		var factor=maxf(size.x/background.get_width(),size.y/background.get_height())
		var extent=background.get_size()*factor
		draw_texture_rect(background,Rect2((size-extent)*0.5,extent),false)
		return
	draw_rect(Rect2(Vector2.ZERO,size),INK)
	for i in 14:
		var y=float(i)*size.y/14.0
		draw_line(Vector2(0,y),Vector2(size.x,y+70),Color(0.22,0.28,0.32,0.14),1)
	draw_circle(Vector2(size.x*0.5,size.y*0.45),size.y*0.46,Color(0.22,0.19,0.15,0.16))
func label(text_value: String,font_size: int=17,color: Color=TEXT) -> Label:
	var l=Label.new(); l.text=text_value; l.add_theme_font_size_override("font_size",font_size); l.add_theme_color_override("font_color",color)
	return l
func rich_label(text_value: String,font_size: int=17,color: Color=TEXT) -> RichTextLabel:
	var l=RichTextLabel.new(); l.bbcode_enabled=true; l.text=text_value; l.fit_content=true; l.scroll_active=false
	l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; l.add_theme_font_size_override("normal_font_size",font_size); l.add_theme_color_override("default_color",color)
	return l
func _computed_spell_description(card: Dictionary,rich: bool=false) -> String:
	var external_definition=registry.get_def(card.def_id)

	if card.def_id=="TB_BaconShop_HP_101t2":return ExternalText.phrase("ui_tavern_screen.spell_description.915fd634b008", "说明待补充 · %d") % int(card.get("reward_tier",1))
	var p=presentation_player(card)
	var definition=registry.get_def(card.def_id).duplicate(true)
	if not p.is_empty():
		p=p.duplicate()
		var gem=game.Quilboar.gem_bonus(game,p)
		p["presentation_gem_attack"]=gem.x;p["presentation_gem_health"]=gem.y
		var aura=game.spell_aura(p)
		definition["aura_attack"]=aura.x;definition["aura_health"]=aura.y
	definition["instance_context"]=card
	return SpellText.body(definition,p,rich)
func card_description_rich(card: Dictionary) -> String:
	return SpellText.escape(card_description(card)).replace(SpellText.escape(content_body(card)),content_body(card,true))

func content_body(card: Dictionary,rich: bool=false) -> String:
	var d=registry.get_def(card.def_id)
	var computed=_computed_spell_description(card,rich) if d.kind=="spell" else _computed_elemental_description(card,rich)
	if preload("res://ui/effect_progress_presentation.gd").supported(d):computed=preload("res://ui/effect_progress_presentation.gd").body(d,card)
	return ExternalText.describe(d,card,presentation_player(card),computed,"body",content_parameters(card))

func _computed_elemental_description(card: Dictionary,rich: bool=false) -> String:
	var external_definition=registry.get_def(card.def_id)

	var p=presentation_player(card)
	var definition=registry.get_def(card.def_id).duplicate(true)
	definition.text=preload("res://ui/dynamic_state_presentation.gd").minion_body(definition,card)
	if definition.effects.any(func(e):return e.get("handler","")=="round13"):return preload("res://ui/round13_presentation.gd").minion(game,definition,card,p,rich)
	if definition.effects.any(func(e):return e.get("handler","")=="round12") or definition.id in ["BG28_603t","BG28_603t_G"]:return preload("res://ui/beast_presentation.gd").body(definition,card,p,rich)
	if definition.effects.any(func(e):return e.get("handler","")=="round11"):return preload("res://ui/murloc_presentation.gd").body(game,definition,card,p,rich)
	if definition.effects.any(func(e):return e.get("handler","")=="round10"):return preload("res://ui/demon_presentation.gd").body(definition,card,p,game.state.round if game!=null else 1,rich)
	if definition.effects.any(func(e):return e.get("handler","")=="round9") or definition.id=="BG36_520t":return preload("res://ui/pirate_presentation.gd").body(definition,card,p,rich)
	if definition.effects.any(func(e):return e.get("handler","")=="round8"):
		var view=p.duplicate();view["presentation_round"]=game.state.round if game!=null else -1
		return preload("res://ui/quilboar_presentation.gd").body(definition,card,view,rich)
	if definition.effects.any(func(e):return e.get("handler","")=="round7"):
		var view=p.duplicate();view["presentation_round"]=game.state.round if game!=null else -1
		return preload("res://ui/naga_presentation.gd").body(definition,card,view,rich)
	return preload("res://ui/elemental_presentation.gd").body(definition,p,rich)
func _computed_elemental_card_body(card: Dictionary) -> String:
	var external_definition=registry.get_def(card.def_id)

	if preload("res://ui/effect_progress_presentation.gd").supported(registry.get_def(card.def_id)):
		return preload("res://ui/effect_progress_presentation.gd").body(registry.get_def(card.def_id),card,true)
	var p=presentation_player(card)
	var definition=registry.get_def(card.def_id).duplicate(true);definition.text=preload("res://ui/dynamic_state_presentation.gd").minion_body(definition,card)
	if definition.effects.any(func(e):return e.get("handler","")=="round13"):return preload("res://ui/round13_presentation.gd").minion(game,definition,card,p,true)
	if definition.effects.any(func(e):return e.get("handler","")=="round12") or definition.id in ["BG28_603t","BG28_603t_G"]:return preload("res://ui/beast_presentation.gd").body(definition,card,p,true)
	if definition.effects.any(func(e):return e.get("handler","")=="round11"):return preload("res://ui/murloc_presentation.gd").body(game,definition,card,p,true)
	if definition.effects.any(func(e):return e.get("handler","")=="round10"):return preload("res://ui/demon_presentation.gd").body(definition,card,p,game.state.round if game!=null else 1,true)
	if definition.effects.any(func(e):return e.get("handler","")=="round9") or definition.id=="BG36_520t":return preload("res://ui/pirate_presentation.gd").body(definition,card,p,true)
	if definition.effects.any(func(e):return e.get("handler","")=="round8"):
		var view=p.duplicate();view["presentation_round"]=game.state.round if game!=null else -1
		return preload("res://ui/quilboar_presentation.gd").body(definition,card,view,true)
	if definition.effects.any(func(e):return e.get("handler","")=="round7"):
		var view=p.duplicate();view["presentation_round"]=game.state.round if game!=null else -1
		return preload("res://ui/naga_presentation.gd").body(definition,card,view,true)
	var text=preload("res://ui/elemental_presentation.gd").card_body(definition,p,true)
	return text
func presentation_player(card: Dictionary) -> Dictionary:
	if game==null or not in_match:return {}
	var owner_id=int(card.get("owner",0))
	var p=game.state.players[owner_id].duplicate()
	p["presentation_round"]=int(game.state.round)
	if game.state.phase=="combat":
		var views=combat_presentation.get("player_views",{})
		if views.has(str(owner_id)):p.merge(views[str(owner_id)],true)
	return p
class DescriptionButton extends Button:
	var description_host
	var description_card: Dictionary
	func _make_custom_tooltip(_for_text: String) -> Object:
		var info=description_host.rich_label(description_host.card_description_rich(description_card),15)
		info.mouse_filter=Control.MOUSE_FILTER_IGNORE
		info.custom_minimum_size.x=440
		return info
func button(text_value: String,callback: Callable,node_name: String="",disabled: bool=false) -> Button:
	var b=Button.new(); b.text=text_value; b.custom_minimum_size=Vector2(0,44); b.disabled=disabled
	if node_name!="": b.name=node_name
	b.add_theme_stylebox_override("normal",BTheme.style("button_base"))
	b.add_theme_stylebox_override("hover",box(Color("1d414c"),BTheme.TEAL,8))
	b.add_theme_stylebox_override("pressed",box(Color("164e50"),BTheme.GOLD,8))
	b.add_theme_stylebox_override("disabled",box(Color("142330"),Color("677b88"),8))
	b.add_theme_stylebox_override("focus",box(Color.TRANSPARENT,BTheme.GOLD,8))
	b.add_theme_color_override("font_disabled_color",Color("96a6b2"))
	UISkin.button(b,"button_compact")
	var generation=ui_generation
	b.pressed.connect(func():if generation==ui_generation and not ui_blocked() and b.is_inside_tree():callback.call())
	return b
func panel(parent: Node) -> VBoxContainer:
	var p=PanelContainer.new(); p.add_theme_stylebox_override("panel",box(PANEL,Color("#40525d")));UISkin.panel(p,"panel_detail"); parent.add_child(p)
	var v=VBoxContainer.new(); v.add_theme_constant_override("separation",8); p.add_child(v); return v
func stretch() -> Control:
	var c=Control.new(); c.size_flags_vertical=Control.SIZE_EXPAND_FILL; c.size_flags_horizontal=Control.SIZE_EXPAND_FILL; return c
func image_for(id: String,minimum: Vector2) -> TextureRect:
	var texture_view=TextureRect.new(); texture_view.custom_minimum_size=minimum
	texture_view.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	texture_view.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture_view.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var path=registry.art_path(id)
	if path!="":
		if not texture_cache.has(path): texture_cache[path]=texture_for_path(path)
		texture_view.texture=texture_cache[path]
	return texture_view
func framed_portrait(id: String,minimum: Vector2,compact: bool=false) -> Control:
	var holder=Control.new();holder.name="FramedPortrait_"+id;holder.custom_minimum_size=minimum;holder.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var art=image_for(id,Vector2.ZERO);art.name="PortraitArt";UISkin.mask_portrait(art);holder.add_child(art)
	var frame=UISkin.frame(holder,"portrait_side" if compact else "portrait_main",Rect2(Vector2.ZERO,minimum),"PortraitFrame")
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var layout=func():
		var units=Vector2(44,52) if compact else Vector2(108,116)
		var factor=minf(holder.size.x/units.x,holder.size.y/units.y);var extent=units*factor
		var offset=(holder.size-extent)*0.5
		art.position=offset+extent*Vector2(10.0/108.0,10.0/116.0);art.size=extent*Vector2(88.0/108.0,92.0/116.0)
	layout.call();holder.resized.connect(layout)
	return holder
func texture_for_path(path: String) -> Texture2D:
	if path.is_empty(): return null
	if texture_cache.has(path): return texture_cache[path]
	# Exported built-in images are imported resources; their original files may be absent.
	var builtin_available=path.begins_with("res://") and ResourceLoader.exists(path,"Texture2D")
	if not builtin_available and not FileAccess.file_exists(path):return null
	var texture: Texture2D=null
	if builtin_available or FileAccess.file_exists(path+".import"): texture=load(path)
	else:
		var image=Image.new()
		if image.load(path)==OK: texture=ImageTexture.create_from_image(image)
	if texture==null and path!="res://assets/placeholder.svg":texture=load("res://assets/placeholder.svg")
	texture_cache[path]=texture
	return texture
func ui_texture(asset_key: String) -> Texture2D:
	# Preserve the pre-B freeze overlay and its original no-pack/null behavior.
	if asset_key=="ui:status_frozen:texture:normal:neutral":
		return texture_for_path(str(registry.ui_asset(asset_key).get("path","")))
	var styled=BTheme.texture(asset_key)
	if styled:return styled
	var entry=registry.ui_asset(asset_key)
	return texture_for_path(str(entry.get("path","")))
func ensure_menu_ui() -> void:
	if is_instance_valid(menu_ui):return
	menu_ui=preload("res://ui/menu_settings.gd").new();menu_ui.host=self;add_child(menu_ui)
func ui_blocked() -> bool:
	return is_instance_valid(menu_ui) and menu_ui.blocking()
func request_menu() -> void:
	ensure_menu_ui();menu_ui.request_menu()
func menu() -> void:
	ensure_menu_ui()
	if in_match:
		menu_seed=0;menu_ui.preparation=preload("res://ui/match_preparation.gd").new()
	history_open=false
	clear_pending_play();selected_spell=-1;power_target=false;right_spell_intent=-1;activated_source=-1
	in_match=false;game=null;active_choice="";timer_label=null;toast=null
	for node_name in ["ConsumptionFeedback","Round133Feedback"]:
		var feedback=get_node_or_null(node_name)
		if feedback:remove_child(feedback);feedback.queue_free()
	menu_ui.home()
func start_match(hero: String) -> void:
	if in_match or ui_blocked():return
	autosave_enabled=true
	var seed_value=menu_seed
	game=MatchEngine.new(registry)
	var error=game.start(seed_value,hero)
	if error!="":status_message=ExternalText.ui("ui_tavern_screen.start_match.b33b0325e62d", "此英雄不符合本局种族：")+error;menu();return
	selected_board=-1; selected_spell=-1; power_target=false; active_choice=""; status_message=ExternalText.ui("ui_tavern_screen.start_match.cb73e9b902a1", "点击酒馆卡牌购买，点击手牌打出。")
	in_match=true;frame_index=0;frame_accumulator=0;tick_accumulator=0;combat_presentation={};playback_skipped=false
	render_match();maybe_round_start_autosave()
func load_game() -> void:
	autosave_enabled=true
	game=MatchEngine.new(registry)
	var error=game.load_from("user://open_save.json")
	if error=="NUMERIC_PROFILE_MISMATCH":status_message=ExternalText.ui("resource_packs.save_mismatch","此存档的资源包数值不同。请安装对应资源包后继续，或重新开局。");menu();return
	if error!="": status_message=ExternalText.ui("ui_tavern_screen.load_game.afe99b8dbae6", "无法继续：")+error; menu(); return
	in_match=true; frame_index=0;frame_accumulator=0;tick_accumulator=0; selected_spell=-1; selected_board=-1; power_target=false
	status_message=ExternalText.ui("ui_tavern_screen.load_game.f6e558521d73", "已恢复存档，随机状态与候选保持。"); render_match()
func save_game(show_message: bool=true) -> void:
	if game==null:return
	var checkpoint=game.state.get("round_start_autosave",{})
	var retry=show_message and checkpoint.get("status","")=="failed"
	if retry:checkpoint.status="saved";checkpoint.erase("error")
	last_save_error=game.save_to("user://open_save.json")
	if retry and last_save_error!=OK:checkpoint.status="failed";checkpoint["error"]=last_save_error
	if show_message or last_save_error!=OK: status_message=ExternalText.ui("ui_tavern_screen.save_game.2223a78487d0", "对局已保存") if last_save_error==OK else ExternalText.ui("ui_tavern_screen.save_game.30f339e1afcd", "保存失败：")+error_string(last_save_error)
	if toast: toast.text=status_message
func maybe_round_start_autosave() -> void:
	if not autosave_enabled or not in_match or game==null:return
	var checkpoint=game.state.get("round_start_autosave",{})
	if checkpoint.get("status","")=="failed":
		status_message=ExternalText.ui("ui_tavern_screen.save_game.30f339e1afcd", "保存失败：")+error_string(int(checkpoint.get("error",ERR_FILE_CANT_WRITE)))+" · 请手动保存重试"
		if is_instance_valid(toast) and toast.text!=status_message:toast.text=status_message
		return
	if int(checkpoint.get("round",-1))!=int(game.state.round) or checkpoint.get("status","")!="pending":return
	if not game.round_start_settled():return
	# Serialize success first; a failed write is attempted only once this round.
	checkpoint.status="saved"
	var started=Time.get_ticks_usec();save_game(false);record_stage("autosave:round_start",started)
	if last_save_error!=OK:checkpoint.status="failed";checkpoint["error"]=last_save_error
func load_preferences() -> void:
	fast_mode_enabled=false;fast_mode_level=0;confirmation_enabled=true;reduced_motion_enabled=false
	var path="user://open_preferences.json"
	if not FileAccess.file_exists(path):return
	var parser=JSON.new()
	var parsed=parser.data if parser.parse(FileAccess.get_file_as_string(path))==OK else null
	if parsed is Dictionary:
		fast_mode_level=clampi(int(parsed.get("fast_mode_level",1 if parsed.get("fast_mode_enabled",false) else 0)),0,2)
		fast_mode_enabled=fast_mode_level>0;confirmation_enabled=bool(parsed.get("confirmation_enabled",true))
		reduced_motion_enabled=bool(parsed.get("reduced_motion_enabled",false))
	else:preference_message="偏好文件无法读取，已使用默认设置。"
func save_preferences() -> void:
	var file=FileAccess.open("user://open_preferences.json",FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"schema_version":3,"fast_mode_level":fast_mode_level,"fast_mode_enabled":fast_mode_enabled,"confirmation_enabled":confirmation_enabled,"reduced_motion_enabled":reduced_motion_enabled}));file.flush()
		var error=file.get_error();file.close()
		preference_message="偏好已保存" if error==OK else "偏好写入失败；当前设置仅本次有效："+error_string(error)
	else:preference_message="偏好写入失败；当前设置仅本次有效："+error_string(FileAccess.get_open_error())
func set_fast_mode(level: int) -> void:
	if is_instance_valid(menu_ui) and menu_ui.preferences_busy():return
	cancel_auto_intent();fast_mode_level=clampi(level,0,2);fast_mode_enabled=fast_mode_level>0
	var consumption=get_node_or_null("ConsumptionFeedback")
	if consumption and fast_mode_level==2:consumption.skip_all()
	save_preferences();sync_preferences()
	if in_match and not ui_blocked():render_match()
func toggle_fast_mode() -> void:
	set_fast_mode((fast_mode_level+1)%3)
func set_confirmation(value: bool) -> void:
	if is_instance_valid(menu_ui) and menu_ui.preferences_busy():return
	cancel_auto_intent();confirmation_enabled=value;save_preferences();sync_preferences()
	if in_match and not ui_blocked():render_match()
func set_reduced_motion(value: bool) -> void:
	reduced_motion_enabled=value;save_preferences();sync_preferences()
func sync_preferences() -> void:
	if game!=null:
		game.state["fast_mode_level"]=fast_mode_level if fast_mode_enabled else 0
		game.state["confirmation_enabled"]=confirmation_enabled
		game.state["r134_reduced_motion"]=reduced_motion_enabled
func cancel_auto_intent() -> void:
	right_spell_intent=-1
	if game==null:return
	if game.state.has("confirmation"):
		game.act(0,"cancel_confirmation",{"confirmation_id":game.state.confirmation.id})
	game.stop_auto_chain()
func toggle_confirmation() -> void:
	set_confirmation(not confirmation_enabled)
func render_confirmation() -> void:
	var intent=game.state.confirmation
	var v=modal(ExternalText.ui("ui_tavern_screen.render_confirmation.1b727db67dc5", "此效果需手动继续") if intent.action=="manual_effect" else ExternalText.ui("ui_tavern_screen.render_confirmation.e73ef24093de", "确认")+(ExternalText.ui("ui_tavern_screen.render_confirmation.639ae3ac17b3", "出售") if intent.action=="sell" else ExternalText.ui("ui_tavern_screen.render_confirmation.e0a4ac3b5102", "消灭"))+"："+registry.get_def(intent.target_id).name)
	v.add_child(label(" · ".join(intent.reasons),18,GOLD))
	v.add_child(label(ExternalText.ui("ui_tavern_screen.render_confirmation.86eff72c2faf", "取消将保留已经结算的效果，并停止后续操作。"),16))
	var overlay=get_node("ChoiceOverlay")
	for item in [[ExternalText.ui("ui_tavern_screen.render_confirmation.f78c3b78d742", "确认继续"),"confirm_action","ConfirmAction"],[ExternalText.ui("ui_tavern_screen.render_confirmation.4fa6cdbf1307", "取消"),"cancel_confirmation","CancelConfirmation"]]:
		v.add_child(button(item[0],func():
			if not is_instance_valid(overlay) or overlay.get_meta("resolved",false):return
			overlay.set_meta("resolved",true);command(item[1],{"confirmation_id":intent.id}),item[2]))
func power_feedback_text(reason_code: String) -> String:
	return {"NOT_ENOUGH_COINS":ExternalText.ui("ui_tavern_screen.power_feedback_text.05107fb17ce5", "铸币不足"),"NOT_ENOUGH_HEALTH":ExternalText.ui("ui_tavern_screen.power_feedback_text.c07ad88dc00e", "血量不足"),"CARD_LOCKED":ExternalText.ui("ui_tavern_screen.power_feedback_text.0afca26b955b", "此牌尚未解锁，下一回合可以使用"),"NO_LEGAL_TARGET":ExternalText.ui("ui_tavern_screen.power_feedback_text.8775b52557f4", "当前没有合法目标"),"NO_LEGAL_CANDIDATE":ExternalText.ui("ui_tavern_screen.power_feedback_text.fd089aac28a2", "当前没有可用候选"),"POWER_ALREADY_USED":ExternalText.ui("ui_tavern_screen.power_feedback_text.217352962b64", "本回合技能已使用"),"PASSIVE_POWER":ExternalText.ui("ui_tavern_screen.power_feedback_text.b55d3e0be186", "这是被动技能"),"WRONG_PHASE":ExternalText.ui("ui_tavern_screen.power_feedback_text.6825f024e91b", "当前阶段无法操作"),"MANDATORY_CHOICE":ExternalText.ui("ui_tavern_screen.power_feedback_text.ef084e3642e6", "请先完成当前选择"),"HAND_FULL":ExternalText.ui("ui_tavern_screen.power_feedback_text.ea63321fc910", "手牌已满（16张）"),"POWER_NOT_IMPLEMENTED":ExternalText.ui("ui_tavern_screen.power_feedback_text.1b566465e244", "此技能效果尚未接入")}.get(reason_code,ExternalText.ui("ui_tavern_screen.power_feedback_text.bf9ea4e79855", "当前无法使用：")+reason_code)
func choice_target_pending() -> bool:
	if not in_match or game==null or game.state.players[0].choices.is_empty():return false
	var choice=game.state.players[0].choices[0]
	return choice.kind=="r132_target" or choice.get("round8",false) and choice.kind=="choose_target"
func choice_target_cancellable() -> bool:
	return choice_target_pending() and (game.state.players[0].choices[0].kind=="r132_target" or game.state.players[0].choices[0].get("from_hand",false))
func can_action(kind: String,payload: Dictionary={}) -> bool:
	if not in_match or game==null or game.state.phase!="recruit": return false
	var p=game.state.players[0]
	if not p.alive or not p.choices.is_empty(): return false
	match kind:
		"upgrade": return int(p.tier)<6 and int(p.coins)>=int(p.upgrade_cost)
		"refresh": return game.Payment.refresh(game,p).available
		"buy": return game.preview_action(0,"buy",payload).accepted
		"open_choice":
			var category=str(payload.get("category",""))
			if category!="gift":return game.R13Items.available(game,p,category)
			if category not in ["lesser","greater","gift"]: return false
			if p.sessions.has(category) and not p.sessions[category].resolved: return true
			if category=="lesser":
				return int(game.state.round)>=6 and not p.trinkets.any(func(item):return item.get("slot_size",item.size)=="lesser")
			if category=="greater":
				return int(game.state.round)>=9 and not p.trinkets.any(func(item):return item.get("slot_size",item.size)=="greater")
			return int(game.state.round)>=3 and int(p.coins)>=3 and int(p.gifts_bought)<Selection.GIFT_PURCHASE_LIMIT and int(p.gift_round)!=int(game.state.round) and p.pending_rewards.is_empty()
		"power": return power_availability(int(payload.get("slot_id",0))).available
		"freeze","pause","end": return true
	return false
func power_availability(slot_id: int=0) -> Dictionary:
	return ActionAvailability.power(game,game.state.players[0],slot_id) if in_match and game!=null else {"available":false,"reason":"NO_MATCH","targets":[]}
func payment_view(kind: String,card: Dictionary={}) -> Dictionary:
	var p=game.state.players[0]
	var facts=game.Payment.refresh(game,p) if kind=="refresh" else game.Payment.buy(game,p,card)
	return preload("res://ui/life_payment_presentation.gd").payment(game,facts)
func risk_view(card: Dictionary) -> Dictionary:
	return preload("res://ui/life_payment_presentation.gd").risk(game.Payment.play(game,game.state.players[0],card))
func decorate_refresh(button_node: Button) -> void:
	var view=payment_view("refresh");button_node.set_meta("payment",view)
	button_node.text=ExternalText.ui("ui_tavern_screen.decorate_refresh.0401718ca159", "刷新 · ")+view.text
	var facts=game.Payment.refresh(game,game.state.players[0])
	if not facts.prince_quotas.is_empty():button_node.text+=ExternalText.ui("ui_tavern_screen.decorate_refresh.8c4b1758af4c", "\n免费%d · 生命%d次") % [int(facts.free_count),int(facts.prince_total)]
	button_node.disabled=not view.available;button_node.tooltip_text=view.tooltip
	button_node.add_theme_font_size_override("font_size",14)
	if view.warm:
		for state_name in ["normal","hover","pressed","disabled"]:
			var style=box(Color("722c27") if state_name!="disabled" else Color("422523"),Color("ed8272"),12)
			style.content_margin_top=2;style.content_margin_bottom=2;button_node.add_theme_stylebox_override(state_name,style)
	elif view.life:
		for state_name in ["normal","hover","pressed","disabled"]:
			var style=box(Color("33454a"),Color("86bfd0"),12);style.content_margin_top=2;style.content_margin_bottom=2;button_node.add_theme_stylebox_override(state_name,style)
	if UISkin.has("button_secondary"):
		# Payment still decides availability/text; its warning is an outer trim.
		UISkin.button(button_node,"button_secondary")
		if view.warm or view.life:
			var available_trim=button_node.get_node_or_null("AvailabilityBorder")
			if available_trim:available_trim.visible=false
			UISkin.trim(button_node,Color("ed8272") if view.warm else Color("86bfd0"),"PaymentBorder")
		# Keep Button.text for accessibility and existing payment inspectors,
		# while the visible text gets a measured rail clear of the fixed socket.
		for color_key in ["font_color","font_hover_color","font_pressed_color","font_disabled_color","font_focus_color","font_hover_pressed_color"]:button_node.add_theme_color_override(color_key,Color.TRANSPARENT)
		var payment_text=label(button_node.text,12 if button_node.text.contains("\n") else 14,MUTED if button_node.disabled else TEXT);payment_text.name="PaymentText"
		payment_text.mouse_filter=Control.MOUSE_FILTER_IGNORE;payment_text.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;payment_text.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
		button_node.add_child(payment_text);payment_text.position=Vector2(52,4);payment_text.size=Vector2(maxf(0,button_node.size.x-74),button_node.size.y-8)
func fast_plan(card: Dictionary,zone: String,right_click: bool) -> Dictionary:
	return ActionAvailability.fast_action(game,game.state.players[0],zone,card,right_click,fast_mode_level) if in_match and game!=null else {}
func gift_readiness() -> Dictionary:
	return Selection.gift_readiness(game,game.state.players[0]) if in_match and game!=null else {}
func gift_readiness_text(readiness: Dictionary) -> String:
	if readiness.is_empty(): return ""
	var progress="黑赐已使用 %d/%d\n" % [int(readiness.used),int(readiness.limit)]
	if readiness.options_locked: return progress+ExternalText.phrase("ui_tavern_screen.gift_readiness_text.562b155678a8", "说明待补充 · %d") % int(readiness.locked_count)
	var tiers=[]
	for tier in readiness.allowed_tiers: tiers.append("T"+str(tier))
	var by_tier=[]
	for tier in readiness.allowed_tiers: by_tier.append("T%d：%d" % [int(tier),int(readiness.candidates_by_tier.get(str(tier),0))])
	var status=ExternalText.phrase("ui_tavern_screen.gift_readiness_text.7cb3f7a15ef9", "说明待补充") if readiness.openable else ExternalText.phrase("ui_tavern_screen.gift_readiness_text.6efd6f428db0", "说明待补充")
	if readiness.allowed_tiers.is_empty(): status=ExternalText.phrase("ui_tavern_screen.gift_readiness_text.fbc78eba83e9", "说明待补充")
	return progress+ExternalText.phrase("ui_tavern_screen.gift_readiness_text.d3a871bd1dee", "说明待补充 · %d / %s / %d / %s / %s") % [int(readiness.turn),"、".join(tiers) if not tiers.is_empty() else ExternalText.phrase("ui_tavern_screen.gift_readiness_text.4872d213aefe", "说明待补充"),int(readiness.candidate_count),"；".join(by_tier),status]
func trinket_tooltip(item: Dictionary,p: Dictionary) -> String:
	var d=registry.get_def(str(item.id))
	var details=[preload("res://ui/dynamic_state_presentation.gd").trinket_body(d,item,p,int(game.state.round))]
	if d.effects.any(func(e):return e.get("handler","")=="round9"):details=[preload("res://ui/pirate_presentation.gd").body(d,item,p)]
	if d.effects.any(func(e):return e.get("handler","")=="round8"):details=[preload("res://ui/quilboar_presentation.gd").body(d,item,p)]
	if d.effects.any(func(e):return e.get("handler","")=="round11"):details=[preload("res://ui/murloc_presentation.gd").trinket(game,p,item)]
	if str(item.get("bound_tribe",""))!="": details.append(ExternalText.phrase("ui_tavern_screen.trinket_tooltip.edc179c9b3d7", "说明待补充")+str(item.bound_tribe))
	var values=[]
	for effect_spec in d.get("effects",[]):
		match str(effect_spec.get("handler","")):
			"coin_cap": values.append(ExternalText.phrase("ui_tavern_screen.trinket_tooltip.dc93ae057ec1", "说明待补充 · %d") % int(p.cap_bonus))
			"free_refresh": values.append(ExternalText.phrase("ui_tavern_screen.trinket_tooltip.b119ab5f1a9a", "说明待补充 · %d") % int(p.free_refresh))
			"upgrade_discount": values.append(ExternalText.phrase("ui_tavern_screen.trinket_tooltip.ddbcc9d710c7", "说明待补充 · %d") % int(p.upgrade_cost))
			"coins": values.append(ExternalText.phrase("ui_tavern_screen.trinket_tooltip.61c2edef6538", "说明待补充 · %d") % int(p.coins))
			"heart": pass
			"summon_shield","reborn_copy": values.append(ExternalText.phrase("ui_tavern_screen.trinket_tooltip.f93c684bfea7", "说明待补充 · %d") % maxi(0,int(effect_spec.limit)-int(item.get("combat_uses",0))))
			"avenge_spell": values.append(ExternalText.phrase("ui_tavern_screen.trinket_tooltip.efd652845e86", "说明待补充 · %d") % int(item.get("avenge_avenge_spell",0)))
	if not values.is_empty(): details.append(" · ".join(values))
	return str(d.name)+"\n"+"\n".join(details)
func display_coin_cap(p: Dictionary) -> int:
	return game.coin_capacity(p)
func coin_count_text(p: Dictionary) -> String:
	return "%d/%d" % [int(p.coins),display_coin_cap(p)]
func _process(delta: float) -> void:
	if not in_match or game==null: return
	for node_name in ["Undo","ChoiceUndo"]:
		var undo_button=find_child(node_name,true,false)
		if undo_button:update_undo_button(undo_button)
	keyword_fx.synchronize(game)
	keyword_fx.prune(self)
	keyword_fx.advance(delta,game.state.paused)
	keyword_fx_choice()
	if timing_enabled or OS.get_environment("BG_ROUND51_TIMING")=="1": record_stage("frame_interval",Time.get_ticks_usec()-int(delta*1000000.0))
	if game.state.phase=="recruit":
		for player in game.state.players:
			game.R134.presentation_tick(player,delta,game.state.paused,game.state.get("r134_reduced_motion",false))
		var sale_button=screen.find_child("Sell",true,false)
		if sale_button:sale_button.disabled=selected_board<0 or game.R134.sale_blocked(game.state.players[0])
		var sale_hint=screen.find_child("WheelSaleHint",true,false)
		if sale_hint:sale_hint.text=ExternalText.ui("ui_tavern_screen._process.245366921f3a", "轮盘未结束 · 可跳过动画后出售") if game.R134.sale_blocked(game.state.players[0]) else ExternalText.ui("ui_tavern_screen._process.cff22d746683", "拖动场上随从至此出售")
		if not game.state.paused and (game.state.get("r134_end_requested",false) or game.state.players.any(func(p):return game.R134.pending(p))):game.act(0,"wheel_advance")
		tick_accumulator+=delta
		if tick_accumulator>=1.0:
			tick_accumulator=0
			if not game.state.paused: game.act(0,"tick",{"ms":1000})
			if is_instance_valid(timer_label): timer_label.text=timer_text()
			if int(game.state.remaining_ms)<=0:
				if game.state.players[0].choices.is_empty(): command("end")
	elif game.state.phase=="combat" and not game.state.paused:
		frame_accumulator+=delta
		var table=screen.get_node_or_null("TavernTable")
		var window=table.playback_window if table else maxf(0.55,1.15/battle_speed)
		if frame_accumulator>window:
			frame_accumulator=0
			if frame_index<game.state.get("combat_frames",[]).size()-1:
				frame_index+=1; render_match()
	maybe_round_start_autosave()
func _input(event: InputEvent) -> void:
	if ui_blocked():return
	if history_open:
		if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
			get_viewport().set_input_as_handled();close_spell_history()
		return
	if choice_target_cancellable() or in_match and game!=null and not game.state.players[0].choices.is_empty() and game.state.players[0].choices[0].get("from_hand",false):
		if (event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_RIGHT and event.pressed) or (event is InputEventKey and event.keycode==KEY_ESCAPE and event.pressed):
			get_viewport().set_input_as_handled();command("cancel_choice");return
	
	if in_match and game!=null and not game.state.players[0].choices.is_empty() and event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed and event.double_click:
		get_viewport().set_input_as_handled()
func timer_text() -> String:
	var sec=int(ceil(float(game.state.remaining_ms)/1000.0))
	return (ExternalText.ui("ui_tavern_screen.timer_text.724d359ec409", "已暂停  ") if game.state.paused else "")+"%02d:%02d" % [int(float(sec)/60.0),sec%60]
func update_undo_button(b: Button) -> void:
	var info=game.undo_info()
	var names={"buy":"购买","sell":"出售","play":"打出","fast_play":"快捷打出","fast_play_sell":"打出并出售","move":"换位","shop_move":"酒馆换位","refresh":"刷新","upgrade":"升级","power":"英雄技能","activate":"随从技能","freeze":"冻结","open_choice":"打开选择","resolve_choice":"选择","refresh_choice":"刷新选项","defer_choice":"稍后选择","choose":"选择","choose_target":"选择目标","confirm_action":"确认","cancel_confirmation":"取消确认","cancel_choice":"取消选择"}
	b.disabled=not info.available;b.text="撤销 %d：%s" % [int(info.depth),str(names.get(info.label,info.label))] if info.available else "撤销不可用"
	b.tooltip_text="当前可连续回退%d步；使用次数不限；不跨回合。" % int(info.depth) if info.available else info.reason
func undo_last_operation() -> void:
	var result=game.act(0,"undo")
	if not result.accepted:status_message=result.get("reason","当前无法撤销");return
	selected_board=-1;selected_spell=-1;right_spell_intent=-1;placing_minion=-1;pending_play={};activated_source=-1;power_target=false
	active_choice="";choice_view_key="";choice_view_hidden=false;history_open=false;history_selected_seq=-1
	frame_index=0;frame_accumulator=0;tick_accumulator=0;combat_presentation={};playback_skipped=false
	keyword_fx=preload("res://ui/keyword_fx_timeline.gd").new()
	for node_name in ["ConsumptionFeedback","Round133Feedback"]:
		var feedback=get_node_or_null(node_name)
		if feedback:remove_child(feedback);feedback.queue_free()
	status_message="已撤销上一项招募操作 · 还可回退%d步" % int(game.undo_info().depth);render_match()
func command(kind: String,payload: Dictionary={}) -> void:
	if kind=="undo":undo_last_operation();return
	if kind not in ["play","fast_play","pause","tick"]:right_spell_intent=-1
	if not pending_play.is_empty() and kind not in ["play","pause","tick"]: clear_pending_play()
	var started=Time.get_ticks_usec()
	sync_preferences()
	var r133_anchors={}
	var r133_table=screen.get_node_or_null("TavernTable") if is_instance_valid(screen) else null
	if r133_table:
		for slot_id in r133_table.power_areas:
			r133_anchors["power_"+str(slot_id)]=r133_table.global_position+r133_table.power_areas[slot_id].get_center()
		for token in r133_table.cards:
			if token.zone=="shop":r133_anchors[int(token.card.instance_id)]=token.node.global_position+Vector2(122,70)*token.node.size.x/140.0
	var fx_anchors=keyword_fx_anchors()
	var consumption=get_node_or_null("ConsumptionFeedback")
	if consumption==null:
		consumption=preload("res://ui/consumption_feedback.gd").new();consumption.host=self;add_child(consumption)
	consumption.synchronize()
	if kind in ["cancel_choice","continue"]:keyword_fx.cancel_intent()
	var response=game.act(0,kind,payload)
	record_stage("authority:"+kind,started)
	if response.accepted: clear_pending_play()
	if not response.accepted:
		var messages={"NOT_ENOUGH_COINS":ExternalText.ui("ui_tavern_screen.command.05107fb17ce5", "铸币不足"),"NOT_ENOUGH_HEALTH":ExternalText.ui("ui_tavern_screen.command.c07ad88dc00e", "血量不足"),"CARD_LOCKED":ExternalText.ui("ui_tavern_screen.command.0afca26b955b", "此牌尚未解锁，下一回合可以使用"),"HAND_FULL":ExternalText.ui("ui_tavern_screen.command.ea63321fc910", "手牌已满（16张）"),"RESULT_EXCEEDS_CAPACITY":ExternalText.ui("ui_tavern_screen.command.b9910ed5b471", "操作后阵容会超出容量，无法执行"),"POWER_COOLDOWN":ExternalText.ui("ui_tavern_screen.command.62fd03d79f00", "技能尚在冷却"),"POWER_LOCKED_UNTIL_TURN_3":ExternalText.ui("ui_tavern_screen.command.04d84ef8c18e", "第3回合解锁"),"BOARD_FULL":ExternalText.ui("ui_tavern_screen.command.d24839b76d03", "场上已满"),"TARGET_REQUIRED":ExternalText.ui("ui_tavern_screen.command.603a1408526a", "请点击一个随从作为目标"),"MANDATORY_CHOICE":ExternalText.ui("ui_tavern_screen.command.f31b89cb2ecb", "请先完成发现选择"),"FRIENDLY_UNDEAD_REQUIRED":ExternalText.ui("ui_tavern_screen.command.75806c1d0523", "请选择不同的己方场上亡灵"),"DIFFERENT_FAMILY_REQUIRED":ExternalText.ui("ui_tavern_screen.command.403ea133675e", "请选择不同基础家族的己方亡灵（普通/金色同名均不可）"),"ALREADY_ACTIVATED":ExternalText.ui("ui_tavern_screen.command.dca970e72b7e", "本回合已发动"),"MAGNETIC_TARGET_REQUIRED":ExternalText.ui("ui_tavern_screen.command.f28be7fae0b9", "请选择己方机械或亡灵"),"POWER_ALREADY_USED":ExternalText.ui("ui_tavern_screen.command.217352962b64", "本回合技能已使用"),"PASSIVE_POWER":ExternalText.ui("ui_tavern_screen.command.b55d3e0be186", "这是被动技能"),"WRONG_PHASE":ExternalText.ui("ui_tavern_screen.command.6825f024e91b", "当前阶段无法操作"),"SHOP_TARGET_REQUIRED":ExternalText.ui("ui_tavern_screen.command.8e49d221574a", "请选择合法的酒馆随从"),"BOARD_TARGET_REQUIRED":ExternalText.ui("ui_tavern_screen.command.80bd7dace179", "请选择己方场上随从"),"NO_LEGAL_TARGET":ExternalText.ui("ui_tavern_screen.command.8775b52557f4", "当前没有合法目标"),"NO_LEGAL_CANDIDATE":ExternalText.ui("ui_tavern_screen.command.6513c81143b9", "当前没有可生成的合法候选"),"POWER_NOT_IMPLEMENTED":ExternalText.ui("ui_tavern_screen.command.1b566465e244", "此技能效果尚未接入"),"ALREADY_GOLDEN":ExternalText.ui("ui_tavern_screen.command.9463c8f110d4", "此随从已经是金色"),"INSUFFICIENT_IMPLEMENTED_CANDIDATES":ExternalText.ui("ui_tavern_screen.command.65191cec2a88", "当前验证池候选不足；未扣币、未消耗随机状态"),"CHOICE_LOCKED":ExternalText.ui("ui_tavern_screen.command.41e115454449", "此入口尚未解锁"),"CHOICE_REFRESH_LIMIT":ExternalText.ui("ui_tavern_screen.command.6bcac3bcb82e", "本阶段刷新次数已用完"),"TRINKET_ALREADY_OWNED":ExternalText.ui("ui_tavern_screen.command.469fc79fb2c1", "已购买该阶段饰品"),"GIFT_LIMIT":ExternalText.ui("ui_tavern_screen.command.33925bcf2725", "黑赐本轮或整局购买次数已用完"),"PENDING_REWARDS":ExternalText.ui("ui_tavern_screen.command.e762c3c55c3d", "请先腾出手牌领取奖励")}
		status_message=messages.get(response.error_code,response.error_code)
		if response.error_code=="WHEEL_ANIMATION_PENDING":status_message=ExternalText.ui("ui_tavern_screen.command.bec66a43f103", "轮盘尚未结束，请等待或跳过动画；暂停时请先恢复")
		if response.error_code=="STALE_TRINKET_CANDIDATE":status_message=ExternalText.ui("ui_tavern_screen.command.6b5f76660049", "当前技能不允许选择这件饰品，请选择其他选项")
		if response.error_code=="NO_TOUCH_TARGET":status_message=ExternalText.ui("ui_tavern_screen.command.60f352399be2", "BG28_830无法使用：酒馆中没有可点金的普通随从")
	else:
		status_message=ExternalText.ui("ui_tavern_screen.command.1a6a3e81fa61", "请选择合法目标，随后继续本次快捷结算") if game.state.get("auto_chain",{}).get("stage","")=="manual_target" else ExternalText.ui("ui_tavern_screen.command.9c550d3380cb", "操作已完成"); selected_spell=-1; right_spell_intent=-1; power_target=false; activated_source=-1
		if kind in ["resolve_choice","defer_choice","end","continue"]: active_choice=""
		if kind=="open_choice": active_choice=game.R136Slots.normalize(game,game.state.players[0],str(payload.category))
		if kind=="power":active_choice=game.R136Slots.power_op(game,game.state.players[0],int(payload.get("slot_id",0)))
		if kind=="end": playback_skipped=false; frame_accumulator=0; frame_index=0; status_message=ExternalText.ui("ui_tavern_screen.command.cfa14dd6ab7a", "自动战斗 · 可加速或跳过")
		if kind in ["play","sell","continue"]: selected_board=-1
		maybe_round_start_autosave()
	started=Time.get_ticks_usec(); render_match(); record_stage("render:"+kind,started)
	if response.accepted:
		var feedback=get_node_or_null("Round133Feedback")
		if feedback==null:feedback=R133View.new();feedback.host=self;add_child(feedback)
		feedback.feedback(game.events.slice(int(response.event_start),int(response.event_end)),r133_anchors)
		preload("res://ui/round135_presentation.gd").feedback(self,game.events.slice(int(response.event_start),int(response.event_end)))
		fx_anchors.merge(keyword_fx_anchors(),true)
		keyword_fx.events(self,game.events.slice(int(response.event_start),int(response.event_end)),fx_anchors)
		consumption.feedback(game.events.slice(int(response.event_start),int(response.event_end)),fx_anchors)
func playback_label() -> String:
	return ExternalText.ui("ui_tavern_screen.playback_label.d4ef5e962b7b", "播放 · 1倍") if battle_speed==1.0 else ExternalText.ui("ui_tavern_screen.playback_label.97c674d317dd", "播放 · 快放")
func toggle_playback_speed() -> void:
	battle_speed=4.0 if battle_speed==1.0 else 1.0
	
	var speed_button=screen.find_child("Speed",true,false)
	if speed_button: speed_button.text=playback_label()
func skip_combat() -> void:
	playback_skipped=true; frame_accumulator=0
	frame_index=maxi(0,game.state.get("combat_frames",[]).size()-1)
	render_match()
func render_match() -> void:
	keyword_fx.synchronize(game)
	if game.state.players[0].choices.is_empty():keyword_fx.active=keyword_fx.active.filter(func(v):return v.role!="choice")
	sync_preferences()
	sync_choice_view()
	history_cutoff=int(game.state.event_seq)
	if choice_target_pending():
		var choice=game.state.players[0].choices[0]
		selected_spell=int(choice.get("root",{}).get("root_instance",-1));power_target=false;activated_source=-1
		if status_message==ExternalText.ui("ui_tavern_screen.render_match.9c550d3380cb", "操作已完成"):status_message=ExternalText.ui("ui_tavern_screen.render_match.629402201ea1", "抉择已选定 · 点击合法随从（右键或Esc取消）")
	if not game.state.players[0].choices.is_empty() or (active_choice!="" and game.state.players[0].sessions.has(active_choice) and not game.state.players[0].sessions[active_choice].resolved):history_open=false
	var pointer_position=Vector2(-1000,-1000)
	var hover_id=-1
	var hover_time=0.0
	if screen:
		var old_table=screen.get_node_or_null("TavernTable")
		if old_table:
			pointer_position=old_table.pointer
			hover_time=old_table.hovered_seconds
			if not old_table.hovered.is_empty(): hover_id=int(old_table.hovered.card.instance_id)
	clear_screen()
	if game.state.phase in ["recruit","combat"]:
		var table=TavernTable.new()
		table.name="TavernTable"
		table.host=self
		screen.add_child(table)
		table.restore_hover(pointer_position,hover_id,hover_time)
		if game.state.phase=="recruit":
			var wheel_view=R134Wheel.new();wheel_view.host=self;add_child(wheel_view)
		if game.state.has("confirmation"):render_confirmation()
		elif not game.state.players[0].choices.is_empty(): render_choice(game.state.players[0])
		elif active_choice!="" and game.state.players[0].sessions.has(active_choice) and not game.state.players[0].sessions[active_choice].resolved: render_selection(game.state.players[0])
		if history_open:render_spell_history()
		return
	var root=VBoxContainer.new(); root.add_theme_constant_override("separation",10); screen.add_child(root)
	var header=HBoxContainer.new(); root.add_child(header)
	header.add_child(label(ExternalText.ui("ui_tavern_screen.render_match.949e9468c622", "战棋开放工程"),28,GOLD))
	header.add_child(label(ExternalText.ui("ui_tavern_screen.render_match.83932cc76f60", "  第 %d 回合") % game.state.round,23))
	var s=stretch(); header.add_child(s)
	timer_label=label(timer_text() if game.state.phase=="recruit" else ExternalText.ui("ui_tavern_screen.render_match.b896f7e006a8", "自动战斗") if game.state.phase=="combat" else ExternalText.ui("ui_tavern_screen.render_match.35fe6feef012", "对局结算"),24,GOLD); header.add_child(timer_label)
	header.add_child(button(ExternalText.ui("ui_tavern_screen.render_match.e55d2d5fac4f", "保存"),func():save_game(),"Save"))
	header.add_child(button(ExternalText.ui("ui_tavern_screen.render_match.c008f063456a", "返回"),request_menu,"Menu"))
	var status=label(ExternalText.ui("ui_tavern_screen.render_match.6e0d9b4aaf95", "开发验证池  ·  正式完整内容未全部实现  ·  种子 %d") % game.state.seed,14,MUTED); root.add_child(status)
	var middle=HBoxContainer.new(); middle.size_flags_vertical=Control.SIZE_EXPAND_FILL; middle.add_theme_constant_override("separation",12); root.add_child(middle)
	var standings=panel(middle); standings.get_parent().custom_minimum_size.x=185
	standings.add_child(label(ExternalText.ui("ui_tavern_screen.render_match.272655f73892", "八人酒馆"),22,GOLD))
	for p in game.state.players:
		var row=label(("%s  %s" % [p.name,"♥ %d  ◇ %d" % [p.health,p.armor] if p.alive else ExternalText.ui("ui_tavern_screen.render_match.5ee8420e50bc", "已淘汰")]),16,TEXT if p.alive else MUTED)
		standings.add_child(row)
		standings.add_child(label(registry.get_def(p.hero_id).name+"  ·  "+str(p.tier)+ExternalText.ui("ui_tavern_screen.render_match.1867a21a5ca4", "本"),12,MUTED))
	standings.add_child(stretch())
	standings.add_child(label(ExternalText.ui("ui_tavern_screen.render_match.a70d8765fb8c", "本局类型
")+" · ".join(ExternalText.terms_list(game.state.enabled_tribes)),14,GOLD))
	var center_window=PanelContainer.new();center_window.name="ResultsWindow";center_window.size_flags_horizontal=Control.SIZE_EXPAND_FILL;UISkin.panel(center_window,"window");middle.add_child(center_window)
	var center=VBoxContainer.new(); center.size_flags_horizontal=Control.SIZE_EXPAND_FILL; center.add_theme_constant_override("separation",12); center_window.add_child(center)
	var p=game.state.players[0]
	if game.state.phase=="recruit": recruit_board(center,p)
	elif game.state.phase=="combat": combat_board(center)
	elif game.state.phase=="diagnostic":
		center.add_child(label(ExternalText.ui("ui_tavern_screen.render_match.580ac4043ae2", "规则诊断暂停：")+str(game.state.get("rules_error","unknown")),24,GOLD))
		center.add_child(label(ExternalText.ui("ui_tavern_screen.render_match.fe5ad09f9ade", "请保存对局；诊断队列与种子会保留。"),18))
	else:
		var winner=int(game.state.champion)
		center.add_child(label(ExternalText.ui("ui_tavern_screen.render_match.d88b8af99e6e", "冠军：")+game.state.players[winner].name if winner>=0 else ExternalText.ui("ui_tavern_screen.render_match.041c9c03ef56", "对局结束"),40,GOLD))
		center.add_child(label(ExternalText.ui("ui_tavern_screen.render_match.75d5ea25f2b0", "你的名次：第 %d 名") % p.rank,26))
		center.add_child(button(ExternalText.ui("ui_tavern_screen.render_match.b655f4a259f9", "再来一局"),request_menu,"NewMatch"))
	var controls=panel(middle); controls.get_parent().custom_minimum_size.x=205
	controls.add_theme_constant_override("separation",4)
	controls.add_child(image_for(p.hero_id,Vector2(110,76)))
	controls.add_child(label(registry.get_def(p.hero_id).name,20,GOLD))
	controls.add_child(label("铸币 "+coin_count_text(p),24,GOLD))
	controls.add_child(label(ExternalText.ui("ui_tavern_screen.render_match.5a5663dbc542", "酒馆等级 %d") % p.tier,18))
	if game.state.phase=="recruit":
		var disabled=not p.alive
		var refresh_node=button("",func():command("refresh"),"Refresh",disabled);controls.add_child(refresh_node);decorate_refresh(refresh_node)
		controls.add_child(button(ExternalText.ui("ui_tavern_screen.render_match.947d8165ab93", "解冻") if p.frozen else ExternalText.ui("ui_tavern_screen.render_match.9735bab88cd6", "冻结 · 免费"),func():command("freeze"),"Freeze",disabled))
		controls.add_child(button(ExternalText.ui("ui_tavern_screen.render_match.d04536d28a80", "升级 · %d币") % p.upgrade_cost if p.tier<6 else ExternalText.ui("ui_tavern_screen.render_match.c3cf5f7160cd", "已达6本"),func():command("upgrade"),"Upgrade",disabled or p.tier>=6))
		controls.add_child(button(ExternalText.ui("ui_tavern_screen.render_match.81e0013c77ef", "英雄技能 · %d币") % game.power_cost(p),request_power,"Power",disabled))
		controls.add_child(button(ExternalText.ui("ui_tavern_screen.render_match.a71566015971", "继续计时") if game.state.paused else ExternalText.ui("ui_tavern_screen.render_match.37dd55a59866", "暂停"),func():command("pause"),"Pause"))
		controls.add_child(button(ExternalText.ui("ui_tavern_screen.render_match.88702828015b", "结束回合") if p.alive else ExternalText.ui("ui_tavern_screen.render_match.ec19581d35f8", "观战下一轮"),func():command("end"),"EndTurn"))
	elif game.state.phase=="combat":
		controls.add_child(button(playback_label(),toggle_playback_speed,"Speed"))
		controls.add_child(button(ExternalText.ui("ui_tavern_screen.render_match.36035edbb6e7", "跳过战斗"),skip_combat,"Skip"))
		controls.add_child(button(ExternalText.ui("ui_tavern_screen.render_match.8735770c2979", "下一回合") if not game.state.get("match_over",false) else ExternalText.ui("ui_tavern_screen.render_match.9351b5bd3d24", "查看结算"),func():command("continue"),"Continue"))
	controls.add_child(stretch())
	if game.state.phase=="recruit" and p.alive:
		controls.add_child(button(ExternalText.phrase("ui_tavern_screen.render_match.05c1ab510a31", "说明待补充"),func():command("open_choice",{"category":"lesser"}),"Lesser",game.state.round<6))
		controls.add_child(button(ExternalText.phrase("ui_tavern_screen.render_match.1c050e066f89", "说明待补充"),func():command("open_choice",{"category":"greater"}),"Greater",game.state.round<9))
		controls.add_child(button(ExternalText.phrase("ui_tavern_screen.render_match.34dd27d31117", "说明待补充"),func():command("open_choice",{"category":"gift"}),"Gift",game.state.round<3))
	for item in p.trinkets:
		controls.add_child(label(registry.get_def(item.id).name,13,GOLD))
	toast=label(status_message.split("\n")[0],17,GOLD); toast.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; root.add_child(toast)
	if game.state.phase=="recruit":
		render_hand(root,p)
		if not p.choices.is_empty(): render_choice(p)
		elif active_choice!="" and p.sessions.has(active_choice) and not p.sessions[active_choice].resolved: render_selection(p)
func row_cards(parent: Node,title: String,cards: Array,zone: String) -> void:
	parent.add_child(label(title,18,GOLD))
	var scroll=ScrollContainer.new(); scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO; scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y=173; parent.add_child(scroll)
	var row=HBoxContainer.new(); row.add_theme_constant_override("separation",8); scroll.add_child(row)
	for c in cards: row.add_child(card_button(c,zone))
	if cards.is_empty(): row.add_child(label(ExternalText.ui("ui_tavern_screen.row_cards.2979c78cac3c", "这里暂时没有随从"),18,MUTED))
func visible_spell_history() -> Array:
	return game.spell_history.filter(func(entry):return int(entry.seq)<=history_cutoff)
func open_spell_history() -> void:
	if not game.state.players[0].choices.is_empty():return
	if active_choice!="" and game.state.players[0].sessions.has(active_choice) and not game.state.players[0].sessions[active_choice].resolved:return
	history_open=true;history_page=0;history_selected_seq=-1;render_spell_history()
func close_spell_history() -> void:
	history_open=false
	var panel_node=get_node_or_null("SpellHistoryOverlay")
	if panel_node:remove_child(panel_node);panel_node.queue_free()
func render_spell_history() -> void:
	var old=get_node_or_null("SpellHistoryOverlay")
	if old:remove_child(old);old.queue_free()
	var panel_node=SpellHistoryPanel.new();panel_node.host=self;panel_node.page=history_page;panel_node.selected_seq=history_selected_seq;add_child(panel_node)
func show_history_until(seq: int) -> void:
	history_cutoff=seq
	var records=visible_spell_history()
	var open_button=screen.find_child("SpellHistoryOpen",true,false)
	if open_button:open_button.text=ExternalText.ui("ui_tavern_screen.show_history_until.0735232b42ec", "法术记录 · %d") % records.size()
	var summary=screen.find_child("SpellHistorySummary",true,false)
	if summary:
		var lines=[]
		for entry in records.slice(maxi(0,records.size()-2)):
			lines.append({"cast":ExternalText.ui("ui_tavern_screen.show_history_until.593d013875d0", "施放"),"gain":ExternalText.ui("ui_tavern_screen.show_history_until.441c6ce24dbf", "获得"),"pending":ExternalText.ui("ui_tavern_screen.show_history_until.6dbd453c8223", "待领取"),"unavailable":ExternalText.ui("ui_tavern_screen.show_history_until.10ad77c2ab83", "无收益")}.get(entry.action,entry.action)+" · "+str(entry.name))
		summary.text="\n".join(lines)
	if history_open:render_spell_history()
func recruit_board(parent: VBoxContainer,p: Dictionary) -> void:
	row_cards(parent,ExternalText.ui("ui_tavern_screen.recruit_board.ba233389cf98", "酒馆  ·  点击购买  ")+(ExternalText.ui("ui_tavern_screen.recruit_board.441eacfcfdf2", "❄ 已冻结") if p.frozen else ""),p.shop,"shop")
	var selected_index=game.find_index(p.board,selected_board)
	if selected_index>=0:
		var detail=label(card_description(p.board[selected_index]),15,GOLD)
		detail.name="SelectedCardDetail"
		detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		parent.add_child(detail)

	parent.add_child(stretch())
	row_cards(parent,ExternalText.ui("ui_tavern_screen.recruit_board.0d4bd828416a", "你的战队  %d / %d") % [p.board.size(),Special.capacity(p.board)],p.board,"board")
	var bar=HBoxContainer.new(); parent.add_child(bar)
	bar.add_child(button(ExternalText.ui("ui_tavern_screen.recruit_board.41047349f1a0", "← 左移"),func():move_selected(-1),"MoveLeft",selected_board<0))
	bar.add_child(button(ExternalText.ui("ui_tavern_screen.recruit_board.9efa561b721a", "右移 →"),func():move_selected(1),"MoveRight",selected_board<0))
	bar.add_child(button(ExternalText.ui("ui_tavern_screen.recruit_board.e2f0e6db9fb5", "出售选中随从 · +1币"),func():command("sell",{"instance_id":selected_board}),"Sell",selected_board<0 or game.R134.sale_blocked(p)))
func render_hand(parent: Node,p: Dictionary) -> void:
	var title=ExternalText.ui("ui_tavern_screen.render_hand.f68ae00e7c10", "手牌  %d / 16") % p.hand.size()
	if not p.pending_rewards.is_empty(): title+=ExternalText.ui("ui_tavern_screen.render_hand.d09372fb9963", "  ·  奖励已保留，腾出手牌后发放")
	row_cards(parent,title+ExternalText.ui("ui_tavern_screen.render_hand.a430d64e3412", "  ·  点击打出；法术再点击目标"),p.hand,"hand")
func card_button(card: Dictionary,zone: String,inline_description: bool=false) -> Button:
	var d=game.play_definition(card) if game!=null and in_match else registry.get_def(card.def_id)
	var b: Button
	if inline_description:
		b=Button.new()
	else:
		var description_button=DescriptionButton.new()
		description_button.description_host=self; description_button.description_card=card
		b=description_button
	b.name=zone.capitalize()+"_"+str(int(card.instance_id)); b.custom_minimum_size=Vector2(108,155)
	UISkin.button(b,"option_card")
	if zone=="choice":b.custom_minimum_size=Vector2(190,280)
	if not inline_description:b.tooltip_text=card_description(card)
	var gift_counts={}
	var shown_gifts=preload("res://ui/dynamic_state_presentation.gd").displayed_gifts(game,card)
	for gift in shown_gifts:
		var gift_id=int(gift.id)
		gift_counts[gift_id]=int(gift_counts.get(gift_id,0))+1
	for gift_id in gift_counts:
		for gift_def in registry.definitions.values():
			if gift_def.kind=="dark_gift" and int(gift_def.numeric_id)==gift_id:
				b.tooltip_text+=ExternalText.ui("ui_tavern_screen.card_button.6a2d84a53a6c", "\n黑赐 · ")+gift_def.name+" ×"+str(gift_counts[gift_id])+"\n"+gift_def.text
	var gold_badge=GoldenText.badge(d,card,game.state.enabled_tribes)
	var highlighted=int(card.instance_id) in [selected_board,selected_spell]
	if d.get("golden",false) or highlighted: b.add_theme_stylebox_override("normal",box(Color("#3c3527"),GOLD,9))
	var v=VBoxContainer.new(); v.mouse_filter=Control.MOUSE_FILTER_IGNORE; b.add_child(v)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); v.offset_left=5; v.offset_right=-5; v.offset_top=5; v.offset_bottom=-5
	var name_label=label(d.name,13,GOLD if d.get("golden",false) else TEXT)
	name_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; name_label.custom_minimum_size.x=96; v.add_child(name_label)
	v.add_child(image_for(d.id,Vector2(94,64 if gold_badge!="" else 80)))
	if d.kind=="minion":
		var stats=game.stats(card) if not card.has("attack") else Vector2i(int(card.attack),int(card.health))
		v.add_child(label("%s / %s  ★%d" % [Presentation.number(stats.x),Presentation.number(stats.y),d.tier],17,GOLD))
		var kw=Presentation.effective(card,game)
		var tags=[]
		for k in kw:
			var names={"TAUNT":ExternalText.ui("ui_tavern_screen.card_button.0238d1e3da2c", "嘲讽"),"REBORN":ExternalText.ui("ui_tavern_screen.card_button.b5a9c20568b6", "复生"),"DIVINE_SHIELD":ExternalText.ui("ui_tavern_screen.card_button.364ecf3c3959", "圣盾"),"WINDFURY":ExternalText.ui("ui_tavern_screen.card_button.bc1cb4e341a4", "风怒"),"VENOMOUS":ExternalText.ui("ui_tavern_screen.card_button.7d83e2137b93", "烈毒")}
			if k in names: tags.append(ExternalText.term(str(k),names[k]))
		if not gift_counts.is_empty(): tags.append(ExternalText.ui("ui_tavern_screen.card_button.bdbc594d0d6f", "黑赐×")+str(shown_gifts.size()))
		var tags_label=label(" ".join(tags),11,MUTED); tags_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; v.add_child(tags_label)
		if zone=="choice" and card.has("r13_gift_id"):
			var gift_label=label(ExternalText.ui("ui_tavern_screen.card_button.1c77cae0f2d2", "黑赐 · ")+preload("res://ui/dynamic_state_presentation.gd").gifts(game,card),12,GOLD)
			gift_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
			v.add_child(gift_label)
	else:
		v.add_child(label(ExternalText.phrase("ui_tavern_screen.card_button.a80a9437e4bd", "说明待补充 · %d") % int(d.prize_tier) if d.get("is_darkmoon_prize",false) else ExternalText.phrase("ui_tavern_screen.card_button.bd5cda029c79", "说明待补充 · %d / %s") % [d.get("cost",0),ExternalText.phrase("ui_tavern_screen.card_button.7b6e54ac41a3", "说明待补充") if d.get("payment_resource","")=="health" else ExternalText.phrase("ui_tavern_screen.card_button.3ebb80ebb72c", "说明待补充")],15,GOLD))
		var effect_body=rich_label(spell_description(card,true),10)
		effect_body.custom_minimum_size.x=180 if zone=="choice" else 96
		effect_body.mouse_filter=Control.MOUSE_FILTER_IGNORE; v.add_child(effect_body)
	if gold_badge!="":
		var badge_label=label(gold_badge,11,GOLD)
		badge_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		v.add_child(badge_label)
	if zone!="choice":
		var generation=ui_generation
		b.pressed.connect(func():if generation==ui_generation:card_clicked(card,zone))
	return b
func clear_pending_play() -> void:
	pending_play={}; placing_minion=-1
func begin_minion_placement(id: int,index: int) -> void:
	var args={"instance_id":id,"index":index}
	var result=game.preview_placement(0,args)
	if not result.accepted:
		status_message=ExternalText.ui("ui_tavern_screen.begin_minion_placement.db4b050809e4", "无法落位：")+str(result.error_code); clear_pending_play(); render_match(); return
	var p=game.state.players[0]; var card=p.hand[game.find_index(p.hand,id)]
	var d=game.play_definition(card) if game!=null and in_match else registry.get_def(card.def_id)
	var has_target=false
	if game.preview_action(0,"play",args).accepted:
		clear_pending_play();command("play",args);return
	for target in p.board+p.shop:
		var query=args.duplicate(); query["target_id"]=int(target.instance_id)
		if game.preview_action(0,"play",query).accepted: has_target=true; break
	if not has_target:
		clear_pending_play(); status_message=ExternalText.ui("ui_tavern_screen.begin_minion_placement.db79264b2302", "没有合法战吼目标，随从保留在手牌"); render_match(); return
	pending_play=args; placing_minion=-1; selected_spell=id; power_target=false; activated_source=-1
	status_message=ExternalText.ui("ui_tavern_screen.begin_minion_placement.0e6d95af4e84", "落位已确定 · 请选择战吼目标（右键或Esc取消）"); render_match()
func placement_board() -> Array:
	var p=game.state.players[0]; var result=p.board.duplicate()
	if not p.choices.is_empty() and p.choices[0].get("from_hand",false) and p.choices[0].root.kind=="minion":
		var held=game.find_index(p.hand,int(p.choices[0].root.root_instance))
		if held>=0:result.insert(clampi(int(p.choices[0].root.placement_index),0,result.size()),p.hand[held])
	if not pending_play.is_empty():
		var index=game.find_index(p.hand,int(pending_play.instance_id))
		if index>=0: result.insert(clampi(int(pending_play.index),0,result.size()),p.hand[index])
	return result
func record_stage(stage: String,started: int) -> void:
	if not timing_enabled and OS.get_environment("BG_ROUND51_TIMING")!="1": return
	var record={"stage":stage,"elapsed_usec":Time.get_ticks_usec()-started,"round":game.state.round,"revision":game.state.revision,"board_count":game.state.players[0].board.size(),"events":game.events.size()}
	var file=FileAccess.open("user://round51-timings.jsonl",FileAccess.READ_WRITE if FileAccess.file_exists("user://round51-timings.jsonl") else FileAccess.WRITE)
	if file: file.seek_end(); file.store_line(JSON.stringify(record)); file.close()
func card_clicked(card: Dictionary,zone: String) -> void:
	if ui_blocked():return
	if game.state.phase!="recruit": return
	if choice_target_pending():
		if zone in ["board","shop"]:command("choose_target",{"target_id":int(card.instance_id)})
		return
	if not pending_play.is_empty():
		if zone in ["board","shop"]:
			var args=pending_play.duplicate(); args["target_id"]=int(card.instance_id)
			command("play",args); return
		clear_pending_play(); selected_spell=-1
	if activated_source>=0:
		if zone in ["board","shop"]:command("activate",{"instance_id":activated_source,"target_id":card.instance_id,"ability":activated_ability})
		return
	if power_target and zone in ["board","shop"]:
		command("power",{"slot_id":selected_power_slot,"epoch":game.Powers.selected(game,game.state.players[0],selected_power_slot).epoch,"target_id":card.instance_id}); return
	if selected_spell>=0 and zone in ["board","shop"]:
		var from_right=right_spell_intent==selected_spell and fast_mode_level==2
		command("fast_play" if from_right else "play",{"instance_id":selected_spell,"target_id":card.instance_id,"right_click":from_right}); return
	if zone=="shop": command("buy",{"instance_id":card.instance_id})
	elif zone=="hand":
		right_spell_intent=-1
		placing_minion=-1
		var d=game.play_definition(card) if game!=null and in_match else registry.get_def(card.def_id)
		if d.kind=="minion" and game.requires_battlecry_target(d):
			begin_minion_placement(int(card.instance_id),game.state.players[0].board.size())
		elif (d.kind=="spell" and d.effects[0].get("target","none") in ["minion","friendly_minion","friendly_undead"]) or d.effects.any(func(e):return e.handler=="magnetic"):
			selected_spell=int(card.instance_id); status_message=ExternalText.ui("ui_tavern_screen.card_clicked.9e73bb64d0a3", "已选择 ")+d.name+ExternalText.ui("ui_tavern_screen.card_clicked.fa6677491627", "：点击己方或酒馆随从"); render_match()
		else: command("play",{"instance_id":card.instance_id})
	elif zone=="board":
		selected_board=int(card.instance_id); status_message=card_description(card); render_match()
func request_activate(ability: String="native") -> void:
	activated_ability=ability
	var available=game.activate_availability(0,selected_board,ability)
	if not available.available: status_message=power_feedback_text(str(available.reason)); render_match(); return
	if available.targets==[-1]: command("activate",{"instance_id":selected_board,"ability":ability});return
	clear_pending_play()
	activated_source=selected_board; selected_spell=-1; power_target=false
	var source=game.find_target(game.state.players[0],selected_board)
	var r6=registry.get_def(source.def_id).effects.any(func(e):return e.get("handler","")=="round6")
	var shop_target=available.targets.any(func(id):return game.find_index(game.state.players[0].shop,int(id))>=0)
	var native_effects=registry.get_def(source.def_id).effects.filter(func(e):return e.get("trigger","")=="activate")
	var cost=1 if ability=="gold" or native_effects.is_empty() else int(native_effects[0].get("cost",1))
	status_message=(ExternalText.phrase("ui_tavern_screen.request_activate.8538cda86b71", "说明待补充 · %d") % cost) if shop_target and available.targets.any(func(id):return game.find_index(game.state.players[0].board,int(id))>=0) else (ExternalText.phrase("ui_tavern_screen.request_activate.c271e2e4f096", "说明待补充 · %d") % cost) if shop_target else ExternalText.phrase("ui_tavern_screen.request_activate.883eefd7369c", "说明待补充") if r6 else ExternalText.phrase("ui_tavern_screen.request_activate.a1c7c01023a2", "说明待补充")
	render_match()
func move_selected(delta: int) -> void:
	var index=game.find_index(game.state.players[0].board,selected_board)
	command("move",{"instance_id":selected_board,"index":index+delta})
func request_power(slot_id: int=0) -> void:
	selected_power_slot=slot_id
	clear_pending_play()
	activated_source=-1
	var handler=game.Powers.handler(game,game.state.players[0],selected_power_slot)
	var availability=ActionAvailability.power(game,game.state.players[0],selected_power_slot)
	if not availability.available:
		status_message=power_feedback_text(str(availability.reason)); render_match(); return
	if not availability.targets.is_empty():
		power_target=true; selected_spell=-1
		if handler=="BG20_HERO_301p":
			status_message="吞噬：点击要出售的己方场上随从；售后随机传递属性";render_match();return
		status_message=ExternalText.ui("ui_tavern_screen.request_power.24b493a4fa2d", "英雄技能：点击")+(ExternalText.ui("ui_tavern_screen.request_power.d8bc4f49a922", "己方场上或酒馆") if handler=="reborn" else ExternalText.ui("ui_tavern_screen.request_power.8ebeca1ad080", "酒馆") if handler=="xyrella" else ExternalText.ui("ui_tavern_screen.request_power.f704bde0830b", "己方场上"))+ExternalText.ui("ui_tavern_screen.request_power.ca45d10ace47", "随从"); render_match()
	else: command("power",{"slot_id":selected_power_slot,"epoch":game.Powers.selected(game,game.state.players[0],selected_power_slot).epoch})
func combat_board(parent: VBoxContainer) -> void:
	var frames=game.state.get("combat_frames",[])
	if not frames.is_empty():
		var f=frames[mini(frame_index,frames.size()-1)]
		parent.add_child(label(f.message,20))
		row_cards(parent,ExternalText.ui("ui_tavern_screen.combat_board.7a86f9174006", "左方 · ")+game.state.players[int(game.state.human_left)].name,f.left,"combat")
		row_cards(parent,ExternalText.ui("ui_tavern_screen.combat_board.d2c0296cb816", "右方 · ")+game.state.players[int(game.state.human_right)].name,f.right,"combat")
		parent.add_child(label(ExternalText.ui("ui_tavern_screen.combat_board.5b511caabfaa", "战斗播放 %d / %d") % [frame_index+1,frames.size()],14,MUTED))
	else: parent.add_child(label(ExternalText.ui("ui_tavern_screen.combat_board.8a7d93badaec", "你已淘汰 · 观看全桌战斗结果"),24,GOLD))
	for r in game.state.results:
		var message=ExternalText.ui("ui_tavern_screen.combat_board.1a4675aa847c", "平局") if int(r.winner)<0 else ExternalText.ui("ui_tavern_screen.combat_board.f4fabc922c25", "%s 获胜 · %d伤害") % [game.state.players[int(r.a if int(r.winner)==0 else r.b)].name,r.damage]
		parent.add_child(label("%s vs %s  ·  %s" % [game.state.players[int(r.a)].name,game.state.players[int(r.b)].name,message],15))
func choice_view_identity() -> String:
	if not in_match or game==null:return ""
	if game.state.has("confirmation"):return "confirmation:"+str(game.state.confirmation.id)
	var p=game.state.players[0]
	if not p.choices.is_empty():
		var c=p.choices[0]
		return "choice:"+str(c.get("session_id",var_to_str(c).sha256_text()))+":"+str(c.get("revision",0))
	if active_choice!="" and p.sessions.has(active_choice) and not p.sessions[active_choice].resolved:
		var session=p.sessions[active_choice]
		return "session:"+active_choice+":"+str(session.get("session_id",""))+":"+str(session.get("revision",0))
	return ""
func sync_choice_view() -> void:
	var current=choice_view_identity()
	if current!=choice_view_key:choice_view_key=current;choice_view_hidden=false
func choice_view_is_hidden() -> bool:
	return choice_view_hidden and choice_view_key!="" and choice_view_key==choice_view_identity()
func set_choice_view_hidden(hidden: bool) -> void:
	var overlay=get_node_or_null("ChoiceOverlay")
	if overlay==null or choice_view_identity()=="":return
	choice_view_hidden=hidden
	var table=screen.get_node_or_null("TavernTable") if is_instance_valid(screen) else null
	if table:table.clear_hidden_inspection()
	overlay.get_node("ChoiceDim").visible=not hidden
	overlay.get_node("ChoiceContent").visible=not hidden
	overlay.get_node("ChoiceVisibility").text=ExternalText.ui("ui.choice.show","显示选择") if hidden else ExternalText.ui("ui.choice.hide","隐藏选择")
	if hidden:get_viewport().gui_release_focus()
func modal(title: String) -> VBoxContainer:
	
	var overlay=ChoiceShield.new();overlay.host=self; overlay.name="ChoiceOverlay"; add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); overlay.z_index=100
	var dim=ColorRect.new(); dim.name="ChoiceDim";dim.color=Color(0,0,0,0.8); overlay.add_child(dim); dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center=CenterContainer.new(); center.name="ChoiceContent";overlay.add_child(center); center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var p=PanelContainer.new();p.name="ModalWindow"; p.add_theme_stylebox_override("panel",box(INK,GOLD,14));UISkin.panel(p,"window"); center.add_child(p)
	var v=VBoxContainer.new(); v.add_theme_constant_override("separation",12); p.add_child(v)
	sync_choice_view()
	if choice_view_key!="":
		# Keep the transparent overlay as an input shield: inspection is allowed,
		# but hiding a decision never bypasses its pending transaction.
		var toggle=button("",func():set_choice_view_hidden(not choice_view_hidden),"ChoiceVisibility")
		overlay.add_child(toggle);toggle.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		toggle.offset_left=-190;toggle.offset_right=-18;toggle.offset_top=75;toggle.offset_bottom=121;toggle.z_index=1
		var save=button(ExternalText.ui("ui_tavern_screen.render_match.e55d2d5fac4f", "保存"),save_game,"ChoiceSave")
		overlay.add_child(save);save.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		save.offset_left=-304;save.offset_right=-202;save.offset_top=75;save.offset_bottom=121;save.z_index=1
		var undo_button=button("",undo_last_operation,"ChoiceUndo");update_undo_button(undo_button)
		overlay.add_child(undo_button);undo_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		undo_button.offset_left=-552;undo_button.offset_right=-316;undo_button.offset_top=75;undo_button.offset_bottom=121;undo_button.z_index=1
		set_choice_view_hidden(choice_view_hidden)
	var title_plate=PanelContainer.new();title_plate.name="ModalTitlePlate";UISkin.panel(title_plate,"title_plaque");v.add_child(title_plate)
	var title_label=label(title,25,GOLD);title_label.name="ModalTitle";title_label.custom_minimum_size.y=38;title_plate.add_child(title_label); return v
func choose_visible(choice: Dictionary,index: int,overlay: Control) -> void:
	if ui_blocked():return
	if not is_instance_valid(overlay) or overlay.get_parent()!=self or overlay.get_meta("resolved",false):return
	if game.state.players[0].choices.is_empty() or not is_same(game.state.players[0].choices[0],choice):return
	overlay.set_meta("resolved",true)
	command("choose",{"index":index,"session_id":choice.get("session_id","")})
func render_power_choice(choice: Dictionary) -> void:
	var v=modal(ExternalText.phrase("ui_tavern_screen.render_power_choice.d22eafede613", "说明待补充") if choice.kind=="r132_power" else ExternalText.phrase("ui_tavern_screen.render_power_choice.039dc0f6c33f", "说明待补充") if choice.kind=="r132_conviction" else ExternalText.phrase("ui_tavern_screen.render_power_choice.4021d2d4fc84", "说明待补充"))
	var overlay=get_node("ChoiceOverlay")
	for i in choice.options.size():
		var d=registry.get_def(choice.options[i].def_id);var row=HBoxContainer.new();v.add_child(row)
		var binding=registry.hero_power_binding(d.id);var art=registry.art_path(d.id) if choice.kind=="r132_conviction" else registry.art_path_for_key(str(binding.get("asset_key","")))
		if art!="":
			var image=TextureRect.new();image.texture=texture_for_path(art);image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;image.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;image.custom_minimum_size=Vector2(130,34) if d.id in ["BG21_HERO_000_Buddyt","BG21_HERO_000_Buddyt2"] else Vector2(56,56);row.add_child(image)
		var select=button(d.name,func():choose_visible(choice,i,overlay),"PowerOption"+str(i));select.custom_minimum_size=Vector2(160,56);row.add_child(select)
		var detail=label(str(d.get("text","")),16);detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;detail.custom_minimum_size.x=520;row.add_child(detail)
func render_choice(p: Dictionary) -> void:
	var choice=p.choices[0]
	if choice.kind=="r136_teach":preload("res://ui/round136_presentation.gd").teaching_choice(self,choice);return
	if choice.kind=="r136_evidence":preload("res://ui/round136_presentation.gd").evidence_choice(self,choice);return
	if choice.kind=="quest_offer":preload("res://ui/round135_presentation.gd").choice(self,choice);return
	if choice_target_pending():return
	if choice.kind in ["r133_route","r133_secret"]:R133View.choice(self,choice);return
	if choice.kind in ["r132_power","r132_element","r132_conviction"]:
		render_power_choice(choice);return
	if p.choices[0].kind in ["gold_route","quilboar_gold"]:
		var v=modal(ExternalText.phrase("ui_tavern_screen.render_choice.6694198016d1", "说明待补充"))
		for i in p.choices[0].options.size():
			var overlay=get_node("ChoiceOverlay")
			v.add_child(button(ExternalText.phrase(str(choice.options[i]),"说明待补充") if choice.kind=="quilboar_gold" else ExternalText.term(str(choice.options[i])),func():choose_visible(choice,i,overlay)))
		return
	var v=modal((ExternalText.phrase("ui_tavern_screen.render_choice.7f26d28bcc9f", "说明待补充 · %d") % int(choice.tier)) if choice.kind=="r134_prize" else ExternalText.phrase("ui_tavern_screen.render_choice.99a3e19f6d71", "说明待补充") if choice.kind=="r136_teach" else ExternalText.phrase("ui_tavern_screen.render_choice.45e99ddb4d6b", "说明待补充") if choice.kind=="r136_locket" else ExternalText.phrase("ui_tavern_screen.render_choice.8e2133b40a5b", "说明待补充") if choice.kind=="r134_spell" else ExternalText.phrase("ui_tavern_screen.render_choice.077507190051", "说明待补充") if choice.kind=="choose_one" and choice.get("double",false) else ExternalText.phrase("ui_tavern_screen.render_choice.e4d2bdef85e0", "说明待补充") if p.choices[0].kind=="choose_one" else ExternalText.phrase("ui_tavern_screen.render_choice.3bf0f4f28da9", "说明待补充") if p.choices[0].kind=="triple" else ExternalText.phrase("ui_tavern_screen.render_choice.5da062598b2d", "说明待补充"))
	var row=HBoxContainer.new(); v.add_child(row)
	var overlay=get_node("ChoiceOverlay")
	for i in p.choices[0].options.size():
		var b=card_button(p.choices[0].options[i],"choice",choice.kind=="choose_one")
		if choice.kind=="choose_one":
			
			b.tooltip_text=""
			for body in b.find_children("*","RichTextLabel",true,false):
				body.add_theme_font_size_override("normal_font_size",14)
		var generation=ui_generation
		var overlay_ref=weakref(overlay)
		b.pressed.connect(func():if generation==ui_generation and not ui_blocked():choose_visible(choice,i,overlay_ref.get_ref()))
		row.add_child(b)
	if choice.get("round8",false) and choice.get("from_hand",false):v.add_child(button(ExternalText.ui("ui_tavern_screen.render_choice.4fa6cdbf1307", "取消"),func():command("cancel_choice")))
func render_selection(p: Dictionary) -> void:
	var session=p.sessions[active_choice]
	var title=ExternalText.phrase("ui_tavern_screen.render_selection.8921e8b69e51", "说明待补充") if active_choice=="gift" else ExternalText.phrase("ui_tavern_screen.render_selection.18d805e02a79", "说明待补充") if session.get("offered_size","")=="lesser" else ExternalText.phrase("ui_tavern_screen.render_selection.29f996f31d64", "说明待补充")
	var v=modal(title+ExternalText.ui("ui_tavern_screen.render_selection.2a548f4b9255", " · 选项已锁定"))
	if active_choice!="gift":v.add_child(label(preload("res://ui/round136_presentation.gd").session_status(game,p,session),18,GOLD))
	var row=HBoxContainer.new();row.add_theme_constant_override("separation",12);v.add_child(row)
	for i in session.options.size():
		var option=session.options[i];var d=registry.get_def(option.id)
		var option_panel=PanelContainer.new();UISkin.panel(option_panel,"option_card");row.add_child(option_panel)
		var column=VBoxContainer.new();column.custom_minimum_size=Vector2(210,0);option_panel.add_child(column)
		column.add_child(image_for(option.id,Vector2(160,90)))
		var heading=label(d.name,20,GOLD);heading.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;column.add_child(heading)
		var detail=str(d.get("text",""))
		if active_choice=="gift":
			for gd in registry.definitions.values():
				if gd.kind=="dark_gift" and int(gd.numeric_id)==int(option.gift_id):detail=gd.name+"\n"+gd.text
		else:
			var price_color=Color("8bea9f") if int(option.cost)<int(option.get("base_cost",d.cost)) else GOLD
			var price_label=label(ExternalText.phrase("ui_tavern_screen.render_selection.493191676e1a", "说明待补充 · %d") % int(option.cost),20,price_color);price_label.name="TrinketPrice_"+str(i);column.add_child(price_label)
			if int(option.get("pivot_discount",0))>0:column.add_child(label("转型优惠 −%d币" % int(option.pivot_discount),14,Color("9de3b0")))
			detail=ExternalText.describe(d,option,game.state.players[0],detail,"body",{"effective_cost":int(option.cost),"bound_tribe":str(option.bound_tribe)})
		var scroll=ScrollContainer.new();scroll.custom_minimum_size=Vector2(210,210);column.add_child(scroll)
		var body=label(detail,20);body.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;body.custom_minimum_size.x=192;scroll.add_child(body)
		var shown_revision=int(session.get("revision",0));var shown_session=str(session.get("session_id",""))
		var select=button(ExternalText.ui("ui_tavern_screen.render_selection.c8f6051c9d7f", "选择") if active_choice=="gift" else ExternalText.ui("ui_tavern_screen.render_selection.96e7f38f685e", "购买 · %d币") % int(option.cost),func():command("resolve_choice",{"category":active_choice,"index":i,"revision":shown_revision,"session_id":shown_session,"option_id":option.id}),"Option_"+str(i));select.custom_minimum_size.y=44;column.add_child(select)
		if active_choice!="gift" and int(option.cost)<int(option.get("base_cost",d.cost)):
			for color_key in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:select.add_theme_color_override(color_key,Color("8bea9f"))
	var controls=HBoxContainer.new();v.add_child(controls)
	var count=int(p.gift_refreshes if active_choice=="gift" else p.trinket_refreshes);var cost=(1 if active_choice=="gift" else 2)+count
	controls.add_child(button(ExternalText.ui("ui_tavern_screen.render_selection.0ac328a71a2b", "刷新 · %d币") % cost,func():command("refresh_choice",{"category":active_choice}),"RefreshChoice"))
	controls.add_child(button(ExternalText.ui("ui_tavern_screen.render_selection.1b857b5c54ff", "稍后（本轮内）") if active_choice=="gift" else ExternalText.ui("ui_tavern_screen.render_selection.67d4e9d27e87", "稍后（可跨回合）"),func():command("defer_choice",{"category":active_choice}),"DeferChoice"))
	var hint=label(status_message,16,MUTED);hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;hint.custom_minimum_size.x=600;v.add_child(hint)
func encyclopedia() -> void:
	in_match=false; clear_screen()
	var v=VBoxContainer.new(); screen.add_child(v)
	var bar=HBoxContainer.new(); v.add_child(bar)
	bar.add_child(label(ExternalText.ui("ui_tavern_screen.encyclopedia.3b1050730c3e", "内容百科 / 实现进度"),30,GOLD))
	bar.add_child(button(ExternalText.ui("ui_tavern_screen.encyclopedia.c008f063456a", "返回"),menu))
	var search=LineEdit.new(); search.placeholder_text=ExternalText.ui("ui_tavern_screen.encyclopedia.390c2b1036d8", "搜索名称、稳定 ID 或类型"); search.name="Search"; v.add_child(search)
	var scroll=ScrollContainer.new(); scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; v.add_child(scroll)
	var list=VBoxContainer.new(); list.size_flags_horizontal=Control.SIZE_EXPAND_FILL; scroll.add_child(list)
	var update=func(query: String):
		for child in list.get_children(): child.queue_free()
		var n=0
		for id in registry.definitions:
			var d=registry.definitions[id]
			if query!="" and not query.to_lower() in (d.name+" "+id+" "+d.kind).to_lower(): continue
			if n>=120: break
			n+=1
			var item=rich_label(("%s   %s   [lb]%s[rb]\n%s\n%s" % [d.name,id,ExternalText.ui("ui_tavern_screen.encyclopedia.1a78986f77bd", "验证池") if d.implemented else ExternalText.ui("ui_tavern_screen.encyclopedia.9b84dd35ccd6", "未实现 · 未进入验证池"),ExternalText.describe(d,{}, {},SpellText.body(d,{},true) if d.kind=="spell" else SpellText.escape(str(d.get("text","")))),GoldenText.describe(d,{},registry.rules.validation_tribes)]),15,TEXT if d.implemented else MUTED)
			item.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; item.custom_minimum_size.x=800; list.add_child(item)
	search.text_changed.connect(update); update.call("")
	v.add_child(label(ExternalText.ui("ui_tavern_screen.encyclopedia.41edfaf8848d", "共有 %d 个定义（含金色和依赖）；每次显示前120项。导入、实现、验证在逐ID报告中分别记录。") % registry.definitions.size(),15,MUTED))


func card_description(card: Dictionary) -> String:
	var definition=registry.get_def(card.def_id)
	var text_value=definition.name+"\n"+content_body(card)
	if definition.kind=="minion":
		var stats=game.stats(card) if not card.has("attack") else Vector2i(int(card.attack),int(card.health))
		text_value+=ExternalText.ui("ui_tavern_screen.card_description.f5c3972a3b37", "\n精确属性：攻击 %d / 生命 %d\n") % [stats.x,stats.y]+Presentation.status(card,game)
		var gifts=preload("res://ui/dynamic_state_presentation.gd").gifts(game,card)
		if gifts!="":text_value+=(ExternalText.phrase("ui_tavern_screen.card_description.8e23e6477c89", "\n说明待补充") if card.has("r13_gift_id") and game.card_gifts(card).is_empty() else ExternalText.phrase("ui_tavern_screen.card_description.bd778b1b416f", "\n说明待补充"))+gifts
	if Presentation.grave_warning(card,game,"hand"): text_value+=ExternalText.phrase("ui_tavern_screen.card_description.a15c110aa250", "\n说明待补充")
	if definition.effects.any(func(e):return e.get("handler","")=="round10"):
		text_value+="\n"+preload("res://ui/demon_presentation.gd").progress(definition,card,game.state.players[int(card.owner)],int(game.state.round))
	if definition.effects.any(func(e):return e.get("trigger","")=="activate"):
		if not definition.effects.any(func(e):return e.get("handler","")=="round10"):text_value+=ExternalText.phrase("ui_tavern_screen.card_description.6f7adc61ecf5", "\n说明待补充")+(ExternalText.phrase("ui_tavern_screen.card_description.7bae3f54bc28", "说明待补充") if int(card.get("activated_round",0))==int(game.state.round) else ExternalText.phrase("ui_tavern_screen.card_description.e545d85465bf", "说明待补充 · %d") % int(definition.effects.filter(func(e):return e.get("trigger","")=="activate")[0].get("cost",1)))
	var zone="combat" if card.has("keywords") else "board" if game.find_index(game.state.players[0].board,int(card.instance_id))>=0 else "hand"
	var extra=GoldenText.describe(definition,card,game.state.enabled_tribes,zone)
	if extra!="": text_value+="\n"+extra
	return text_value


func spell_description(card: Dictionary,rich: bool=false) -> String:
	return ExternalText.describe(registry.get_def(card.def_id), card, presentation_player(card), _computed_spell_description(card,rich), "body", content_parameters(card))

func elemental_description(card: Dictionary,rich: bool=false) -> String:
	return ExternalText.describe(registry.get_def(card.def_id), card, presentation_player(card), _computed_elemental_description(card,rich), "body", content_parameters(card))

func elemental_card_body(card: Dictionary) -> String:
	return ExternalText.describe(registry.get_def(card.def_id), card, presentation_player(card), _computed_elemental_card_body(card), "compact", content_parameters(card))

func content_parameters(card: Dictionary) -> Dictionary:
	var result={}
	if game!=null and in_match:
		var p=game.state.players[int(card.get("owner",0))]
		if registry.get_def(card.def_id).kind=="minion":
			var value=game.stats(card);result.attack=value.x;result.health=value.y
		result.round=int(game.state.round)
		if game.find_index(p.shop,int(card.get("instance_id",-1)))>=0:result.effective_cost=game.Payment.buy(game,p,card).cost
	return result

func resource_pack_menu() -> void:
	if in_match:return
	var v=modal(ExternalText.ui("resource_packs.open","资源包"));v.custom_minimum_size.x=600
	var current=ExternalText.ui("resource_packs.current","当前：%s") % PackStore.summary(str(ProjectSettings.get_setting("application/resources/external_pack_path","res://local_resources/pack.json")))
	v.add_child(label(current,18,GOLD))
	v.add_child(label(ExternalText.ui("resource_packs.help","选择包内的 pack.json 安装。卸载后恢复默认内容，导入来源包保留。"),16))
	v.add_child(label(ExternalText.ui("resource_packs.saves","旧存档保留，读取时会核对资源包数值。"),16,MUTED))
	var override_active=ExternalText.command_line_override()
	if override_active:v.add_child(label(ExternalText.ui("resource_packs.override","本次启动指定了资源包路径；移除启动参数后可在此切换。"),16,GOLD))
	v.add_child(button(ExternalText.ui("resource_packs.install","安装资源包…"),choose_resource_pack,"InstallResourcePack",override_active))
	v.add_child(button(ExternalText.ui("resource_packs.uninstall","卸载并恢复默认"),uninstall_resource_pack,"UninstallResourcePack",override_active or ExternalText.configured_path().is_empty()))
	v.add_child(button(ExternalText.ui("resource_packs.close","返回"),close_resource_pack_menu,"CloseResourcePacks"))

func choose_resource_pack() -> void:
	var dialog=FileDialog.new();dialog.name="ResourcePackFileDialog";dialog.file_mode=FileDialog.FILE_MODE_OPEN_FILE;dialog.access=FileDialog.ACCESS_FILESYSTEM;dialog.filters=PackedStringArray(["*.json ; Resource pack"])
	var local=ProjectSettings.globalize_path("res://local_resources")
	if DirAccess.dir_exists_absolute(local):dialog.current_dir=local
	add_child(dialog)
	dialog.file_selected.connect(func(path):dialog.queue_free();install_resource_pack(path))
	dialog.canceled.connect(dialog.queue_free);dialog.popup_centered_ratio(0.75)

func refresh_resource_pack(result: Dictionary,installed: bool) -> void:
	if not result.get("ok",false):
		status_message=ExternalText.ui("resource_packs.failed","资源包操作失败，当前内容未改变。")+"\n"+str(result.get("error","INVALID_PACK"))
		menu();return
	ExternalText.reset();registry=Registry.new();texture_cache.clear();game=null
	status_message=ExternalText.ui("resource_packs.installed","资源包已安装，当前菜单已更新。") if installed else ExternalText.ui("resource_packs.removed","资源包已卸载，已恢复默认内容；来源包保留。")
	if not result.get("warnings",[]).is_empty():status_message+="\n"+"\n".join(result.warnings)
	menu()

func install_resource_pack(path: String) -> void:
	if in_match or ExternalText.command_line_override():return
	var inspection=ExternalText.inspect_pack(path)
	refresh_resource_pack(PackStore.install(path,inspection),true)

func uninstall_resource_pack() -> void:
	if in_match or ExternalText.command_line_override():return
	refresh_resource_pack(PackStore.uninstall(),false)

func close_resource_pack_menu() -> void:
	var overlay=get_node_or_null("ChoiceOverlay")
	if overlay:remove_child(overlay);overlay.queue_free()

func keyword_fx_anchors() -> Dictionary:
	var result={}
	var table=screen.get_node_or_null("TavernTable") if is_instance_valid(screen) else null
	if table:
		for token in table.cards:
			var geometry=token.node.minion_geometry()
			result[int(token.card.instance_id)]=token.node.global_position+geometry.art.get_center()*token.node.visual_ratio()
		for marker in table.find_children("KeywordHostMarkers","Control",true,false):
			if not marker.source.is_empty() and int(marker.source.get("instance_id",-1))>=0:result[int(marker.source.instance_id)]=marker.get_parent().get_global_rect().position+Vector2(marker.get_parent().size.x*0.5,26)
	return result
func keyword_fx_anchor(instance: int) -> Vector2:return keyword_fx_anchors().get(instance,Vector2.ZERO)
func keyword_fx_card(instance: int) -> Dictionary:
	var table=screen.get_node_or_null("TavernTable") if is_instance_valid(screen) else null
	if table:
		for value in table.cards:
			if int(value.card.instance_id)==instance:return value.card
	return {}
func keyword_fx_source_anchor(source: Dictionary) -> Vector2:
	var instance=int(source.get("instance_id",-1))
	if instance>=0:return keyword_fx_anchor(instance)
	var table=screen.get_node_or_null("TavernTable") if is_instance_valid(screen) else null
	if table:
		for slot in game.state.players[0].power_slots:
			if slot.active_power_id==source.get("id",source.get("def_id","")) and table.power_areas.has(int(slot.slot_id)):return table.global_position+table.power_areas[int(slot.slot_id)].get_center()
	return Vector2.ZERO
func keyword_fx_choice() -> void:
	var p=game.state.players[0]
	if p.choices.is_empty() or p.choices[0].get("kind","")!="choose_one" or choice_target_pending():return
	var overlay=get_node_or_null("ChoiceOverlay")
	if overlay==null:return
	var options=overlay.find_children("Choice_*","Button",true,false)
	if options.size()<2 or options[0].size.x<=0:return
	var key="choice:"+str(p.choices[0].get("session_id",p.choices[0].get("choice_id",game.state.event_seq)))
	keyword_fx.add_once(key,"fx.choose_one.event.active",-1,"choice",options[0].get_global_rect().get_center(),options[1].get_global_rect().get_center())
	if not overlay.has_node("KeywordChoiceFX"):
		var paint=KeywordFX.EventCanvas.new();paint.only_choice=true;paint.painter=KeywordFX.draw;paint.texture_reader=KeywordFX.image;paint.host=self;paint.name="KeywordChoiceFX";paint.mouse_filter=Control.MOUSE_FILTER_IGNORE;overlay.add_child(paint);paint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	else:overlay.get_node("KeywordChoiceFX").queue_redraw()
