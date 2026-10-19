extends RefCounted
const MARIN="BG30_HERO_304p"
const BUTTONS="BG32_HERO_002p"
static func ensure(p: Dictionary) -> void:
	if not p.has("r136_slots"):p["r136_slots"]={"opportunities":{},"seq":0,"cube_sources":[]}
static func owner(s: Dictionary) -> Dictionary:
	return {"slot_id":int(s.slot_id),"epoch":int(s.epoch),"power_id":str(s.active_power_id)}
static func owner_valid(engine,p: Dictionary,o: Dictionary) -> bool:
	if o.is_empty():return true
	var s=engine.Powers.selected(engine,p,int(o.slot_id))
	return not s.is_empty() and int(s.epoch)==int(o.epoch) and str(s.active_power_id)==str(o.power_id)
static func owner_suspended(engine,p: Dictionary,o: Dictionary) -> bool:
	if o.is_empty():return false
	var s=engine.Powers.selected(engine,p,int(o.slot_id));var restore=s.get("temporary_restore",{})
	return restore.get("power_id","")==o.power_id and int(restore.get("epoch",-1))==int(o.epoch)
static func key(o: Dictionary) -> String:
	return "power:%d:%d" % [int(o.slot_id),int(o.epoch)]
static func create(engine,p: Dictionary,o: Dictionary,size: String,unlock: int,coins: bool=false) -> String:
	ensure(p);var id=key(o)
	if not p.r136_slots.opportunities.has(id):
		p.r136_slots.opportunities[id]={"owner":o,"category":id,"base_size":size,"unlock_round":unlock,"coins_due":coins,"coins_receipt":false,"purchased":false,"cancelled":false}
	return id
static func sync(engine,p: Dictionary) -> void:
	ensure(p)
	for s in p.get("power_slots",[]):
		if s.active_power_id in [MARIN,BUTTONS]:create(engine,p,owner(s),"lesser" if s.active_power_id==MARIN else "greater",5 if s.active_power_id==MARIN else 8)
static func reward_opportunity(engine,p: Dictionary,q: Dictionary) -> String:
	return create(engine,p,{"slot_id":int(q.slot_id),"epoch":int(q.epoch),"power_id":engine.R135.POWER},"lesser" if q.reward_id=="BG33_Reward_014" else "greater",int(engine.state.round)+1,true)
static func start(engine,p: Dictionary) -> void:
	sync(engine,p)
	sync_vouchers(engine,p)
	for op in p.r136_slots.opportunities.values():
		if op.cancelled or op.purchased or not owner_valid(engine,p,op.owner):continue
		if op.coins_due and not op.coins_receipt and int(engine.state.round)>=int(op.unlock_round):
			op.coins_receipt=true;engine.gain_coins(p,4);engine.emit("RewardTrinketCoinsGranted",int(p.id),{"opportunity":op.category,"amount":4,"owner":op.owner})
static func normalize(engine,p: Dictionary,category: String) -> String:
	if category=="voucher":
		var candidates=p.get("voucher_sources",[p.voucher_source] if p.has("voucher_source") else []).filter(func(iid):return not engine.R13Items.item(engine,p,int(iid)).is_empty())
		return "voucher:"+str(candidates[0]) if not candidates.is_empty() else "voucher"
	if category not in ["marin","buttons"]:return category
	var power=MARIN if category=="marin" else BUTTONS
	var selected=engine.Powers.selected(engine,p)
	if selected.get("active_power_id","")==power:return key(owner(selected))
	for s in p.power_slots:
		if s.active_power_id==power:return key(owner(s))
	return "invalid:"+category
static func opportunity(engine,p: Dictionary,category: String) -> Dictionary:
	ensure(p);return p.r136_slots.opportunities.get(normalize(engine,p,category),{})
