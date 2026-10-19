extends RefCounted
const ExternalText = preload("res://domain/resources/external_content.gd")
static func font_size(host,normal: int,compact: int) -> int:
	var ratio=minf(1.0,float(host.get_window().size.x)/host.get_viewport_rect().size.x)
	return normal if ratio>=0.94 else ceili(float(compact)/maxf(0.5,ratio))
static func feedback(host,events: Array) -> void:
	for event in events:
		if event.kind!="QuestCompleted" or int(event.owner)!=0:continue
		var notice=host.label(ExternalText.phrase("round135_presentation.3df8c5eec087", "说明待补充"),20,host.GOLD);notice.name="QuestCompletionFeedback";notice.mouse_filter=Control.MOUSE_FILTER_IGNORE;notice.position=Vector2(1038,610);notice.z_index=85;host.add_child(notice)
		var tween=host.create_tween();tween.tween_property(notice,"modulate:a",0.0,0.9);tween.finished.connect(notice.queue_free)
static func _computed_condition(registry,o: Dictionary) -> String:
	var n=int(o.threshold)
	match str(o.quest_id):
		"BG24_Quest_114":return ExternalText.phrase("ui_round135_presentation.condition.042e2afeda0a", "说明待补充 · %d") % n
		"BG24_Quest_123":return ExternalText.phrase("round135_presentation.7f24453261eb", "说明待补充 · %d") % n
		"BG24_Quest_124":return ExternalText.phrase("ui_round135_presentation.condition.6ffa9159c7a9", "说明待补充 · %d") % n
		"BG24_Quest_126":return ExternalText.phrase("ui_round135_presentation.condition.37f93974ef6b", "说明待补充 · %d") % n
		"BG24_Quest_151":return ExternalText.phrase("ui_round135_presentation.condition.06bfc33313fd", "说明待补充 · %d / %s / %s") % [n,o.bound_tribes[0],o.bound_tribes[1]]
		"BG24_Quest_311":return ExternalText.phrase("ui_round135_presentation.condition.782e3fa34e32", "说明待补充 · %d") % n
		"BG24_Quest_313":return ExternalText.phrase("ui_round135_presentation.condition.544d56433c6c", "说明待补充 · %d") % n
		"BG24_Quest_314":return ExternalText.phrase("ui_round135_presentation.condition.523fd7378808", "说明待补充 · %d") % n
		"BG24_Quest_352":return ExternalText.phrase("ui_round135_presentation.condition.23a3f666e84b", "说明待补充 · %d") % n
		"BG27_Quest_801":return ExternalText.phrase("round135_presentation.2d80ce1bea90", "说明待补充 · %d") % n
		"BG27_Quest_802":return ExternalText.phrase("round135_presentation.a0ffc4ecd1d8", "说明待补充 · %d") % n
		"BG28_Quest_500":return ExternalText.phrase("ui_round135_presentation.condition.d8740a9e261f", "说明待补充 · %d") % n
	return ""
static func _computed_reward(registry,q: Dictionary) -> String:
	var external=registry.get_def(str(q.reward_id))

	var extra=preload("res://ui/round136_presentation.gd").reward(registry,q)
	if extra!="":return extra
	var id=str(q.reward_id);var state=q.get("reward_state",{})
	var name=str(registry.get_def(str(q.get("bound",""))).get("name",""))
	match id:
		"BG24_Reward_130":return ExternalText.phrase("round135_presentation.4645b4411fbd", "说明待补充 · %s") % name
		"BG27_Reward_802":return ExternalText.phrase("round135_presentation.c21081bb3fe2", "说明待补充 · %s") % name
		"BG27_Reward_803":return ExternalText.phrase("round135_presentation.b1f61c6eeec3", "说明待补充 · %s") % name
		"BG28_Reward_510":return ExternalText.phrase("round135_presentation.6d7fdcd90b69", "说明待补充 · %s") % name
		"BG24_Reward_134":return ExternalText.phrase("round135_presentation.a15c4f419824", "说明待补充 · %s") % q.bound
		"BG24_Reward_306":return ExternalText.phrase("round135_presentation.2d09e6a6f535", "说明待补充 · %d / %d") % [int(state.get("next_buff",2)),int(state.get("next_buff",2))]
		"BG24_Reward_361":return ExternalText.phrase("round135_presentation.7ee1232a76b1", "说明待补充 · %d") % int(state.get("next_coins",1))
		"BG24_Reward_715":return ExternalText.phrase("round135_presentation.280ece55dc87", "说明待补充")
		"BG28_Reward_502":return ExternalText.phrase("round135_presentation.6b4466b48ddf", "说明待补充")
		"BG24_Reward_111":return ExternalText.phrase("round135_presentation.e6a6ec3bb59d", "说明待补充")
		"BG24_Reward_138":return ExternalText.phrase("round135_presentation.6f4358e08d23", "说明待补充")
	return str(registry.get_def(id).get("text",""))
