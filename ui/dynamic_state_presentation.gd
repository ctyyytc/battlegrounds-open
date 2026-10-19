extends RefCounted
const ExternalText = preload("res://domain/resources/external_content.gd")

static func remaining(limit: int,progress: int) -> int:
	return maxi(0,limit-progress)
static func replace_remaining(text: String,n: int) -> String:
	return text+"\n"+ExternalText.named("status.remaining",{"remaining":n},str(n))
static func minion_body(d: Dictionary,c: Dictionary) -> String:
	var text=str(d.get("text",""))
	for e in d.get("effects",[]):
		if e.get("op","")=="spend_wind":text=replace_remaining(text,remaining(7,int(c.get("spend_progress",0))))
		if e.get("op","")=="thunder":text=replace_remaining(text,remaining(3,int(c.get("thunder_progress",0))))
	return text
static func _computed_trinket_body(d: Dictionary,item: Dictionary,p: Dictionary,round_number: int) -> String:

	if d.effects.any(func(e):return e.get("handler","")=="round13_item"):return preload("res://ui/round13_presentation.gd").item(d,item,p,round_number)
	if d.effects.any(func(e):return e.get("handler","")=="round12"):return preload("res://ui/beast_presentation.gd").item(d,item,p)
	if d.effects.any(func(e):return e.get("handler","")=="round10"):return preload("res://ui/demon_presentation.gd").body(d,item,p,round_number)
	if d.effects.any(func(e):return e.get("handler","")=="round7"):return preload("res://ui/naga_presentation.gd").item(d,item,p,round_number)
	var text=str(d.get("text",""))
	var states=[]
	for e in d.get("effects",[]):
		match str(e.get("op",e.get("handler",""))):
			"progress":text=replace_remaining(text,remaining(int(e.threshold),int(item.get("progress",0))))
			"waterwheel":
				var used=int(item.get("water_uses",0)) if int(item.get("water_round",0))==round_number else 0
				text=replace_remaining(text,remaining(2,used));states.append(ExternalText.phrase("ui_dynamic_state_presentation.trinket_body.2e8a4f0f1def", "说明待补充 · %d") % remaining(2,used))
			"bound_gold":states.append(ExternalText.phrase("ui_dynamic_state_presentation.trinket_body.694c087be978", "说明待补充") if item.get("gold_used",false) else ExternalText.phrase("ui_dynamic_state_presentation.trinket_body.b19c1277a132", "说明待补充"))
			"heart":text=replace_remaining(text,remaining(int(e.threshold),int(item.get("death_progress",0))))
			"summon_shield","reborn_copy":states.append(ExternalText.phrase("ui_dynamic_state_presentation.trinket_body.c0b219a46ae9", "说明待补充 · %d") % remaining(int(e.limit),int(item.get("combat_uses",0))))
			"avenge_spell":states.append(ExternalText.phrase("dynamic_state_presentation.85fa06a7451b", "说明待补充 · %d") % remaining(4,int(item.get("avenge_avenge_spell",0))))
	if str(item.get("bound_tribe",""))!="":states.append(ExternalText.phrase("ui_dynamic_state_presentation.trinket_body.edc179c9b3d7", "说明待补充")+str(item.bound_tribe))
	return text+("\n"+" · ".join(states) if not states.is_empty() else "")
static func trinket_summary(d: Dictionary,item: Dictionary,round_number: int) -> String:
	if d.id=="BG30_MagicItem_707":return ExternalText.phrase("ui_dynamic_state_presentation.trinket_summary.af029d73541b", "说明待补充 · %d") % maxi(0,int(item.get("r134_due",round_number))-round_number)
	if d.id=="BG35_MagicItem_812":return ExternalText.phrase("ui_dynamic_state_presentation.trinket_summary.251068b91e21", "说明待补充")
	if d.id=="BG30_MagicItem_994":return ExternalText.phrase("dynamic_state_presentation.265c626d0c3d", "说明待补充")
	if d.effects.any(func(e):return e.get("handler","")=="round13_item"):return preload("res://ui/round13_presentation.gd").summary(d,item,round_number)
	if d.effects.any(func(e):return e.get("handler","")=="round10"):return preload("res://ui/demon_presentation.gd").progress(d,item,{},round_number)
	for e in d.get("effects",[]):
		match str(e.get("op",e.get("handler",""))):
			"progress":return ExternalText.phrase("ui_dynamic_state_presentation.trinket_summary.a5edb8ead6b5", "说明待补充 · %d / %s") % [remaining(int(e.threshold),int(item.get("progress",0))),ExternalText.phrase("ui_dynamic_state_presentation.trinket_summary.fd1aea69e3fd", "说明待补充") if e.trigger=="minion_played" else ExternalText.phrase("ui_dynamic_state_presentation.trinket_summary.a2ca9cddb0b2", "说明待补充")]
			"waterwheel":return ExternalText.phrase("ui_dynamic_state_presentation.trinket_summary.43b8a3892fff", "说明待补充 · %d") % remaining(2,int(item.get("water_uses",0)) if int(item.get("water_round",0))==round_number else 0)
			"bound_gold":return str(item.get("bound_tribe",ExternalText.phrase("ui_dynamic_state_presentation.trinket_summary.3b3599bd2e58", "说明待补充")))+" · "+(ExternalText.phrase("ui_dynamic_state_presentation.trinket_summary.694c087be978", "说明待补充") if item.get("gold_used",false) else ExternalText.phrase("ui_dynamic_state_presentation.trinket_summary.b19c1277a132", "说明待补充"))
			"heart":return ExternalText.phrase("ui_dynamic_state_presentation.trinket_summary.e34ebe8b9b81", "说明待补充 · %d") % remaining(int(e.threshold),int(item.get("death_progress",0)))
	return ""