static func available(engine,p: Dictionary,category: String) -> bool:
	var id=normalize(engine,p,category);var op=opportunity(engine,p,id)
	if not op.is_empty():return not op.cancelled and not op.purchased and owner_valid(engine,p,op.owner) and int(engine.state.round)>=int(op.unlock_round)
	if id.begins_with("power:") or id.begins_with("invalid:"):return false
	if id.begins_with("voucher:"):
		var source=engine.R13Items.item(engine,p,int(id.trim_prefix("voucher:")))
		return voucher_ready(engine,p,source) and (not p.sessions.has(id) or not p.sessions[id].resolved)
	if p.sessions.has(id):return not p.sessions[id].resolved
	if id=="voucher":return false
	return id in ["lesser","greater"] and int(engine.state.round)>=(6 if id=="lesser" else int(p.get("greater_unlock",9)))
static func installed(engine,p: Dictionary,slot_id: int) -> Dictionary:
	for c in p.trinkets:
		var o=c.get("power_owner",{})
		if not o.is_empty() and int(o.slot_id)==slot_id and owner_valid(engine,p,o):return c
	return {}
static func power_op(engine,p: Dictionary,slot_id: int) -> String:
	ensure(p)
	var voucher=voucher_category(engine,p,installed(engine,p,slot_id))
	if voucher!="":return voucher
	var s=engine.Powers.selected(engine,p,slot_id)
	if s.is_empty():return ""
	var id=key(owner(s))
	return id if available(engine,p,id) else ""
static func loss(engine,p: Dictionary,s: Dictionary) -> void:
	ensure(p)
	
	for op in p.r136_slots.opportunities.values():
		if int(op.owner.slot_id)==int(s.slot_id) and int(op.owner.epoch)==int(s.epoch):
			op.cancelled=true
			if p.sessions.has(op.category):p.sessions[op.category].resolved=true;p.sessions[op.category]["cancelled"]=true
	var removed=p.trinkets.filter(func(c):return c.has("power_owner") and int(c.power_owner.slot_id)==int(s.slot_id) and int(c.power_owner.epoch)==int(s.epoch))
	var ids=removed.map(func(c):return int(c.instance_id))
	p.choices=p.choices.filter(func(c):return int(c.get("source_instance",-1)) not in ids)
	if int(p.get("voucher_source",-1)) in ids:
		p.erase("voucher_source")
		if p.sessions.has("voucher"):p.sessions.voucher.resolved=true;p.sessions.voucher["cancelled"]=true
	p["voucher_sources"]=p.get("voucher_sources",[]).filter(func(iid):return int(iid) not in ids)
	if not p.voucher_sources.is_empty():p["voucher_source"]=p.voucher_sources[0]
	for session in p.sessions.values():
		if int(session.get("voucher_instance",-1)) in ids:session.resolved=true;session["cancelled"]=true
	p.r136_slots.cube_sources=p.r136_slots.cube_sources.filter(func(c):return not (int(c.owner.get("slot_id",-1))==int(s.slot_id) and int(c.owner.get("epoch",-1))==int(s.epoch)))
	p.trinkets=p.trinkets.filter(func(c):return int(c.get("instance_id",-1)) not in ids)
	if removed.any(func(c):return engine.content.get_def(c.id).effects.any(func(e):return e.get("op","") in ["iceblock","safety"])):
		if not p.trinkets.any(func(c):return engine.content.get_def(c.id).effects.any(func(e):return e.get("op","") in ["iceblock","safety"])):p.erase("iceblock")
	
	engine.emit("PowerTrinketSourceRemoved",int(p.id),{"slot_id":s.slot_id,"epoch":s.epoch,"instances":ids})
static func suspend(engine,p: Dictionary,s: Dictionary) -> void:
	
	var items=p.trinkets.filter(func(c):return c.has("power_owner") and int(c.power_owner.slot_id)==int(s.slot_id) and int(c.power_owner.epoch)==int(s.epoch))
	s.progress["paused_trinkets"]=items.duplicate(true);p.trinkets=p.trinkets.filter(func(c):return c not in items)
