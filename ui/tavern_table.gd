extends Control
const ExternalText = preload("res://domain/resources/external_content.gd")
const Reminder=preload("res://ui/trinket_reminder.gd")
const KeywordFX=preload("res://ui/keyword_fx.gd")
const Card=preload("res://ui/tavern_card.gd")
const CapabilityRegistry=preload("res://domain/rules/capability_registry.gd")
const Special=preload("res://domain/rules/special_rules.gd")
const BTheme=preload("res://ui/round142_theme.gd")
const UISkin=preload("res://ui/round143_skin.gd")
const Opponents=preload("res://ui/round143_opponents.gd")
const Layout=preload("res://ui/round142_layout.gd")
const GOLD=BTheme.GOLD
var keyword_redraw_accumulator=0.0
var layout_offset=Vector2.ZERO
var hand_count_label: Label
var pending_count_label: Label
var pending_preview: PanelContainer
var pending_preview_key=""
var pending_frame_cards=[]
var power_areas={}
var quest_areas=[]
var host
var retired: bool=false
var playback_window=1.15
var cards: Array=[]
var regions={}
var down={}
var dragging=false
var pointer=Vector2.ZERO
var ghost: Control
var overlay: Control
var hovered={}
var hovered_seconds=0.0
var inspection: PanelContainer
var hint: Label
var inspecting_trinket=false
var detail_key=""
var hidden_inspection_active=false
var validation_cache={}
var current_plan={}
var last_plan_key=""
var board_positions: Array=[]
var hand_positions: Array=[]
var cancel_feedback=""
class PaintLayer extends Control:
	var table
	func _draw() -> void: table.paint_overlay(self)
func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	layout_offset=Vector2(maxf(0,(host.size.x-1440)*0.5),0)
	if host.game.state.phase=="combat": build_combat()
	else: build()
	build_inspection()
func build_inspection() -> void:
	inspection=PanelContainer.new();inspection.name="FixedDetail";inspection.mouse_filter=Control.MOUSE_FILTER_STOP
	inspection.add_theme_stylebox_override("panel",BTheme.style("detail_panel"));UISkin.panel(inspection,"panel_detail");place(inspection,area(Layout.DETAIL));inspection.z_index=40
	var action_rows=2 if has_node("ActivateGold") else 1 if has_node("Activate") or has_node("ActivateCancel") or has_node("ChoiceTargetCancel") else 0
	if action_rows>0:inspection.position.y+=action_rows*50;inspection.size.y-=action_rows*50
	var info=host.rich_label("[b]详情[/b]\n\n悬停卡牌、技能或饰品查看完整效果。\n\n长文可在此滚动查看。",16,BTheme.TEXT);info.name="Info";info.fit_content=false;info.scroll_active=true;info.mouse_filter=Control.MOUSE_FILTER_STOP;inspection.add_child(info)
	overlay=PaintLayer.new();overlay.table=self;overlay.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(overlay);overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var event_canvas=KeywordFX.EventCanvas.new();event_canvas.painter=KeywordFX.draw;event_canvas.texture_reader=KeywordFX.image;event_canvas.host=host;event_canvas.name="KeywordEventCanvas";event_canvas.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(event_canvas);event_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	refresh_inspection()
func show_detail(value: String,art: Texture2D=null) -> void:
	if not is_instance_valid(inspection):return
	var info=inspection.get_node("Info")
	var key=value+"|"+str(art.get_instance_id() if art else 0)
	if detail_key!=key:
		detail_key=key;info.clear()
		if art:
			var factor=minf(130.0/art.get_width(),140.0/art.get_height())
			info.push_paragraph(HORIZONTAL_ALIGNMENT_CENTER)
			info.add_image(art,roundi(art.get_width()*factor),roundi(art.get_height()*factor))
			info.pop();info.append_text("\n")
		info.append_text(value)
		info.scroll_to_line(0)
	inspection.visible=true

# Native controls cannot receive mouse_entered through the choice input shield.
# Read their descriptions without forwarding input or changing action locks.
func inspection_text_at(point: Vector2,node: Node=null) -> String:
	if node==null:node=self
	if retired or node==inspection or node==pending_preview:return ""
	if node is Control and not node.is_visible_in_tree():return ""
	var children=node.get_children()
	for i in range(children.size()-1,-1,-1):
		var found=inspection_text_at(point,children[i])
		if not found.is_empty():return found
	if node is Control and Rect2(Vector2.ZERO,node.size).has_point(node.get_global_transform_with_canvas().affine_inverse()*point):
		if node.has_meta("inspection_reader"):return str(node.get_meta("inspection_reader").call())
		if node.mouse_filter!=Control.MOUSE_FILTER_IGNORE:return node.tooltip_text
	return ""
func clear_hidden_inspection() -> void:
	inspecting_trinket=false
	if hidden_inspection_active:
		hidden_inspection_active=false
		show_detail("[b]详情[/b]\n\n悬停卡牌、技能或饰品查看完整效果。\n\n长文可在此滚动查看。")

func rect(x: float,y: float,w: float,h: float) -> Rect2: return Rect2(Vector2(x,y)+layout_offset,Vector2(w,h))
func area(value: Rect2) -> Rect2:return Rect2(value.position+layout_offset,value.size)
func place(node: Control,area: Rect2) -> Control:
	add_child(node); node.position=area.position; node.size=area.size
	return node
func text(value: String,area: Rect2,font_size: int=18,color: Color=Color("e8d5af")) -> Label:
	var l=host.label(value,font_size,color); l.mouse_filter=Control.MOUSE_FILTER_IGNORE
	place(l,area); return l
# Shared logical-canvas layout for own main hero in both phases.
func main_hero_badges(p: Dictionary,health_color: Color) -> void:
	number_badge("badge_health",int(p.health),rect(503,702,48,34),health_color,"HeroHealth")
	number_badge("badge_armor",int(p.armor),rect(508,664,38,34),BTheme.TEXT,"HeroArmor")
