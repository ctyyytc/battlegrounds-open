extends RefCounted
const ExternalText = preload("res://domain/resources/external_content.gd")

static func reward(registry,q: Dictionary) -> String:
	match str(q.reward_id):
		"BG27_Reward_812":return ExternalText.phrase("round136_presentation.d35982dc9b64", "说明待补充 · %s") % str(q.get("bound",ExternalText.phrase("ui_round136_presentation.reward.293f501a8739", "说明待补充")))
		"BG28_Reward_509":return ExternalText.phrase("round136_presentation.a246b84e5129", "说明待补充 · %d") % int(q.get("reward_state",{}).get("smelting_level",1))
		"BG33_Reward_020":return ExternalText.phrase("round136_presentation.b18fe9f20e16", "说明待补充")
	return ""
static func summary(engine,q: Dictionary) -> String:
	var r=q.reward_state
	match str(q.reward_id):
		"BG24_Reward_363":return " · "+str(engine.content.get_def(q.get("child",{}).get("reward_id","")).get("name",ExternalText.phrase("ui_round136_presentation.summary.e4224a8dcf2b", "说明待补充")))
		"BG28_Reward_509":return ExternalText.phrase("ui_round136_presentation.summary.eefc4b8edc74", "说明待补充 · %d") % int(r.get("smelting_level",1))
		"BG33_Reward_020":return ExternalText.phrase("ui_round136_presentation.summary.c96764a70de8", "说明待补充 · %d / %d / %d / %d / %d") % [int(q.progress),int(q.threshold),int(r.get("completed_cycles",0)),int(r.get("cumulative_attack",0)),int(r.get("cumulative_health",0))]
	return ""
static func description(engine,p: Dictionary,q: Dictionary) -> String:
	var text="";var r=q.reward_state
	if q.reward_id=="BG24_Reward_363":
		if q.has("child"):
			var c=q.child
			text+=ExternalText.phrase("ui_round136_presentation.description.6e51d293d110", "\n说明待补充")+str(engine.content.get_def(c.reward_id).name)+"\n"+preload("res://ui/round135_presentation.gd").reward(engine.content,c)
			text+=ExternalText.phrase("round136_presentation.47e79986fbbc", "说明待补充")
			if c.reward_state.has("teaching_due"):text+=ExternalText.phrase("round136_presentation.0d35c89656b1", "说明待补充")
		if r.get("phase","")=="select":text+=ExternalText.phrase("round136_presentation.850ef5b3408c", "说明待补充")
		if r.has("diagnostic"):text+=ExternalText.phrase("round136_presentation.cbdb70e1484a", "说明待补充")
	if q.reward_id=="BG33_Reward_011" and r.has("teaching_due"):text+=ExternalText.phrase("round136_presentation.e92f8d927dc5", "说明待补充")
	if q.reward_id in ["BG33_Reward_014","BG33_Reward_015"]:
		var op=p.get("r136_slots",{}).get("opportunities",{}).get(r.get("opportunity",""),{})
		if not op.is_empty():
			text+=ExternalText.phrase("ui_round136_presentation.description.87d55bdb191e", "\n说明待补充")+("A" if int(q.slot_id)==0 else "B")+" · "+(ExternalText.phrase("ui_round136_presentation.description.d9f28f91cc59", "说明待补充") if op.coins_receipt else ExternalText.phrase("round136_presentation.2efc7bc05cd3", "说明待补充"))
			text+="\n"+(ExternalText.phrase("ui_round136_presentation.description.fb17a31001aa", "说明待补充") if op.purchased else ExternalText.phrase("ui_round136_presentation.description.341d66ef068b", "说明待补充") if op.cancelled else ExternalText.phrase("ui_round136_presentation.description.1287deeb6109", "说明待补充") if int(engine.state.round)>=int(op.unlock_round) else ExternalText.phrase("ui_round136_presentation.description.5a1886c04742", "说明待补充 · %d") % int(op.unlock_round))
	return text