static func restore(engine,p: Dictionary,s: Dictionary,old_epoch: int) -> void:
	ensure(p)
	for c in s.progress.get("paused_trinkets",[]):c.power_owner.epoch=s.epoch;p.trinkets.append(c)
	s.progress.erase("paused_trinkets")
	var old_key="power:%d:%d" % [int(s.slot_id),old_epoch]
	if p.r136_slots.opportunities.has(old_key):
		var op=p.r136_slots.opportunities[old_key];op.owner.epoch=s.epoch;var id=key(op.owner);op.category=id;p.r136_slots.opportunities[id]=op;p.r136_slots.opportunities.erase(old_key)
		if p.sessions.has(old_key):p.sessions[id]=p.sessions[old_key];p.sessions.erase(old_key);p.sessions[id].power_owner=op.owner.duplicate(true);p.sessions[id].revision+=1
	if p.get("r135",{}).get("slots",{}).has(str(s.slot_id)):
		var q=p.r135.slots[str(s.slot_id)]
		if int(q.epoch)==old_epoch:
			q.epoch=s.epoch
			if q.has("child"):q.child.epoch=s.epoch
			if q.reward_state.has("opportunity"):q.reward_state.opportunity=key(owner(s))
	for src in p.r136_slots.cube_sources:
		if int(src.owner.get("slot_id",-1))==int(s.slot_id) and int(src.owner.get("epoch",-1))==old_epoch:src.owner.epoch=s.epoch
	for session in p.sessions.values():
		var o=session.get("power_owner",{})
		if int(o.get("slot_id",-1))==int(s.slot_id) and int(o.get("epoch",-1))==old_epoch:o.epoch=s.epoch;session.revision+=1
static func orb_ready(p: Dictionary) -> bool:
	return p.trinkets.any(func(c):return c.id=="BG35_MagicItem_818" and c.get("orb_ready",false))
static func eligible_orb(category: String) -> bool:
	return category not in ["marin","buttons"]
static func adjust_orb(engine,p: Dictionary) -> void:
	for category in p.sessions:
		var session=p.sessions[category]
		if category=="gift" or session.resolved or not session.has("base_size"):continue
		var convert=orb_ready(p) and session.base_size=="greater" and session.get("orb_eligible",true)
		if convert and session.offered_size!="lesser":
			if not session.has("converted_options"):
				var options=engine.Selection.generate(engine,p,"lesser",[])
				if options.size()!=4:continue
				session["converted_options"]=options
			session.options=session.converted_options.duplicate(true);session.offered_size="lesser";session.revision+=1
		elif not convert and session.offered_size!=session.base_size:
			session.options=session.original_options.duplicate(true);session.offered_size=session.base_size;session.revision+=1
