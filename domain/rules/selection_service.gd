extends RefCounted
const Choices=preload("res://domain/rules/choice_service.gd")
const Special=preload("res://domain/rules/special_rules.gd")
const RNG=preload("res://domain/rules/deterministic_rng.gd")
const Offering=preload("res://domain/rules/trinket_offering.gd")
const GIFT_PURCHASE_LIMIT=3
static func generate(engine,p: Dictionary,kind: String,excluded: Array) -> Array:
	if kind=="gift":
		var minions=[]
		for id in engine.content.pool("minion",engine.state.enabled_tribes): minions.append(engine.content.get_def(id))
		var gifts=[]
		for id in engine.content.definitions:
			var d=engine.content.get_def(id)
			if d.kind=="dark_gift" and d.implemented: gifts.append({"id":int(d.numeric_id),"min_turn":d.min_turn,"max_turn":d.max_turn})
		var preference=Special.preference(p.hand,p.board,engine.content.definitions,engine.state.enabled_tribes)
		return Choices.gift_options(minions,gifts,int(engine.state.round),engine.state.enabled_tribes,excluded,engine.state.streams,{"player":p,"enabled":engine.state.enabled_tribes,"guaranteed_tribe":preference})
	var options=Offering.generate(engine,p,kind,excluded)
	for option in options:
		if engine.content.get_def(option.id).get("bind_tribe",false) and option.bound_tribe=="":
			var eligible=[]
			for tribe in engine.state.enabled_tribes:
				for id in engine.content.pool("minion",engine.state.enabled_tribes):
					if tribe in engine.content.get_def(id).card_types:
						eligible.append(tribe); break
			if eligible.is_empty(): return []
			option.bound_tribe=eligible[RNG.next(engine.state.streams,"choice",eligible.size())]
	return options
static func gift_readiness(engine,p: Dictionary) -> Dictionary:
	var minions=[]
	for id in engine.content.pool("minion",engine.state.enabled_tribes): minions.append(engine.content.get_def(id))
	var gifts=[]
	for id in engine.content.definitions:
		var d=engine.content.get_def(id)
		if d.kind=="dark_gift" and d.implemented: gifts.append({"id":int(d.numeric_id),"min_turn":d.min_turn,"max_turn":d.max_turn})
	var tiers=Special.regular_tiers(int(engine.state.round))
	var candidates=Choices.gift_candidates(minions,gifts,int(engine.state.round),engine.state.enabled_tribes,[],{"player":p,"enabled":engine.state.enabled_tribes})
	var by_tier={}
	for tier in tiers: by_tier[str(tier)]=0
	for candidate in candidates:
		var tier=int(engine.content.get_def(str(candidate.id)).tier)
		by_tier[str(tier)]=int(by_tier.get(str(tier),0))+1
	return {"source":"regular_button","used":int(p.gifts_bought),"limit":GIFT_PURCHASE_LIMIT,"turn":int(engine.state.round),"allowed_tiers":tiers,"candidate_count":candidates.size(),"candidates_by_tier":by_tier,"options_locked":p.sessions.has("gift") and not p.sessions.gift.resolved,"locked_count":p.sessions.gift.options.size() if p.sessions.has("gift") and not p.sessions.gift.resolved else 0,"openable":candidates.size()>=3}
