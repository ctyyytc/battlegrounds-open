extends Button
const ExternalText = preload("res://domain/resources/external_content.gd")
const Presentation=preload("res://ui/card_presentation.gd")
const ShieldShader=preload("res://ui/divine_shield.gdshader")
const KeywordFX=preload("res://ui/keyword_fx.gd")
const BTheme=preload("res://ui/round142_theme.gd")
var shield_surface: ColorRect
var host
var card: Dictionary
var zone: String
var hovered=false
var available_action: bool=false
var base_position=Vector2.ZERO
var motion: Tween
var spell_body: RichTextLabel
var last_spell_body: String=""
var payment_notice: Dictionary={}
var risk_notice: Dictionary={}
var visual_reference_size=Vector2.ZERO
var sale_bonus_coins: int=0
var sale_bonus_time: float=0.0
func canvas_size() -> Vector2:
	return size if visual_reference_size==Vector2.ZERO else visual_reference_size
func visual_ratio() -> float:
	return size.x/canvas_size().x
func icon_geometry() -> Dictionary:
	var extent=canvas_size()
	return {"art":Rect2(13,13,extent.x-26,extent.y-45),"frame":Rect2(2,0,extent.x-4,extent.y-18),"scale":visual_ratio()}
func _ready() -> void:
	focus_mode=Control.FOCUS_NONE
	mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	for state_name in ["normal","hover","pressed","focus","disabled"]: add_theme_stylebox_override(state_name,StyleBoxEmpty.new())
	tooltip_text=""
	var definition=host.registry.get_def(card.def_id)
	set_process(zone=="board" and str(definition.get("base_id",definition.id))=="BG24_018")
	if definition.kind in ["spell","special"]:
		spell_body=host.rich_label("",12,Color("eee2c5")); spell_body.fit_content=false; spell_body.scroll_active=false;spell_body.clip_contents=true; spell_body.mouse_filter=Control.MOUSE_FILTER_IGNORE
		add_child(spell_body); refresh_spell_body()
	shield_surface=ColorRect.new(); shield_surface.mouse_filter=Control.MOUSE_FILTER_IGNORE
	shield_surface.material=ShaderMaterial.new(); shield_surface.material.shader=ShieldShader
	
	shield_surface.z_index=0 if zone=="combat" else -1
	add_child(shield_surface)
	mouse_entered.connect(func():set_hovered(true))
	mouse_exited.connect(func():set_hovered(false))
func set_hovered(value: bool) -> void:
	if hovered==value:return
	hovered=value
	refresh_spell_body()
	queue_redraw()
func _process(delta: float) -> void:
	var coins=Presentation.turtle_sale_coins(card,host.game,zone)
	if coins>0 or coins!=sale_bonus_coins:
		sale_bonus_time=fmod(sale_bonus_time+delta,1.8)
		sale_bonus_coins=coins
		queue_redraw()
func sale_bonus_badge_rect() -> Rect2:
	var extent=canvas_size()
	# Above the tier star: no name, stats, art or keyword markers are covered.
	return Rect2(3,-38,extent.x-6,22)
func sale_bonus_caption() -> String:
	return ("售%d币" if visual_ratio()<0.7 else "出售 %d币") % sale_bonus_coins
func draw_sale_bonus() -> void:
	sale_bonus_coins=Presentation.turtle_sale_coins(card,host.game,zone)
	if sale_bonus_coins<=0:return
	var extent=canvas_size()
	var pulse=0.55+0.35*(sin(sale_bonus_time*TAU/1.8)+1.0)*0.5
	var rim=host.box(Color(0,0,0,0),Color(1.0,0.72,0.20,pulse),6)
	rim.set_border_width_all(3)
	draw_style_box(rim,Rect2(Vector2(-2,-2),extent+Vector2(4,4)))
	for x in [4.0,extent.x-4.0]:
		draw_circle(Vector2(x,6),2.5+1.5*pulse,Color(1.0,0.87,0.35,pulse))
	var badge=sale_bonus_badge_rect()
	draw_style_box(host.box(Color("38270d"),Color("f1c45a"),5),badge)
	line(sale_bonus_caption(),badge.grow(-1),17 if visual_ratio()<0.7 else 14,Color("fff0b5"))
func texture(path: String) -> Texture2D:
	if path=="": return null
	if path.begins_with("res://assets/ui/"):
		var key="ui:"+path.get_file().get_basename()+":texture:normal:neutral"
		return host.ui_texture(key)
	return host.texture_for_path(path)
