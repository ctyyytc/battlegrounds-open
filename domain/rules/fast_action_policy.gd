extends RefCounted
const ExternalText = preload("res://domain/resources/external_content.gd")

static func exception(e: Dictionary) -> String:
	if e.get("op","") in ["avalanche","invoke"]:return ExternalText.phrase("domain_rules_fast_action_policy.exception.f46a0ad83f84", "说明待补充")
	if e.get("op","") in ["hamul","special_shop","shark"]:return ExternalText.phrase("domain_rules_fast_action_policy.exception.7edf732c4cbe", "说明待补充")
	if e.get("handler","")=="round10" and e.get("op","")=="damage_discover":return ExternalText.phrase("domain_rules_fast_action_policy.exception.71f9b125dff7", "说明待补充")
	return ""
static func scan(engine,es: Array,result: Dictionary,visited: Array,depth: int=0) -> void:
	if depth>16:result.unknown_dynamic=true;return
	for e in es:
		var reason=exception(e)
		if reason!="" and reason not in result.reasons:result.reasons.append(reason)
		if e.get("target","") in ["minion","friendly_minion","friendly_undead"]:result.needs_target=true
		if e.get("op","")=="choice":
			for id in e.get("ids",[]):
				if id in visited:continue
				visited.append(id);scan(engine,engine.content.get_def(id).get("effects",[]),result,visited,depth+1)
static func classify(engine,p: Dictionary,card: Dictionary,selling: bool=false) -> Dictionary:
	var result={"reasons":[],"needs_target":false,"unknown_dynamic":false}
	var d=engine.play_definition(card)
	var es=engine.Triggers.effects(engine,card).filter(func(e):return d.kind=="spell" or e.get("trigger","") in ["battlecry","choice_play","spellcraft"] or (selling and e.get("trigger","")=="sell"))
	scan(engine,es,result,[])
	if card.has("learned_spell"):scan(engine,engine.content.get_def(card.learned_spell).effects,result,[])
	for source in p.board:
		scan(engine,engine.Triggers.effects(engine,source).filter(func(e):return e.get("trigger","")=="minion_played" or (selling and e.get("trigger","")=="minion_sold")),result,[])
	return result
static func chain(engine,p: Dictionary,mode: String,instance_id: int=-1,target_policy: String="manual") -> Dictionary:
	return {"v":3,"input_origin":"right_click","owner":p.id,"root_action_id":engine.state.get("active_root",engine.cause),"mode":mode,"instance_id":instance_id,"source_instance":instance_id,"choice_policy":"random_legal_effect_option","target_policy":target_policy,"stage":"settle","steps":0,"sold":false}
