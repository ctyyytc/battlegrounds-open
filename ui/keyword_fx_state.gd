extends RefCounted
# Read-only presentation queries. Never call power availability helpers that
# lazily initialize ledgers, effects, RNG, or the action dispatcher here.
const Presentation=preload("res://ui/card_presentation.gd")
const STATIC_FIVE=["BATTLECRY","RALLY","SELL_TRIGGER","COMBAT_START","IMMUNE_ATTACK"]
const ALL=["TAUNT","DIVINE_SHIELD","REBORN","WINDFURY","DEATHRATTLE","ACTIVATE","TURN_START","TURN_END","AVENGE","VENOMOUS","POISONOUS","STEALTH","MAGNETIC","SPELLCRAFT","CHOOSE_ONE","CLEAVE","BATTLECRY","RALLY","SELL_TRIGGER","COMBAT_START","IMMUNE_ATTACK"]
static func item(key: String,state: String="active",glow: bool=false,details: Array=[]) -> Dictionary:
	return {"key":key,"state":state,"glow":glow,"details":details}
static func alive(card: Dictionary) -> bool:return not card.has("health") or int(card.health)>0
static func keys(engine,card: Dictionary) -> Array:
	var result=Presentation.effective(card,engine)
	if card.get("reborn_consumed",false):result.erase("REBORN")
	if card.has("poison"):
		result.erase("POISONOUS")
		if card.poison:result.append("POISONOUS")
	return result
static func end_ready(engine,p: Dictionary,source: Dictionary,e: Dictionary) -> bool:
	var op=str(e.get("op",e.get("handler","")))
	match op:
		"gold_supply":return int(source.get("supply_remaining",3))<=engine.Triggers.times(engine,p,"turn_end")
		"consume_shop","rendle":return p.shop.any(func(v):return engine.content.get_def(v.def_id).kind=="minion") if op=="consume_shop" else not p.shop.is_empty()
		"last_spell","memory":return str(p.get("last_tavern_spell",""))!=""
		"future":return p.hand.any(func(v):return engine.content.get_def(v.def_id).kind=="minion")
		"whisper","neighbors_gold":return p.board.size()>1
		"hammer","shakers","murky":return not p.board.is_empty()
		"left_deathrattles":return p.board.any(func(v):return engine.Triggers.has_deathrattle(engine,v))
		"rallies":return p.board.any(func(v):return engine.Triggers.effects(engine,v).any(func(x):return x.get("trigger","")=="rally"))
		"upgrade_effect":return int(source.get(str(e.get("field","discovery_tier")),e.get("initial",1)))<int(e.get("maximum",6))
		"tier_growth":return int(source.get("strategic_tier",1))<6
		"coin_cap":return int(p.get("cap_bonus",0))<int(engine.content.rules.get("coin_cap_limit",1000000))
	return op in ["self_buff","give","cost_spells","spell_strength","parents","undead_attack"]
static func countdown_gifts(engine,card: Dictionary) -> Dictionary:
	var starts=false;var ends=false;var due=false
	for g in engine.card_gifts(card):
		var id=int(g.id)
		if id==19:starts=true
		if id in [2,9,11,21,25,27]:
			ends=true
			if id in [9,11]:due=due or (int(engine.state.round)-int(g.acquired_round)+1)%2==0
			elif id==27:due=due or (not g.get("doubled",false) and int(engine.state.round)-int(g.acquired_round)>=2)
			else:due=true
	return {"start":starts,"end":ends,"due":due}
static func death_count(engine,owner: int,cutoff: int) -> int:
	# Trinket avenge counters reset at each combat start. Count only the shown
	# combat's actual friendly MinionDied events, not the already-resolved future.
	var count=0
	for event in engine.events:
		if int(event.seq)>cutoff:break
		if int(event.get("round",0))!=int(engine.state.round) or event.get("phase","")!="combat":continue
		if event.kind=="MinionDied" and int(event.owner)==owner:count+=1
	return count
static func triggers(engine,p: Dictionary,source: Dictionary,effects: Array,combat: bool,cutoff: int=-1) -> Array:
	var result=[];var starts=false;var ends=false;var due=false;var revenge=[]
	for e in effects:
		match str(e.get("trigger","")):
			"turn_start","obtain_and_start":starts=true
			"turn_end":ends=true;due=due or end_ready(engine,p,source,e)
			"avenge":
				var threshold=int(e.get("threshold",0));var field="avenge_"+str(e.get("handler",""))
				var progress=int(source.get(field,0))
				if source.has("id") and not source.has("def_id") and combat and cutoff>=0:progress=death_count(engine,int(p.id),cutoff)%maxi(1,threshold)
				revenge.append({"handler":e.get("handler",""),"threshold":threshold,"progress":progress,"remaining":threshold-progress})
	if source.has("def_id"):
		var gifts=countdown_gifts(engine,source);starts=starts or gifts.start;ends=ends or gifts.end;due=due or gifts.due
	if starts:result.append(item("TURN_START"))
	if ends:result.append(item("TURN_END","active",not combat and due))
	if not revenge.is_empty():result.append(item("AVENGE","active",combat and revenge.any(func(v):return int(v.remaining)==1),revenge))
	if source.has("id") and not source.has("def_id") and effects.any(func(e):return e.get("trigger","")=="combat_start" and e.get("handler","")!="first_deathrattle"):result.append(item("COMBAT_START"))
	return result