# One geometry drives the real card and its drag ghost. Compact hands stack stats.
func minion_geometry() -> Dictionary:
	var extent=canvas_size()
	var compact=zone=="hand" and extent.x<80
	var stats_height=42.0 if compact else 27.0 if zone=="hand" else 31.0
	var stats=Rect2(3,extent.y-stats_height-1,extent.x-6,stats_height)
	var title_height=20.0 if zone=="hand" else 25.0
	var title=Rect2(3,stats.position.y-title_height-3,extent.x-6,title_height)
	var art=Rect2(6,5,extent.x-12,title.position.y-9) if zone=="hand" else icon_geometry().art
	var cells=[Rect2(stats.position,Vector2(stats.size.x,20)),Rect2(stats.position+Vector2(0,22),Vector2(stats.size.x,20))] if compact else [Rect2(stats.position,Vector2((stats.size.x-3)/2,stats.size.y)),Rect2(stats.position+Vector2((stats.size.x+3)/2,0),Vector2((stats.size.x-3)/2,stats.size.y))]
	return {"art":art,"title":title,"stats":stats,"cells":cells,"compact":compact,"icon_size":12.0 if compact else 16.0 if zone=="hand" else 21.0,"name_font":14 if zone=="hand" else 16,"stat_font":16 if compact else 21 if zone=="hand" else 24}
func fitted_art_rect(art: Texture2D,area: Rect2) -> Rect2:
	if art==null:return Rect2()
	var factor=minf(area.size.x/art.get_width(),area.size.y/art.get_height())
	var extent=art.get_size()*factor
	return Rect2(area.position+(area.size-extent)*0.5,extent)
