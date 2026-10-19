extends RefCounted
const ExternalText = preload("res://domain/resources/external_content.gd")
const Attributes=preload("res://domain/rules/spell_attributes.gd")
const GREEN="7ee58d"
static func escape(value: String) -> String:
	return value.replace("[","[lb]")
static func clean(value: String) -> String:
	return value.strip_edges()
static func signed(value: int) -> String:
	return ("+" if value>=0 else "")+str(value)
static func number(base_value: int,extra: int,rich: bool) -> String:
	if extra==0: return signed(base_value)
	var total=str(base_value+extra); var addition=signed(extra)
	if rich:
		total="[color=#"+GREEN+"]"+total+"[/color]"
		addition="[color=#"+GREEN+"]"+addition+"[/color]"
	return total+"("+str(base_value)+addition+")"
static func stats(spell: Dictionary,effect: Dictionary,player: Dictionary,rich: bool) -> String:
	var b=Attributes.base(effect); var extra=Attributes.bonus(spell,effect,player); var total=b+extra
	var parts=[]
	if total.x!=0: parts.append(number(b.x,extra.x,rich)+ExternalText.phrase("ui_spell_presentation.stats.7b600c5288e6", "说明待补充"))
	if total.y!=0: parts.append(number(b.y,extra.y,rich)+ExternalText.phrase("ui_spell_presentation.stats.0ec278d99e98", "说明待补充"))
	return "/".join(parts)
static func body(spell: Dictionary,player: Dictionary={},rich: bool=false) -> String:
	var text=clean(str(spell.get("text","")))
	if spell.get("effects",[]).any(func(e):return e.get("handler","")=="round12"):
		return preload("res://ui/beast_presentation.gd").body(spell,spell.get("instance_context",{}),player,rich)
	if spell.get("effects",[]).any(func(e):return e.get("handler","")=="round10"):
		return preload("res://ui/demon_presentation.gd").body(spell,spell.get("instance_context",{}),player,1,rich)
	if spell.get("effects",[]).any(func(e):return e.get("handler","")=="round9"):
		return preload("res://ui/pirate_presentation.gd").body(spell,spell.get("instance_context",{}),player,rich)
	if spell.get("effects",[]).any(func(e):return e.get("handler","")=="round8"):
		return preload("res://ui/quilboar_presentation.gd").body(spell,spell.get("instance_context",{}),player,rich)
	if spell.get("effects",[]).any(func(e):return e.get("handler","")=="round7"):
		return preload("res://ui/naga_presentation.gd").body(spell,spell.get("instance_context",{}),player,rich)
	if spell.get("kind","")!="spell": return escape(text) if rich else text
	for effect in spell.get("effects",[]):
		if not Attributes.eligible(spell,effect): continue
		var gains=stats(spell,effect,player,rich)
		match str(effect.handler):
			"round11":
				var b=Attributes.base(effect);var extra=Attributes.bonus(spell,effect,player)
				var original=signed(b.x)+"/"+signed(b.y)
				var shown=number(b.x,extra.x,rich)+"/"+number(b.y,extra.y,rich)
				var body_text=escape(text) if rich else text
				return body_text.replace(original,shown) if original in body_text else body_text+"\n目标及每个符合条件的随从各获得："+gains
			"round6":return ExternalText.phrase("spell_presentation.55598ce80b65", "说明待补充")+gains+ExternalText.phrase("ui_spell_presentation.body.bf6388997251", "说明待补充")
			"slaughter": return ExternalText.phrase("spell_presentation.063939e2f608", "说明待补充")+gains+"。"
			"menagerie": return ExternalText.phrase("spell_presentation.d1c21e65bcf9", "说明待补充")+gains+"。"
			"shop_buff": return ExternalText.phrase("spell_presentation.1330ba95309a", "说明待补充")+gains+"。"
			"buff","grow_self":
				var keyword=str(effect.get("keyword",""))
				var name={"TAUNT":ExternalText.phrase("ui_spell_presentation.body.0238d1e3da2c", "说明待补充"),"DIVINE_SHIELD":ExternalText.phrase("ui_spell_presentation.body.364ecf3c3959", "说明待补充"),"REBORN":ExternalText.phrase("ui_spell_presentation.body.b5a9c20568b6", "说明待补充"),"WINDFURY":ExternalText.phrase("ui_spell_presentation.body.bc1cb4e341a4", "说明待补充")}.get(keyword,keyword)
				name=ExternalText.term(str(keyword),str(name))
				return ExternalText.phrase("ui_spell_presentation.body.60bb67facf9e", "说明待补充")+gains+(ExternalText.phrase("ui_spell_presentation.body.d3658c5031dc", "说明待补充")+name if keyword!="" else "")+"。"
	return escape(text) if rich else text
