extends RefCounted

static func common(engine,p: Dictionary,cost: int,plan: Dictionary) -> Dictionary:
	var life=bool(plan.life)
	var damage=engine.Demons.hurt_preview(p,cost if life else 0)
	var reason=""
	if engine.state.phase!="recruit" or not p.alive:reason="WRONG_PHASE"
	elif not p.choices.is_empty():reason="MANDATORY_CHOICE"
	elif life and int(p.health)<cost-mini(int(p.armor),cost):reason="NOT_ENOUGH_HEALTH"
	elif not life and int(p.coins)<cost:reason="NOT_ENOUGH_COINS"
	var rewind=p.board.any(func(c):return not engine.Demons.specs(engine,c,"rewind").is_empty() or not engine.Demons.specs(engine,c,"corrosion").is_empty())
	return {"cost":cost,"plan":plan,"life":life,"damage":damage,"reason":reason,"available":reason=="","rewind":rewind,"source_id":"","remaining":-1}
static func refresh(engine,p: Dictionary) -> Dictionary:
	if p.trinkets.any(func(v):return v.id=="BG35_MagicItem_930" and v.get("whistle_ready",false)):
		var facts=common(engine,p,0,{"life":false});facts.merge({"kind":"refresh","free":true,"free_count":int(p.free_refresh),"prince_quotas":[],"prince_total":0,"source_id":"BG35_MagicItem_930","remaining":1},true);return facts
	var cost=0 if int(p.free_refresh)>0 else 1
	var plan=engine.Demons.refresh_payment(engine,p,cost)
	var result=common(engine,p,cost,plan);result["kind"]="refresh";result["free"]=cost==0
	result["free_count"]=maxi(0,int(p.free_refresh));result["prince_quotas"]=[]
	for c in p.board:
		var specs=engine.Demons.specs(engine,c,"prince")
		if specs.is_empty():continue
		var limit=int(specs[0].amount);var used=int(c.get("prince_used",0)) if int(c.get("prince_round",-1))==int(engine.state.round) else 0
		result.prince_quotas.append({"instance_id":c.instance_id,"id":c.def_id,"remaining":maxi(0,limit-used)})
	result["prince_total"]=result.prince_quotas.reduce(func(total,q):return total+int(q.remaining),0)
	if plan.has("card"):
		var c=plan.card;result.source_id=str(c.def_id)
		var limit=int(engine.Demons.specs(engine,c,"prince")[0].amount)
		result.remaining=limit-(int(c.get("prince_used",0)) if int(c.get("prince_round",-1))==int(engine.state.round) else 0)
	return result
static func buy(engine,p: Dictionary,c: Dictionary) -> Dictionary:
	if c.is_empty():return {"available":false,"reason":"WRONG_PHASE" if engine.state.phase!="recruit" or not p.alive else "MANDATORY_CHOICE" if not p.choices.is_empty() else "CARD_NOT_IN_SHOP"}
	var d=engine.content.get_def(c.def_id);var plan=engine.Demons.payment(engine,p,d)
	var result=common(engine,p,engine.Fish.purchase_cost(engine,p,c,engine.Naga.power_cost(engine,p,d)),plan);result["kind"]="buy";result["free"]=int(result.cost)==0
	if result.reason not in ["WRONG_PHASE","MANDATORY_CHOICE"]:
		if engine.find_index(p.shop,int(c.instance_id))<0:result.reason="CARD_NOT_IN_SHOP"
		elif p.hand.size()>=int(engine.content.rules.hand_limit):result.reason="HAND_FULL"
	result.available=result.reason==""
	if plan.has("item"):
		result.source_id=str(plan.item.id);result.remaining=1
	elif result.life:result.source_id=str(d.id)
	return result
static func play(engine,p: Dictionary,c: Dictionary) -> Dictionary:
	var d=engine.content.get_def(c.def_id);var hits=0;var sources=[];var discoveries=0
	if d.kind=="minion":
		for listener in p.board:
			for e in engine.Triggers.effects(engine,listener):
				if e.get("handler","")!="round10" or e.get("op","")!="weaver" or e.get("trigger","")!="minion_played":continue
				if e.get("exclude_source",false) and int(listener.instance_id)==int(c.instance_id):continue
				if "恶魔" not in d.card_types and "全部种族" not in d.card_types:continue
				hits+=int(e.amount);sources.append(str(listener.def_id))
		for e in engine.Triggers.effects(engine,c):
			if e.get("handler","")=="round10" and e.get("op","")=="damage_discover" and e.get("trigger","")=="battlecry":discoveries+=int(e.amount)*engine.Triggers.times(engine,p,"battlecry")
	var eligible=engine.state.phase=="recruit" and p.alive and p.choices.is_empty() and not engine.CardLock.locked(engine,p,c) and engine.find_index(p.hand,int(c.instance_id))>=0
	return {"trigger_hits":hits,"sources":sources,"discoveries":discoveries,"immune":bool(p.get("hero_immune",false)),"active":eligible and (hits>0 or discoveries>0),"damage":engine.Demons.hurt_preview(p,hits)}