static func card(engine,card_value: Dictionary,zone: String,cutoff: int=-1) -> Dictionary:
	var result={"body":[],"markers":[],"capabilities":[],"event_keys":[]}
	var d=engine.content.get_def(str(card_value.get("def_id","")))
	if d.get("kind","")!="minion" or not alive(card_value):return result
	var effects=engine.Triggers.effects(engine,card_value);var effective=keys(engine,card_value)
	var p=engine.state.players[int(card_value.get("owner",0))]
	for key in ["TAUNT","DIVINE_SHIELD","REBORN","WINDFURY","STEALTH"]:
		if key in effective:result.body.append(key)
	for key in ["VENOMOUS","POISONOUS"]:
		if key in effective:result.markers.append(item(key))
	if engine.Triggers.has_deathrattle(engine,card_value):result.markers.append(item("DEATHRATTLE"))
	var native=effects.any(func(e):return e.get("trigger","")=="activate")
	if native or card_value.get("gold_route","")=="恶魔":
		var q=engine.activate_availability(int(p.id),int(card_value.instance_id),"native" if native else "gold")
		var used=q.get("reason","")=="ALREADY_ACTIVATED" or int(card_value.get("activated_round",-1))==int(engine.state.round)
		result.markers.append(item("ACTIVATE","used" if used else "available" if q.available and zone=="board" else "unavailable"))
	for pair in [["battlecry","BATTLECRY"],["rally","RALLY"],["sell","SELL_TRIGGER"],["combat_start","COMBAT_START"]]:
		if effects.any(func(e):return e.get("trigger","")==pair[0]):result.markers.append(item(pair[1]))
	if not result.markers.any(func(v):return v.key=="RALLY") and engine.card_gifts(card_value).any(func(g):return int(g.id) in [8,22,31]):result.markers.append(item("RALLY"))
	if not result.markers.any(func(v):return v.key=="COMBAT_START") and (effects.any(func(e):return e.get("op","")=="opening_damage") or engine.card_gifts(card_value).any(func(g):return int(g.id) in [17,34,35,36,37])):result.markers.append(item("COMBAT_START"))
	if card_value.get("immune_attacking",false) or effects.any(func(e):return e.get("handler","")=="attack_immune") or engine.card_gifts(card_value).any(func(g):return int(g.id)==44):result.markers.append(item("IMMUNE_ATTACK"))
	result.markers.append_array(triggers(engine,p,card_value,effects,zone=="combat",cutoff))
	if zone!="board" or engine.state.phase!="recruit" or not p.alive or not p.board.any(func(v):return int(v.instance_id)==int(card_value.instance_id)):
		for entry in result.markers:
			if entry.key=="TURN_END":entry.glow=false
	for pair in [["magnetic","MAGNETIC"],["spellcraft","SPELLCRAFT"],["cleave","CLEAVE"]]:
		if effects.any(func(e):return e.get("handler","")==pair[0] or e.get("trigger","")==pair[0] or e.get("op","")==pair[0]):result.event_keys.append(pair[1])
	if engine.Quilboar.choice(d):result.event_keys.append("CHOOSE_ONE")
	result.capabilities=result.body.duplicate()
	for marker in result.markers:
		if marker.key not in result.capabilities:result.capabilities.append(marker.key)
	result.capabilities.append_array(result.event_keys)
	# Hand cards use the real core silhouette at the original art size. No badge
	# shelf: small/static/event capability details remain in existing inspection.
	if zone=="hand":result.markers=[]
	return result
static func power(engine,p: Dictionary,slot: Dictionary,combat: bool,cutoff: int=-1) -> Array:
	var id=str(slot.get("active_power_id",""));var d=engine.content.get_def(id)
	var result=triggers(engine,p,slot.get("progress",{}),d.get("effects",[]),combat,cutoff)
	# Native power implementations encode these lifecycle hooks in their handlers.
	if id in engine.Powers.START_BORROWS or id in ["TB_BaconShop_HP_008","BG20_HERO_202p","BG35_HERO_001p"]:
		if not result.any(func(v):return v.key=="TURN_START"):result.append(item("TURN_START"))
	if id in ["TB_BaconShop_HP_076","BG26_HERO_104p"]:
		var ready=id=="TB_BaconShop_HP_076" or (int(engine.state.round)%3==0 and not p.hand.is_empty())
		result.append(item("TURN_END","active",not combat and ready))
	if id=="BG22_HERO_305p":
		var progress=death_count(engine,int(p.id),cutoff)%4 if combat and cutoff>=0 else int(p.get("onyxia_avenge",0))
		result.append(item("AVENGE","active",combat and progress==3,[{"threshold":4,"progress":progress,"remaining":4-progress}]))
	if id in ["TB_BaconShop_HP_069","BG20_HERO_282p","BG22_HERO_001p","TB_BaconShop_HP_086","BG25_HERO_103p"] and not result.any(func(v):return v.key=="COMBAT_START"):result.append(item("COMBAT_START"))
	return result