static func summary(engine,p: Dictionary,slot_id: int) -> String:
	var q=p.get("r135",{}).get("slots",{}).get(str(slot_id),{})
	if q.is_empty():return ExternalText.phrase("ui_round135_presentation.summary.ba3cf6d86081", "说明待补充")
	if q.status=="offered":return ExternalText.phrase("ui_round135_presentation.summary.4fa8a06f5464", "说明待补充")
	if q.status=="reward_active":
		var suffix=""
		if q.reward_id=="BG24_Reward_306":suffix=ExternalText.phrase("ui_round135_presentation.summary.b83964524492", "说明待补充 · %d / %d") % [int(q.reward_state.next_buff),int(q.reward_state.next_buff)]
		if q.reward_id=="BG24_Reward_361":suffix=ExternalText.phrase("ui_round135_presentation.summary.1427a663fe7b", "说明待补充 · %d") % int(q.reward_state.next_coins)
		suffix+=preload("res://ui/round136_presentation.gd").summary(engine,q)
		return str(engine.content.get_def(q.reward_id).name)+suffix
	return "%s %d/%d" % [engine.content.get_def(q.quest_id).name,int(q.progress),int(q.threshold)]
static func description(engine,p: Dictionary,slot_id: int) -> String:
	var q=p.get("r135",{}).get("slots",{}).get(str(slot_id),{})
	if q.is_empty() or q.status=="offered":return ExternalText.phrase("round135_presentation.9f284f66315a", "说明待补充")
	var result=summary(engine,p,slot_id)+"\n"+condition(engine.content,q)+ExternalText.phrase("ui_round135_presentation.description.63b47aadd569", "\n说明待补充")+str(engine.content.get_def(q.reward_id).name)+"\n"+reward(engine.content,q)
	result+=preload("res://ui/round136_presentation.gd").description(engine,p,q)
	if q.status=="completion_pending":result+=ExternalText.phrase("round135_presentation.e700780cc7a6", "说明待补充")
	var waiting=p.pending_rewards.filter(func(c):return c.get("acquisition_source",{}).get("quest_instance","")==q.instance).size()
	if waiting>0:result+=ExternalText.phrase("round135_presentation.ab9e5e50c6cf", "说明待补充")
	if not q.reward_state.get("unresolved",{}).is_empty():result+=ExternalText.phrase("round135_presentation.81701b2d6fd9", "说明待补充")
	return result
