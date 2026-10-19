extends Control
const ExternalText = preload("res://domain/resources/external_content.gd")

var host
var task: Dictionary={}
var title: Label
var body: Label
var details: RichTextLabel
var disk: TextureRect
var selected: TextureRect
var skip: Button
var reduced: CheckButton
var visuals: Dictionary
func tex(key: String) -> Texture2D:
	return host.texture_for_path(host.registry.art_path_for_key(key))
func _ready() -> void:
	name="Round134Wheel";z_index=68;mouse_filter=Control.MOUSE_FILTER_IGNORE
	position=Vector2((host.size.x-850)*0.5,48);size=Vector2(850,650)
	visuals=JSON.parse_string(FileAccess.get_file_as_string("res://content/packs/round134_visuals.json"))
	for result in visuals.results:
		var d=host.registry.get_def(result.id)
		result.name=str(d.get("name",result.id)); result.effect=str(d.get("text","说明待补充"))
	var panel=Panel.new();panel.size=size;panel.mouse_filter=Control.MOUSE_FILTER_IGNORE;panel.add_theme_stylebox_override("panel",host.BTheme.style());add_child(panel)
	title=host.label(ExternalText.phrase("ui_round134_wheel._ready.e82086847d77", "说明待补充"),24,Color("ffe09b"));title.position=Vector2(20,12);title.size=Vector2(450,34);add_child(title)
	disk=TextureRect.new();disk.texture=tex("ui:r134_wheel_disk:texture:normal:neutral");disk.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;disk.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;disk.position=Vector2(145,55);disk.size=Vector2(300,300);disk.pivot_offset=disk.size/2;disk.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(disk)
	disk.position=Vector2(40,65)
	selected=TextureRect.new();selected.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;selected.size=disk.size;selected.mouse_filter=Control.MOUSE_FILTER_IGNORE;disk.add_child(selected)
	var hub=TextureRect.new();hub.texture=tex("ui:r134_wheel_hub:texture:normal:neutral");hub.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;hub.size=Vector2(62,62);hub.position=Vector2(119,119);hub.mouse_filter=Control.MOUSE_FILTER_IGNORE;disk.add_child(hub)
	var pointer=TextureRect.new();pointer.texture=tex("ui:r134_wheel_pointer:texture:normal:neutral");pointer.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;pointer.position=Vector2(271,41);pointer.size=Vector2(48,66);pointer.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(pointer)
	pointer.position=Vector2(166,50)
	for i in visuals.results.size():
		var result=visuals.results[i]
		var icon=TextureRect.new();icon.texture=tex(result.asset_key);icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;icon.mouse_filter=Control.MOUSE_FILTER_IGNORE
		if icon.texture:
			icon.size=icon.texture.get_size();var factor=minf(55.0/icon.size.x,44.0/icon.size.y);icon.scale=Vector2.ONE*factor;icon.position=Vector2(365,58+i*51+(44-icon.size.y*factor)/2)
		add_child(icon)
		var legend=host.rich_label(result.name+" · %d%%\n" % int(result.weight)+result.effect,13,Color("e7dcb9"));legend.fit_content=false;legend.scroll_active=false;legend.position=Vector2(428,58+i*51);legend.size=Vector2(402,49);legend.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;legend.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(legend)
	body=host.label("",20,Color("fff0c8"));body.position=Vector2(20,380);body.size=Vector2(810,82);body.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;body.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(body)
	details=host.rich_label("",16,Color("d9d4eb"));details.fit_content=false;details.scroll_active=true;details.bbcode_enabled=false;details.position=Vector2(20,470);details.size=Vector2(810,100);details.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;details.mouse_filter=Control.MOUSE_FILTER_PASS;add_child(details)
	skip=host.button(ExternalText.phrase("ui_round134_wheel._ready.83b207df60fb", "说明待补充"),func():if not task.is_empty():host.command("wheel_skip",{"receipt":task.receipt}),"WheelSkip");skip.position=Vector2(20,560);skip.size=Vector2(190,36);add_child(skip)
	var close=host.button(ExternalText.phrase("ui_round134_wheel._ready.47869f3c3571", "说明待补充"),func():if not task.is_empty():task.read=true;visible=false,"WheelClose");close.position=Vector2(450,560);close.size=Vector2(120,36);add_child(close)
	close.position=Vector2(710,600);skip.position.y=600
	reduced=CheckButton.new();reduced.text=ExternalText.phrase("ui_round134_wheel._ready.6562592434ee", "说明待补充");reduced.position=Vector2(185,560);reduced.size=Vector2(220,36);reduced.button_pressed=bool(host.game.state.get("r134_reduced_motion",false));reduced.toggled.connect(func(value):if not host.ui_blocked():host.set_reduced_motion(value));add_child(reduced)
	reduced.position.y=600
	reduced.position.x=225
	refresh_task()
func refresh_task() -> void:
	if host.game==null or not host.in_match:visible=false;return
	var p=host.game.state.players[0];task={}
	if not p.choices.is_empty():visible=false;return
	task=host.game.R134.presenting(p)
	if task.is_empty():
		for t in p.get("r134",{}).get("wheel",[]):
			if not t.get("read",false):task=t;break
	visible=not task.is_empty() and not task.get("read",false)
