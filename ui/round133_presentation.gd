extends Control
const ExternalText = preload("res://domain/resources/external_content.gd")
var host
var flights=[]
var clock_time=0.0
func _ready():
	name="Round133Feedback";mouse_filter=Control.MOUSE_FILTER_IGNORE;z_index=70
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
func texture(key: String) -> Texture2D:
	return host.texture_for_path(host.registry.art_path_for_key(key))
func feedback(events: Array,anchors: Dictionary):
	var offset=0.0
	for event in events:
		if event.kind!="TicketCollected" or int(event.owner)!=0:continue
		var f=event.payload.duplicate(true);f["start"]=clock_time+offset;offset+=0.055
		f["from"]=anchors.get(int(f.instance_id),Vector2(650,340));f["to"]=anchors.get("power_"+str(int(f.slot_id)),Vector2(842,740))
		flights.append(f)
func _process(delta):
	clock_time+=delta
	if host.game==null:flights=[];return
	var p=host.game.state.players[0]
	flights=flights.filter(func(f):return clock_time-f.start<0.95 and p.power_slots.any(func(s):return int(s.slot_id)==int(f.slot_id) and int(s.epoch)==int(f.epoch) and s.active_power_id==host.game.R133.TICKETS))
	queue_redraw()
func _draw():
	for f in flights:
		var age=clock_time-f.start
		if age<0:continue
		var t=clampf(age/0.42,0,1);var pos=f.from.lerp(f.to,t)+Vector2(0,-90*sin(t*PI))
		if t<1:
			var icon=texture("ui:r133_ticket_badge:texture:normal:neutral")
			if icon:draw_texture_rect(icon,Rect2(pos-Vector2(14,14),Vector2(28,28)),false)
			var particle=texture("ui:r133_collect_spark:texture:normal:neutral")
			if particle:draw_texture_rect(particle,Rect2(pos-Vector2(23,23),Vector2(46,46)),false,Color(1,1,1,0.65))
		elif f.completed:
			var opacity=clampf(1-(age-0.42)/0.53,0,1)
			var ring=texture("ui:r133_collect_ring:texture:normal:neutral")
			var extent=Vector2.ONE*(42+40*(age-0.42))
			if ring:draw_texture_rect(ring,Rect2(f.to-extent/2,extent),false,Color(1,1,1,opacity))
			draw_string(get_theme_default_font(),f.to+Vector2(-28,-16),ExternalText.phrase("ui_round133_presentation._draw.652d1fc1e00c", "说明待补充"),HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color(1,0.9,0.5,opacity))
static func stamp(table,key: String,area: Rect2,depth=0):
	var icon=TextureRect.new();icon.texture=table.host.texture_for_path(table.host.registry.art_path_for_key(key));icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;icon.stretch_mode=TextureRect.STRETCH_SCALE;icon.mouse_filter=Control.MOUSE_FILTER_IGNORE;icon.z_index=depth;table.place(icon,area);return icon