static func choice(host,c: Dictionary) -> void:
	var v=host.modal(ExternalText.phrase("round135_presentation.1d216f7840eb", "说明待补充"))
	var viewport=host.get_viewport_rect().size
	var width=minf(920,viewport.x-100);v.custom_minimum_size=Vector2(width,0)
	var row=HBoxContainer.new();row.add_theme_constant_override("separation",20);v.add_child(row)
	var overlay=host.get_node("ChoiceOverlay")
	for i in c.options.size():
		var o=c.options[i];var column=VBoxContainer.new();column.custom_minimum_size.x=(width-28)/2;row.add_child(column)
		var scroll=ScrollContainer.new();scroll.custom_minimum_size=Vector2((width-28)/2,minf(460,viewport.y-250));column.add_child(scroll)
		var body=VBoxContainer.new();body.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(body)
		var title=host.label(str(host.registry.get_def(o.quest_id).name),font_size(host,24,22),host.GOLD);body.add_child(title)
		var text=host.label(condition(host.registry,o),font_size(host,20,17));text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;body.add_child(text)
		var heading=host.label(ExternalText.phrase("ui_round135_presentation.choice.71d49bd8faaf", "说明待补充")+str(host.registry.get_def(o.reward_id).name),font_size(host,22,20),host.GOLD);heading.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;body.add_child(heading)
		var art=host.registry.art_path(o.reward_id)
		if art!="":body.add_child(host.image_for(o.reward_id,Vector2(174,102)))
		var details=host.label(reward(host.registry,o),font_size(host,19,17));details.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;body.add_child(details)
		var bound_def=host.registry.get_def(str(o.get("bound","")))
		if bound_def.get("kind","")=="minion":
			body.add_child(host.image_for(bound_def.id,Vector2(174,102)))
			var bound_text=host.label(ExternalText.phrase("ui_round135_presentation.choice.2c169b7c7ded", "说明待补充 · %s / %d / %s") % [bound_def.name,int(bound_def.tier)," / ".join(ExternalText.terms_list(bound_def.get("card_types",[]))) if not bound_def.get("card_types",[]).is_empty() else ExternalText.phrase("ui_round135_presentation.choice.a193d8fabee9", "说明待补充")],font_size(host,18,17));bound_text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;body.add_child(bound_text)
		var select=host.button(ExternalText.phrase("ui_round135_presentation.choice.14b6595cd7e9", "说明待补充"),func():host.choose_visible(c,i,overlay),"QuestOption"+str(i));select.add_theme_font_size_override("font_size",font_size(host,18,17));select.custom_minimum_size.y=60 if font_size(host,19,17)>19 else 50;column.add_child(select)
static func build(table) -> void:
	var host=table.host;var p=host.game.state.players[0]
	var quest_slots=p.power_slots.filter(func(s):return s.active_power_id==host.game.R135.POWER)
	if p.pending_rewards.any(func(c):return c.get("acquisition_source",{}).get("origin_kind","")=="quest_reward") and is_instance_valid(host.toast):host.toast.text=ExternalText.phrase("round135_presentation.ce2c89f5b566", "说明待补充")
	for s in p.power_slots:
		if s.active_power_id!=host.game.R135.POWER:continue
		var detail=description(host.game,p,int(s.slot_id));var text=summary(host.game,p,int(s.slot_id))
		var q=p.get("r135",{}).get("slots",{}).get(str(s.slot_id),{})
		if q.is_empty():continue
		var power_area=table.power_areas.get(int(s.slot_id),table.area(table.Layout.power(p.power_slots.find(s),p.power_slots.size())))
		var area=Rect2(power_area.position+Vector2(0,82),Vector2(power_area.size.x,22))
		table.quest_areas.append({"area":area,"slot_id":int(s.slot_id)})
		var bar=table.slab(area,host.BTheme.PANEL,host.GOLD,5);bar.name="QuestProgress";bar.z_index=25
		var label=table.text(text,area.grow(-2),14,host.BTheme.TEXT);label.name="QuestProgressText";label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;label.z_index=26

	var removed=p.get("r135",{}).get("removed",[])
	if not removed.is_empty() and quest_slots.is_empty():
		var waiting=p.pending_rewards.filter(func(c):return c.get("acquisition_source",{}).get("origin_kind","")=="quest_reward").size()
		var text=ExternalText.phrase("round135_presentation.f3287735296c", "说明待补充")
		var notice=table.text(text,table.rect(856,636,200,22),16,Color("b8ad98"));notice.name="QuestLostStatus";notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART

static func condition(registry,o: Dictionary) -> String:
	return ExternalText.describe(registry.get_def(str(o.quest_id)), o, {}, _computed_condition(registry,o), "condition", {"threshold":int(o.threshold),"progress":int(o.get("progress",0)),"remaining":maxi(0,int(o.threshold)-int(o.get("progress",0)))})

static func reward(registry,q: Dictionary) -> String:
	return ExternalText.describe(registry.get_def(str(q.reward_id)), q.get("reward_state",{}), {}, _computed_reward(registry,q), "body", {})