static func session_status(engine,p: Dictionary,s: Dictionary) -> String:
	var local_limit=2 if s.get("base_size","")=="greater" else 1
	var text=ExternalText.phrase("round136_presentation.abf5f0ff146b", "说明待补充 · %d / %d / %d / %d") % [int(p.coins),int(s.refreshes),local_limit,int(p.trinket_refreshes)]
	if int(p.trinket_refreshes)<3:text+=ExternalText.phrase("ui_round136_presentation.session_status.1427a663fe7b", "说明待补充 · %d") % (2+int(p.trinket_refreshes))
	var o=s.get("power_owner",{})
	if not o.is_empty():text+=ExternalText.phrase("ui_round136_presentation.session_status.87d55bdb191e", "\n说明待补充")+("A" if int(o.slot_id)==0 else "B")
	if s.get("offered_size","")!=s.get("base_size",""):text+=ExternalText.phrase("round136_presentation.5ea9fb1cbdc7", "说明待补充")
	var op=p.get("r136_slots",{}).get("opportunities",{}).get(s.get("kind",""),{})
	if op.get("coins_due",false):text+="\n"+(ExternalText.phrase("round136_presentation.0d2679fc2121", "说明待补充") if op.coins_receipt else ExternalText.phrase("ui_round136_presentation.session_status.8ff01df5152a", "说明待补充"))
	return text
static func evidence_choice(host,c: Dictionary) -> void:
	var v=host.modal(ExternalText.phrase("round136_presentation.28cdc73b0df9", "说明待补充"))
	v.add_child(host.label(ExternalText.phrase("round136_presentation.f6735d8e2cee", "说明待补充"),18,host.GOLD))
	var row=HBoxContainer.new();row.add_theme_constant_override("separation",20);v.add_child(row)
	var overlay=host.get_node("ChoiceOverlay")
	for i in c.options.size():
		var o=c.options[i];var column=VBoxContainer.new();column.custom_minimum_size=Vector2(360,0);row.add_child(column)
		column.add_child(host.image_for(o.reward_id,Vector2(192,142)))
		column.add_child(host.label(str(host.registry.get_def(o.reward_id).name),23,host.GOLD))
		var scroll=ScrollContainer.new();scroll.custom_minimum_size=Vector2(360,260);column.add_child(scroll)
		var body=host.label(preload("res://ui/round135_presentation.gd").reward(host.registry,o),20);body.custom_minimum_size.x=338;body.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;scroll.add_child(body)
		column.add_child(host.button(ExternalText.phrase("ui_round136_presentation.evidence_choice.494102092f78", "说明待补充"),func():host.choose_visible(c,i,overlay),"EvidenceOption"+str(i)))
static func teaching_choice(host,c: Dictionary) -> void:
	var v=host.modal(ExternalText.phrase("round136_presentation.34871176b2b7", "说明待补充"))
	v.add_child(host.label(ExternalText.phrase("round136_presentation.9da1dcd04e4c", "说明待补充"),18,host.GOLD))
	var row=HBoxContainer.new();row.add_theme_constant_override("separation",16);v.add_child(row)
	var overlay=host.get_node("ChoiceOverlay")
	for i in c.options.size():
		var d=host.registry.get_def(c.options[i].def_id);var column=VBoxContainer.new();column.custom_minimum_size=Vector2(250,0);row.add_child(column)
		column.add_child(host.image_for(d.id,Vector2(174,102)))
		var title=host.label(d.name,22,host.GOLD);title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;column.add_child(title)
		var scroll=ScrollContainer.new();scroll.custom_minimum_size=Vector2(250,250);column.add_child(scroll)
		var body=host.label(preload("res://ui/spell_presentation.gd").body(d,{}),20);body.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;body.custom_minimum_size.x=228;scroll.add_child(body)
		var select=host.button(ExternalText.phrase("ui_round136_presentation.teaching_choice.845c4fe19b37", "说明待补充"),func():host.choose_visible(c,i,overlay),"TeachingOption"+str(i));select.custom_minimum_size.y=44;column.add_child(select)