static func command(engine,p: Dictionary,kind: String,args: Dictionary) -> String:
	var category=str(args.get("category",""))
	if category!="gift":return engine.R13Items.command(engine,p,kind,args)
	if category not in ["lesser","greater","gift"]: return "INVALID_CHOICE_CATEGORY"
	if kind=="open_choice":
		if p.sessions.has(category) and not p.sessions[category].resolved:
			p.sessions[category].deferred=false; return ""
		if category!="gift":
			if int(engine.state.round)<(6 if category=="lesser" else 9): return "CHOICE_LOCKED"
			for trinket in p.trinkets:
				if trinket.get("slot_size",trinket.size)==category: return "TRINKET_ALREADY_OWNED"
		else:
			if int(engine.state.round)<3: return "CHOICE_LOCKED"
			if int(p.gifts_bought)>=GIFT_PURCHASE_LIMIT or int(p.gift_round)==int(engine.state.round): return "GIFT_LIMIT"
			if not p.pending_rewards.is_empty(): return "PENDING_REWARDS"
			if int(p.coins)<3: return "NOT_ENOUGH_COINS"
		var options=generate(engine,p,category,[])
		if options.size()!=(3 if category=="gift" else 4): return "INSUFFICIENT_IMPLEMENTED_CANDIDATES"
		p.sessions[category]={"kind":category,"options":options,"created_round":engine.state.round,"refreshes":0,"resolved":false,"deferred":false}
		engine.Choices.paid_identity(engine,p,p.sessions[category])
		if category=="gift":
			p.coins-=3; p.gifts_bought+=1; p.gift_round=engine.state.round
			engine.Elementals.spent(engine,p,3)
		engine.emit("ChoiceOpened",int(p.id),{"kind":category,"options":options})
		return ""
	if not p.sessions.has(category) or p.sessions[category].resolved: return "NO_CHOICE"
	var session=p.sessions[category]
	if kind=="defer_choice": session.deferred=true; return ""
	if kind=="refresh_choice":
		var global_count=int(p.gift_refreshes if category=="gift" else p.trinket_refreshes)
		if not Choices.refresh_allowed(category,int(session.refreshes),global_count): return "CHOICE_REFRESH_LIMIT"
		var cost=Choices.refresh_cost(category,global_count)
		if p.coins<cost: return "NOT_ENOUGH_COINS"
		var excluded=[]
		for option in session.options: excluded.append(option.id)
		var options=generate(engine,p,category,excluded)
		if options.size()!=session.options.size(): return "INSUFFICIENT_IMPLEMENTED_CANDIDATES"
		p.coins-=cost; session.options=options; session.refreshes+=1
		engine.Elementals.spent(engine,p,cost)
		if category=="gift": p.gift_refreshes+=1
		else: p.trinket_refreshes+=1
		engine.emit("ChoiceRefreshed",int(p.id),{"kind":category,"cost":cost}); return ""
	if kind=="resolve_choice":
		var index=int(args.get("index",-1))
		if index<0 or index>=session.options.size(): return "INVALID_OPTION"
		var option=session.options[index]
		if category=="gift":
			var card=engine.make_card(option.id,int(p.id))
			engine.Gifts.acquire(engine,p,card,int(option.gift_id))
			engine.receive_card(p,card,engine.Acquisition.context(engine,{},"paid_gift"))
			
		else:
			if not engine.R13Items.allowed(engine,p,engine.content.get_def(option.id)):return "STALE_TRINKET_CANDIDATE"
			if int(p.coins)<int(option.cost): return "NOT_ENOUGH_COINS"
			p.coins-=int(option.cost)
			engine.Elementals.spent(engine,p,int(option.cost))
			var installed={"id":option.id,"bound_tribe":option.bound_tribe,"size":category,"slot_size":category}
			p.trinkets.append(installed)
			engine.trinket_effects(p,"obtain",{},installed)
		session.resolved=true; session.deferred=true
		engine.check_triples(p)
		engine.emit("ChoiceResolved",int(p.id),{"kind":category,"id":option.id}); return ""
	return "UNKNOWN_CHOICE_COMMAND"
static func close_recruit(engine,p: Dictionary) -> void:
	if p.sessions.has("gift") and not p.sessions.gift.resolved:
		var index=RNG.next(engine.state.streams,"choice",p.sessions.gift.options.size())
		command(engine,p,"resolve_choice",{"category":"gift","index":index})
		engine.emit("GiftAutoResolved",int(p.id),{"index":index})
	for category in ["lesser","greater","marin","voucher","buttons"]:
		if p.sessions.has(category): p.sessions[category].deferred=true