func line_layout(text_value: String,rect: Rect2,font_size: int) -> Dictionary:
	var font=get_theme_default_font()
	while font_size>11 and (font.get_string_size(text_value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x>rect.size.x-2 or font.get_height(font_size)>rect.size.y):font_size-=1
	if font.get_string_size(text_value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x>rect.size.x-2:
		while text_value.length()>1 and font.get_string_size(text_value+"…",HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x>rect.size.x-2:text_value=text_value.left(-1)
		text_value+="…"
	var height=font.get_height(font_size)
	return {"text":text_value,"font":font_size,"baseline":rect.position+Vector2(0,(rect.size.y-height)*0.5+font.get_ascent(font_size)),"height":height}
func line(text_value: String,rect: Rect2,font_size: int,color: Color=Color("eee2c5")) -> void:
	var fit=line_layout(text_value,rect,font_size)
	var font=get_theme_default_font()
	draw_string_outline(font,fit.baseline,fit.text,HORIZONTAL_ALIGNMENT_CENTER,rect.size.x,fit.font,2,Color("f6db8a") if color==Color("241c0d") else Color("0b1622"))
	draw_string(font,fit.baseline,fit.text,HORIZONTAL_ALIGNMENT_CENTER,rect.size.x,fit.font,color)
func stat_caption(value: int) -> String:
	var caption=Presentation.number(value)
	# Keep the familiar precise format when it fits; narrow cards use whole units.
	if caption.length()>5:
		var magnitude=absf(float(value));var divisor=1.0;var suffix=""
		for unit in ["K","M","B","T","Q","E"]:
			if magnitude<divisor*1000.0:break
			divisor*=1000.0;suffix=unit
		caption=str(int(float(value)/divisor))+suffix
	return caption
func stat_layout(value: int,rect: Rect2,preferred: int) -> Dictionary:
	var caption=stat_caption(value)
	var font=get_theme_default_font()
	var point_size=preferred
	# Numeric text never takes the name/label ellipsis path.
	while point_size>10 and (font.get_string_size(caption,HORIZONTAL_ALIGNMENT_LEFT,-1,point_size).x>rect.size.x-2 or font.get_height(point_size)>rect.size.y):point_size-=1
	return {"text":caption,"font":point_size,"baseline":rect.position+Vector2(0,(rect.size.y-font.get_height(point_size))*0.5+font.get_ascent(point_size))}
func stat_value_rect(cell: Rect2,geometry: Dictionary) -> Rect2:
	return Rect2(cell.position+Vector2(geometry.icon_size+4,0),Vector2(cell.size.x-geometry.icon_size-5,cell.size.y))
func draw_stats(stats: Vector2i,geometry: Dictionary) -> void:
	for i in 2:
		var cell: Rect2=geometry.cells[i]
		draw_style_box(host.box(Color("101f2a"),Color("60787d"),4),cell)
		var icon_size: float=geometry.icon_size
		var icon=Rect2(cell.position+Vector2(2,(cell.size.y-icon_size)*0.5),Vector2.ONE*icon_size)
		draw_texture_rect(BTheme.texture("attack" if i==0 else "health"),icon,false)
		var value_area=stat_value_rect(cell,geometry)
		var fit=stat_layout(stats[i],value_area,geometry.stat_font)
		var font=get_theme_default_font()
		draw_string_outline(font,fit.baseline,fit.text,HORIZONTAL_ALIGNMENT_CENTER,value_area.size.x,fit.font,2,Color("0b1622"))
		draw_string(font,fit.baseline,fit.text,HORIZONTAL_ALIGNMENT_CENTER,value_area.size.x,fit.font,Color("ffe9a0") if i==0 else Color("ffddd6"))
func refresh_spell_body() -> void:
	if not is_instance_valid(spell_body): return
	var text=host.elemental_card_body(card) if host.registry.get_def(card.def_id).kind=="minion" else host.spell_description(card,true)
	if host.registry.get_def(card.def_id).kind=="special":text=ExternalText.ui("ui_tavern_card.refresh_spell_body.f0f69fac9130", "无法手用")
	if text!=last_spell_body: spell_body.text=text; last_spell_body=text
	spell_body.visible=host.registry.get_def(card.def_id).kind!="minion" and size.x>=80 and (hovered or card.def_id=="BG_TRIPLE_REWARD_R92" or host.registry.get_def(card.def_id).get("is_darkmoon_prize",false) or card.def_id=="BG35_MagicItem_812t")
	var extent=canvas_size();var ratio=visual_ratio();spell_body.scale=Vector2.ONE*ratio
	spell_body.position=Vector2(6,extent.y*0.35)*ratio; spell_body.size=Vector2(extent.x-12,extent.y*0.36)
	if host.registry.get_def(card.def_id).kind!="minion":spell_body.position=Vector2(5,extent.y*0.62)*ratio;spell_body.size=Vector2(extent.x-10,extent.y*0.30)
func _draw() -> void:
	if host==null: return
	
	var size=canvas_size();var ratio=visual_ratio()
	draw_set_transform(Vector2.ZERO,0,Vector2.ONE*ratio)
	var d=host.registry.get_def(card.def_id)
	payment_notice=host.payment_view("buy",card) if zone=="shop" else {}
	risk_notice=host.risk_view(card) if zone=="hand" else {}
	var fx_view=KeywordFX.State.card(host.game,card,zone,int(host.combat_presentation.get("event_seq",host.game.state.event_seq)))
	var golden=d.get("golden",false)
	var hand=zone=="hand" or d.kind!="minion"
	var edge=Color("e3bb62") if golden else Color("ada295")
	if available_action:
		var glow=host.ui_texture("ui:available_glow_square:texture:normal:neutral")
		if glow: draw_texture_rect(glow,Rect2(Vector2(-4,-4),size+Vector2(8,8)),false,Color(1,1,1,0.88))
	var selected=int(card.instance_id)==host.selected_spell or int(card.instance_id)==host.selected_board
	if hovered or selected:
		draw_texture_rect(BTheme.texture("state_selected" if selected else "state_hover"),Rect2(Vector2(-3,-3),size+Vector2(6,6)),false)
	var art=texture(host.registry.art_path(d.id))
	if hand:
		draw_style_box(host.box(BTheme.PANEL,edge,10),Rect2(Vector2.ZERO,size))
		KeywordFX.back(self,fx_view)
		if art:
			var area=minion_geometry().art if d.kind=="minion" else Rect2(size.x*0.13,12,size.x*0.74,size.y*0.48)
			if d.id=="TB_BaconShop_HP_101t2" or d.get("is_darkmoon_prize",false) and art.get_width()>art.get_height()*2:
				var height=area.size.x*34.0/130.0;area.position.y+=(area.size.y-height)/2;area.size.y=height
			KeywordFX.portrait(self,art,fitted_art_rect(art,area),fx_view) if d.kind=="minion" else draw_texture_rect(art,fitted_art_rect(art,area),false)
		var frame_name=("spell_card_frame_golden" if golden else "spell_card_frame") if d.kind!="minion" else "minion_card_frame_golden" if golden else "minion_card_frame"
		var frame=texture("res://assets/ui/"+frame_name+".png")
		if frame: draw_texture_rect(frame,Rect2(Vector2.ZERO,size),false)
		if d.kind!="minion":line(d.name,Rect2(5,size.y*0.51,size.x-10,18),13,BTheme.TEXT)
		if d.kind!="minion":
			if d.kind=="special":line(ExternalText.ui("ui_tavern_card._draw.29273517b9fe", "剩%d回合") % int(card.get("box_remaining",5)),Rect2(5,size.y*0.72,size.x-10,18),14)
			else:
				var price=payment_notice.get("text",str(int(d.get("cost",0))))
				line(str(price),Rect2(0,2,85 if zone=="shop" else 30,26),16 if zone=="shop" else 22,Color("fca395") if payment_notice.get("warm",false) else Color("86c9ff"))
	else:
		KeywordFX.back(self,fx_view)
		var geometry=icon_geometry()
		if art: KeywordFX.portrait(self,art,fitted_art_rect(art,geometry.art),fx_view)
		var frame=texture("res://assets/ui/minion_frame_golden.png" if golden else "res://assets/ui/minion_frame.png")
		if frame: draw_texture_rect_region(frame,geometry.frame,Rect2(47,32,204,282))
	KeywordFX.front(self,fx_view)
	if d.kind=="minion" and not hand:
		draw_texture_rect(BTheme.texture("tier_star"),Rect2(size.x*0.5-18,-12,18,18),false)
		line(str(int(d.tier)),Rect2(size.x*0.5,-9,20,18),14,BTheme.GOLD)
	if d.kind=="minion":
		var name_area: Rect2=minion_geometry().title
		if golden:draw_style_box(BTheme.style("golden_nameplate"),name_area)
		else:draw_style_box(host.box(BTheme.PANEL,Color("81999d"),3),name_area)
		line(d.name,name_area.grow(-2),minion_geometry().name_font,Color("241c0d") if golden else BTheme.TEXT)
	if zone=="shop" and (payment_notice.get("life",false) or card.has("shop_price")):
		
		var warm=bool(payment_notice.warm)
		draw_style_box(host.box(Color("61231e") if warm else Color("263e46"),Color("ed8272") if warm else Color("86bfd0"),4),Rect2(3,31,size.x-6,20))
		line(payment_notice.text,Rect2(4,32,size.x-8,18),13,Color("fff1e9") if warm else Color("ceefff"))
	if zone=="hand" and risk_notice.get("text","")!="":
		draw_style_box(host.box(Color("61231e") if risk_notice.warm else Color("263e46"),Color("ed8272") if risk_notice.warm else Color("86bfd0"),4),Rect2(3,31,size.x-6,20))
		line(risk_notice.text,Rect2(4,32,size.x-8,18),12,Color("fff1e9") if risk_notice.warm else Color("ceefff"))
	if host.game.CardLock.locked(host.game,host.game.state.players[int(card.owner)],card):line(ExternalText.ui("ui_tavern_card._draw.3da91dd4abce", "已锁定"),Rect2(4,3,size.x-8,18),12,Color("9dc8ec"))
	if card.def_id=="BG_TRIPLE_REWARD_R92":
		line("★%d" % int(card.get("reward_tier",1)),Rect2(18,34,size.x-36,36),30,Color("ffe598"))
		line(ExternalText.ui("ui_tavern_card._draw.7daf17c294e9", "发现随从"),Rect2(12,78,size.x-24,24),17,Color("ffe5b2"))
	if zone=="hand" and host.game.Quilboar.choice(d):
		var root=d.duplicate();root["double_choose"]=bool(card.get("double_choose",false))
		var dual=host.game.Quilboar.double_source(host.game,host.game.state.players[0],root)
		if dual.double:
			draw_style_box(host.box(Color("164129"),Color("7cf29e"),4),Rect2(3,25,size.x-6,20))
			line(ExternalText.ui("ui_tavern_card._draw.57627d5f8dae", "双效")+(ExternalText.ui("ui_tavern_card._draw.9aefbe749973", " · 剩%d次") % int(dual.remaining) if dual.has("remaining") else ""),Rect2(4,26,size.x-8,18),13,Color("b9ffd0"))
	if d.kind=="minion" and hovered:
		var gifts=host.game.card_gifts(card)
		if not gifts.is_empty():
			var attack=0;var health=0
			for gift in gifts:
				if int(gift.id)==6:attack+=3
				if int(gift.id)==7:health+=3
			var progress=[];var progress_counts={}
			for gift in gifts:
				if int(gift.id)==2:progress.append(ExternalText.ui("ui_tavern_card._draw.9d584bf3c7f0", "锁%d/%d") % [int(gift.get("attack",2)),int(gift.get("health",2))])
				if int(gift.id) in [9,11,27]:progress.append(ExternalText.ui("ui_tavern_card._draw.98419d8a54cf", "已翻倍") if int(gift.id)==27 and gift.get("doubled",false) else ExternalText.ui("ui_tavern_card._draw.29273517b9fe", "剩%d回合") % maxi(0,2-int(gift.get("progress",0))))
			for value in progress:progress_counts[value]=int(progress_counts.get(value,0))+1
			progress=[]
			for value in progress_counts:progress.append(str(value)+("×%d" % int(progress_counts[value]) if int(progress_counts[value])>1 else ""))
			draw_style_box(host.box(Color("27162e",0.98),Color("bc88cc"),3),Rect2(3,size.y*0.18,size.x-6,29))
			line(ExternalText.ui("ui_tavern_card._draw.cf59ae95aacf", "黑赐%d") % gifts.size()+(ExternalText.ui("ui_tavern_card._draw.1c13084f2058", " ·用牌%d攻%d血") % [attack,health] if attack+health>0 else ExternalText.ui("ui_tavern_card._draw.aa0802b91610", " ·效果见详情")),Rect2(4,size.y*0.18,size.x-8,14),12,Color("f2c4ff"))
			line(" · ".join(progress) if not progress.is_empty() else ExternalText.ui("ui_tavern_card._draw.493f6d8aa2b9", "各份效果见详情"),Rect2(4,size.y*0.18+14,size.x-8,14),12,Color("f2c4ff"))
	
	if hovered and Presentation.grave_warning(card,host.game,zone):
		draw_style_box(host.box(Color(0.82,0.06,0.04,0.32),Color("ff6254"),10),Rect2(Vector2(3,3),size-Vector2(6,6)))
		draw_style_box(host.box(Color("7b211d"),Color("ff6254"),3),Rect2(3,-20,size.x-6,18))
		line(ExternalText.ui("ui_tavern_card._draw.0bc2eed26953", "本回合打出后死亡"),Rect2(4,-20,size.x-8,17),12,Color("fff1dd"))
	if zone=="shop" and (host.game.state.players[0].frozen or card.get("frozen_card",false)):
		var ice=texture("res://assets/ui/status_frozen.png")
		var bottom=size.y-79 if d.kind=="minion" else size.y*0.5
		if ice: draw_texture_rect(ice,Rect2(10,8,size.x-20,bottom-8),false,Color(1,1,1,0.7))
	if zone=="shop" and card.get("r133_ticket",false):
		var ticket=texture(host.registry.art_path_for_key("ui:r133_ticket_badge:texture:normal:neutral"))
		if ticket:draw_texture_rect(ticket,Rect2(size.x-32,56*size.y/184,28,28),false)
	if card.def_id=="TB_BaconShop_HP_101t2":
		line(ExternalText.ui("ui_tavern_card._draw.c6ff15d51c05", "★%d 奖品") % int(card.get("reward_tier",1)),Rect2(5,size.y*0.34,size.x-10,30),19,Color("ffe598"))
	if d.kind=="minion":
		var stats=Vector2i(int(card.attack),int(card.health)) if card.has("attack") else host.game.stats(card)
		var geometry=minion_geometry()
		var stat_y=geometry.stats.position.y
		draw_stats(stats,geometry)
		var badge=host.GoldenText.badge(d,card,host.game.state.enabled_tribes)
		if hovered and badge!="": line(badge,Rect2(5,geometry.title.position.y-18,size.x-10,17),12,Color("eac778"))
		var keys=Presentation.effective(card,host.game)
		if is_instance_valid(shield_surface):
			shield_surface.position=Vector2(9,9)*ratio
			shield_surface.size=Vector2(size.x-18,stat_y-34)*ratio
			shield_surface.visible=false
		if golden: line(ExternalText.ui("ui_tavern_card._draw.a77060dae697", "金"),Rect2(size.x-23,0,22,20),13,Color("ffe29a"))
	draw_sale_bonus()
func stop_motion() -> void:
	if is_instance_valid(motion) and motion.is_running(): motion.kill()
func glide(destination: Vector2) -> void:
	stop_motion()
	if not is_inside_tree() or is_queued_for_deletion(): return
	motion=create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	motion.tween_property(self,"position",destination,0.12)
