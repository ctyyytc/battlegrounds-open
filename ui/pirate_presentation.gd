extends RefCounted
const ExternalText = preload("res://domain/resources/external_content.gd")
const S=preload("res://ui/spell_presentation.gd")
static func body(d: Dictionary,c: Dictionary,p: Dictionary,rich: bool=false) -> String:
 var text=str(d.get("text",""));var e=d.get("effects",[])
 if d.id=="BG_TRIPLE_REWARD_R92":return ExternalText.phrase("ui_pirate_presentation.body.cf108347052c", "说明待补充 · %d") % int(c.get("reward_tier",1))
 if d.id=="BG36_520t":return ExternalText.phrase("pirate_presentation.d3f57e9473e7", "说明待补充 · %d") % int(c.get("box_remaining",5))
 for spec in e:
  var op=str(spec.get("op",""))
  if op in ["spend_buff","spend_box","spend_bounty"]:
   text=text+ExternalText.phrase("ui_pirate_presentation.body.a1a35d834457", "说明待补充 · %d") % (int(spec.threshold)-int(c.get("pirate_spent",0)))
  elif op=="parrot":text=ExternalText.phrase("pirate_presentation.8608572a7261", "说明待补充 · %d / %s") % [int(spec.amount),ExternalText.phrase("ui_pirate_presentation.body.cd008a306777", "说明待补充") if c.get("parrot_done",false) else ExternalText.phrase("ui_pirate_presentation.body.f347c6c86822", "说明待补充 · %d") % maxi(0,35-int(c.get("parrot_damage",0)))]
  elif op=="neighbors_gold":text=ExternalText.phrase("pirate_presentation.7e4327f24c79", "说明待补充 · %d") % int(spec.attack)
  elif op=="board_buff":text=ExternalText.phrase("pirate_presentation.1fc6345be562", "说明待补充")+(ExternalText.phrase("ui_pirate_presentation.body.28478c0b891e", "说明待补充") if int(spec.get("repeat",1))==2 else "。")
  elif op=="grifter":text=ExternalText.phrase("pirate_presentation.9a04ce5db204", "说明待补充 · %d / %d") % [int(spec.amount),4-int(c.get("pirate_obtained",0))]
  elif op=="ballad":text=ExternalText.phrase("pirate_presentation.e70dedf594df", "说明待补充 · %d / %s") % [1+int(p.get("coins_spent_round",0)),ExternalText.phrase("ui_pirate_presentation.body.106292927d3e", "说明待补充") if int(spec.repeat)==2 else ""]
  elif op=="discovered_buff":text=ExternalText.phrase("pirate_presentation.beb822ab7c73", "说明待补充 · %d / %d / %d") % [int(spec.attack)*(1+int(p.get("golden_played",0))),int(spec.health)*(1+int(p.get("golden_played",0))),int(p.get("golden_played",0))]
  elif op=="hammer":text=ExternalText.phrase("pirate_presentation.3edd305f76d1", "说明待补充 · %d / %d / %d") % [int(spec.attack)*(1+int(p.get("golden_played",0))),int(spec.health)*(1+int(p.get("golden_played",0))),int(p.get("golden_played",0))]
  elif op=="shard":text+="（"+(ExternalText.phrase("ui_pirate_presentation.body.630a2ff51ba5", "说明待补充") if c.get("shard_used",false) else ExternalText.phrase("ui_pirate_presentation.body.6b4ed351c2a1", "说明待补充"))+"）"
  elif op=="pants":return ExternalText.phrase("ui_pirate_presentation.body.60bb67facf9e", "说明待补充")+S.stats(d,spec,p,rich)+ExternalText.phrase("ui_pirate_presentation.body.be7f405829a4", "说明待补充")
  elif op=="shop_growth":return ExternalText.phrase("ui_pirate_presentation.body.ac72af063e3e", "说明待补充")+S.stats(d,spec,p,rich)+"。"
  elif op=="favor":return ExternalText.phrase("pirate_presentation.d49972f245a2", "说明待补充")+S.stats(d,spec,p,rich)+ExternalText.phrase("pirate_presentation.6923a84f1dda", "说明待补充")
  elif op=="seafood":return ExternalText.phrase("ui_pirate_presentation.body.60bb67facf9e", "说明待补充")+S.stats(d,spec,p,rich)+ExternalText.phrase("pirate_presentation.6bf8ad057990", "说明待补充")
  elif op=="bounty_buff":return ExternalText.phrase("pirate_presentation.4251bd7420bd", "说明待补充")+S.stats(d,spec,p,rich)+"。"
  elif op=="left_buff":return ExternalText.phrase("pirate_presentation.36060a5516b0", "说明待补充")+S.stats(d,spec,p,rich)+"。"
  elif op=="golden_buff":return ExternalText.phrase("ui_pirate_presentation.body.685f1f483a55", "说明待补充")+S.stats(d,spec,p,rich)+ExternalText.phrase("pirate_presentation.85bd049b32ac", "说明待补充")
 return S.escape(text) if rich else text
static func hero(engine,p: Dictionary) -> String:
 if engine.hero_handler(p)=="eudora":return ExternalText.phrase("pirate_presentation.1dbbc29acf39", "说明待补充 · %d") % (4-int(p.get("eudora_digs",0)))
 return ""
