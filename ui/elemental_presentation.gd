extends RefCounted
const ExternalText = preload("res://domain/resources/external_content.gd")
const Special=preload("res://domain/rules/special_rules.gd")
const Gain=preload("res://domain/rules/elemental_gain.gd")
static func colored(n: int,color: String,rich: bool) -> String:
	var s=("+" if n>=0 else "")+str(n)
	return "[color=#"+color+"]"+s+"[/color]" if rich else s
static func number(base: int,history: int,extra: int,rich: bool) -> String:
	var s="[color=#ffffff]"+str(base)+"[/color]" if rich else str(base)
	if history!=0:s+=colored(history,"ffd166",rich)
	if extra!=0:s+=colored(extra,"79e69d",rich)
	return str(base+history+extra)+( "("+s+")" if history!=0 or extra!=0 else "")
static func stats(base: Vector2i,extra: Vector2i,rich: bool,history: Vector2i=Vector2i.ZERO) -> String:
	var parts=[]
	if base.x+history.x+extra.x!=0:parts.append("+"+number(base.x,history.x,extra.x,rich)+ExternalText.phrase("ui_elemental_presentation.stats.7b600c5288e6", "说明待补充"))
	if base.y+history.y+extra.y!=0:parts.append("+"+number(base.y,history.y,extra.y,rich)+ExternalText.phrase("ui_elemental_presentation.stats.0ec278d99e98", "说明待补充"))
	return "/".join(parts)
static func supported(d: Dictionary) -> bool:
	if "元素" not in d.get("card_types",[]):return false
	return d.get("effects",[]).any(func(e):return e.get("handler","") in ["elemental_counter","grow_self"] or e.get("op","") in ["ball","shop_aura","refresh_growth","elemental_board","consume_shop","activate_next","thunder","spend_wind","self_buff","activate_buff"])
static func compact(text: String) -> String:
	return text
static func card_body(d: Dictionary,p: Dictionary,rich: bool=true) -> String:
	if not supported(d):return preload("res://ui/spell_presentation.gd").escape(str(d.get("text",""))) if rich else str(d.get("text",""))
	for e in d.get("effects",[]):
		var gain=compact(stats(Vector2i(int(e.get("attack",0)),int(e.get("health",0))),Gain.extra(p),rich))
		var times=" ×2" if int(e.get("repeat",e.get("amount",1)))==2 else ""
		if e.get("handler","")=="grow_self":return growth_trigger(e,true)+ExternalText.phrase("ui_elemental_presentation.card_body.dd4504e4a70c", "说明待补充")+gain+times
		match e.get("op",""):
			"elemental_board":return ExternalText.phrase("ui_elemental_presentation.card_body.90d4dcce0f3e", "说明待补充")+gain+times
			"refresh_growth":return (ExternalText.phrase("ui_elemental_presentation.card_body.428612a6429d", "说明待补充") if e.trigger=="deathrattle" else ExternalText.phrase("ui_elemental_presentation.card_body.172c4d258f28", "说明待补充"))+ExternalText.phrase("ui_elemental_presentation.card_body.1a6a149a6907", "说明待补充")+gain+times
			"shop_aura":return (ExternalText.phrase("ui_elemental_presentation.card_body.aa4caf1c9b7c", "说明待补充") if e.trigger=="deathrattle" else ExternalText.phrase("ui_elemental_presentation.card_body.456cae36bacf", "说明待补充"))+ExternalText.phrase("ui_elemental_presentation.card_body.4174e453cb84", "说明待补充")+gain+times
			"ball":
				var value=Gain.ball_parts(d,p);return ExternalText.phrase("ui_elemental_presentation.card_body.f0c913b4634d", "说明待补充")+compact(stats(value.base,value.elemental,rich,value.history))
			"activate_next":return ExternalText.phrase("elemental_presentation.8bee2df0f2fa", "说明待补充")+str(int(e.amount))+ExternalText.phrase("ui_elemental_presentation.card_body.e704bafd933f", "\n说明待补充")+compact(stats(Vector2i.ZERO,Gain.extra(p),rich))
	return compact(body(d,p,rich))

static func legacy_card_body(d: Dictionary,p: Dictionary,rich: bool=true) -> String:
	if d.get("base_id","")=="BG26_537":return ExternalText.phrase("ui_elemental_presentation.legacy_card_body.0851a14a2151", "说明待补充")+compact(stats(Special.ice_gain(bool(d.golden),0,0),Gain.extra(p),rich))
	for e in d.get("effects",[]):
		if e.get("op","")=="ball":
			var parts=Gain.ball_parts(d,p);return ExternalText.phrase("ui_elemental_presentation.legacy_card_body.04823235356b", "说明待补充")+compact(stats(parts.base,parts.elemental,rich,parts.history))
		if e.has("attack") or e.has("health"):
			var times=" ×2" if int(e.get("repeat",e.get("amount",1)))==2 else ""
			return ExternalText.phrase("ui_elemental_presentation.legacy_card_body.8e9e803ee19c", "说明待补充")+compact(stats(Vector2i(int(e.get("attack",0)),int(e.get("health",0))),Gain.extra(p),rich))+times
	return body(d,p,rich)