func _process(delta: float) -> void:
	refresh_task()
	reduced.set_pressed_no_signal(host.reduced_motion_enabled)
	if task.is_empty():return
	var elapsed=float(task.ui_elapsed)
	var result=visuals.results.filter(func(v):return v.id==task.result_id)[0]
	var t=clampf(elapsed/4.0,0,1);var eased=1-pow(1-t,3)
	disk.rotation_degrees=(1440.0-90.0-float(result.center_deg))*eased
	selected.texture=tex("ui:r134_selected_"+str(result.id).trim_prefix(host.game.R134.WHEEL)+":texture:normal:neutral");selected.visible=elapsed>=4
	title.text=ExternalText.phrase("ui_round134_wheel._process.cb933cc59399", "说明待补充")+(ExternalText.phrase("ui_round134_wheel._process.70a2aa04960e", "说明待补充") if elapsed<4 else result.name)
	body.text=ExternalText.phrase("round134_wheel.3a19b2c87e11", "说明待补充") if elapsed<4 else result.name+"\n"+result.effect
	details.text=ExternalText.phrase("round134_wheel.c166a1bfe8c2", "说明待补充") if elapsed<4.45 else feedback(result,elapsed)
	skip.text=ExternalText.phrase("ui_round134_wheel._process.2347146851d6", "说明待补充") if host.game.state.paused and task.phase!="done" else ExternalText.phrase("ui_round134_wheel._process.7e5b70c14a87", "说明待补充") if task.get("skip_requested",false) and task.phase!="done" else ExternalText.phrase("ui_round134_wheel._process.83b207df60fb", "说明待补充") if elapsed<6.2 else ExternalText.phrase("ui_round134_wheel._process.a7a41f68a3d8", "说明待补充")
	task.ui_phase="spin" if elapsed<4 else "selected" if elapsed<4.45 else "feedback"
func feedback(result: Dictionary,elapsed: float) -> String:
	var lines=[];var shown=task.steps.size() if elapsed>=6.2 else mini(task.steps.size(),maxi(1,int((elapsed-4.45)/0.4)+1))
	for i in range(shown):
		var f=task.steps[i];var text=""
		if f.has("prize_id"):text=ExternalText.phrase("ui_round134_wheel.feedback.a7647824a68d", "说明待补充")+host.registry.get_def(f.prize_id).name
		elif f.has("stop"):text=ExternalText.phrase("ui_round134_wheel.feedback.bf61c604fd6c", "说明待补充")+(ExternalText.phrase("ui_round134_wheel.feedback.e2c1ca02fafe", "说明待补充") if f.stop=="hero" else ExternalText.phrase("ui_round134_wheel.feedback.13440ea33375", "说明待补充"))+ExternalText.phrase("ui_round134_wheel.feedback.db1d475801e8", "说明待补充")
		elif f.has("cast"):
			var spells=[]
			for spell in f.get("spells",[]):spells.append(str(spell.name)+( " → "+str(spell.target.name) if spell.target.has("name") else ""))
			text="、".join(spells) if not spells.is_empty() else ExternalText.phrase("round134_wheel.6903311ccbf9", "说明待补充")
		elif not f.targets.is_empty():
			var names=f.get("target_names",[]).duplicate()
			for target in f.targets:
				var iid=int(target.get("to",-1)) if target is Dictionary else int(target)
				var c=host.game.find_target(host.game.state.players[0],iid)
				if names.is_empty() and not c.is_empty():names.append(host.registry.get_def(c.def_id).name)
			text="、".join(names)+(" +%d/+%d" % [int(f.attack),int(f.health)] if f.has("attack") else ExternalText.phrase("ui_round134_wheel.feedback.5c3059a331a1", "说明待补充"))
		else:text=ExternalText.phrase("ui_round134_wheel.feedback.fd3844aa0bd6", "说明待补充") if result.id.ends_with("t5") else ExternalText.phrase("ui_round134_wheel.feedback.bc458cd26158", "说明待补充")
		lines.append(ExternalText.phrase("ui_round134_wheel.feedback.c4ec0058ea7a", "说明待补充 · %d / %s") % [i+1,text])
	if task.phase!="done":lines.append(ExternalText.phrase("ui_round134_wheel.feedback.586644adfbad", "说明待补充"))
	return "\n".join(lines)
static func build(table) -> void:
	var h=table.host;var p=h.game.state.players[0]
	for s in p.power_slots:
		if s.active_power_id==h.game.R134.POWER:
			var n=int(h.game.state.round);var rail=table.text(ExternalText.phrase("ui_round134_wheel.build.320eae254511", "说明待补充 · %d / %d") % [h.game.R134.tier(n),4-n%4],Rect2(table.power_areas.get(int(s.slot_id),table.area(table.Layout.power(0,1))).position+Vector2(0,82),Vector2(210,22)),14,Color("ffe19b"));rail.name="PrizeProgress"+str(s.slot_id);rail.z_index=28
	if not p.get("r134",{}).get("wheel",[]).is_empty():
		table.action(ExternalText.phrase("ui_round134_wheel.build.b2ca34beaad2", "说明待补充"),table.rect(878,0,172,44),func():
			var history=p.r134.wheel
			history[-1].read=false
		,"WheelHistory")
