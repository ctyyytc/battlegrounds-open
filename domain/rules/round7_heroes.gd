extends RefCounted
const ExternalText = preload("res://domain/resources/external_content.gd")
const HANDLERS=["gally","kragg","chen","inge","brann_buy","tae"]
static func supports(d: Dictionary,e: Dictionary) -> bool:
 return d.kind in ["hero","hero_power"] and e.get("handler","") in HANDLERS
static func availability(engine,p: Dictionary) -> Dictionary:
 var handler=engine.hero_handler(p)
 if handler not in HANDLERS:return {}
 if handler in ["gally","chen","brann_buy","tae"]:return {"available":false,"reason":"PASSIVE_POWER","targets":[]}
 if handler=="kragg":return {"available":not engine.power_used(p,true),"reason":"POWER_ALREADY_USED" if engine.power_used(p,true) else "","targets":[],"cost":0,"handler":handler}
 var targets=[]
 for c in p.board+p.shop:
  if engine.content.get_def(c.def_id).kind=="minion":targets.append(c.instance_id)
 var used=int(p.get("inge_uses",0)) if int(p.get("inge_round",0))==int(engine.state.round) else 0
 return {"available":used<2 and not targets.is_empty(),"reason":"POWER_ALREADY_USED" if used>=2 else "NO_LEGAL_TARGET" if targets.is_empty() else "","targets":targets,"handler":handler,"cost":0}
static func use(engine,p: Dictionary,args: Dictionary) -> String:
 var handler=engine.hero_handler(p)
 if handler=="kragg":
  engine.gain_coins(p,int(p.get("kragg_amount",2)));engine.Powers.ledger(engine,p).game_used=1
 elif handler=="inge":
  var target=engine.find_target(p,int(args.get("target_id",-1)))
  if target.is_empty():return "TARGET_REQUIRED"
  if int(p.get("inge_round",0))!=int(engine.state.round):p["inge_round"]=int(engine.state.round);p["inge_uses"]=0
  p.inge_uses+=1
  engine.buff(target,0 if p.get("inge_health",false) else int(p.tier),int(p.tier) if p.get("inge_health",false) else 0)
 else:return "POWER_NOT_IMPLEMENTED"
 engine.consume_power(p);engine.emit("HeroPowerUsed",int(p.id),{"hero":p.hero_id,"power_id":engine.power_definition(p).id});return ""
static func bought(engine,p: Dictionary,d: Dictionary) -> void:
 if d.get("is_tavern_spell",false):
  if engine.has_handler(p,"tae"):p["tavern_bought"]=int(p.get("tavern_bought",0))+1
  p["next_spell_discount"]=0
 if engine.has_handler(p,"brann_buy") and not p.get("brann_granted",false) and d.kind=="minion" and d.effects.any(func(e):return e.get("trigger","")=="battlecry"):
  p["brann_buys"]=int(p.get("brann_buys",0))+1
  if int(p.brann_buys)>=4:
   p["brann_granted"]=true;engine.receive_card(p,engine.make_card("BG_LOE_077",int(p.id)),engine.content.get_def(p.hero_id))
static func sold(engine,p: Dictionary) -> void:
 if engine.has_handler(p,"gally"):p["gally_stored"]=int(p.get("gally_stored",0))+1
static func end(engine,p: Dictionary) -> void:
 if engine.has_handler(p,"kragg"):p["kragg_amount"]=int(p.get("kragg_amount",2))+engine.Triggers.times(engine,p,"turn_end")
static func start(engine,p: Dictionary) -> void:
 if int(p.get("gally_stored",0))>0:
  engine.gain_coins(p,int(p.get("gally_stored",0)));p["gally_stored"]=0
 if engine.has_handler(p,"inge"):p["inge_health"]=not p.get("inge_health",false);p["inge_uses"]=0;p["inge_round"]=int(engine.state.round)
static func description(engine,p: Dictionary) -> String:
 match engine.hero_handler(p):
  "gally":return ExternalText.phrase("domain_rules_round7_heroes.description.cca929ffaef9", "说明待补充 · %d") % int(p.get("gally_stored",0))
  "kragg":return ExternalText.phrase("domain_rules_round7_heroes.description.d91d201e7eb1", "说明待补充 · %d / %s") % [int(p.get("kragg_amount",2)),ExternalText.phrase("domain_rules_round7_heroes.description.581b75460faf", "说明待补充") if engine.power_used(p,true) else ""]
  "inge":return ExternalText.phrase("domain_rules_round7_heroes.description.ef4cc9f80ae8", "说明待补充 · %d / %s / %d") % [int(p.tier),ExternalText.phrase("domain_rules_round7_heroes.description.0ec278d99e98", "说明待补充") if p.get("inge_health",false) else ExternalText.phrase("domain_rules_round7_heroes.description.7b600c5288e6", "说明待补充"),maxi(0,2-int(p.get("inge_uses",0)))]
  "chen":return ExternalText.phrase("domain_rules_round7_heroes.description.0ebf4cd36f6d", "说明待补充 · %d") % (3-int(p.get("chen_plays",0))%3)
  "brann_buy":return ExternalText.phrase("domain_rules_round7_heroes.description.ae3bc7ddf185", "说明待补充 · %s") % (ExternalText.phrase("domain_rules_round7_heroes.description.630a2ff51ba5", "说明待补充") if p.get("brann_granted",false) else ExternalText.phrase("domain_rules_round7_heroes.description.68455820c60e", "说明待补充 · %d") % maxi(0,4-int(p.get("brann_buys",0))))
  "tae":return ExternalText.phrase("domain_rules_round7_heroes.description.8f4b8b12a4e7", "说明待补充 · %s") % (ExternalText.phrase("domain_rules_round7_heroes.description.a0a94199bfd5", "说明待补充") if int(p.get("tavern_bought",0))%3==2 else ExternalText.phrase("domain_rules_round7_heroes.description.68455820c60e", "说明待补充 · %d") % (2-int(p.get("tavern_bought",0))%3))
 return ""