static func body(d: Dictionary,p: Dictionary={},rich: bool=false) -> String:
	if not supported(d):return preload("res://ui/spell_presentation.gd").escape(str(d.get("text",""))) if rich else str(d.get("text",""))
	var extra=Gain.extra(p)
	if d.get("base_id","")=="BG26_537":
		return ExternalText.phrase("elemental_presentation.a9679a73087d", "说明待补充")+stats(Special.ice_gain(bool(d.golden),0,0),extra,rich)+ExternalText.phrase("ui_elemental_presentation.body.f12bbc0238c9", "说明待补充")
	var parts=[]
	for e in d.get("effects",[]):
		var base=Vector2i(int(e.get("attack",0)),int(e.get("health",0)))
		var gains=stats(base,extra,rich)
		var twice=ExternalText.phrase("ui_elemental_presentation.body.106292927d3e", "说明待补充") if int(e.get("repeat",e.get("amount",1)))==2 else ""
		if e.get("handler","")=="grow_self":
			parts.append(growth_trigger(e)+ExternalText.phrase("ui_elemental_presentation.body.dcbe4e35c51e", "说明待补充")+gains+twice+"。")
		match e.get("op",""):
			"ball":
				var values=Gain.ball_parts(d,p)
				parts.append(ExternalText.phrase("elemental_presentation.9259724f3ee0", "说明待补充")+stats(values.base,values.elemental,rich,values.history)+ExternalText.phrase("elemental_presentation.00a0baba6bc1", "说明待补充"))
			"refresh_growth":parts.append((ExternalText.phrase("ui_elemental_presentation.body.eafeefa58409", "说明待补充") if e.trigger=="deathrattle" else ExternalText.phrase("ui_elemental_presentation.body.31c7fddde4de", "说明待补充"))+ExternalText.phrase("elemental_presentation.17e9da14c268", "说明待补充")+gains+twice+"。")
			"shop_aura":parts.append((ExternalText.phrase("ui_elemental_presentation.body.eafeefa58409", "说明待补充") if e.trigger=="deathrattle" else ExternalText.phrase("ui_elemental_presentation.body.31c7fddde4de", "说明待补充"))+ExternalText.phrase("elemental_presentation.c087356ad364", "说明待补充")+gains+twice+"。")
			"elemental_board":parts.append(ExternalText.phrase("elemental_presentation.94520d665323", "说明待补充")+gains+twice+"。")
			"self_buff":parts.append(ExternalText.phrase("ui_elemental_presentation.body.824b3716fd6b", "说明待补充")+gains+twice+"。")
			"activate_buff":parts.append(ExternalText.phrase("elemental_presentation.d03886bc33d3", "说明待补充")+gains+twice+"。")
			"spend_wind":parts.append(str(d.get("text","")))
			"consume_shop","activate_next","thunder":
				var original=str(d.get("text",""))
				parts.append(original+(ExternalText.phrase("ui_elemental_presentation.body.003e34d96fcb", "说明待补充")+stats(Vector2i.ZERO,extra,rich)+"。" if extra!=Vector2i.ZERO else ""))
	return "\n".join(parts) if not parts.is_empty() else str(d.get("text",""))
static func growth_trigger(e: Dictionary,short: bool=false) -> String:
	var tribe=str(e.get("tribe",""))
	match str(e.get("trigger","")):
		"minion_played":return ExternalText.phrase("ui_elemental_presentation.growth_trigger.185c27f9606f", "说明待补充")+tribe if short else ExternalText.phrase("ui_elemental_presentation.growth_trigger.9d729a08ba26", "说明待补充")+tribe+ExternalText.phrase("ui_elemental_presentation.growth_trigger.4c7bfb18d5da", "说明待补充")
		"minion_sold":return ExternalText.phrase("ui_elemental_presentation.growth_trigger.639ae3ac17b3", "说明待补充")+tribe if short else ExternalText.phrase("ui_elemental_presentation.growth_trigger.31fbfe9741f8", "说明待补充")+tribe+ExternalText.phrase("ui_elemental_presentation.growth_trigger.8129448685e1", "说明待补充")
		"rally":return ExternalText.phrase("ui_elemental_presentation.growth_trigger.2a857118bfae", "说明待补充")
		"turn_end":return ExternalText.phrase("ui_elemental_presentation.growth_trigger.6c641cf8f1df", "说明待补充")
	return str(e.get("trigger",""))