static func displayed_gifts(engine,c: Dictionary) -> Array:
	var result=engine.card_gifts(c).duplicate()
	
	
	var offered=int(c.get("r13_gift_id",0))
	if offered>0 and not result.any(func(g):return int(g.id)==offered):
		var gift={"id":offered,"progress":0,"acquired_round":int(engine.state.round)}
		if offered==2:
			gift["attack"]=3 if int(engine.state.round)>=5 else 2
			gift["health"]=4 if int(engine.state.round)>=5 else 3 if int(engine.state.round)==4 else 2
		result.append(gift)
	return result
static func gifts(engine,c: Dictionary,compact: bool=false) -> String:
	var lines=[];var counts={}
	for gift in displayed_gifts(engine,c):
		var id=int(gift.id);var definition={}
		for d in engine.content.definitions.values():
			if d.get("kind","")=="dark_gift" and int(d.get("numeric_id",-1))==id:definition=d;break
		var text=str(definition.get("text",""));var name=str(definition.get("name",ExternalText.phrase("ui_dynamic_state_presentation.gifts.7abe8d60fb3e", "说明待补充")+str(id)))
		if id==2:text=ExternalText.phrase("dynamic_state_presentation.f47dfe722a69", "说明待补充 · %d / %d") % [int(gift.get("attack",2)),int(gift.get("health",2))]
		if id in [9,11]:text+=ExternalText.phrase("dynamic_state_presentation.c70f46fae73e", "说明待补充 · %d") % (2-int(gift.get("progress",0)))
		if id==27:text+=ExternalText.phrase("ui_dynamic_state_presentation.gifts.52d27ebf0238", "说明待补充") if gift.get("doubled",false) else ExternalText.phrase("ui_dynamic_state_presentation.gifts.2aa5e4e4ae91", "说明待补充 · %d") % maxi(0,2-int(gift.get("progress",0)))
		text=ExternalText.describe(definition,gift,{},text,"body",{"threshold":2 if id in [9,11,27] else 0,"progress":int(gift.get("progress",0)),"remaining":maxi(0,2-int(gift.get("progress",0)))})
		var key=name+"："+text;counts[key]=int(counts.get(key,0))+1
	for key in counts:lines.append(str(key)+(" ×"+str(counts[key]) if int(counts[key])>1 else ""))
	if compact and not lines.is_empty():
		var attack=0;var health=0;var other=0
		for gift in displayed_gifts(engine,c):
			if int(gift.id)==6:attack+=3
			elif int(gift.id)==7:health+=3
			else:other+=1
		return ExternalText.phrase("ui_dynamic_state_presentation.gifts.0ed13f74bb0c", "说明待补充 · %d") % displayed_gifts(engine,c).size()+(ExternalText.phrase("ui_dynamic_state_presentation.gifts.af1598374e71", "说明待补充 · %d / %d") % [attack,health] if attack+health>0 else "")+(ExternalText.phrase("ui_dynamic_state_presentation.gifts.232c28c3737a", "说明待补充 · %d") % other if other>0 else "")
	return "\n".join(lines)

static func trinket_body(d: Dictionary,item: Dictionary,p: Dictionary,round_number: int) -> String:
	return ExternalText.describe(d, item, p, _computed_trinket_body(d,item,p,round_number), "body", {"round":round_number,"detail":trinket_summary(d,item,round_number)})
