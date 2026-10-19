extends RefCounted
const ExternalText = preload("res://domain/resources/external_content.gd")
static func beetle_number(base: int,extra: int,rich: bool) -> String:
	var total=str(base+extra)
	if extra==0:return "[color=#ffffff]"+total+"[/color]" if rich else total
	var addition=("+" if extra>=0 else "")+str(extra)
	return "[color=#7ee58d]"+total+"[/color]([color=#ffffff]"+str(base)+"[/color][color=#7ee58d]"+addition+"[/color])" if rich else total+"("+str(base)+addition+")"
static func summon_body(d: Dictionary,p: Dictionary,rich: bool=false) -> String:
	var text=str(d.text).replace("[","[lb]") if rich else str(d.text)
	var previous=[]
	for e in d.get("effects",[]):
		var token=str(e.get("id",""));var op=str(e.get("op",""))
		if e.get("handler","")=="round12" and ((op=="summon" and token in ["BG28_603t","BG28_603t_G"]) or op in ["boon","beetle_ring"]):
			var definitions=JSON.parse_string(FileAccess.get_file_as_string("res://content/packs/catalog.json")).definitions
			var base=definitions.get(token if token!="" else "BG28_603t",{})
			var imported=ExternalText.load_pack().get("definitions",{}).get(token if token!="" else "BG28_603t",{})
			var a=int(imported.get("attack",base.get("attack",1)));var h=int(imported.get("health",base.get("health",1)))
			var prior=Vector2i.ZERO
			for earlier in previous:
				if earlier.get("op","")=="beetle_growth" and earlier.get("trigger","")==e.get("trigger",""):prior+=Vector2i(int(earlier.attack),int(earlier.health))
			var values={"count":int(e.get("amount",1)),"attack":a+int(p.get("beetle_attack",0))+prior.x,"health":h+int(p.get("beetle_health",0))+prior.y}
			text+="\n"+ExternalText.named("beetle.summon",values,"%d · %d/%d" % [values.count,values.attack,values.health])
		previous.append(e)
	return text
static func body(d: Dictionary,c: Dictionary,p: Dictionary,rich: bool=false) -> String:
	var text=summon_body(d,p,rich)
	for e in d.effects:
		match str(e.get("op","")):
			"behemoth":text=ExternalText.phrase("beast_presentation.deed0c6a781c", "说明待补充 · %d / %d") % [3*int(e.scale)*(1+int(c.get("behemoth_count",0))),int(c.get("behemoth_count",0))]
			"lobster":text=ExternalText.phrase("beast_presentation.fe91001a5e34", "说明待补充 · %d / %d") % [2*int(e.scale)*(1+int(p.get("lobster_count",0))),int(e.scale)*(1+int(p.get("lobster_count",0)))]
			"fishbait":text+="\n"+(ExternalText.phrase("ui_beast_presentation.body.dca970e72b7e", "说明待补充") if int(c.get("activated_round",-1))==int(p.get("presentation_round",-2)) else ExternalText.phrase("ui_beast_presentation.body.97fe8e74af3c", "说明待补充"))
	if d.id in ["BG28_603t","BG28_603t_G"]:text+=ExternalText.phrase("ui_beast_presentation.body.f7cf7091423c", "\n说明待补充 · %d / %d") % [int(p.get("beetle_attack",0)),int(p.get("beetle_health",0))]
	return text
static func item(d: Dictionary,c: Dictionary,p: Dictionary={}) -> String:
	var text=summon_body(d,p,true)
	for e in d.effects:
		match str(e.get("op","")):
			"babyfood":text=ExternalText.phrase("beast_presentation.2992c9c3ed4e", "说明待补充 · %d") % (3*(1+int(c.get("babyfood_count",0))))
			"anklet":text=ExternalText.phrase("beast_presentation.db3a5180c89c", "说明待补充 · %d / %d") % [1+int(c.get("anklet_count",0)),1+int(c.get("anklet_count",0))]
			"duster":text+=ExternalText.phrase("ui_beast_presentation.item.76aa9fe9aba6", "\n说明待补充 · %d") % (6-int(c.get("duster_count",0)))
			"cat":text+=ExternalText.phrase("ui_beast_presentation.item.3621eecd55ee", "\n说明待补充 · %d") % (7-int(c.get("cat_count",0)))
			"beetle_ring":text+=ExternalText.phrase("ui_beast_presentation.item.fa4ad8ca87d2", "\n说明待补充 · %d") % (int(e.threshold)-int(c.get("avenge_round12",0)))
	return text
static func hero(engine,p: Dictionary) -> String:
	match engine.hero_handler(p):
		"snake":return ExternalText.phrase("beast_presentation.1659c910d224", "说明待补充 · %d / %s") % [int(p.get("snake_ready_round",1)),ExternalText.phrase("ui_beast_presentation.hero.fef48d91645c", "说明待补充 · %d") % int(p.snake_last_roll) if p.has("snake_last_roll") else ""]
		"onyxia":return ExternalText.phrase("beast_presentation.d4e9e342a062", "说明待补充 · %d / %d") % [1+int(p.get("onyxia_count",0)),1+int(p.get("onyxia_count",0))]
		"teron":return ExternalText.phrase("beast_presentation.0d4809ed771e", "说明待补充")+(ExternalText.phrase("ui_beast_presentation.hero.2234564e1be4", "\n说明待补充 · %d") % int(p.teron_target) if p.has("teron_target") else "")
		"sylvanas":return ExternalText.phrase("beast_presentation.290c9eaead51", "说明待补充 · %d") % engine.Beasts.sylvanas_pool(engine,p).size()
	return ""
