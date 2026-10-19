extends RefCounted
const ExternalText = preload("res://domain/resources/external_content.gd")

const LIMIT=160
static func actor(engine,source: Dictionary) -> Dictionary:
 var id=str(source.get("def_id",source.get("id","")))
 var d=engine.content.get_def(id)
 return {"id":id,"instance_id":int(source.get("instance_id",-1)),"name":str(d.get("name",ExternalText.phrase("domain_rules_spell_history.actor.6fb6e25be395", "说明待补充"))) if not d.is_empty() else ExternalText.phrase("domain_rules_spell_history.actor.6fb6e25be395", "说明待补充")}
static func context(engine,p: Dictionary,card: Dictionary,source: Dictionary={}) -> Dictionary:
 var d=engine.content.get_def(str(card.get("def_id",card.get("id","")))).duplicate(true)
 var origin=source if not source.is_empty() else engine.effect_source
 if origin.is_empty():origin=card.get("spellcraft_source_snapshot",{})
 var from=actor(engine,origin)
 if card.get("played_from_hand",false):from={"id":"","instance_id":-1,"name":ExternalText.phrase("domain_rules_spell_history.context.3852b6b88666", "说明待补充")}
 elif origin.is_empty():from={"id":p.hero_id,"instance_id":-1,"name":str(engine.content.get_def(p.hero_id).name)+ExternalText.phrase("domain_rules_spell_history.context.0773fffafe7e", "说明待补充")}
 for key in ["aura_attack","aura_health"]:
  if card.has(key):d[key]=card[key]
 var gem=engine.Quilboar.gem_bonus(engine,p)
 d["instance_context"]=card.duplicate(true)
 return {"origin":from,"spell":d,"player":{"spell_bonus_attack":int(p.get("spell_bonus_attack",0)),"spell_bonus_health":int(p.get("spell_bonus_health",0)),"spell_count":int(p.get("spell_count",0)),"tavern_spell_count":int(p.get("tavern_spell_count",0)),"presentation_gem_attack":gem.x,"presentation_gem_health":gem.y},"resolution_phase":engine.resolution_phase}
static func project(engine,event: Dictionary) -> Dictionary:
 if int(event.owner)!=0:return {}
 var payload=event.payload
 var action={"SpellResolved":"cast","CardGranted":"gain","RewardQueued":"pending","AutomaticSpellUnavailable":"unavailable","EmptyDiscoveryPool":"unavailable"}.get(event.kind,"")
 if action=="":return {}
 if event.kind=="EmptyDiscoveryPool" and payload.get("kind","")!="tavern_spell":return {}
 var id=str(payload.get("id",""));var d=engine.content.get_def(id)
 if action!="unavailable" and d.get("kind","")!="spell":return {}
 var info=payload.get("presentation",{})
 var source=info.get("origin",actor(engine,{}))
 return {"seq":int(event.seq),"round":int(event.round),"phase":str(info.get("resolution_phase","")) if str(info.get("resolution_phase",""))!="" else str(event.phase),"action":action,"id":id,"name":str(d.get("name",ExternalText.phrase("domain_rules_spell_history.project.fa49c7aeee2e", "说明待补充"))),"source":source,"target":payload.get("target",{}),"spell":info.get("spell",d).duplicate(true),"player":info.get("player",{}).duplicate(true),"repeat_index":int(payload.get("repeat_index",0)),"reason":str(payload.get("reason",ExternalText.phrase("domain_rules_spell_history.project.24183b8b6b7e", "说明待补充"))),"remaining":int(payload.get("remaining",0))}
static func append(engine,event: Dictionary) -> void:
 var entry=project(engine,event)
 if entry.is_empty():return
 engine.spell_history.append(entry)
 if engine.spell_history.size()>LIMIT:engine.spell_history.pop_front()