static func command(engine,p: Dictionary,kind: String,args: Dictionary) -> String:
	sync_vouchers(engine,p)
	var raw=str(args.get("category",""));var category=normalize(engine,p,raw);var op=opportunity(engine,p,category)
	var voucher=category.begins_with("voucher:")
	if category not in ["lesser","greater"] and not voucher and op.is_empty():return "INVALID_CHOICE_CATEGORY"
	if not op.is_empty() and (op.cancelled or not owner_valid(engine,p,op.owner)):return "STALE_POWER_TRINKET_OWNER"
	if kind=="open_choice":
		if voucher and not voucher_ready(engine,p,engine.R13Items.item(engine,p,int(category.trim_prefix("voucher:")))):return "CHOICE_LOCKED"
		if p.sessions.has(category):
			if p.sessions[category].resolved:return "TRINKET_ALREADY_OWNED"
			p.sessions[category].deferred=false;return ""
		if not available(engine,p,category):return "CHOICE_LOCKED"
		var base=str(op.base_size) if not op.is_empty() else "lesser" if category=="lesser" else "greater"
		var source=engine.R13Items.item(engine,p,int(category.trim_prefix("voucher:"))) if voucher else {}
		var options=engine.Selection.generate(engine,p,base,[])
		if options.size()!=4:return "INSUFFICIENT_IMPLEMENTED_CANDIDATES"
		var o=op.get("owner",{}).duplicate(true) if not voucher else source.get("power_owner",{}).duplicate(true)
		p.sessions[category]={"kind":category,"base_size":base,"offered_size":base,"original_options":options.duplicate(true),"options":options,"created_round":engine.state.round,"refreshes":0,"revision":0,"require_revision":true,"resolved":false,"deferred":false,"power_owner":o,"orb_eligible":op.get("owner",{}).get("power_id","") not in [MARIN,BUTTONS],"voucher_instance":source.get("instance_id",-1)}
		engine.Choices.paid_identity(engine,p,p.sessions[category]);adjust_orb(engine,p);return ""
	if not p.sessions.has(category) or p.sessions[category].resolved:return "NO_CHOICE"
	var session=p.sessions[category]
	if not owner_valid(engine,p,session.get("power_owner",{})):return "STALE_POWER_TRINKET_OWNER"
	if args.has("session_id") and str(args.session_id)!=str(session.session_id):return "STALE_CHOICE"
	if kind=="defer_choice":session.deferred=true;return ""
	if kind=="refresh_choice":
		if not engine.Selection.Choices.refresh_allowed(session.base_size,int(session.refreshes),int(p.trinket_refreshes)):return "CHOICE_REFRESH_LIMIT"
		var cost=engine.Selection.Choices.refresh_cost(session.base_size,int(p.trinket_refreshes))
		if int(p.coins)<cost:return "NOT_ENOUGH_COINS"
		var options=engine.Selection.generate(engine,p,session.offered_size,session.options.map(func(v):return v.id))
		if options.size()!=4:return "INSUFFICIENT_IMPLEMENTED_CANDIDATES"
		p.coins-=cost;engine.Elementals.spent(engine,p,cost);session.options=options;session.refreshes+=1;session.revision+=1;p.trinket_refreshes+=1
		if session.offered_size!=session.base_size:session.converted_options=options.duplicate(true)
		else:session.original_options=options.duplicate(true)
		return ""
	if kind!="resolve_choice":return "UNKNOWN_CHOICE_COMMAND"
	if int(args.get("revision",-1))!=int(session.revision):return "STALE_CHOICE"
	var index=int(args.get("index",-1))
	if index<0 or index>=session.options.size():return "INVALID_OPTION"
	var option=session.options[index]
	if args.has("option_id") and str(args.option_id)!=str(option.id):return "STALE_CHOICE"
	if not engine.R13Items.allowed(engine,p,engine.content.get_def(option.id)):return "STALE_TRINKET_CANDIDATE"
	if int(p.coins)<int(option.cost):return "NOT_ENOUGH_COINS"
	var old=int(session.get("voucher_instance",-1));var slot=category
	if voucher:
		var original=engine.R13Items.item(engine,p,old)
		if original.is_empty() or old not in p.get("voucher_sources",[]):return "TRINKET_SOURCE_MISSING"
		slot=str(original.slot_size)
	p.coins-=int(option.cost);engine.Elementals.spent(engine,p,int(option.cost));session.resolved=true;session.deferred=true
	if not op.is_empty():op.purchased=true
	var consume=orb_ready(p) and session.orb_eligible
	if consume:
		for c in p.trinkets:
			if c.id=="BG35_MagicItem_818" and c.get("orb_ready",false):c.orb_ready=false
	var stands=p.trinkets.filter(func(c):return c.id=="BG30_MagicItem_888").duplicate()
	engine.R13Items.install(engine,p,option.id,slot,option.bound_tribe,old,session.get("power_owner",{}))
	if voucher:
		p.voucher_sources.erase(old)
		if int(p.get("voucher_source",-1))==old:p.erase("voucher_source")
		if not p.voucher_sources.is_empty():p["voucher_source"]=p.voucher_sources[0]
	if engine.content.get_def(option.id).size=="greater":
		for c in stands:engine.R13Items.install(engine,p,option.id,str(c.slot_size),option.bound_tribe,int(c.instance_id))
	adjust_orb(engine,p);engine.check_triples(p);engine.emit("ChoiceResolved",int(p.id),{"kind":category,"id":option.id});return ""