static func build(table):
	var h=table.host;var p=h.game.state.players[0]
	for s in p.power_slots:
		var slot_area=table.power_areas.get(int(s.slot_id),table.area(table.Layout.power(0,1)))
		var rail_area=Rect2(slot_area.position+Vector2(0,82),Vector2(slot_area.size.x,22))
		if s.active_power_id==h.game.R133.TICKETS:
			var bar=table.slab(rail_area,Color("322519"),Color("e9b94f"),5)
			bar.name="TicketProgress"+str(s.slot_id);bar.mouse_filter=Control.MOUSE_FILTER_IGNORE;bar.z_index=25
			stamp(table,"ui:r133_progress_track:texture:normal:neutral",rail_area,26)
			var progress=table.text(ExternalText.phrase("ui_round133_presentation.build.9442cf93a0ad", "说明待补充 · %d") % int(s.progress.get("tickets",0)),rail_area,15,Color("ffdf87"));progress.name="TicketProgressText"+str(s.slot_id)
			progress.z_index=27
		if s.active_power_id==h.game.R133.FLIGHT:
			var f=s.progress.get("flight",{});var value=ExternalText.phrase("ui_round133_presentation.build.e713985bdc5a", "说明待补充") if f.is_empty() else h.registry.get_def(f.id).name+ExternalText.phrase("ui_round133_presentation.build.84ebdaab7a7d", "说明待补充 · %d") % int(f.remaining)
			stamp(table,"ui:r133_route_frame:texture:normal:neutral",rail_area,26)
			var state=table.text(value,rail_area,14,Color("e5d1a3"));state.name="FlightStatus"
			state.z_index=27
	var secrets=p.get("secrets",[]).map(func(s):return s.id)
	if p.get("iceblock",false):secrets.append("TB_Bacon_Secrets_12")
	if not secrets.is_empty():
		table.text(ExternalText.phrase("ui_round133_presentation.build.b44c0a50b7f1", "说明待补充"),table.rect(8,744,110,18),14)
		for i in secrets.size():
			var id=secrets[i];var art=h.registry.art_path(id)
			stamp(table,"ui:r133_secret_mount:texture:normal:neutral",table.rect(8+(i%3)*36,766+int(i/3)*34,32,30))
			var icon=TextureRect.new();icon.texture=h.texture_for_path(art);icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.mouse_filter=Control.MOUSE_FILTER_PASS;icon.tooltip_text=h.registry.get_def(id).name+"\n"+str(h.registry.get_def(id).get("text",""));table.place(icon,table.rect(8+(i%3)*36,766+int(i/3)*34,32,30));icon.name="MountedSecret"+str(i)
	var anomalies=p.get("r133_anomalies",{})
	if anomalies.is_empty():return
	if anomalies.values().all(func(a):return a.closed):
		table.action(ExternalText.phrase("ui_round133_presentation.build.5fa191008131", "说明待补充"),table.rect(1230,196,164,34),func():h.command("reward_anomaly",{"closed":false}),"RewardAnomalyExpand")
	else:
		var panel=table.slab(table.rect(1218,190,180,102),Color("573d18"),Color("efb34b"),8);panel.mouse_filter=Control.MOUSE_FILTER_IGNORE;panel.name="RewardAnomalyPanel"
		var title=table.text(ExternalText.phrase("ui_round133_presentation.build.29be7825b906", "说明待补充"),table.rect(1228,193,132,19),15,Color("ffe0a0"));title.name="RewardAnomalyTitle"
		var body=h.label(ExternalText.phrase("round133_presentation.9e05ae5e1bc2", "说明待补充"),15,Color("fff0d2"));body.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;body.mouse_filter=Control.MOUSE_FILTER_IGNORE;table.place(body,table.rect(1228,214,160,76));body.name="RewardAnomalyBody"
		stamp(table,"ui:r133_exception_mark:texture:normal:neutral",table.rect(1341,194,17,17))
		var close=table.action("×",table.rect(1360,192,30,23),func():h.command("reward_anomaly",{"closed":true}),"RewardAnomalyClose")
		for style in ["normal","hover","pressed","focus"]:
			var flat=StyleBoxFlat.new();flat.bg_color=Color("573d18");close.add_theme_stylebox_override(style,flat)
		close.custom_minimum_size=Vector2.ZERO
		close.size=Vector2(30,23)
static func choice(h,choice: Dictionary):
	var v=h.modal(ExternalText.phrase("ui_round133_presentation.choice.05cc9d570f90", "说明待补充") if choice.kind=="r133_route" else ExternalText.phrase("ui_round133_presentation.choice.21470c53da65", "说明待补充"))
	var overlay=h.get_node("ChoiceOverlay");var p=h.game.state.players[0]
	for i in choice.options.size():
		var d=h.registry.get_def(choice.options[i].def_id);var row=HBoxContainer.new();row.custom_minimum_size=Vector2(680,96);v.add_child(row)
		var image=TextureRect.new();image.texture=h.texture_for_path(h.registry.art_path(d.id));image.custom_minimum_size=Vector2(130,96);image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;image.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;image.mouse_filter=Control.MOUSE_FILTER_IGNORE;row.add_child(image)
		var error=h.game.R133.option_error(h.game,p,choice,i)
		var select=h.button(d.name,func():h.choose_visible(choice,i,overlay),"R133Option"+str(i));select.custom_minimum_size=Vector2(148,96);select.disabled=error!="";row.add_child(select)
		var details=h.label(str(d.get("text",""))+(ExternalText.phrase("ui_round133_presentation.choice.f82ebcdc81e6", "\n说明待补充") if error=="SECRET_ALREADY_MOUNTED" else ExternalText.phrase("round133_presentation.316474af8e2b", "说明待补充") if error=="SAME_FLIGHT_ROUTE" else ""),16);details.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;details.custom_minimum_size=Vector2(380,96);row.add_child(details)
