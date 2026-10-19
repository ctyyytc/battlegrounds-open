extends RefCounted

const AURAS={"battlecry":"BG_LOE_077","deathrattle":"BG25_354","turn_end":"BG26_ICC_901"}
static func times(engine,p: Dictionary,trigger_name: String) -> int:
	var result=1
	var cards=p.board
	for local_player in engine.combat_context.get("players",[]):
		if int(local_player.id)==int(p.id):
			cards=engine.combat_context.boards[engine.combat_context.players.find(local_player)]; break
	for c in cards:
		if c.has("health") and int(c.health)<=0: continue
		var d=engine.content.get_def(c.def_id)
		if str(d.get("base_id",d.id))!=str(AURAS.get(trigger_name,"")): continue
		var extra=2 if d.get("golden",false) else 1
		if trigger_name=="deathrattle": result+=extra
		else: result=maxi(result,1+extra)
	if trigger_name=="turn_end":result+=p.trinkets.filter(func(v):return v.id=="BG32_MagicItem_367").size()
	if trigger_name=="battlecry":result+=int(p.get("r134",{}).get("battlecry",0))
	for pair in [["battlecry","BG27_Reward_802"],["deathrattle","BG27_Reward_803"],["turn_end","BG24_Reward_130"]]:
		if trigger_name==pair[0]:result+=engine.R135.active(engine,p,pair[1]).size()
	return result
static func effects(engine,card: Dictionary) -> Array:
	var definition=engine.play_definition(card)
	
	if card.has("learned_spell") and engine.Quilboar.choice(definition):definition=engine.content.get_def(card.def_id)
	var result=definition.effects.duplicate(true)
	for attached in card.get("attached_effects",[]): result.append(attached.duplicate(true))
	return result
static func deathrattle_effects(engine,card: Dictionary) -> Array:
	var selected=effects(engine,card).filter(func(e):return e.get("trigger","")=="deathrattle")
	# Gifts stay on the instance; derive one batch so copied/attached effects do
	# not duplicate them. The normal trigger expansion owns all repetitions.
	if engine.Gifts.has_deathrattle(engine,card):selected.append({"handler":"gift_deathrattle","trigger":"deathrattle"})
	return selected
static func has_deathrattle(engine,card: Dictionary) -> bool:
	return not deathrattle_effects(engine,card).is_empty()
static func expanded(engine,p: Dictionary,card: Dictionary,trigger_name: String) -> Array:
	var result=[]
	var selected=deathrattle_effects(engine,card) if trigger_name=="deathrattle" else effects(engine,card).filter(func(e):return e.get("trigger","")==trigger_name)
	for unused in times(engine,p,trigger_name): result.append_array(selected.duplicate(true))
	if trigger_name=="deathrattle" and not selected.is_empty() and not engine.combat_context.is_empty():
		for item in p.trinkets:
			if not item.get("combat_used",false) and engine.content.get_def(item.id).effects.any(func(e):return e.handler=="first_deathrattle"):
				item["combat_used"]=true;result.append_array(selected.duplicate(true));engine.count_trigger(p,"deathrattle",1)
	return result