static func voucher_ready(engine,p: Dictionary,c: Dictionary) -> bool:
	return c.get("id","")=="BG30_MagicItem_891" and owner_valid(engine,p,c.get("power_owner",{})) and (c.get("voucher_open",false) or int(engine.state.round)>=int(c.get("acquired_round",c.get("next_round",int(engine.state.round)+2)-2))+2)
static func voucher_category(engine,p: Dictionary,c: Dictionary) -> String:
	var id="voucher:"+str(c.get("instance_id",-1))
	return id if voucher_ready(engine,p,c) and (not p.sessions.has(id) or not p.sessions[id].resolved) else ""
static func sync_vouchers(engine,p: Dictionary) -> void:
	var ids=[]
	for c in p.trinkets:
		if not voucher_ready(engine,p,c):continue
		c["voucher_open"]=true;c["next_round"]=int(c.get("acquired_round",c.get("next_round",int(engine.state.round))-2))+2
		ids.append(int(c.instance_id))
	p["voucher_sources"]=ids
	if ids.is_empty():p.erase("voucher_source")
	else:p["voucher_source"]=ids[0]
static func cube(engine,p: Dictionary,c: Dictionary) -> void:
	ensure(p);var o=c.get("power_owner",{}).duplicate(true)
	if not p.r136_slots.cube_sources.any(func(v):return v.slot==c.slot_size and v.owner==o):p.r136_slots.cube_sources.append({"slot":c.slot_size,"owner":o})
static func cube_start(engine,p: Dictionary) -> void:
	ensure(p)
	for src in p.r136_slots.cube_sources:
		if not owner_valid(engine,p,src.owner):continue
		var sources=p.trinkets.filter(func(c):return c.slot_size==src.slot and c.get("power_owner",{})==src.owner)
		if not sources.is_empty() and not p.choices.any(func(c):return c.kind=="r13_replace" and int(c.source_instance)==int(sources[0].instance_id)):engine.R13Items.random_replacement(engine,p,sources[0],"lesser",true)
static func validate(engine,p: Dictionary) -> String:
	if not p.has("r136_slots"):return ""
	if not p.r136_slots.get("opportunities") is Dictionary or not p.r136_slots.get("cube_sources") is Array:return "INVALID_TRINKET_LEDGER"
	for op in p.r136_slots.opportunities.values():
		if not op.get("owner") is Dictionary or op.get("base_size","") not in ["lesser","greater"] or int(op.get("unlock_round",0))<1:return "INVALID_TRINKET_OPPORTUNITY"
		if not op.cancelled and not owner_valid(engine,p,op.owner) and not owner_suspended(engine,p,op.owner):return "STALE_TRINKET_OWNER"
	for c in p.trinkets:
		if c.has("power_owner") and not owner_valid(engine,p,c.power_owner):return "STALE_TRINKET_OWNER"
	for s in p.sessions.values():
		if s.get("resolved",false) or not s.has("base_size"):continue
		if not owner_valid(engine,p,s.get("power_owner",{})) and not owner_suspended(engine,p,s.get("power_owner",{})):return "STALE_TRINKET_SESSION"
		if s.options.size()!=4 or s.original_options.size()!=4 or int(s.refreshes)<0 or int(s.revision)<0:return "INVALID_TRINKET_SESSION"
	return ""
