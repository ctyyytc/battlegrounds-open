extends RefCounted
const ExternalText = preload("res://domain/resources/external_content.gd")
const ALWAYS=["BG33_825","BG_LOE_077","BG25_354","BG26_ICC_901","BG35_883","BG36_204","BG36_208","BG36_733","BG32_846","BG33_318","BG33_823","BG32_837"]
const GOLD_ONLY=["BG36_760","BG36_701","BG34_925"]
static func pair(p: Dictionary,a: String,h: String) -> Vector2i:
	return Vector2i(int(p.get(a,0)),int(p.get(h,0)))
static func over(v: Vector2i,n: int) -> bool:return v.x>n and v.y>n
static func metrics(engine,p: Dictionary) -> Dictionary:
	var gem=Vector2i.ONE+engine.Quilboar.gem_bonus(engine,p)
	var barrage=Vector2i.ZERO
	for layer in p.get("gem_barrages",[]):barrage+=Vector2i(int(layer.attack),int(layer.health))+engine.Quilboar.gem_bonus(engine,p)
	var general=pair(p,"shop_growth_attack","shop_growth_health")+pair(p,"demon_shop_attack","demon_shop_health")
	if int(p.get("corrosion_round",-1))==int(engine.state.round):general+=Vector2i.ONE*int(p.get("corrosion_bonus",0))
	for item in p.trinkets:
		if not engine.Demons.specs(engine,item,"void").is_empty():general+=Vector2i.ONE*int(item.get("void_bonus",2))
		if not engine.Demons.specs(engine,item,"cheese").is_empty():general+=Vector2i.ONE*int(item.get("cheese_bonus",2))
		if not engine.Demons.specs(engine,item,"gauntlet").is_empty():general+=Vector2i(3,3)
	var once=preload("res://domain/rules/shop_bonus.gd").current(engine,p)
	return {"J":gem,"B":barrage,"S":general+once,"S_persistent":general,"S_current":once,"E":pair(p,"nomi_attack","nomi_health"),"P":pair(p,"spell_bonus_attack","spell_bonus_health")+engine.spell_aura(p),"K":pair(p,"beetle_attack","beetle_health"),"L":int(p.get("lobster_count",0)),"G":int(p.get("golden_played",0)),"U":int(p.get("undead_attack",0)),"C":int(p.get("spell_count",0))}
static func inspect(engine,p: Dictionary,card: Dictionary,action: String="sell") -> Dictionary:
	var d=engine.content.get_def(card.get("def_id",""));var base=str(d.get("base_id",d.get("id","")))
	var m=metrics(engine,p);var reasons=[]
	if d.get("kind","")!="minion":return {"protected":false,"reasons":[],"metrics":m}
	if action=="destroy" and not engine.Undead.tribe(engine,card,"亡灵"):return {"protected":false,"reasons":[],"metrics":m}
	var named=base in ALWAYS or (base in GOLD_ONLY and d.get("golden",false))
	match base:
		"BG36_510","BG31_323":named=over(m.J,5)
		"BG36_202":named=m.L>10
		"BG36_209":named=over(m.K,100)
		"BG28_633":named=over(m.S,100) or over(m.B,50)
		"BG36_762":named=over(m.S,100)
		"BG32_821":named=over(m.P,10)
		"BGS_104":named=over(m.E,100)
		"BG36_352":named=over(m.E,100) or over(m.S,100)
		"BG36_344":named=m.G>15
		"BG36_515","BG34_692","BG32_324":named=m.U>15
		"BG28_309":named=m.U>15 and d.get("golden",false)
		"BG31_035":named=m.C>50
	if named:reasons.append(ExternalText.phrase("domain_rules_core_protection.inspect.1e8cf972303b", "说明待补充"))
	if d.get("golden",false) and int(d.get("tier",0))==6:reasons.append(ExternalText.phrase("domain_rules_core_protection.inspect.8591bea09e0f", "说明待补充"))
	if int(d.get("tier",0))==7:reasons.append(ExternalText.phrase("domain_rules_core_protection.inspect.efe3a524f992", "说明待补充"))
	var maximum=Vector2i.ZERO
	for c in p.board:
		var v=engine.stats(c);maximum.x=maxi(maximum.x,v.x);maximum.y=maxi(maximum.y,v.y)
	var actual=engine.stats(card)
	if actual.x*2>maximum.x or actual.y*2>maximum.y:reasons.append(ExternalText.phrase("domain_rules_core_protection.inspect.5e3c7b2d9c7b", "说明待补充"))
	return {"protected":not reasons.is_empty(),"reasons":reasons,"metrics":m,"maximum":maximum,"actual":actual,"instance_id":card.instance_id,"action":action}
static func enabled(engine,p: Dictionary) -> bool:
	return int(p.id)==0 and engine.combat_context.is_empty() and engine.state.phase=="recruit" and int(engine.state.round)>=8 and int(engine.state.get("fast_mode_level",0))>0 and engine.state.get("confirmation_enabled",true)
