extends RefCounted
const ExternalText = preload("res://domain/resources/external_content.gd")
static func body(engine,d: Dictionary,c: Dictionary,p: Dictionary,rich: bool=false) -> String:
	var text=str(d.text)
	if engine==null or p.is_empty():return text
	for e in d.effects:
		match str(e.get("op","")):
			"family":
				var n=maxi(1,int(p.get("family_played",0))+(1 if engine.find_index(p.hand,int(c.instance_id))>=0 else 0))
				text=ExternalText.phrase("murloc_presentation.45234d9d1aee", "说明待补充 · %d / %s / %d") % [int(e.get("attack",0)+e.get("health",0))*n,ExternalText.phrase("ui_murloc_presentation.body.7b600c5288e6", "说明待补充") if int(e.get("attack",0))>0 else ExternalText.phrase("ui_murloc_presentation.body.0ec278d99e98", "说明待补充"),int(p.get("family_played",0))]
			"learned":
				var learned=engine.content.get_def(c.get("learned_spell",""))
				text=ExternalText.phrase("ui_murloc_presentation.body.97267d1d93d4", "说明待补充 · %s / %s") % [learned.get("name",ExternalText.phrase("ui_murloc_presentation.body.cfdec5af480f", "说明待补充")),learned.get("text","")]
			"teach":text=ExternalText.phrase("murloc_presentation.200d3aec00b4", "说明待补充 · %d") % engine.Fish.quota(engine,c,"teach",int(e.amount))
	return preload("res://ui/spell_presentation.gd").escape(text) if rich else text
static func trinket(engine,p: Dictionary,c: Dictionary) -> String:
	var d=engine.content.get_def(c.id);var text=str(d.text)
	for e in d.effects:
		match str(e.get("op","")):
			"murky":text=ExternalText.phrase("murloc_presentation.0dcb6dd9a7be", "说明待补充 · %d / %d / %d") % [1+int(p.get("battlecry_count",0)),2+2*int(p.get("battlecry_count",0)),int(p.get("battlecry_count",0))]
			"teach":text=ExternalText.phrase("murloc_presentation.5c8e9bcf514d", "说明待补充 · %d") % engine.Fish.quota(engine,c,"teach",int(e.amount))
			"typewriter":text=ExternalText.phrase("murloc_presentation.5766c54f5703", "说明待补充 · %d") % maxi(0,int(e.amount)-int(c.get("typewriter_used",0)))
			"sinstone":text=ExternalText.phrase("murloc_presentation.a4ecb1b45548", "说明待补充 · %d") % engine.Fish.quota(engine,c,"sinstone",2)
			"warcry_free":text=ExternalText.phrase("murloc_presentation.cc017a3c9662", "说明待补充 · %d") % engine.Fish.quota(engine,c,"warcry",2)
			"stir":text=ExternalText.phrase("murloc_presentation.930bb93ecda0", "说明待补充 · %d") % (5-int(c.get("stir_progress",0)))
			"conch_portrait":text=ExternalText.phrase("murloc_presentation.d7246e947490", "说明待补充 · %d") % maxi(0,int(c.get("conch_due",int(engine.state.round)+2))-int(engine.state.round))
			"memory":text=ExternalText.phrase("murloc_presentation.426bbcf16c64", "说明待补充")+engine.content.get_def(p.get("last_tavern_spell","")).get("name",ExternalText.phrase("ui_murloc_presentation.trinket.d54d06d12eb4", "说明待补充"))
	return text
static func hero(_engine,p: Dictionary) -> String:
	match str(p.hero_id):
		"TB_BaconShop_HERO_55":return ExternalText.phrase("murloc_presentation.3a553ebeef4a", "说明待补充 · %d") % (5-int(p.get("flurgl_sales",0)))
		"BG20_HERO_242":return ExternalText.phrase("murloc_presentation.e9d2f7952c57", "说明待补充 · %d") % (20-int(p.get("guff_progress",0)))
		"BG21_HERO_030":return ExternalText.phrase("murloc_presentation.5c00f101432a", "说明待补充")
		"TB_BaconShop_HERO_71":return ExternalText.phrase("murloc_presentation.a8bcca8c8451", "说明待补充")
	return ""