func number_badge(key: String,value: int,area: Rect2,color: Color,node_name: String,max_font_size: int=18) -> Label:
	UISkin.frame(self,key,area,node_name+"Frame")
	var number_area=area.grow(-4);var data=UISkin.data(key)
	if data.has("source_size") and data.get("safe_areas",{}).has("dynamic_number_rect"):
		var source=Vector2(data.source_size[0],data.source_size[1]);var factor=minf(area.size.x/source.x,area.size.y/source.y)
		var safe=data.safe_areas.dynamic_number_rect
		number_area=Rect2(area.position+(area.size-source*factor)*0.5+Vector2(safe[0],safe[1])*factor,Vector2(safe[2],safe[3])*factor)
	var number=text(host.Presentation.number(value),number_area,max_font_size,color);number.name=node_name
	var font=number.get_theme_font("font");var font_size=max_font_size;var minimum=9 if area.size.x<40 else 12
	while font_size>minimum and (font.get_string_size(number.text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x>number_area.size.x or font.get_height(font_size)>number_area.size.y):font_size-=1
	if font.get_string_size(number.text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x>number_area.size.x:
		var suffix="B" if abs(value)>=1000000000 else "M" if abs(value)>=1000000 else "K" if abs(value)>=1000 else ""
		var divisor=1000000000.0 if suffix=="B" else 1000000.0 if suffix=="M" else 1000.0 if suffix=="K" else 1.0
		number.text=str(roundi(value/divisor))+suffix
		if font.get_string_size(number.text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x>number_area.size.x:
			var digits=str(absi(value))
			number.text=("-" if value<0 else "")+digits[0]+"e"+str(digits.length()-1)
	number.add_theme_font_size_override("font_size",font_size)
	number.size=number_area.size
	number.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;number.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	number.mouse_filter=Control.MOUSE_FILTER_PASS;number.tooltip_text=str(value)
	number.add_theme_color_override("font_outline_color",Color("080e16"));number.add_theme_constant_override("outline_size",3)
	return number
func action(value: String,area: Rect2,callback: Callable,node_name: String,disabled=false,available=false) -> Button:
	var b=host.button(value,callback,node_name,disabled)
	var normal_style=BTheme.style("button_primary" if available or node_name in ["EndTurn","Continue"] else "button_base")
	if node_name in ["Refresh","Freeze"]:normal_style.content_margin_top=8;normal_style.content_margin_bottom=8
	b.add_theme_stylebox_override("normal",normal_style)
	b.add_theme_stylebox_override("hover",host.box(Color("1d414c"),BTheme.TEAL,8))
	b.add_theme_constant_override("icon_max_width",36)
	b.expand_icon=true
	var icons={"Upgrade":"button_upgrade","Refresh":"button_refresh","Freeze":"button_unfreeze" if host.game.state.players[0].frozen else "button_freeze","Pause":"button_pause","EndTurn":"button_end_turn","Continue":"button_end_turn"}
	if icons.has(node_name):
		var idle="selected" if node_name=="Freeze" and host.game.state.players[0].frozen else "normal"
		bind_icon(b,icons[node_name],"disabled" if disabled or node_name in ["Upgrade","Refresh"] and not available else idle)
		if node_name in ["Upgrade","Refresh","Freeze"]:
			for state_name in ["normal","hover","pressed","disabled"]:
				var style=b.get_theme_stylebox(state_name).duplicate();style.content_margin_top=4;style.content_margin_bottom=4;b.add_theme_stylebox_override(state_name,style)
	if available or node_name=="Freeze" and host.game.state.players[0].frozen:status_border(b,Color("a1e9ff") if node_name=="Freeze" else Color("77edce"))
	var role="button_primary" if node_name in ["Upgrade","EndTurn","Continue"] else "button_compact" if node_name in ["Save","Menu","FastMode","ConfirmationToggle","SpellHistory","SpellHistoryOpen"] else "skill_seat" if node_name in ["Power","Power2"] else "item_seat" if node_name in ["Lesser","Greater","Gift","Trinket_lesser","Trinket_greater"] else "button_secondary"
	UISkin.button(b,role)
	if available and node_name in ["FastMode","ConfirmationToggle"] or node_name=="Freeze" and host.game.state.players[0].frozen:
		var selected=UISkin.style(role,"selected")
		if selected:b.add_theme_stylebox_override("normal",selected)
	place(b,area)
	if icons.has(node_name):compose_action_icon(b,node_name)
	return b
func compose_action_icon(button: Button,node_name: String) -> void:
	if not UISkin.has("icon_socket_gold"):return
	var socket_key="icon_socket_gold" if node_name in ["Upgrade","EndTurn","Continue"] else "icon_socket_ice" if node_name=="Freeze" else "icon_socket_teal"
	var socket=UISkin.frame(button,socket_key,Rect2(),"IconSocket")
	var art=TextureRect.new();art.name="SkinIcon";art.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;art.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;art.mouse_filter=Control.MOUSE_FILTER_IGNORE;art.texture=button.icon;button.add_child(art)
	for state in ["normal","hover","pressed","disabled","focus"]:button.add_theme_color_override("icon_"+state+"_color",Color.TRANSPARENT)
	var layout=func():
		var diameter=minf(56 if node_name=="Upgrade" else 48,button.size.y)
		socket.position=Vector2(4,(button.size.y-diameter)*0.5);socket.size=Vector2(diameter,diameter)
		art.position=socket.position+(socket.size-Vector2(36,36))*0.5;art.size=Vector2(36,36)
	layout.call();button.resized.connect(layout)
func status_border(button: Button,color: Color) -> void:
	UISkin.trim(button,color)
func bind_icon(button: Button,id: String,idle: String="normal",image: TextureRect=null) -> void:
	var apply=func(state_value):
		var texture=BTheme.icon(id,state_value)
		if image:image.texture=texture
		else:
			button.icon=texture
			var composed=button.get_node_or_null("SkinIcon")
			if composed:composed.texture=texture
	apply.call(idle)
	button.mouse_entered.connect(func():apply.call("hover" if not button.disabled else idle))
	button.mouse_exited.connect(func():apply.call(idle))
	button.button_down.connect(func():apply.call("pressed"))
	button.button_up.connect(func():apply.call(idle))
func decorate_entry_button(button: Button,spec_key: String,content_path: String,caption: String,symbol: String,category: String) -> void:
	var spec=host.registry.ui_asset(spec_key).get("program_render_spec",{})
	button.text=""
	if host.can_action("open_choice",{"category":category}):
		var glow_key=str(spec.get("glow_asset",""))
		if not glow_key.is_empty():
			var glow=TextureRect.new(); glow.texture=host.ui_texture(glow_key); glow.mouse_filter=Control.MOUSE_FILTER_IGNORE; glow.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; glow.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; glow.position=Vector2(-4,-4); glow.size=button.size+Vector2(8,8); button.add_child(glow)
	var outline=TextureRect.new(); outline.texture=host.ui_texture(spec_key); outline.mouse_filter=Control.MOUSE_FILTER_IGNORE; outline.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; outline.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; outline.position=Vector2(3,3); outline.size=Vector2(38,38); button.add_child(outline)
	var content=TextureRect.new(); content.mouse_filter=Control.MOUSE_FILTER_IGNORE; content.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; content.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; content.position=Vector2(10,10); content.size=Vector2(24,24)
	if content_path!="": content.texture=host.texture_for_path(content_path)
	if content.texture: button.add_child(content)
	else:
		content.free()
		var mark=host.label(symbol,18,GOLD); mark.position=Vector2(9,8); mark.size=Vector2(26,26); mark.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; mark.mouse_filter=Control.MOUSE_FILTER_IGNORE; button.add_child(mark)
	var label_node=host.label(caption,13,Color("f6dfad")); label_node.position=Vector2(43,2); label_node.size=Vector2(button.size.x-46,button.size.y-4); label_node.vertical_alignment=VERTICAL_ALIGNMENT_CENTER; label_node.mouse_filter=Control.MOUSE_FILTER_IGNORE; button.add_child(label_node)
func bind_trinket_inspection(control: Control,item: Dictionary,p: Dictionary,_position_value: Vector2) -> void:
	var description=host.trinket_tooltip(item,p)
	if item.has("power_owner"):description="所属技能位 %d\n" % (int(item.power_owner.slot_id)+1)+description
	control.tooltip_text=description;control.mouse_default_cursor_shape=Control.CURSOR_HELP
	control.set_meta("inspection_reader",func():return description)
	control.mouse_entered.connect(func():inspecting_trinket=true;show_detail(description))
	control.mouse_exited.connect(func():inspecting_trinket=false)

func decorate_power_button(button: Button,p: Dictionary,power_state: Dictionary) -> void:
	var slot_id=int(power_state.get("slot_id",0))
	var old=host.game.power_context.get(int(p.id),0);host.game.power_context[int(p.id)]=slot_id
	var handler=host.game.hero_handler(p)
	var power_def=host.game.power_definition(p).duplicate(true)
	var power_id=str(power_def.get("id",""))
	if power_id==host.game.R135.POWER:
		var quest=p.get("r135",{}).get("slots",{}).get(str(slot_id),{})
		if quest.get("status","")=="reward_active":power_def=host.registry.get_def(quest.reward_id).duplicate(true)
	var installed=host.game.R136Slots.installed(host.game,p,slot_id)
	if not installed.is_empty():power_def=host.registry.get_def(installed.id).duplicate(true)
	var binding=host.registry.hero_power_binding(power_id)
	var passive=power_state.get("reason","")=="PASSIVE_POWER"
	var used=host.game.power_used(p) or host.game.power_used(p,true) and handler in ["golden","kragg"]
	button.disabled=not power_state.available
	if UISkin.has("skill_seat"):
		var state="used" if used and not passive else "normal" if passive or power_state.available else "locked" if "LOCKED" in str(power_state.get("reason","")) else "disabled"
		button.set_meta("skin_effective_state",state)
		button.add_theme_stylebox_override("disabled" if button.disabled else "normal",UISkin.style("skill_seat",state))
	button.text=""
	button.tooltip_text=host.game.R132.description(host.game,p,slot_id)
	if not installed.is_empty():
		button.tooltip_text=ExternalText.ui("ui_tavern_table.decorate_power_button.1e1ea22c5955", "所属技能位 ")+str(slot_id+1)+"\n"+host.trinket_tooltip(installed,p)
		bind_trinket_inspection(button,installed,p,Vector2(860,300))
	if power_state.available:
		var glow=TextureRect.new(); glow.texture=host.ui_texture("ui:available_glow_circle:texture:normal:neutral"); glow.mouse_filter=Control.MOUSE_FILTER_IGNORE; glow.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; glow.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; glow.position=Vector2(1,1); glow.size=Vector2(65,65); button.add_child(glow)
	var frame_key=str(binding.get("normal_frame","ui:hero_power_frame:texture:normal:neutral"))
	if passive: frame_key=str(binding.get("passive_frame","ui:hero_power_passive_frame:texture:normal:neutral"))
	if not UISkin.has("skill_seat"):
		var frame=TextureRect.new(); frame.texture=host.ui_texture(frame_key); frame.mouse_filter=Control.MOUSE_FILTER_IGNORE; frame.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; frame.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; frame.position=Vector2(2,2); frame.size=Vector2(62,62); button.add_child(frame)
	var image=TextureRect.new(); image.texture=host.texture_for_path(host.registry.art_path_for_key(str(binding.get("asset_key","")))); image.mouse_filter=Control.MOUSE_FILTER_IGNORE; image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; image.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; image.position=Vector2(12,12); image.size=Vector2(42,42); button.add_child(image)
	if not installed.is_empty() or power_id==host.game.R135.POWER and power_def.id!=power_id:image.texture=host.texture_for_path(host.registry.art_path(power_def.id))
	var state_key=""
	if not passive:
		if used: state_key=str(binding.get("used_layer","ui:hero_power_used_overlay:texture:normal:neutral"))
		elif not power_state.available: state_key=str(binding.get("unavailable_layer","ui:hero_power_unavailable_overlay:texture:normal:neutral"))
	if not state_key.is_empty() and not UISkin.has("skill_seat"):
		var state_image=TextureRect.new(); state_image.texture=host.ui_texture(state_key); state_image.mouse_filter=Control.MOUSE_FILTER_IGNORE; state_image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; state_image.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; state_image.position=Vector2(2,2); state_image.size=Vector2(62,62); button.add_child(state_image)
	var cost=int(power_state.get("cost",host.game.power_cost(p)))
	var state_text="被动" if passive else "已用" if used else ("可用" if power_state.available else "不可用")+" · %d币" % cost
	var label_node=host.label(str(power_def.get("name",ExternalText.ui("ui_tavern_table.decorate_power_button.b9760b49a97c", "技能")))+"\n"+state_text,13,BTheme.TEXT); label_node.position=Vector2(64,4); label_node.size=Vector2(button.size.x-70,72); label_node.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label_node.vertical_alignment=VERTICAL_ALIGNMENT_CENTER; label_node.mouse_filter=Control.MOUSE_FILTER_IGNORE; button.add_child(label_node)
	host.game.power_context[int(p.id)]=old
	if installed.is_empty():
		var description=button.tooltip_text;button.tooltip_text=""
		button.set_meta("inspection_reader",func():return description)
		button.mouse_entered.connect(func():inspecting_trinket=true;show_detail(description))
		button.mouse_exited.connect(func():inspecting_trinket=false)
func slab(area: Rect2,color: Color,border: Color,radius=18,key: String="panel_shop") -> Panel:
	var panel=Panel.new(); panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel",BTheme.style());UISkin.panel(panel,key); place(panel,area); return panel
func build() -> void:
	var p=host.game.state.players[0]
	var reminders=Reminder.entries(host.game)
	regions={"sell":area(Layout.SELL),"shop":area(Layout.SHOP),"board":area(Layout.BOARD),"hand":area(Layout.HAND),"buy":area(Rect2(146,416,916,508)),"cast":area(Rect2(146,416,916,354))}
	slab(rect(138,70,932,108),BTheme.PANEL,BTheme.BORDER)
	slab(rect(138,190,932,424),BTheme.PANEL,BTheme.BORDER)
	slab(rect(138,628,932,110),BTheme.PANEL,BTheme.BORDER,18,"panel_footer")
	var tavern_title=Panel.new();tavern_title.mouse_filter=Control.MOUSE_FILTER_IGNORE;UISkin.panel(tavern_title,"title_plaque");place(tavern_title,rect(0,0,222,42))
	var tavern_label=text("余烬酒馆",rect(0,0,222,40),26,GOLD);tavern_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	text("第 %d 回合" % host.game.state.round,rect(230,6,150,30),20,BTheme.TEXT)
	var undo_button=action("",rect(390,0,236,44),host.undo_last_operation,"Undo")
	host.update_undo_button(undo_button)
	build_history()
	action("保存",rect(1230,0,76,44),func():host.save_game(),"Save")
	action("返回",rect(1314,0,90,44),host.request_menu,"Menu")
	hint=text("拖动换位 · 拖向老板出售 · 法术拖向目标 · 右键 / Esc 取消",rect(146,46,916,24),14,BTheme.MUTED)
	var sell_zone=Panel.new();sell_zone.name="SellZone";sell_zone.mouse_filter=Control.MOUSE_FILTER_IGNORE;sell_zone.add_theme_stylebox_override("panel",host.box(BTheme.PANEL,BTheme.BORDER,12));UISkin.panel(sell_zone,"panel_sell");place(sell_zone,regions.sell)
	UISkin.frame(self,"icon_socket_gold",rect(495,87,48,48),"SaleSocket")
	var sale_icon=TextureRect.new();sale_icon.name="SaleIcon";sale_icon.texture=BTheme.icon("button_sell","disabled" if host.game.R134.sale_blocked(p) else "normal");sale_icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;sale_icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;sale_icon.mouse_filter=Control.MOUSE_FILTER_IGNORE;place(sale_icon,rect(501,93,36,36))
	text("酒馆老板 · 出售区",rect(551,93,300,32),24,GOLD)
	var sale_hint=text("轮盘未结束 · 跳过动画后出售" if host.game.R134.sale_blocked(p) else "拖动场上随从至此出售",rect(415,135,438,25),14,BTheme.MUTED);sale_hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;sale_hint.name="WheelSaleHint"
	action("升级 ★%d · %d币" % [mini(int(p.tier)+1,6),p.upgrade_cost] if p.tier<6 else "酒馆 ★6",rect(158,94,226,64),func():host.command("upgrade"),"Upgrade",p.tier>=6 or not p.alive,host.can_action("upgrade"))
	var refresh_button=action("刷新 · "+("免费" if p.free_refresh>0 else "1币"),area(Layout.REFRESH),func():host.command("refresh"),"Refresh",not p.alive,host.can_action("refresh"));host.decorate_refresh(refresh_button)
	if refresh_button.text.contains("\n"):
		refresh_button.add_theme_font_size_override("font_size",12)
		for state_name in ["normal","hover","pressed","disabled"]:
			var style=refresh_button.get_theme_stylebox(state_name).duplicate();style.content_margin_top=2;style.content_margin_bottom=2;refresh_button.add_theme_stylebox_override(state_name,style)
	refresh_button.size=area(Layout.REFRESH).size
	action("解冻" if p.frozen else "冻结",area(Layout.FREEZE),func():host.command("freeze"),"Freeze",not p.alive)
	UISkin.frame(self,"badge_tier",rect(150,190,170,32))
	var tier_label=text("酒馆 ★%d" % p.tier,rect(160,194,150,28),18,GOLD);tier_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	spawn_row(p.shop,"shop",222,146,1062,Layout.CARD)
	spawn_row(host.placement_board(),"board",436,146,1062,Layout.CARD)
	if host.placement_board().is_empty():text("将手牌随从拖入战场",rect(400,495,410,32),22,BTheme.MUTED)
	slab(rect(0,70,126,674),BTheme.PANEL,BTheme.BORDER).name="OpponentSidebar"
	build_opponents()
	build_tribes()
	var main_portrait=host.image_for(p.hero_id,Vector2(88,92));UISkin.mask_portrait(main_portrait);place(main_portrait,rect(445,638,84,88))
	main_portrait.name="MainHeroPortrait";main_portrait.set_meta("inspection_reader",func():return Opponents.detail(host.game,p))
	var hero_frame=TextureRect.new();hero_frame.texture=UISkin.texture("portrait_main") if UISkin.has("portrait_main") else BTheme.texture("hero_frame");hero_frame.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;hero_frame.mouse_filter=Control.MOUSE_FILTER_IGNORE;place(hero_frame,rect(435,630,104,106))
	main_hero_badges(p,Color("fff1e2"))
	for i in p.power_slots.size():
		var slot=p.power_slots[i];var slot_id=int(slot.slot_id);var power_state=host.power_availability(slot_id);power_state["slot_id"]=slot_id
		var power_area=area(Layout.power(i,p.power_slots.size()));power_areas[slot_id]=power_area
		var power_button=action("",power_area,func():host.request_power(slot_id),"Power" if slot_id==0 else "Power2",not power_state.available,power_state.available)
		decorate_power_button(power_button,p,power_state)
		KeywordFX.attach_host(power_button,host,{},slot)
		Reminder.attach(power_button,host,str(reminders.get("power:"+str(slot_id),"")))
	for spec in [["lesser","小饰品",146],["greater","大饰品",242],["gift","黑暗之赐",338]]:
		var category=str(spec[0]);var item={}
		for owned in p.trinkets:
			if str(owned.get("slot_size",owned.get("size","")))==category:item=owned;break
		var node_name={"lesser":"Lesser","greater":"Greater","gift":"Gift"}[category]
		var readiness=host.gift_readiness() if category=="gift" else {}
		var disabled=not p.alive or (host.game.state.round<3 or not bool(readiness.get("openable",false)) if category=="gift" else host.game.state.round<(6 if category=="lesser" else int(p.get("greater_unlock",9))))
		var caption=str(spec[1]) if item.is_empty() else str(host.registry.get_def(item.id).name)+"\n"+preload("res://ui/dynamic_state_presentation.gd").trinket_summary(host.registry.get_def(item.id),item,int(host.game.state.round))
		var voucher=host.game.R136Slots.voucher_category(host.game,p,item)
		var button=action("",rect(spec[2],636,88,94),func():host.command("open_choice",{"category":category if item.is_empty() else voucher}) if item.is_empty() or voucher!="" else null,node_name if item.is_empty() else "Trinket_"+category,disabled if item.is_empty() else false,host.can_action("open_choice",{"category":voucher if voucher!="" else category}))
		var icon=TextureRect.new();icon.name="EntryIcon";icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;icon.mouse_filter=Control.MOUSE_FILTER_IGNORE;icon.position=Vector2(22,2);icon.size=Vector2(48,48)
		var icon_id="button_dark_gift" if category=="gift" else "button_"+category+"_trinket"
		icon.texture=BTheme.icon(icon_id)
		var locked=host.game.state.round<(3 if category=="gift" else 6 if category=="lesser" else int(p.get("greater_unlock",9)))
		if item.is_empty():bind_icon(button,icon_id,"locked" if locked else "disabled" if disabled else "normal",icon)
		if item.is_empty() and UISkin.has("item_seat"):
			# The existing category icon already carries its own visible lock.
			var skin_state="disabled" if disabled else "normal"
			button.set_meta("skin_effective_state",skin_state)
			if disabled:button.add_theme_stylebox_override("disabled",UISkin.style("item_seat",skin_state))
		if not item.is_empty():
			var binding=host.registry.trinket_binding(str(item.id))
			var art_path=host.registry.art_path_for_key(str(binding.get("asset_key","")))
			if art_path.is_empty():art_path=host.registry.art_path(str(item.id))
			var art=host.texture_for_path(art_path)
			if art:
				icon.texture=art;icon.position=Vector2(22,2);icon.size=Vector2(48,48)
		button.add_child(icon)
		var label_node=host.label(caption,12,BTheme.TEXT);label_node.position=Vector2(10,52);label_node.size=Vector2(72,40);label_node.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label_node.max_lines_visible=2;label_node.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;label_node.mouse_filter=Control.MOUSE_FILTER_IGNORE;button.add_child(label_node)
		var caption_area=UISkin.data("item_seat").get("safe_areas",{}).get("caption_rect",[10,52,72,40])
		label_node.position=Vector2(caption_area[0],caption_area[1]);label_node.size=Vector2(caption_area[2],caption_area[3])
		if not item.is_empty():
			bind_trinket_inspection(button,item,p,Vector2.ZERO)
			KeywordFX.attach_host(button,host,item)
		elif category=="gift":
			button.tooltip_text=host.gift_readiness_text(readiness)
			button.set_meta("inspection_reader",func():return host.gift_readiness_text(host.gift_readiness()))
		Reminder.attach(button,host,str(reminders.get(category,"")))
	build_hand_counts(p.hand,p.pending_rewards)
	spawn_hand(p.hand)
	slab(rect(1080,588,324,194),BTheme.PANEL,BTheme.BORDER,18,"panel_footer")
	var timer_plate=Panel.new();timer_plate.mouse_filter=Control.MOUSE_FILTER_IGNORE;UISkin.panel(timer_plate,"timer_bar");place(timer_plate,rect(1100,596,284,48))
	host.timer_label=text(host.timer_text(),rect(1110,599,264,42),24,GOLD)
	host.timer_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	action("继续计时" if host.game.state.paused else "暂停",rect(1100,738,284,44),func():host.command("pause"),"Pause")
	action("结束回合" if p.alive else "观战下一轮",rect(1100,654,284,64),func():host.command("end"),"EndTurn")
	slab(rect(938,636,120,94),BTheme.PANEL,BTheme.BORDER,18,"nameplate")
	UISkin.frame(self,"badge_coin",rect(946,640,36,32),"CoinsBadgeFrame")
	text("铸币",rect(986,642,64,28),16,GOLD)
	var coins=text(host.coin_count_text(p),rect(944,680,108,36),26,GOLD);coins.name="CoinsBadge"
	coins.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var coin_font=coins.get_theme_font("font");var coin_size=26
	while coin_size>12 and coin_font.get_string_size(coins.text,HORIZONTAL_ALIGNMENT_LEFT,-1,coin_size).x>108:coin_size-=1
	coins.add_theme_font_size_override("font_size",coin_size)
	host.toast=text(host.status_message.split("\n")[0],rect(146,606,916,20),14,BTheme.TEXT)
	var selected_index=host.game.find_index(p.board,host.selected_board)
	if host.choice_target_cancellable():action("取消目标选择",rect(1080,206,324,44),func():host.command("cancel_choice"),"ChoiceTargetCancel")
	elif host.activated_source>=0:action("取消发动目标",rect(1080,206,324,44),func():cancel(),"ActivateCancel")
	elif selected_index>=0:
		var selected=p.board[selected_index];var native=host.registry.get_def(selected.def_id).effects.filter(func(e):return e.get("trigger","")=="activate")
		if not native.is_empty():
			var availability=host.game.activate_availability(0,int(selected.instance_id),"native")
			action("原生发动 · %d币" % int(native[0].get("cost",1)),rect(1080,206,324,44),func():host.request_activate("native"),"Activate",not availability.available)
		if selected.gold_route=="恶魔":
			var availability=host.game.activate_availability(0,int(selected.instance_id),"gold")
			action(ExternalText.phrase("ui_tavern_table.build.4f26879127b5", "说明待补充"),rect(1080,256,324,44),func():host.request_activate("gold"),"ActivateGold",not availability.available)
	host.R133View.build(self);host.R134Wheel.build(self);preload("res://ui/round135_presentation.gd").build(self)
func tribe_groups() -> Dictionary:
	# Only the rules' playable universe participates in this match's random exclusion.
	var approved=[]
	for tribe in host.registry.rules.validation_tribes:
		if tribe not in ["中立","全部","全部种族","ALL","NEUTRAL"] and tribe not in approved:approved.append(tribe)
	return {"enabled":approved.filter(func(t):return t in host.game.state.enabled_tribes),"disabled":approved.filter(func(t):return t not in host.game.state.enabled_tribes)}
class AvatarInfo extends Button:
	var table
	var player: Dictionary
	var ghost_snapshot: bool=false
	func _make_custom_tooltip(_text: String) -> Object:
		if table.blocked() and not table.host.choice_view_is_hidden() and table.host.game.state.phase!="combat":return null
		var info=table.host.rich_label(table.Opponents.detail(table.host.game,player,ghost_snapshot),15)
		info.custom_minimum_size.x=390;info.mouse_filter=Control.MOUSE_FILTER_IGNORE
		return info
func build_opponents() -> void:
	var target=Opponents.target(host.game);var current=host.game.state.phase=="combat"
	for i in host.game.state.players.size():
		var other=host.game.state.players[i];var y=84+i*82
		var marked=not target.is_empty() and int(target.player.id)==i
		var card=AvatarInfo.new();card.name="Avatar_"+str(i);card.table=self;card.player=target.player if marked else other;card.ghost_snapshot=marked and target.ghost
		card.tooltip_text="玩家信息";card.mouse_default_cursor_shape=Control.CURSOR_HELP
		card.set_meta("inspection_reader",func():return Opponents.detail(host.game,card.player,card.ghost_snapshot))
		for state_name in ["normal","hover","pressed","focus"]:card.add_theme_stylebox_override(state_name,host.box(Color("132d38") if marked else Color("102330"),BTheme.TEAL if marked else BTheme.BORDER,7))
		UISkin.button(card,"panel_inset")
		if marked:status_border(card,BTheme.TEAL)
		place(card,rect(3,y,120,78))
		var portrait=host.image_for(other.hero_id,Vector2(40,48));UISkin.mask_portrait(portrait);card.add_child(portrait);portrait.position=Vector2(4,4);portrait.size=Vector2(40,48)
		var portrait_frame=UISkin.frame(card,"portrait_side",Rect2(1,1,46,52));portrait_frame.texture=UISkin.texture("portrait_side","selected" if marked else "normal")
		card.mouse_entered.connect(func():portrait_frame.texture=UISkin.texture("portrait_side","hover"))
		card.mouse_exited.connect(func():portrait_frame.texture=UISkin.texture("portrait_side","selected" if marked else "normal"))
		text(other.name,rect(49,y+4,70,23),13,BTheme.TEXT)
		if other.alive:
			var hp=number_badge("badge_health",int(other.health),rect(48,y+27,38,25),BTheme.TEXT,"SideHealth_"+str(i),12);hp.mouse_filter=Control.MOUSE_FILTER_IGNORE
			var armor=number_badge("badge_armor",int(other.armor),rect(86,y+27,34,25),BTheme.TEXT,"SideArmor_"+str(i),12);armor.mouse_filter=Control.MOUSE_FILTER_IGNORE
		else:text("已淘汰",rect(49,y+29,72,22),12,BTheme.MUTED)
		if marked:
			var marker_id="ghost" if target.ghost else "current_opponent" if current else "next_opponent"
			var icon=TextureRect.new();icon.name="OpponentMarker";icon.texture=BTheme.icon(marker_id);icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;icon.mouse_filter=Control.MOUSE_FILTER_IGNORE;place(icon,rect(6,y+52,24,24))
			card.mouse_entered.connect(func():icon.texture=BTheme.icon(marker_id,"focus"))
			card.mouse_exited.connect(func():icon.texture=BTheme.icon(marker_id))
			var caption=text(("当前" if current else "下一战")+(" · 幽灵" if target.ghost else ""),rect(32,y+52,88,23),13,BTheme.TEAL);caption.name="OpponentMarkerLabel"
		elif i==0:text("你",rect(8,y+52,100,23),13,GOLD)
		card.mouse_entered.connect(func():
			if blocked() and not host.choice_view_is_hidden() and host.game.state.phase!="combat":return
			inspecting_trinket=true;show_detail(Opponents.detail(host.game,card.player,card.ghost_snapshot)))
		card.mouse_exited.connect(func():inspecting_trinket=false)
	if not target.is_empty():
		var title=text(("当前对手 · " if current else "下一战 · ")+str(target.player.name)+(" · 幽灵（已淘汰）" if target.ghost else ""),rect(146,174,916,25) if current else rect(370,194,684,25),17,BTheme.TEAL);title.name="OpponentPreview"
func build_tribes() -> void:
	var groups=tribe_groups()
	var panel=Panel.new();panel.name="TribeSummaryPanel";panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel",host.box(Color("101f2a"),BTheme.BORDER,6));UISkin.panel(panel,"panel_detail");place(panel,rect(1080,58,324,136))
	var column=0
	for key in ["enabled","disabled"]:
		var x=1094.0+column*154
		var heading=text("本局在池" if key=="enabled" else "本局禁用",rect(x,70,144,22),16,GOLD)
		heading.name="EnabledTribesTitle" if key=="enabled" else "DisabledTribesTitle"
		var lines=[];var values: Array=groups[key]
		for i in range(0,values.size(),2):lines.append(" / ".join(ExternalText.terms_list(values.slice(i,i+2))))
		if lines.is_empty():lines.append("无")
		var list=text("\n".join(lines),rect(x,98,144,lines.size()*22.0),14,BTheme.TEXT)
		list.name="TribeList" if key=="enabled" else "DisabledTribeList"
		list.add_theme_constant_override("line_spacing",2)
		column+=1
func build_hand_counts(hand: Array,pending: Array) -> void:
	pending_frame_cards=pending.duplicate(true)
	if not has_node("HandCountPanel"):
		for spec in [["HandCountPanel",rect(146,746,452,28)],["PendingCountPanel",rect(610,746,452,28)]]:
			var panel=Panel.new();panel.name=spec[0];panel.mouse_filter=Control.MOUSE_FILTER_IGNORE;panel.z_index=44
			panel.add_theme_stylebox_override("panel",host.box(Color("101f2a"),BTheme.BORDER,6));UISkin.panel(panel,"nameplate");place(panel,spec[1])
	if not is_instance_valid(hand_count_label):
		hand_count_label=text("",rect(170,746,400,28),18,BTheme.TEXT);hand_count_label.name="HandCount";hand_count_label.z_index=46
	if not is_instance_valid(pending_count_label):
		pending_count_label=text("",rect(666,746,380,28),18,BTheme.TEXT);pending_count_label.name="PendingRewardsCount";pending_count_label.z_index=46
	for label_node in [hand_count_label,pending_count_label]:
		label_node.add_theme_color_override("font_outline_color",Color("070f18"));label_node.add_theme_constant_override("outline_size",2)
	var limit=int(host.registry.rules.hand_limit)
	hand_count_label.text="手牌 [%d/%d]" % [hand.size(),limit]
	hand_count_label.add_theme_color_override("font_color",BTheme.GOLD if hand.size()>=limit else BTheme.TEAL if not hand.is_empty() else BTheme.TEXT)
	pending_count_label.text="候补待领 %d" % pending.size()
	pending_count_label.add_theme_color_override("font_color",BTheme.GOLD if not pending.is_empty() else BTheme.TEXT)
	if not has_node("PendingIcon"):
		var icon=TextureRect.new();icon.name="PendingIcon";icon.texture=BTheme.texture("button_later");icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;icon.mouse_filter=Control.MOUSE_FILTER_IGNORE;icon.z_index=46;place(icon,rect(630,748,24,24))
	if is_instance_valid(pending_preview):update_pending_preview()

func pending_preview_source() -> Array:
	# Combat uses the same presentation-frame snapshot as its count/hand row.
	return pending_frame_cards if host.game.state.phase=="combat" else host.game.state.players[0].pending_rewards
func update_pending_preview() -> void:
	var panel=get_node_or_null("PendingCountPanel")
	var inside=not retired and panel!=null and panel.get_rect().has_point(pointer)
	if not inside:
		if is_instance_valid(pending_preview):pending_preview.hide()
		return
	var pending=pending_preview_source();var first=pending.slice(0,3)
	var key=str(pending.size())+":"+JSON.stringify(first.map(func(c):return [c.instance_id,c.def_id]))
	if not is_instance_valid(pending_preview) or pending_preview_key!=key:
		if is_instance_valid(pending_preview):remove_child(pending_preview);pending_preview.queue_free()
		pending_preview_key=key;pending_preview=PanelContainer.new();pending_preview.name="PendingPreview";pending_preview.mouse_filter=Control.MOUSE_FILTER_IGNORE;pending_preview.z_index=85
		pending_preview.add_theme_stylebox_override("panel",host.box(Color("102330"),BTheme.TEAL,8));place(pending_preview,rect(610,538,452,198))
		var column=VBoxContainer.new();column.mouse_filter=Control.MOUSE_FILTER_IGNORE;pending_preview.add_child(column)
		var title=host.label("候补队首 · 按领取顺序" if not pending.is_empty() else "候补队列为空",15,BTheme.TEXT);title.mouse_filter=Control.MOUSE_FILTER_IGNORE;column.add_child(title)
		var row=HBoxContainer.new();row.mouse_filter=Control.MOUSE_FILTER_IGNORE;column.add_child(row)
		for card in first:
			var d=host.registry.get_def(card.def_id);var item=VBoxContainer.new();item.mouse_filter=Control.MOUSE_FILTER_IGNORE;item.custom_minimum_size.x=136;row.add_child(item)
			var art=TextureRect.new();art.name="Preview_"+str(card.instance_id);art.texture=host.texture_for_path(host.registry.art_path(card.def_id));art.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;art.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;art.custom_minimum_size=Vector2(136,94);art.mouse_filter=Control.MOUSE_FILTER_IGNORE;item.add_child(art)
			var caption=host.label(("金色 · " if d.get("golden",false) else "")+str(d.get("name",card.def_id)),13,BTheme.GOLD if d.get("golden",false) else BTheme.TEXT);caption.name="PreviewName";caption.custom_minimum_size.x=136;caption.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;caption.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;caption.max_lines_visible=2;caption.mouse_filter=Control.MOUSE_FILTER_IGNORE;item.add_child(caption)
		var remainder=host.label("后续还有 %d 张" % maxi(0,pending.size()-3) if pending.size()>3 else "手牌腾出空位后按现有规则领取",13,BTheme.TEAL);remainder.mouse_filter=Control.MOUSE_FILTER_IGNORE;column.add_child(remainder)
	var origin=panel.get_global_rect().position-global_position
	pending_preview.position=Vector2(clampf(origin.x,0,maxf(0,size.x-pending_preview.size.x)),maxf(0,origin.y-pending_preview.size.y-8))
	pending_preview.show()

func spawn_card(card: Dictionary,zone: String,pos: Vector2,dimensions: Vector2,reference_dimensions: Vector2=Vector2.ZERO) -> Control:
	var node=Card.new(); node.host=host; node.card=card; node.zone=zone
	node.visual_reference_size=reference_dimensions
	node.name=zone.capitalize()+"_"+str(int(card.instance_id)); place(node,Rect2(pos,dimensions)); node.base_position=pos
	node.available_action=card_action_available(card,zone)
	cards.append({"node":node,"card":card,"zone":zone,"base":pos,"dimensions":dimensions}); return node
func card_action_available(card: Dictionary,zone: String) -> bool:
	var p=host.game.state.players[0]
	if host.choice_target_pending():return zone in ["board","shop"] and host.game.preview_action(0,"choose_target",{"target_id":int(card.instance_id)}).accepted
	if host.game.state.phase!="recruit" or not p.alive or not p.choices.is_empty(): return false
	if host.activated_source>=0:
		var query=host.game.activate_availability(0,host.activated_source,host.activated_ability)
		return zone in ["board","shop"] and query.available and int(card.instance_id) in query.targets
	var d=host.registry.get_def(str(card.def_id))
	if zone=="shop":
		return host.game.Payment.buy(host.game,p,card).available
	if zone=="board": return true
	if zone!="hand": return false
	if d.kind=="minion": return p.board.size()<Special.capacity(p.board)
	if d.kind=="spell":
		if d.id=="BG28_512":return host.game.preview_action(0,"play",{"instance_id":card.instance_id}).accepted
		if not _is_targeted_spell(card): return host.game.preview_action(0,"play",{"instance_id":card.instance_id}).accepted
		for target in p.board+p.shop:
			if host.game.preview_action(0,"play",{"instance_id":card.instance_id,"target_id":target.instance_id}).accepted:return true
	return false
func spawn_row(list: Array,zone: String,y: float,left: float,right: float,dimensions: Vector2) -> void:
	var row_area=rect(left,y-20,right-left,dimensions.y+40)
	var positions=Layout.row(row_area,list.size(),dimensions)
	for i in positions.size():
		var item=positions[i]
		spawn_card(list[i],zone,item.position,item.size,Vector2(140,184) if zone!="combat" else dimensions)
		if zone=="board":board_positions.append(item.position)
func spawn_hand(list: Array) -> void:
	var positions=Layout.hand(area(Layout.HAND),list.size())
	for i in list.size():
		var item=positions[i];hand_positions.append(item.position)
		var c=spawn_card(list[i],"hand",item.position,item.size);c.z_index=i

func blocked() -> bool:
	if host.ui_blocked() or host.history_open or host.game.state.has("confirmation"):return true
	if not host.in_match or host.game.state.phase!="recruit" or not host.game.state.players[0].alive: return true
	var p=host.game.state.players[0]
	return (not p.choices.is_empty() and not host.choice_target_pending()) or (host.active_choice!="" and p.sessions.has(host.active_choice) and not p.sessions[host.active_choice].resolved)
func token_at(pos: Vector2) -> Dictionary:
	
	for i in range(cards.size()-1,-1,-1):
		var token=cards[i]
		if token.zone=="hand":
			var hit=Rect2(token.node.position,token.node.size).merge(Rect2(token.base,token.node.size))
			if hit.has_point(pos): return token
		elif Rect2(token.node.position,token.node.size).has_point(pos): return token
	return {}
func _input(event: InputEvent) -> void:
	if retired or not is_inside_tree() or not is_instance_valid(host): return
	if host.ui_blocked() or host.history_open:return
	if host.game.state.phase=="combat":
		if event is InputEventMouseMotion:
			pointer=get_global_transform_with_canvas().affine_inverse()*event.position; update_hover()
		return
	if blocked():
		if host.choice_view_is_hidden() and event is InputEventMouseMotion:
			pointer=get_global_transform_with_canvas().affine_inverse()*event.position;update_hover()
		return
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
		consume_input_event(); cancel(); return
	if event is InputEventMouseButton:
		pointer=get_global_transform_with_canvas().affine_inverse()*event.position
		if event.pressed and event.button_index==MOUSE_BUTTON_LEFT and host.placing_minion>=0 and regions.board.has_point(pointer):
			consume_input_event(); host.begin_minion_placement(host.placing_minion,insertion(pointer.x,true)); return
		if event.pressed and host.fast_mode_enabled and host.activated_source<0 and down.is_empty() and not dragging and not host.choice_target_pending():
			var quick_token=token_at(pointer)
			if event.button_index==MOUSE_BUTTON_RIGHT and host.selected_spell<0 and not host.power_target and not quick_token.is_empty() and host.pending_play.is_empty():
				var plan=host.fast_plan(quick_token.card,str(quick_token.zone),true)
				consume_input_event()
				if plan.is_empty() or plan.get("reason","")=="RIGHT_CLICK_CANCEL": cancel()
				else: submit_fast_plan(plan,quick_token.card)
				return

		if event.button_index==MOUSE_BUTTON_RIGHT and event.pressed:
			consume_input_event(); cancel(); return
		if event.button_index!=MOUSE_BUTTON_LEFT: return
		if event.pressed:
			var token=token_at(pointer)
			if not token.is_empty():
				down=token.duplicate(); down["origin"]=pointer
				consume_input_event()
		elif not down.is_empty():
			var released=down; var was_dragging=dragging; var plan=plan_at(pointer) if dragging else {}
			reset_drag()
			consume_input_event()
			if was_dragging:
				if legal(plan):
					var start=pointer+global_position-released.node.size*0.5
					if plan.kind=="place_minion": host.begin_minion_placement(int(plan.payload.instance_id),int(plan.payload.index))
					else: host.command(plan.kind,plan.payload)
					var table=host.screen.get_node_or_null("TavernTable")
					if table: table.animate_result(plan,start)
				else: hint.text=reason(plan); restore_positions()
			else:
				var target=token_at(pointer)
				if not target.is_empty() and int(target.card.instance_id)==int(released.card.instance_id):
					if host.fast_mode_enabled and released.zone=="hand" and host.selected_spell<0 and host.activated_source<0 and not host.power_target:
						var fast=host.fast_plan(released.card,"hand",false)
						if not fast.is_empty():submit_fast_plan(fast,released.card)
						else:host.card_clicked(released.card,released.zone)
					else:host.card_clicked(released.card,released.zone)
	elif event is InputEventMouseMotion:
		pointer=get_global_transform_with_canvas().affine_inverse()*event.position
		if not down.is_empty():
			if not dragging and pointer.distance_to(down.origin)>=9: start_drag()
			if dragging:
				var spec=host.registry.get_def(down.card.def_id)
				var aiming=down.zone=="hand" and spec.kind=="spell" and spec.effects[0].get("target","")=="minion"
				ghost.position=down.base+Vector2(0,-24) if aiming else pointer-ghost.size*0.5
				current_plan=plan_at(pointer); update_preview()
				consume_input_event()
		else: update_hover()
	if is_instance_valid(overlay): overlay.queue_redraw()
func consume_input_event() -> void:
	var viewport=get_viewport()
	if viewport: viewport.set_input_as_handled()
func _is_targeted_spell(card: Dictionary) -> bool:
	var d=host.registry.get_def(str(card.get("def_id","")))
	return not d.get("effects",[]).is_empty() and str(d.effects[0].get("target","none")) in ["minion","friendly_minion","friendly_undead"]
func submit_fast_plan(plan: Dictionary,card: Dictionary) -> void:
	if plan.get("noop",false):return
	if plan.get("manual",false):
		if plan.get("reason","")=="FAST_EFFECT_REQUIRES_MANUAL":
			host.status_message=ExternalText.ui("ui_tavern_table.submit_fast_plan.5235f4017516", "此牌会出售随从或立即刷新酒馆，请使用左键");host.render_match();return
		if int(plan.get("instance_id",-1))>=0:
			host.card_clicked(card,"hand")
			if plan.get("right_click",false):host.right_spell_intent=int(card.instance_id)
		return
	var action_plan={"kind":plan.kind,"payload":plan.payload}
	if action_plan.kind=="fast_play_sell":
		# This discrete click commits through submit's validated rollback transaction.
		# Running the whole play/choice/sale chain as a preflight doubles its work.
		host.command(str(action_plan.kind),action_plan.payload);return
	if legal(action_plan):
		host.command(str(action_plan.kind),action_plan.payload); return
	if plan.get("manual_on_reject",false):
		host.card_clicked(card,"hand")
		if plan.get("payload",{}).get("right_click",false) and host.fast_mode_level==2:host.right_spell_intent=int(card.instance_id)
		host.status_message=(ExternalText.ui("ui_tavern_table.submit_fast_plan.3b0ae5172743", "最左") if plan.get("endpoint","")=="left" else ExternalText.ui("ui_tavern_table.submit_fast_plan.c7c84abb1509", "最右"))+ExternalText.ui("ui_tavern_table.submit_fast_plan.6fb4855a440a", "随从不是此法术的合法目标；请选择合法目标")
		host.render_match(); return
	hint.text=reason(action_plan)
	hint.modulate=Color("efa397")
func start_drag() -> void:
	dragging=true
	down.node.modulate.a=0.22
	ghost=Card.new(); ghost.host=host; ghost.card=down.card; ghost.zone=down.zone; ghost.mouse_filter=Control.MOUSE_FILTER_IGNORE; ghost.z_index=100
	ghost.visual_reference_size=down.node.visual_reference_size
	ghost.size=down.node.size; add_child(ghost); ghost.position=pointer-ghost.size*0.5
func plan_at(pos: Vector2) -> Dictionary:
	if down.is_empty(): return {}
	var target=token_at(pos); var id=int(down.card.instance_id); var d=host.registry.get_def(down.card.def_id)
	if host.activated_source>=0:
		if not target.is_empty() and target.zone in ["shop","board"]:return {"kind":"activate","payload":{"instance_id":host.activated_source,"target_id":int(target.card.instance_id),"ability":host.activated_ability},"hint":ExternalText.ui("ui_tavern_table.plan_at.84921418af4f", "松手发动 · 选择目标")}
		return {}
	if down.zone=="board":
		if regions.sell.has_point(pos): return {"kind":"sell","payload":{"instance_id":id},"hint":ExternalText.ui("ui_tavern_table.plan_at.e5bc5921548e", "轮盘未结束 · 请等待或跳过动画") if host.game.R134.sale_blocked(host.game.state.players[0]) else ExternalText.ui("ui_tavern_table.plan_at.14186e867646", "松手出售 · +1铸币")}
		if regions.board.has_point(pos): return {"kind":"move","payload":{"instance_id":id,"index":insertion(pos.x,false)},"hint":ExternalText.ui("ui_tavern_table.plan_at.10a2748d7f18", "松手调整站位")}
	if down.zone=="shop":
		if d.kind=="minion" and regions.shop.has_point(pos):return {"kind":"shop_move","payload":{"instance_id":id,"index":shop_insertion(pos.x)},"hint":ExternalText.ui("ui_tavern_table.plan_at.eb786789f0b6", "松手调整酒馆随从顺序 · 免费")}
		if regions.buy.has_point(pos):return {"kind":"buy","payload":{"instance_id":id},"hint":ExternalText.ui("ui_tavern_table.plan_at.a76034e17168", "松手购买 · ")+host.payment_view("buy",down.card).text+ExternalText.ui("ui_tavern_table.plan_at.5b297338d8a1", " · 放入手牌")}
	if down.zone=="hand":
		if d.kind=="minion" and regions.board.has_point(pos) and host.game.requires_battlecry_target(d): return {"kind":"place_minion","payload":{"instance_id":id,"index":insertion(pos.x,true)},"hint":ExternalText.ui("ui_tavern_table.plan_at.1e4e9f98f880", "松手确定落位，再选择战吼目标")}
		if d.kind=="minion" and regions.board.has_point(pos) and (d.effects.any(func(e):return e.handler=="magnetic")) and not target.is_empty() and target.zone=="board": return {"kind":"play","payload":{"instance_id":id,"target_id":int(target.card.instance_id)},"hint":ExternalText.ui("ui_tavern_table.plan_at.4cc775244aa0", "松手选择目标")}
		if d.kind=="minion" and regions.board.has_point(pos): return {"kind":"play","payload":{"instance_id":id,"index":insertion(pos.x,true)},"hint":ExternalText.ui("ui_tavern_table.plan_at.a9a124a7d43f", "松手打出到此位置")}
		if d.kind=="spell":
			if d.effects[0].get("target","none") in ["minion","friendly_minion","friendly_undead"]:
				if not target.is_empty() and target.zone in ["shop","board"] and host.registry.get_def(target.card.def_id).kind=="minion": return {"kind":"play","payload":{"instance_id":id,"target_id":int(target.card.instance_id)},"hint":ExternalText.ui("ui_tavern_table.plan_at.3d2b44e3d684", "松手施放 · ")+host.registry.get_def(target.card.def_id).name}
			elif regions.cast.has_point(pos): return {"kind":"play","payload":{"instance_id":id},"hint":ExternalText.ui("ui_tavern_table.plan_at.25aba58ed30e", "松手施放")}
	return {}
func shop_insertion(x: float) -> int:
	var minions=cards.filter(func(t):return t.zone=="shop" and host.registry.get_def(t.card.def_id).kind=="minion")
	var index=0
	for token in minions:
		if int(token.card.instance_id)!=int(down.card.instance_id) and x>token.base.x+token.node.size.x*0.5:index+=1
	return clampi(index,0,maxi(0,minions.size()-1))
func insertion(x: float,adding: bool) -> int:
	var n=host.game.state.players[0].board.size()+(1 if adding else 0)
	var positions=Layout.row(regions.board,n)
	if positions.is_empty():return 0
	var nearest=0;var distance=INF
	for i in positions.size():
		var candidate=absf(x-positions[i].get_center().x)
		if candidate<distance:nearest=i;distance=candidate
	return nearest

func legal(plan: Dictionary) -> bool:
	if plan.is_empty(): return false
	if plan.get("kind","") in ["sell","fast_play_sell"] and host.game.R134.sale_blocked(host.game.state.players[0]):return false
	var key=JSON.stringify(plan)
	if not validation_cache.has(key):
		var started=Time.get_ticks_usec()
		validation_cache[key]=host.game.preview_placement(0,plan.payload) if plan.kind=="place_minion" else host.game.preview_action(0,plan.kind,plan.payload)
		host.record_stage("preview:"+str(plan.kind),started)
	return validation_cache[key].accepted
func reason(plan: Dictionary) -> String:
	if plan.is_empty(): return ExternalText.ui("ui_tavern_table.reason.e214c841be51", "已取消：拖到无效位置，牌和铸币保持不变")
	if plan.get("kind","") in ["sell","fast_play_sell"] and host.game.R134.sale_blocked(host.game.state.players[0]):return ExternalText.ui("ui_tavern_table.reason.e5bc5921548e", "轮盘未结束 · 请等待或跳过动画")
	legal(plan)
	var error=validation_cache[JSON.stringify(plan)].get("error_code","")
	return {"NO_TOUCH_TARGET":ExternalText.ui("ui_tavern_table.reason.60f352399be2", "BG28_830无法使用：酒馆中没有可点金的普通随从"),"SHOP_MINION_REQUIRED":ExternalText.ui("ui_tavern_table.reason.3261258c76d5", "只能重排酒馆随从"),"HAND_FULL":ExternalText.ui("ui_tavern_table.reason.edbb9250abd9", "手牌已满，无法购买"),"RESULT_EXCEEDS_CAPACITY":ExternalText.ui("ui_tavern_table.reason.b9910ed5b471", "操作后阵容会超出容量，无法执行"),"POWER_COOLDOWN":ExternalText.ui("ui_tavern_table.reason.62fd03d79f00", "技能尚在冷却"),"POWER_LOCKED_UNTIL_TURN_3":ExternalText.ui("ui_tavern_table.reason.04d84ef8c18e", "第3回合解锁"),"BOARD_FULL":ExternalText.ui("ui_tavern_table.reason.32df6a06e5e0", "场上已满，无法打出"),"NOT_ENOUGH_COINS":ExternalText.ui("ui_tavern_table.reason.05107fb17ce5", "铸币不足"),"NOT_ENOUGH_HEALTH":ExternalText.ui("ui_tavern_table.reason.c07ad88dc00e", "血量不足"),"CARD_LOCKED":ExternalText.ui("ui_tavern_table.reason.5a64df82fc4e", "此牌尚未解锁")}.get(error,ExternalText.ui("ui_tavern_table.reason.b99f5573f2ff", "当前无法执行：")+str(error))
func update_preview() -> void:
	var valid=legal(current_plan)
	hint.text=current_plan.hint if valid else reason(current_plan)
	if valid and current_plan.kind in ["play","place_minion"]:
		var warning=host.risk_view(down.card)
		if warning.text!="":hint.text+=" · "+warning.text
	hint.modulate=Color("b2efb9") if valid else Color("efa397")
	var key=JSON.stringify(current_plan)
	if key==last_plan_key: return
	last_plan_key=key
	if valid and current_plan.kind=="shop_move":
		var minions=cards.filter(func(t):return t.zone=="shop" and host.registry.get_def(t.card.def_id).kind=="minion")
		var ordered=minions.filter(func(t):return int(t.card.instance_id)!=int(down.card.instance_id));ordered.insert(int(current_plan.payload.index),{})
		for i in ordered.size():
			if not ordered[i].is_empty():ordered[i].node.glide(minions[i].base)
		return
	if valid and current_plan.kind in ["move","play","place_minion"] and current_plan.payload.has("index"):
		var ordered=[]
		for token in cards:
			if token.zone=="board" and int(token.card.instance_id)!=int(down.card.instance_id): ordered.append(token)
		ordered.insert(int(current_plan.payload.index),{})
		var positions=Layout.row(regions.board,ordered.size())
		for i in ordered.size():
			if not ordered[i].is_empty():
				ordered[i].node.size=positions[i].size
				ordered[i].node.glide(positions[i].position)
	else: restore_positions()
func restore_positions() -> void:
	if retired or not is_inside_tree(): return
	for token in cards:
		if is_instance_valid(token.node) and token.node.is_inside_tree(): token.node.size=token.dimensions;token.node.glide(token.base);token.node.queue_redraw()
func reset_drag() -> void:
	if not down.is_empty() and is_instance_valid(down.node): down.node.modulate.a=1.0
	if is_instance_valid(ghost): ghost.queue_free(); ghost=null
	down={}; dragging=false; current_plan={}; last_plan_key=""
func retire() -> void:
	retired=true; set_process_input(false); set_process(false)
	hidden_inspection_active=false;inspecting_trinket=false
	if is_instance_valid(inspection):inspection.hide()
	if is_instance_valid(pending_preview):pending_preview.hide()
	reset_drag(); hovered={}
	for token in cards:
		if is_instance_valid(token.node): token.node.stop_motion()
func cancel(show_hint=true) -> void:
	host.keyword_fx.cancel_intent()
	if retired or not is_inside_tree(): return
	if host.choice_target_cancellable():
		reset_drag();host.command("cancel_choice");return
	var had_pending=not host.pending_play.is_empty()
	var had_activation=host.activated_source>=0
	reset_drag(); restore_positions()
	host.selected_spell=-1; host.right_spell_intent=-1; host.power_target=false; host.activated_source=-1; host.clear_pending_play()
	
	if show_hint: host.status_message=ExternalText.ui("ui_tavern_table.cancel.9c02f712ac4f", "操作已取消")
	if show_hint and is_instance_valid(hint): hint.text=ExternalText.ui("ui_tavern_table.cancel.9c02f712ac4f", "操作已取消"); hint.modulate=Color.WHITE
	if is_instance_valid(overlay): overlay.queue_redraw()
	if had_pending or had_activation: host.render_match()
func _notification(what: int) -> void:
	if retired or not is_inside_tree() or not is_instance_valid(host): return
	if what==NOTIFICATION_WM_WINDOW_FOCUS_OUT and is_node_ready():host.cancel_auto_intent()
	if what==NOTIFICATION_WM_WINDOW_FOCUS_OUT and is_node_ready() and (not down.is_empty() or host.selected_spell>=0 or host.power_target or host.activated_source>=0 or host.placing_minion>=0 or not host.pending_play.is_empty()): cancel()
func update_hover() -> void:
	if inspecting_trinket or is_instance_valid(inspection) and inspection.get_rect().has_point(pointer): return
	var token={} if blocked() and host.game.state.phase!="combat" and not host.choice_view_is_hidden() else token_at(pointer)
	if not token.is_empty() and not hovered.is_empty() and token.node==hovered.node:
		token.node.set_hovered(true)
		return
	var same_instance=not token.is_empty() and not hovered.is_empty() and token.card.instance_id==hovered.card.instance_id
	if not hovered.is_empty() and is_instance_valid(hovered.node):
		hovered.node.set_hovered(false)
		if hovered.zone=="hand":hovered.node.z_index=0; hovered.node.glide(hovered.base)
	hovered=token
	if not same_instance: hovered_seconds=0.0
	if not hovered.is_empty():hovered.node.set_hovered(true)
	if not hovered.is_empty() and hovered.zone=="hand": hovered.node.z_index=30; hovered.node.glide(hovered.base)
func refresh_inspection() -> void:
	if not is_instance_valid(inspection):return
	if blocked() and not host.choice_view_is_hidden() and host.game.state.phase!="combat":return
	if host.choice_view_is_hidden():
		inspecting_trinket=false
		if inspection.get_rect().has_point(pointer):return
		var native_text=inspection_text_at(get_global_transform_with_canvas()*pointer)
		if not native_text.is_empty():
			hidden_inspection_active=true;show_detail(native_text);return
		if hovered.is_empty():clear_hidden_inspection()
		else:hidden_inspection_active=true
	var player=host.game.state.players[0]
	for item in quest_areas:
		if item.area.has_point(pointer):
			show_detail(preload("res://ui/round135_presentation.gd").description(host.game,player,item.slot_id));return
	if inspecting_trinket or inspection.get_rect().has_point(pointer):return
	if hovered.is_empty() or not is_instance_valid(hovered.node):return
	if hovered_seconds>0.35:
		var detail=host.card_description_rich(hovered.node.card)
		var sale_coins=host.Presentation.turtle_sale_coins(hovered.card,host.game,hovered.zone)
		if sale_coins>0:detail+="\n[color=#ffe09a]高价出售已生效：上场战斗失利，本轮出售共获得%d币（含基础出售1币）。[/color]" % sale_coins
		var notice=host.payment_view("buy",hovered.card) if hovered.zone=="shop" else host.risk_view(hovered.card) if hovered.zone=="hand" else {}
		if notice.get("tooltip","")!="":detail+="\n[color=#f7ae96]"+host.SpellText.escape(notice.tooltip)+"[/color]"
		var art=hovered.node.texture(host.registry.art_path(hovered.card.def_id)) if host.registry.get_def(hovered.card.def_id).kind=="minion" else null
		show_detail(detail,art)

func restore_hover(position_value: Vector2,instance_id: int,seconds: float) -> void:
	pointer=position_value; update_hover()
	if not hovered.is_empty() and int(hovered.card.instance_id)==instance_id: hovered_seconds=seconds
	refresh_inspection()
func _process(delta: float) -> void:
	if not retired and is_inside_tree() and is_instance_valid(host):update_pending_preview()
	keyword_redraw_accumulator+=delta
	if not retired and keyword_redraw_accumulator>=1.0/30.0:
		keyword_redraw_accumulator=0.0
		for value in cards:value.node.queue_redraw()
		for marker in find_children("KeywordHostMarkers","Control",true,false):marker.queue_redraw()
		var fx_canvas=get_node_or_null("KeywordEventCanvas")
		if fx_canvas:fx_canvas.queue_redraw()
	if retired or not is_inside_tree() or not is_instance_valid(host): return
	var sale_icon=get_node_or_null("SaleIcon")
	if sale_icon:
		var sale_state="disabled" if host.game.R134.sale_blocked(host.game.state.players[0]) else "hover" if dragging and down.get("zone","")=="board" and regions.sell.has_point(pointer) else "normal"
		sale_icon.texture=BTheme.icon("button_sell",sale_state)
	if blocked() and host.game.state.phase!="combat" and not host.choice_view_is_hidden(): return
	
	if host.game.state.phase=="combat": update_hover()
	if not dragging:
		if not hovered.is_empty(): hovered_seconds+=delta
		refresh_inspection()

	if is_instance_valid(overlay): overlay.queue_redraw()
func paint_overlay(canvas: Control) -> void:
	if retired or not is_inside_tree(): return
	if blocked(): return
	var valid=legal(current_plan) if dragging else false
	if dragging:
		var area=regions.sell if down.zone=="board" and regions.sell.has_point(pointer) else regions.board if down.zone in ["board","hand"] and regions.board.has_point(pointer) else regions.shop if current_plan.get("kind","")=="shop_move" else regions.buy if down.zone=="shop" else Rect2()
		if area.size!=Vector2.ZERO: canvas.draw_style_box(host.box(Color(0.8,0.8,0.3,0.06),Color("9bdfa3") if valid else Color("d66b55"),30),area)
		if valid and current_plan.kind=="shop_move":
			var minions=cards.filter(func(t):return t.zone=="shop" and host.registry.get_def(t.card.def_id).kind=="minion")
			var slot=minions[int(current_plan.payload.index)];var x=slot.base.x+slot.node.size.x*0.5
			canvas.draw_line(Vector2(x,regions.shop.position.y+20),Vector2(x,regions.shop.end.y),BTheme.TEAL,4,true)
		elif valid and current_plan.payload.has("index"):
			var positions=Layout.row(regions.board,host.game.state.players[0].board.size()+(1 if down.zone=="hand" else 0))
			var slot=positions[int(current_plan.payload.index)]
			canvas.draw_line(Vector2(slot.get_center().x,slot.position.y),Vector2(slot.get_center().x,slot.end.y),BTheme.TEAL,4,true)
	var spell_id=host.selected_spell
	if dragging and down.zone=="hand" and host.registry.get_def(down.card.def_id).kind=="spell": spell_id=int(down.card.instance_id)
	if spell_id>=0 or host.power_target or host.activated_source>=0 or host.choice_target_pending():
		var origin=power_areas.get(host.selected_power_slot,area(Layout.power(0,1))).get_center()
		for token in cards:
			if int(token.card.instance_id) in [spell_id,host.activated_source]: origin=token.base+token.node.size*0.5
		var target=token_at(pointer)
		var target_valid=false
		for token in cards:
			if token.zone not in ["shop","board"]: continue
			var args=host.pending_play.duplicate() if not host.pending_play.is_empty() else {"instance_id":spell_id}
			args["target_id"]=int(token.card.instance_id)
			var query={"kind":"power","payload":{"slot_id":host.selected_power_slot,"target_id":int(token.card.instance_id)}} if host.power_target else {"kind":"activate","payload":{"instance_id":host.activated_source,"target_id":int(token.card.instance_id),"ability":host.activated_ability}} if host.activated_source>=0 else {"kind":"play","payload":args}
			if host.choice_target_pending():query={"kind":"choose_target","payload":{"target_id":int(token.card.instance_id)}}
			if legal(query):
				canvas.draw_texture_rect(BTheme.texture("available_glow_shield"),Rect2(token.node.position-Vector2(2,2),token.node.size+Vector2(4,4)),false)
				if not target.is_empty() and target.card.instance_id==token.card.instance_id: target_valid=true
		var end=pointer; var color=Color("98e7d2") if target_valid else Color("e87962")
		var curve=PackedVector2Array()
		for i in 25:
			var t=i/24.0; curve.append(origin.lerp(end,t)+Vector2(0,-sin(t*PI)*45))
		canvas.draw_polyline(curve,color,4,true)
		var direction=(end-curve[-2]).normalized(); canvas.draw_colored_polygon(PackedVector2Array([end,end-direction.rotated(0.5)*22,end-direction.rotated(-0.5)*22]),color)
		if not target.is_empty() and target.zone in ["shop","board"]: canvas.draw_rect(Rect2(target.node.position-Vector2(3,3),target.node.size+Vector2(6,6)),color,false,3)

func build_combat() -> void:
	slab(rect(0,70,126,674),BTheme.PANEL,BTheme.BORDER).name="OpponentSidebar"
	build_opponents()
	playback_window=maxf(0.55,1.15/host.battle_speed)
	var state=host.game.state
	var undo_button=action("",rect(390,0,236,44),host.undo_last_operation,"Undo")
	host.update_undo_button(undo_button)
	build_history()
	build_tribes()
	text(ExternalText.ui("ui_tavern_table.build_combat.3c83193d1a3b", "战斗"),rect(18,8,140,40),30)
	text(ExternalText.ui("ui_tavern_table.build_combat.7c506f4e6663", "第 %d 回合") % state.round,rect(174,15,150,30),22)
	slab(rect(138,190,932,424),Color("513d2c"),Color("b99a66"),64)
	var frames=state.get("combat_frames",[])
	if not frames.is_empty():
		var frame=frames[mini(host.frame_index,frames.size()-1)]
		var own_left=int(state.human_left)==0
		var shown=frame if host.playback_skipped else frame.get("presentation",{}).get("before",frame)
		host.combat_presentation=shown
		host.show_history_until(int(shown.get("event_seq",state.event_seq)))
		var own=shown.left if own_left else shown.right
		var enemy=shown.right if own_left else shown.left
		spawn_row(enemy,"combat",226,146,1062,Layout.CARD)
		spawn_row(own,"combat",440,146,1062,Layout.CARD)
		var hand_side="left" if own_left else "right"
		var hands=shown.get("hands",{})
		var own_hand=hands.get(hand_side,[])
		var pending=hands.get(hand_side+"_pending",[])
		build_hand_counts(own_hand,pending)
		if not own_hand.is_empty():spawn_combat_hand(own_hand)
		host.keyword_fx.shown_events(host,shown)
		var opponent=Opponents.target(host.game).get("player",state.players[int(state.human_right if own_left else state.human_left)])
		var opponent_art=host.image_for(opponent.hero_id,Vector2(85,95));UISkin.mask_portrait(opponent_art);place(opponent_art,rect(520,74,85,95))
		UISkin.frame(self,"portrait_side",rect(515,69,95,105),"CombatOpponentFrame")
		text(opponent.name,rect(620,102,300,30),18)
		number_badge("badge_health",int(opponent.health),rect(619,134,54,34),BTheme.TEXT,"OpponentHealth")
		number_badge("badge_armor",int(opponent.armor),rect(679,134,44,34),BTheme.TEXT,"OpponentArmor")
		var own_art=host.image_for(state.players[0].hero_id,Vector2(88,98));UISkin.mask_portrait(own_art);place(own_art,rect(445,638,84,88))
		UISkin.frame(self,"portrait_main",rect(435,630,104,106),"CombatHeroFrame")
		main_hero_badges(state.players[0],BTheme.TEXT)
		var caption=text(frame.message,rect(160,396,890,40),18)
		caption.name="CombatCaption"; caption.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; caption.size=Vector2(890,40)
		if frame.has("presentation") and not host.playback_skipped: call_deferred("animate_combat",frame)
	else:
		text(ExternalText.ui("ui_tavern_table.build_combat.c4772943f65b", "你已淘汰 · 观看本轮结果"),rect(399,345,650,40),28)
		build_hand_counts([],[])
	action(ExternalText.ui("ui_tavern_table.build_combat.8735770c2979", "下一回合") if not state.get("match_over",false) else ExternalText.ui("ui_tavern_table.build_combat.9351b5bd3d24", "查看结算"),rect(1100,654,284,64),func():host.command("continue"),"Continue")
	action(ExternalText.ui("ui_tavern_table.build_combat.36035edbb6e7", "跳过战斗"),rect(1100,738,284,44),host.skip_combat,"Skip")
	action(host.playback_label(),rect(1100,596,284,48),host.toggle_playback_speed,"Speed")
	text("%d / %d" % [host.frame_index+1,frames.size()],rect(1100,548,284,32),22)
	build_combat_keyword_hosts()
	var y=636
	for result in state.results:
		var message=ExternalText.ui("ui_tavern_table.build_combat.1a4675aa847c", "平局") if int(result.winner)<0 else ExternalText.ui("ui_tavern_table.build_combat.798ea022f652", "%d 伤害") % result.damage
		text("%s vs %s · %s" % [state.players[int(result.a)].name,state.players[int(result.b)].name,message],rect(146,y,290,26),13)
		y+=28
	preload("res://ui/round135_presentation.gd").build(self)

func spawn_combat_hand(list: Array) -> void:
	spawn_hand(list)

func animate_result(plan: Dictionary,from_global: Vector2) -> void:
	for token in cards:
		if int(token.card.instance_id)==int(plan.payload.get("instance_id",-1)) and plan.kind in ["move","buy","play"]:
			token.node.position=from_global-global_position
			token.node.glide(token.base)
		if int(token.card.instance_id)==int(plan.payload.get("target_id",-1)):
			token.node.self_modulate=Color(1.4,1.35,0.6)
			create_tween().tween_property(token.node,"self_modulate",Color.WHITE,0.25)
	if plan.kind=="sell":
		var receipt=text(ExternalText.ui("ui_tavern_table.animate_result.042f356f7fd9", "+1 铸币"),rect(650,85,180,40),25,Color("ffe394"))
		var animation=create_tween().set_parallel(true)
		animation.tween_property(receipt,"position",receipt.position+Vector2(0,-28),0.4)
		animation.tween_property(receipt,"modulate:a",0.0,0.4)
		animation.finished.connect(receipt.queue_free)

func combat_token(id: int) -> Dictionary:
	for token in cards:
		if int(token.card.instance_id)==id: return token
	return {}
func combat_popup(token: Dictionary,value: String,color: Color,duration: float) -> void:
	if token.is_empty(): return
	var label_node=text(value,Rect2(token.base+Vector2(-14,48),Vector2(160,35)),24,color)
	label_node.z_index=80
	var tween=create_tween().set_parallel(true)
	tween.tween_property(label_node,"position",label_node.position+Vector2(0,-30),duration)
	tween.tween_property(label_node,"modulate:a",0.0,duration)
	tween.finished.connect(label_node.queue_free)
func animate_combat(frame: Dictionary) -> void:
	var data=frame.presentation
	var duration=playback_window
	var actor=combat_token(int(data.attacker)); var target=combat_token(int(data.target))
	var caption=get_node("CombatCaption")
	caption.text=frame.message+(ExternalText.ui("ui_tavern_table.animate_combat.0d8dc9642a2d", " · 连击 %d/%d") % [data.strike,data.strikes] if int(data.strikes)>1 else "")
	if not actor.is_empty() and not target.is_empty():
		actor.node.z_index=40
		var motion=create_tween()
		motion.tween_property(actor.node,"position",actor.base+(target.base-actor.base)*0.72,duration*0.19).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		motion.tween_property(actor.node,"position",actor.base,duration*0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		target.node.self_modulate=Color(1.3,0.85,0.7)
	var sequence=create_tween()
	sequence.tween_interval(duration*0.20)
	sequence.tween_callback(func():
		host.keyword_fx.combat(host,frame,"combat:"+str(host.game.state.round)+":"+str(host.frame_index))
		host.combat_presentation=data.damaged
		for c in data.damaged.left+data.damaged.right:
			var token=combat_token(int(c.instance_id))
			if token.is_empty(): continue
			var previous=token.card
			if previous.get("shield",false) and not c.shield: combat_popup(token,ExternalText.ui("ui_tavern_table.animate_combat.65f5ed513c85", "破盾"),Color("fff6b5"),duration*0.6)
			elif int(c.health)<int(previous.health): combat_popup(token,"−"+host.Presentation.number(int(previous.health)-int(c.health)),Color("ffb5a0"),duration*0.6)
			token.card=c; token.node.card=token.card; token.node.refresh_spell_body(); token.node.queue_redraw()
			token.node.self_modulate=Color.WHITE
			if int(c.health)<=0: create_tween().tween_property(token.node,"modulate:a",0.0,duration*0.2)
		refresh_inspection()
	)
	sequence.tween_interval(duration*0.25)
	sequence.tween_callback(func():
		var hover_id=int(hovered.card.instance_id) if not hovered.is_empty() else -1
		host.combat_presentation=frame
		host.show_history_until(int(frame.get("event_seq",host.game.state.event_seq)))
		var hover_time=hovered_seconds
		for token in cards:
			remove_child(token.node); token.node.queue_free()
		cards=[]; hovered={}
		var own_left=int(host.game.state.human_left)==0
		spawn_row(frame.right if own_left else frame.left,"combat",226,146,1062,Layout.CARD)
		spawn_row(frame.left if own_left else frame.right,"combat",440,146,1062,Layout.CARD)
		var hand_side="left" if own_left else "right"
		var own_hand=frame.get("hands",{}).get(hand_side,[])
		var own_pending=frame.get("hands",{}).get(hand_side+"_pending",[])
		build_hand_counts(own_hand,own_pending)
		if not own_hand.is_empty():spawn_combat_hand(own_hand)

		host.keyword_fx.shown_events(host,frame)
		restore_hover(pointer,hover_id,hover_time)
		var feedback=[]
		for e in data.feedback:
			var name_value=host.registry.get_def(e.def_id).name
			var kind={"death":ExternalText.ui("ui_tavern_table.animate_combat.7ac7d536e49c", "阵亡"),"deathrattle":ExternalText.ui("ui_tavern_table.animate_combat.6e6d5b407276", "亡语触发"),"summon":ExternalText.ui("ui_tavern_table.animate_combat.e9c752722972", "召唤"),"reborn":ExternalText.ui("ui_tavern_table.animate_combat.b5a9c20568b6", "复生"),"reward":ExternalText.ui("ui_tavern_table.animate_combat.91b7d4a452ec", "获得卡牌"),"reward_queued":ExternalText.ui("ui_tavern_table.animate_combat.7cf8f944c575", "手满待领取")}.get(e.kind,e.kind)
			feedback.append(name_value+" · "+kind)
			if e.kind in ["summon","reborn"]:
				var token=combat_token(int(e.instance_id))
				if not token.is_empty():
					token.node.modulate.a=0.15
					create_tween().tween_property(token.node,"modulate:a",1.0,duration*0.22)
					combat_popup(token,kind,Color("9ae5ff"),duration*0.5)
		if not feedback.is_empty(): caption.text+="\n"+"；".join(feedback)
	)
func build_history() -> void:
	action("法术记录 · %d" % host.visible_spell_history().size(),rect(640,0,228,44),host.open_spell_history,"SpellHistoryOpen")

func build_combat_keyword_hosts() -> void:
	var p=host.game.state.players[0]
	for i in p.power_slots.size():
		var slot=p.power_slots[i];var seat=Panel.new();seat.name="CombatPowerFX_"+str(slot.slot_id);seat.mouse_filter=Control.MOUSE_FILTER_IGNORE
		UISkin.panel(seat,"skill_seat");place(seat,rect(564+i*176,642,168,80))
		var d=host.registry.get_def(slot.active_power_id);var art=TextureRect.new();art.texture=host.texture_for_path(host.registry.hero_power_art(slot.active_power_id));art.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;art.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;art.mouse_filter=Control.MOUSE_FILTER_IGNORE;seat.add_child(art);art.position=Vector2(8,18);art.size=Vector2(44,44)
		var caption=host.label(str(d.name),12,BTheme.TEXT);caption.position=Vector2(55,24);caption.size=Vector2(106,46);caption.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;caption.mouse_filter=Control.MOUSE_FILTER_IGNORE;seat.add_child(caption)
		KeywordFX.attach_host(seat,host,{},slot)
	var width=144.0/maxi(1,p.trinkets.size())
	for i in p.trinkets.size():
		var item=p.trinkets[i];var seat=Panel.new();seat.name="CombatTrinketFX_"+str(item.get("instance_id",i));seat.mouse_filter=Control.MOUSE_FILTER_IGNORE
		UISkin.panel(seat,"item_seat");place(seat,rect(920+i*width,642,width-2,80))
		var d=host.registry.get_def(item.id);var binding=host.registry.trinket_binding(item.id);var art=TextureRect.new();art.texture=host.texture_for_path(host.registry.art_path_for_key(str(binding.get("asset_key",""))));art.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;art.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;art.mouse_filter=Control.MOUSE_FILTER_IGNORE;seat.add_child(art);art.position=Vector2(15,4);art.size=Vector2(maxf(1,width-20),40)
		var caption=host.label(str(d.name),10,BTheme.TEXT);caption.position=Vector2(4,45);caption.size=Vector2(width-10,31);caption.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;caption.mouse_filter=Control.MOUSE_FILTER_IGNORE;seat.add_child(caption)
		KeywordFX.attach_host(seat,host,item)
