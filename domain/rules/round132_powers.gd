extends RefCounted
const ExternalText = preload("res://domain/resources/external_content.gd")
# Source eligibility only; ordinary affordability, targets and passive status
# are not unlock conditions. Other acquisition sources retain their policy.
const NGUYEN_MIN_ROUND={"BG22_HERO_002p":7,"BG22_HERO_003p":7,"BG23_HERO_306p":3,"BG31_HERO_006p":3,"TB_BaconShop_HP_022":3}
const NGUYEN_MIN_TIER={"TB_BaconShop_HP_015":4}
const NGUYEN_GAME_USE_LIMITS={"BG31_HERO_005p":1,"TB_BaconShop_HP_046":1,"TB_BaconShop_HP_102":3}
const NEW=["BG20_HERO_201p","BG20_HERO_202p","BG20_HERO_280p5","BG20_HERO_282p","BG20_HERO_301p","BG21_HERO_000p","BG21_HERO_010p","BG21_HERO_020p","BG22_HERO_000p_Alt","BG22_HERO_001p","BG22_HERO_002p","BG22_HERO_003p","BG22_HERO_004p","BG22_HERO_007p","BG22_HERO_007p2","BG22_HERO_200p","BG22_HERO_201p","BG23_HERO_305p","BG26_HERO_104p","BG27_HERO_801p2","BG31_HERO_003p","BG31_HERO_005p","BG31_HERO_006p","BG32_HERO_002p","BG34_HERO_001p","BG34_HERO_002p","BG35_HERO_001p","BG36_HERO_101p","BG36_HERO_105p","TB_BaconShop_HP_010","TB_BaconShop_HP_014","TB_BaconShop_HP_015","TB_BaconShop_HP_022","TB_BaconShop_HP_028","TB_BaconShop_HP_033","TB_BaconShop_HP_038","TB_BaconShop_HP_039t","TB_BaconShop_HP_044","TB_BaconShop_HP_047","TB_BaconShop_HP_052","TB_BaconShop_HP_053","TB_BaconShop_HP_057","TB_BaconShop_HP_068","TB_BaconShop_HP_069","TB_BaconShop_HP_080","TB_BaconShop_HP_102"]
const PASSIVE=["BG20_HERO_202p","BG20_HERO_280p5","BG20_HERO_282p","BG22_HERO_002p","BG22_HERO_003p","BG22_HERO_004p","BG22_HERO_007p","BG22_HERO_200p","BG22_HERO_201p","BG26_HERO_104p","BG27_HERO_801p2","BG32_HERO_002p","BG34_HERO_002p","BG35_HERO_001p","BG36_HERO_101p","BG36_HERO_105p","TB_BaconShop_HP_014","TB_BaconShop_HP_033","TB_BaconShop_HP_038","TB_BaconShop_HP_039t","TB_BaconShop_HP_044","TB_BaconShop_HP_057","TB_BaconShop_HP_069","TB_BaconShop_HP_080"]
static func supports(d: Dictionary,e: Dictionary) -> bool:
	return e.get("handler","")=="round132" and (e.get("op","") in NEW or e.get("op","") in ["identity","TB_BaconShop_HP_077"] or e.get("op","").begins_with("BG22_HERO_001p_t")) and d.kind in ["hero","hero_power","spell"]
static func source_pool(engine,p: Dictionary,source: String) -> Array:
	var data=engine.content.power_sources
	var ids=data.get("sources",{}).get(source,[])
	# Preserve legacy slot resolution without initializing the caller on query.
	var current=engine.active_powers(p.duplicate(true))
	return ids.filter(func(id):return engine.content.eligible(engine.content.get_def(id),engine.state.enabled_tribes) and id not in current and (source!="identity" or id not in p.get("identity_lost_limited",[])) and (source!="nguyen" or nguyen_unlocked(engine,p,id)))
static func nguyen_unlocked(engine,p: Dictionary,id: String) -> bool:
	if NGUYEN_GAME_USE_LIMITS.has(id) and int(p.get("power_ledger",{}).get(id,{}).get("game_used",0))>=int(NGUYEN_GAME_USE_LIMITS[id]):return false
	return int(engine.state.get("round",1))>=int(NGUYEN_MIN_ROUND.get(id,1)) and int(p.get("tier",1))>=int(NGUYEN_MIN_TIER.get(id,1))
static func discover_power(engine,p: Dictionary,source: String,slot_id: int,n: int=3) -> bool:
	var ids=source_pool(engine,p,source)
	if ids.is_empty():return false
	var s=engine.Powers.selected(engine,p,slot_id)
	var options=[]
	while not ids.is_empty() and options.size()<n:
		var id=ids.pop_at(engine.RNG.next(engine.state.streams,"choice",ids.size()))
		options.append({"def_id":id,"instance_id":-1,"owner":p.id,"modifiers":[],"extra_keywords":[],"gifts":[]})
	engine.enqueue_choice(p,{"kind":"r132_power","source":source,"slot_id":slot_id,"epoch":s.epoch,"rule_version":62,"options":options,"rng_after":engine.state.streams.duplicate(true)})
	return true
static func original(engine,p: Dictionary,c: Dictionary) -> Dictionary:
	return engine.make_card(engine.R13Items.original_id(engine,c),int(p.id))
static func full_copy(engine,p: Dictionary,c: Dictionary,clone_exhibition: bool=false) -> Dictionary:
	var result=c.duplicate(true);result.instance_id=int(engine.state.next_instance);engine.state.next_instance+=1;result.owner=int(p.id)
	engine.R133.strip(result)
	result.pool_copies=0;result["attached_pool"]=[];result.erase("shop_price");result.erase("shop_price_source")
	if clone_exhibition:
		var route=str(result.get("gold_route",""));result.gold_route="";result.enhanced_reborn_available=false;result["capacity_bonus"]=0
		var added=result.get("gold_route_added_keywords",["WINDFURY"] if route=="元素" else ["VENOMOUS"] if route=="鱼人" else ["REBORN"] if route=="亡灵" else [])
		for key in added:result.extra_keywords.erase(key)
		result.erase("gold_route_added_keywords")
	engine.exclude_gold_reward(result,"hero_copy")
	return result
static func data(engine,p: Dictionary,s: Dictionary) -> Dictionary:
	var id=str(s.persistent_power_id) if not s.has("temporary_restore") else str(s.active_power_id)
	if not p.power_ledger.has(id):p.power_ledger[id]={"round":int(engine.state.round),"used":0,"game_used":0}
	return p.power_ledger[id]
static func cost(engine,p: Dictionary,s: Dictionary) -> int:
	var id=str(s.active_power_id);var d=engine.content.get_def(id);var v=int(d.get("cost",0));var entry=data(engine,p,s)
	if id=="TB_BaconShop_HP_047":v+=int(entry.get("price_growth",0))
	if id in ["BG23_HERO_305p","BG31_HERO_003p"]:v=maxi(0,v-int(entry.get("price_discount",0)))
	return v
static func pairs(engine,p: Dictionary) -> Array:
	var counts={}
	for c in p.board+p.hand:
		var d=engine.content.get_def(c.def_id)
		if d.get("kind","")!="minion" or d.get("golden",false) or d.get("base_id",d.id)=="BG33_890t" or engine.CardLock.locked(engine,p,c):continue
		counts[d.id]=int(counts.get(d.id,0))+1
	return counts.keys().filter(func(id):return int(counts[id])>=2)
static func malygos_pool(engine,p: Dictionary,c: Dictionary) -> Array:
	var d=engine.content.get_def(c.def_id);var tier=mini(6,int(d.get("tier",0)))
	return engine.content.pool(d.kind,engine.state.enabled_tribes).filter(func(id):return int(engine.content.get_def(id).get("tier",0))==tier and id!=d.id and (d.kind!="minion" or int(engine.state.pool.get(id,0))>0))
static func query(engine,p: Dictionary) -> Dictionary:
	var s=engine.Powers.selected(engine,p);var id=str(s.get("active_power_id",""))
	if id not in NEW and id!="TB_BaconShop_HP_077":return {}
	var targets=[];var reason="";var price=cost(engine,p,s);var used=engine.Powers.used(engine,p)
	if id in PASSIVE:reason="PASSIVE_POWER"
	elif id=="BG31_HERO_005p" and engine.Powers.used(engine,p,true)>0 or id=="TB_BaconShop_HP_102" and engine.Powers.used(engine,p,true)>=3:reason="POWER_ALREADY_USED"
	elif used>=(2 if id=="TB_BaconShop_HP_052" else 1):reason="POWER_ALREADY_USED"
	elif int(p.coins)<price:reason="NOT_ENOUGH_COINS"
	if reason!="":return {"available":false,"reason":reason,"targets":[],"cost":price,"handler":id}
	match id:
		"BG20_HERO_201p":targets=(p.board+p.shop).filter(func(c):return engine.content.get_def(c.def_id).kind=="minion").map(func(c):return c.instance_id);reason="NO_LEGAL_TARGET" if targets.size()<2 else ""
		"BG20_HERO_301p":targets=p.board.filter(func(c):return engine.content.get_def(c.def_id).kind=="minion").map(func(c):return c.instance_id);reason="NO_LEGAL_TARGET" if targets.is_empty() else ""
		"BG21_HERO_000p":reason="NO_LEGAL_TARGET" if p.board.is_empty() else ""
		"BG21_HERO_010p":reason="NO_LEGAL_CANDIDATE" if next_board(engine,p).is_empty() else ""
		"BG21_HERO_020p":targets=(p.board+p.shop).filter(func(c):return engine.content.get_def(c.def_id).kind=="minion" and not engine.card_types(c).is_empty() and not cookie_pool(engine,p,c).is_empty()).map(func(c):return c.instance_id)
		"BG22_HERO_000p_Alt":targets=p.shop.filter(func(c):return engine.content.get_def(c.def_id).kind=="minion").map(func(c):return c.instance_id)
		"BG22_HERO_001p":pass
		"BG22_HERO_007p2":reason="NO_LEGAL_CANDIDATE" if engine.discovery_candidates(p,{"tribe":"纳迦"}).is_empty() else ""
		"BG23_HERO_305p":reason="NO_LEGAL_TARGET" if p.shop.is_empty() else ""
		"BG31_HERO_003p":reason="NO_LEGAL_CANDIDATE" if not p.has("last_tavern_spell") else ""
		"BG31_HERO_005p":targets=p.board.map(func(c):return c.instance_id);reason="BOARD_FULL" if p.board.size()>=engine.capacity(p.board) else ""
		"BG31_HERO_006p","TB_BaconShop_HP_022":reason="POWER_LOCKED_UNTIL_TURN_3" if int(engine.state.round)<3 else ""
		"BG34_HERO_001p","TB_BaconShop_HP_028":reason="NO_LEGAL_CANDIDATE" if not engine.Shop132.possible(engine,p,id) else ""
		"TB_BaconShop_HP_010":targets=(p.board+p.shop).filter(func(c):return engine.content.get_def(c.def_id).kind=="minion").map(func(c):return c.instance_id)
		"TB_BaconShop_HP_015":reason="POWER_LOCKED" if int(p.tier)<4 else "NO_LEGAL_CANDIDATE" if engine.generation_candidates(p,{"tribe":"机械"}).is_empty() else ""
		"TB_BaconShop_HP_047":reason="NO_LEGAL_CANDIDATE" if engine.discovery_candidates(p,{"tier":int(p.tier)}).is_empty() else ""
		"TB_BaconShop_HP_052":targets=(p.board+p.shop).filter(func(c):return (c in p.shop or engine.content.get_def(c.def_id).kind=="minion") and not malygos_pool(engine,p,c).is_empty()).map(func(c):return c.instance_id)
		"TB_BaconShop_HP_053":pass
		"TB_BaconShop_HP_068":targets=p.shop.map(func(c):return c.instance_id)
		"TB_BaconShop_HP_077":reason="NO_LEGAL_CANDIDATE" if p.get("previous_recruit_board",[]).is_empty() else ""
		"TB_BaconShop_HP_102":reason="NO_LEGAL_CANDIDATE" if pairs(engine,p).is_empty() else ""
	if id=="TB_BaconShop_HP_022":targets=p.board.filter(func(c):return engine.Triggers.effects(engine,c).any(func(e):return e.get("trigger","")=="battlecry")).map(func(c):return c.instance_id)
	if id in ["BG21_HERO_020p","BG22_HERO_000p_Alt","BG31_HERO_005p","TB_BaconShop_HP_010","TB_BaconShop_HP_022","TB_BaconShop_HP_052","TB_BaconShop_HP_068"] and targets.is_empty() and reason=="":reason="NO_LEGAL_TARGET"
	return {"available":reason=="","reason":reason,"targets":targets,"cost":price,"handler":id,"slot_id":s.slot_id,"epoch":s.epoch}
static func target_choice(engine,p: Dictionary,s: Dictionary,op: String,first: Dictionary) -> void:
	var options=(p.board+p.shop if op=="soul" else p.board).filter(func(c):return c.instance_id!=first.instance_id and engine.content.get_def(c.def_id).kind=="minion")
	engine.enqueue_choice(p,{"kind":"r132_target","options":options.duplicate(true),"slot_id":s.slot_id,"epoch":s.epoch,"op":op,"first_id":first.instance_id})
static func target_error(engine,p: Dictionary,choice: Dictionary,target_id: int,args: Dictionary={}) -> String:
	if choice.get("op","")=="swallow":return "LEGACY_DEVOUR_CHOICE_REOPEN_POWER"
	if args.has("session_id") and str(args.session_id)!=str(choice.session_id):return "STALE_CHOICE"
	var s=engine.Powers.selected(engine,p,int(choice.slot_id))
	if s.is_empty() or int(s.epoch)!=int(choice.epoch) or args.has("epoch") and int(args.epoch)!=int(s.epoch):return "STALE_POWER_EPOCH"
	var expected={"soul":"BG20_HERO_201p","swallow":"BG20_HERO_301p","battlecry":"TB_BaconShop_HP_022"}
	if str(s.active_power_id)!=expected.get(str(choice.op),""):return "STALE_POWER_EPOCH"
	var first=engine.find_target(p,int(choice.first_id));var target=engine.find_target(p,target_id)
	if first.is_empty() or target.is_empty() or int(first.instance_id)==target_id:return "STALE_TARGET"
	if not choice.options.any(func(c):return int(c.instance_id)==target_id):return "INVALID_POWER_TARGET"
	if engine.content.get_def(first.def_id).kind!="minion" or engine.content.get_def(target.def_id).kind!="minion":return "INVALID_POWER_TARGET"
	var old=engine.power_context.get(int(p.id),0);engine.power_context[int(p.id)]=s.slot_id
	var q=query(engine,p);engine.power_context[int(p.id)]=old
	if not q.get("available",false):return str(q.get("reason","POWER_NOT_IMPLEMENTED"))
	if first.instance_id not in q.targets:return "STALE_TARGET"
	if choice.op in ["soul","swallow"] and target_id not in q.targets:return "STALE_TARGET"
	if choice.op=="battlecry":
		var legal=[]
		for effect in engine.content.get_def(first.def_id).effects:
			if effect.get("trigger","")=="battlecry":legal.append_array(engine.battlecry_candidates(p,first,effect))
		if target not in legal:return "STALE_TARGET"
	return ""
static func use(engine,p: Dictionary,args: Dictionary) -> String:
	var q=query(engine,p)
	if q.is_empty():return "POWER_NOT_IMPLEMENTED"
	if not q.available:return q.reason
	var id=str(q.handler);var s=engine.Powers.selected(engine,p);var entry=data(engine,p,s)
	var target={}
	for c in p.board+p.shop:
		if int(c.instance_id)==int(args.get("target_id",-1)):target=c;break
	if not q.targets.is_empty() and (target.is_empty() or target.instance_id not in q.targets):return "TARGET_REQUIRED"
	match id:
		"BG20_HERO_201p":target_choice(engine,p,s,"soul",target);return ""
		"BG20_HERO_301p":
			if engine.Continuation.request(engine,p,target,"sell",{"kind":"command","command":"power","payload":{"slot_id":s.slot_id,"epoch":s.epoch,"target_id":target.instance_id}}):return ""
			# Capture the same pre-sale displayed stats as the former swallow resolution.
			var v=engine.stats(target)
			engine.state["devour_tail"]={"owner":int(p.id),"source_instance":int(target.instance_id),"consumed_snapshot":target.duplicate(true),"attack":v.x,"health":v.y,"slot_id":s.slot_id,"epoch":s.epoch,"root_action_id":engine.state.get("active_root",engine.cause)}
			if not engine.sell_card(p,target):return "CARD_NOT_ON_BOARD"
		"BG21_HERO_000p":
			var v=entry.get("conviction",{"targets":1,"attack":1,"health":1});var pool=p.board.duplicate()
			for unused in mini(pool.size(),int(v.targets)):engine.buff(pool.pop_at(engine.RNG.next(engine.state.streams,"effects",pool.size())),int(v.attack),int(v.health))
		"BG21_HERO_010p":copy_discover(engine,p,next_board(engine,p),"spy",true)
		"BG21_HERO_020p":
			var tribes=engine.Naga.types(engine,target);var tribe="全部种族" if tribes.is_empty() else tribes[engine.RNG.next(engine.state.streams,"effects",tribes.size())]
			if not s.progress.has("cookie_inputs"):s.progress["cookie_inputs"]=[]
			# Ingredient order fixes only each discovery slot's tribe. Old saved
			# early card/tier snapshots no longer constrain the eventual reward.
			s.progress.cookie_inputs=s.progress.cookie_inputs.map(func(v):return {"tribe":str(v.tribe),"source_instance":v.get("source_instance",-1)})
			s.progress.cookie_inputs.append({"tribe":tribe,"source_instance":target.instance_id})
			p.board.erase(target);p.shop.erase(target);engine.return_pool(target)
			if s.progress.cookie_inputs.size()==3:
				var options=cookie_options(engine,p,s.progress.cookie_inputs)
				engine.enqueue_choice(p,{"kind":"r132_cookie","options":options,"inputs":s.progress.cookie_inputs.duplicate(true),"generated_tier":int(p.tier)});s.progress.cookie_inputs=[]
		"BG22_HERO_000p_Alt":p.shop.erase(target);engine.R133.strip(target);s.progress["ammo"]={"card":target.duplicate(true),"epoch":s.epoch,"consumed":false}
		"BG22_HERO_001p":
			engine.enqueue_choice(p,{"kind":"r132_element","slot_id":s.slot_id,"epoch":s.epoch,"options":range(1,5).map(func(n):return {"def_id":"BG22_HERO_001p_t"+str(n),"instance_id":-1,"modifiers":[],"extra_keywords":[],"gifts":[]})})
		"BG22_HERO_007p2":engine.resolve_discovery(p,engine.discovery_candidates(p,{"tribe":"纳迦"}),"r132_naga")
		"BG23_HERO_305p":
			for c in p.shop.duplicate():p.shop.erase(c);engine.Fish.leave_shop(c);engine.receive_card(p,c,engine.power_definition(p))
			entry.price_discount=0
		"BG31_HERO_003p":engine.receive_card(p,engine.make_card(p.last_tavern_spell,int(p.id)),engine.power_definition(p));entry.price_discount=0
		"BG31_HERO_005p":
			var copy=full_copy(engine,p,target,true);p.board.append(copy)
			engine.Naga.recruit_entered(engine,p,copy)
		"BG31_HERO_006p":p["next_spell_discount"]=int(p.get("next_spell_discount",0))+1
		"BG34_HERO_001p","TB_BaconShop_HP_028","TB_BaconShop_HP_077":
			var error=engine.Shop132.refresh(engine,p,id)
			if error!="":return error
		"TB_BaconShop_HP_010":engine.add_keyword(target,"DIVINE_SHIELD")
		"TB_BaconShop_HP_022":
			var options=[]
			for effect in engine.content.get_def(target.def_id).effects:
				if effect.get("trigger","")=="battlecry":
					for c in engine.battlecry_candidates(p,target,effect):
						if c not in options:options.append(c)
			if not options.is_empty():
				engine.enqueue_choice(p,{"kind":"r132_target","options":options.duplicate(true),"slot_id":s.slot_id,"epoch":s.epoch,"op":"battlecry","first_id":target.instance_id});return ""
			engine.run_effects(p,target,"battlecry")
		"TB_BaconShop_HP_047":engine.resolve_discovery(p,engine.discovery_candidates(p,{"tier":int(p.tier)}),"r132_elise");entry.price_growth=int(entry.get("price_growth",0))+1
		"TB_BaconShop_HP_052":
			var pool=malygos_pool(engine,p,target);var chosen=pool[engine.RNG.next(engine.state.streams,"effects",pool.size())];var d=engine.content.get_def(chosen)
			var zone=p.shop if target in p.shop else p.board;var pos=zone.find(target);engine.return_pool(target)
			if d.kind=="minion":engine.state.pool[chosen]-=1
			zone[pos]=engine.make_card(chosen,int(p.id),1 if d.kind=="minion" else 0)
			engine.Naga.recruit_entered(engine,p,zone[pos])
		"TB_BaconShop_HP_053":s.progress["rafaam_ready"]=true
		"TB_BaconShop_HP_068":p.shop.erase(target);engine.Fish.leave_shop(target);target["card_lock"]={"round":int(engine.state.round)+2};engine.receive_card(p,target,engine.power_definition(p))
		"TB_BaconShop_HP_102":
			var pool=pairs(engine,p);var chosen=pool[engine.RNG.next(engine.state.streams,"effects",pool.size())]
			engine.receive_card(p,engine.make_card(chosen,int(p.id)),engine.power_definition(p))
		_:return "PASSIVE_POWER"
	p.coins-=int(q.cost);engine.consume_power(p,id in ["BG31_HERO_005p","TB_BaconShop_HP_102"]);engine.Elementals.spent(engine,p,int(q.cost))
	engine.emit("HeroPowerUsed",int(p.id),{"power_id":id,"slot_id":s.slot_id,"epoch":s.epoch,"cost":q.cost});return ""
static func cookie_pool(engine,p: Dictionary,c: Dictionary,tribe: String="") -> Array:
	if engine.card_types(c).is_empty():return []
	var ts=engine.Naga.types(engine,c)
	if tribe!="":ts=[tribe]
	if ts.is_empty():ts=["全部种族"]
	return engine.generation_candidates(p,{}).filter(func(id):return engine.content.get_def(id).card_types.any(func(t):return t in ts or t=="全部种族"))
static func cookie_family(engine,id: String) -> String:
	return str(engine.content.get_def(id).get("base_id",id))
static func cookie_assign(engine,index: int,pools: Array,owners: Dictionary,chosen: Dictionary,seen: Dictionary) -> bool:
	for id in pools[index]:
		var base=cookie_family(engine,id)
		if seen.has(base):continue
		seen[base]=true
		if not owners.has(base) or cookie_assign(engine,int(owners[base]),pools,owners,chosen,seen):
			owners[base]=index;chosen[index]=id;return true
	return false
static func cookie_options(engine,p: Dictionary,inputs: Array) -> Array:
	var pools=[]
	for entry in inputs:
		var candidates=[];var families={}
		# All three pools are evaluated now, at the third use's current tier.
		# Matching never exchanges pools between ingredient/option indices.
		for id in engine.generation_candidates(p,{"tribe":str(entry.tribe)}):
			var base=cookie_family(engine,id)
			if not families.has(base):candidates.append(id);families[base]=true
		pools.append(engine.RNG.shuffle(candidates,engine.state.streams,"effects"))
	var owners={};var chosen={}
	for i in pools.size():cookie_assign(engine,i,pools,owners,chosen,{})
	var options=[]
	for i in inputs.size():
		inputs[i]["offered_id"]=chosen.get(i,"");inputs[i]["option_index"]=options.size() if chosen.has(i) else -1
		if chosen.has(i):options.append(engine.make_card(chosen[i],int(p.id)))
	return options
static func copy_discover(engine,p: Dictionary,cards: Array,source: String,base: bool) -> bool:
	if cards.is_empty():return false
	var pool=cards.duplicate();var options=[]
	while not pool.is_empty() and options.size()<3:
		var c=pool.pop_at(engine.RNG.next(engine.state.streams,"choice",pool.size()))
		options.append(original(engine,p,c) if base else full_copy(engine,p,c))
	engine.enqueue_choice(p,{"kind":"r132_copy","options":options,"copy_source":source});return true
static func cat_copy(choice: Dictionary) -> bool:
	return choice.get("kind","")=="r132_copy" and str(choice.get("copy_source","")).begins_with("eliminated:")
static func cat_reward_error(engine,p: Dictionary,choice: Dictionary) -> String:
	if not cat_copy(choice):return "NOT_CAT_REWARD"
	var source=str(choice.copy_source).trim_prefix("eliminated:")
	if not source.is_valid_int():return "INVALID_CAT_REWARD_SOURCE"
	var pid=int(source)
	if pid<0 or pid>=engine.state.players.size() or pid==int(p.id) or source!=str(pid):return "INVALID_CAT_REWARD_SOURCE"
	var eliminated=engine.state.players[pid]
	if eliminated.alive or int(eliminated.rank)<=0 or eliminated.get("eliminated_board",[]).is_empty():return "INVALID_CAT_REWARD_SOURCE"
	
	
	var issued=-1
	for event in engine.events:
		if event.kind=="SelectionEnqueued" and int(event.owner)==int(p.id) and event.payload.get("kind","")=="r132_copy" and event.payload.get("session_id","")==choice.get("session_id",""):issued=int(event.seq);break
	var actual=-1
	if issued>=0:
		for event in engine.events:
			if int(event.seq)>issued and event.kind=="PlayerEliminated":actual=int(event.owner);break
	if actual!=pid:return "INVALID_CAT_REWARD_PROVENANCE"
	if p.get("cat_rewards_claimed",{}).has(source):return "CAT_REWARD_ALREADY_CLAIMED"
	for card in choice.options:
		if int(card.get("owner",-1))!=int(p.id) or int(card.get("pool_copies",-1))!=0 or engine.content.get_def(card.get("def_id","")).get("kind","")!="minion":return "INVALID_CAT_REWARD_OPTION"
	return ""
static func resolve(engine,p: Dictionary,choice: Dictionary,index: int) -> String:
	if choice.kind not in ["r132_power","r132_element","r132_conviction","r132_target","r132_start"]:return "UNHANDLED"
	var s=engine.Powers.selected(engine,p,int(choice.get("slot_id",0)))
	if choice.kind!="r132_start" and (s.is_empty() or int(s.epoch)!=int(choice.epoch)):return "STALE_POWER_EPOCH"
	var selected=choice.options[index]
	match choice.kind:
		"r132_power":
			var id=str(selected.def_id);var source=str(choice.source)
			if id not in source_pool(engine,p,source):return "STALE_POWER_CANDIDATE"
			p.choices.pop_front()
			engine.Powers.replace(engine,p,int(s.slot_id),id,source=="nguyen")
			if source=="finley":start_power(engine,p,s,true)
			if source=="genn" and int(s.slot_id)==0:
				p.power_slots.append(engine.Powers.slot("BG35_HERO_001p",1))
				var second=engine.Powers.selected(engine,p,1)
				second.progress["genn_due"]={"source":"genn","slot_id":1,"epoch":second.epoch,"first_power_id":id}
				retry_genn(engine,p,second)
		"r132_element":s.progress["element_id"]=selected.def_id;p.choices.pop_front()
		"r132_conviction":
			var entry=data(engine,p,s)
			if not entry.has("conviction"):entry["conviction"]={"targets":1,"attack":1,"health":1}
			var key="targets" if selected.def_id=="BG21_HERO_000p_t1" else "attack" if selected.def_id=="BG21_HERO_000_Buddyt" else "health"
			entry.conviction[key]+=1;p.choices.pop_front()
		"r132_target":
			var error=target_error(engine,p,choice,int(selected.instance_id))
			if error!="":return error
			var first=engine.find_target(p,int(choice.first_id));var target=engine.find_target(p,int(selected.instance_id))
			if first.is_empty() or target.is_empty() or first.instance_id==target.instance_id:return "STALE_TARGET"
			if choice.op=="battlecry":engine.run_effects(p,first,"battlecry",target)
			else:
				var a=engine.stats(first).x;var b=engine.stats(target).x;engine.buff(first,b,0,"next_turn");engine.buff(target,a,0,"next_turn")
			p.choices.pop_front();var old=engine.power_context.get(int(p.id),0);engine.power_context[int(p.id)]=s.slot_id
			var price=cost(engine,p,s);p.coins-=price;engine.Elementals.spent(engine,p,price);engine.consume_power(p);engine.power_context[int(p.id)]=old
		"r132_start":
			if choice.get("source_policy","")=="xavius_gift_window":
				var d=engine.content.get_def(selected.def_id)
				var gift=int(selected.get("r13_gift_id",0))
				if int(d.tier) not in choice.allowed_tiers or not engine.content.eligible(d,engine.state.enabled_tribes) or gift not in d.manual_gift_ids.map(func(v):return int(v)):return "STALE_GIFT_CANDIDATE"
			p.choices.pop_front();var card=selected
			if card.has("r13_gift_id"):engine.R13Items.selected(engine,p,choice,card)
			if choice.has("lock"):card["card_lock"]=choice.lock.duplicate(true)
			engine.receive_card(p,card,engine.Acquisition.context(engine,{"def_id":choice.power_id},"hero_start"))
			if not choice.get("remaining",[]).is_empty() and not start_discovery(engine,p,int(choice.slot_id),str(choice.power_id),choice.remaining[0],choice.remaining.slice(1),{}):hold_start(p,int(choice.slot_id),str(choice.power_id),choice.remaining[0],choice.remaining.slice(1),{})
	return ""
static func next_board(engine,p: Dictionary) -> Array:
	var pid=int(p.get("next_opponent",-1))
	return engine.state.players[pid].board if pid>=0 and pid<engine.state.players.size() and engine.state.players[pid].alive else p.get("next_opponent_board",[])
static func pairings(engine) -> void:
	engine.Pairing.ensure(engine)
static func start_discovery(engine,p: Dictionary,slot_id: int,id: String,tier: int,remaining: Array,lock: Dictionary) -> bool:
	var pool=engine.R13Items.seven_pool(engine) if tier==7 else engine.generation_candidates(p,{"tier":tier})
	if pool.is_empty():return false
	var options=[]
	while not pool.is_empty() and options.size()<3:options.append(engine.make_card(pool.pop_at(engine.RNG.next(engine.state.streams,"choice",pool.size())),int(p.id)))
	if id=="BG22_HERO_201p":lock={"tier":tier}
	engine.enqueue_choice(p,{"kind":"r132_start","power_id":id,"slot_id":slot_id,"options":options,"remaining":remaining,"lock":lock})
	return true
static func start_power(engine,p: Dictionary,s: Dictionary,finley: bool=false) -> void:
	var id=str(s.active_power_id);var entry=data(engine,p,s)
	if entry.get("start_granted",false):return
	match id:
		"BG24_HERO_100p":
			if not engine.R135.start(engine,p,s):return
		"TB_BaconShop_HP_035":
			if finley:p.health+=30
		"TB_BaconShop_HP_033":p.board.append(engine.make_card("TB_BaconShop_HP_033t",int(p.id)))
		"BG21_HERO_030p":engine.Fish.initialize(engine,p)
		"TB_BaconShop_HP_057":
			if not discover_power(engine,p,"finley",int(s.slot_id)):return
		"BG22_HERO_201p":
			p["skip_recruit_until"]=2
			if not start_discovery(engine,p,int(s.slot_id),id,6,[4,2],{}):hold_start(p,int(s.slot_id),id,6,[4,2],{})
		"TB_BaconShop_HP_044":p["skip_recruit_until"]=3;p["afk_due"]=true
		"BG27_HERO_801p2":
			if not start_discovery(engine,p,int(s.slot_id),id,7,[],{"debt":60}):hold_start(p,int(s.slot_id),id,7,[],{"debt":60})
		"BG36_HERO_101p":
			p["hero_gift_due"]={"power_id":id,"slot_id":s.slot_id,"epoch":s.epoch,"tier":5,"lock_round":7}
			retry_hero_gift(engine,p)
	entry["start_granted"]=true
static func initialize(engine,p: Dictionary) -> void:
	for s in p.power_slots:start_power(engine,p,s)
static func recover_genn(engine,p: Dictionary,s: Dictionary) -> void:
	
	
	if s.active_power_id!="BG35_HERO_001p" or s.persistent_power_id!="BG35_HERO_001p" or int(s.slot_id)!=1 or int(s.epoch)!=1 or p.power_slots.size()!=2 or s.progress.has("genn_due"):return
	var first=engine.Powers.selected(engine,p,0)
	if int(first.epoch)!=2 or first.active_power_id=="BG35_HERO_001p" or not p.get("power_ledger",{}).get("BG35_HERO_001p",{}).get("genn_started",false):return
	if not engine.events.any(func(event):return event.kind=="HeroPowerBound" and int(event.owner)==int(p.id) and int(event.payload.get("slot_id",-1))==0 and event.payload.get("previous","")=="BG35_HERO_001p" and event.payload.get("power_id","")==first.active_power_id and int(event.payload.get("epoch",0))==2):return
	s.progress["genn_due"]={"source":"genn","slot_id":1,"epoch":s.epoch,"first_power_id":first.active_power_id}
static func retry_genn(engine,p: Dictionary,s: Dictionary) -> void:
	if not s.progress.has("genn_due"):return
	var due=s.progress.genn_due
	if s.active_power_id!="BG35_HERO_001p" or int(due.epoch)!=int(s.epoch) or int(due.slot_id)!=int(s.slot_id):s.progress.erase("genn_due");return
	if p.choices.any(func(choice):return choice.kind=="r132_power" and choice.get("source","")=="genn" and int(choice.get("slot_id",-1))==int(s.slot_id) and int(choice.get("epoch",0))==int(s.epoch)):return
	if not discover_power(engine,p,"genn",int(s.slot_id)):engine.emit("HeroPowerDiscoveryPending",int(p.id),due)
static func turn_start(engine,p: Dictionary,discover_nguyen_now: bool=true) -> void:
	var waiting=p.get("hero_start_due",[]).duplicate(true);p["hero_start_due"]=[]
	for request in waiting:
		if not start_discovery(engine,p,int(request.slot_id),str(request.power_id),int(request.tier),request.remaining,request.lock):p.hero_start_due.append(request)
	for slot_id in p.power_slots.map(func(slot):return int(slot.slot_id)):
		p=engine.state.players[int(p.id)]
		var s=engine.Powers.selected(engine,p,slot_id)
		var id=str(s.active_power_id);var entry=data(engine,p,s)
		recover_genn(engine,p,s)
		retry_genn(engine,p,s)
		if id=="BG20_HERO_280p5":s.progress["blade_buys"]=[]
		if id=="BG22_HERO_001p":s.progress.erase("element_id")
		if id=="BG20_HERO_202p" and discover_nguyen_now:discover_power(engine,p,"nguyen",int(s.slot_id),2)
		if id=="BG35_HERO_001p" and int(engine.state.round)>=4 and not entry.get("genn_started",false):
			if discover_power(engine,p,"genn",int(s.slot_id)):entry["genn_started"]=true
		if id in ["BG23_HERO_305p","BG31_HERO_003p"]:entry["price_discount"]=int(entry.get("price_discount",0))+1
		if id=="TB_BaconShop_HP_038":
			for receiver in engine.state.players:
				if not receiver.alive:continue
				for unused in (2 if int(receiver.id)==int(p.id) else 1):
					var roll=engine.RNG.next(engine.state.streams,"effects",100);var banana="BG_TB_006" if roll<33 else "BG_EX1_014t"
					engine.receive_card(receiver,engine.make_card(banana,int(receiver.id)),{"def_id":id});engine.emit("BananaIssued",int(receiver.id),{"roll":roll,"id":banana,"power_owner":p.id})
		if id=="TB_BaconShop_HP_039t" and int(engine.state.round)>=3:engine.Yogg.trigger(engine,p)
		if id=="BG36_HERO_105p" and int(engine.state.round)%4==0:
			var key="xavius:"+str(engine.state.round)
			if not entry.has("xavius_periods"):entry["xavius_periods"]={}
			if not entry.xavius_periods.has(key):
				entry.xavius_periods[key]="pending" if not entry.has("xavius_pending") else "pending_already_held"
				if not entry.has("xavius_pending"):entry["xavius_pending"]={"round":int(engine.state.round),"slot_id":s.slot_id,"epoch":s.epoch}
	if p.get("afk_due",false) and int(engine.state.round)>=3:
		if start_discovery(engine,p,0,"TB_BaconShop_HP_044",3,[4],{}):p.afk_due=false
	retry_hero_gift(engine,p)
	retry_xavius(engine,p)
static func retry_hero_gift(engine,p: Dictionary) -> void:
	if not p.has("hero_gift_due"):return
	var due=p.hero_gift_due
	var slot=engine.Powers.selected(engine,p,int(due.slot_id))
	# Legacy pending records have no epoch. Never award a departed source.
	if slot.is_empty() or slot.active_power_id!=due.power_id or int(slot.epoch)!=int(due.get("epoch",slot.epoch)):
		p.erase("hero_gift_due");return
	if p.choices.any(func(c):return c.kind=="r132_start" and c.get("power_id","")==due.power_id and int(c.get("slot_id",-1))==int(due.slot_id)):
		p.erase("hero_gift_due");return
	if gift_discovery(engine,p,slot,int(due.tier),int(due.lock_round),str(due.power_id)):p.erase("hero_gift_due")
static func nguyen_start(engine,p: Dictionary) -> void:
	for s in p.power_slots:
		if s.active_power_id=="BG20_HERO_202p":discover_power(engine,p,"nguyen",int(s.slot_id),2)
static func retry_xavius(engine,p: Dictionary) -> void:
	var entry=p.power_ledger.get("BG36_HERO_105p",{})
	if not entry.has("xavius_pending"):return
	var due=entry.xavius_pending
	var source_slot={"active_power_id":"BG36_HERO_105p","slot_id":due.slot_id,"epoch":due.epoch}
	if gift_discovery(engine,p,source_slot,0,0,"BG36_HERO_105p",int(due.round)):
		entry.xavius_periods["xavius:"+str(due.round)]="offered"
		engine.Powers.receipt(engine,p,source_slot,"xavius:"+str(due.round))
		entry.erase("xavius_pending")
static func hold_start(p: Dictionary,slot_id: int,id: String,tier: int,remaining: Array,lock: Dictionary) -> void:
	if not p.has("hero_start_due"):p["hero_start_due"]=[]
	p.hero_start_due.append({"slot_id":slot_id,"power_id":id,"tier":tier,"remaining":remaining,"lock":lock})
static func gift_discovery(engine,p: Dictionary,s: Dictionary,tier: int,lock_round: int,source_power_id: String="",origin_round: int=0) -> bool:
	var source_id=str(s.active_power_id) if source_power_id=="" else source_power_id
	var cross_window=source_id=="BG36_HERO_105p" and tier==0
	var allowed_tiers=engine.Special.regular_tiers(int(engine.state.round)) if cross_window else [tier] if tier>0 else engine.Special.regular_tiers(int(engine.state.round))
	var ids=[]
	if cross_window:
		for allowed in allowed_tiers:ids.append_array(engine.generation_candidates(p,{"tier":allowed},{"def_id":source_id}))
	else:ids=engine.generation_candidates(p,{"tier":tier} if tier>0 else {})
	var minions=ids.map(func(id):return engine.content.get_def(id))
	var gifts=[]
	for d in engine.content.definitions.values():
		if d.kind=="dark_gift" and d.implemented:gifts.append({"id":int(d.numeric_id),"min_turn":d.min_turn,"max_turn":d.max_turn})
	var policy={"player":p,"enabled":engine.state.enabled_tribes,"tiers":allowed_tiers,"special_free":true,"source_policy":"xavius_gift_window" if cross_window else "fixed_gift_tier","source_power_id":source_id}
	# Discovery time, this source's gift window, and card unlock are independent.
	var gift_turn=7 if source_id=="BG36_HERO_101p" else int(engine.state.round)
	var pairs=engine.Selection.Choices.gift_options(minions,gifts,gift_turn,engine.state.enabled_tribes,[],engine.state.streams,policy)
	if pairs.is_empty():return false
	var options=[]
	while not pairs.is_empty() and options.size()<3:
		var pair=pairs.pop_at(engine.RNG.next(engine.state.streams,"choice",pairs.size()))
		var c=engine.make_card(pair.id,int(p.id));c["r13_gift_id"]=int(pair.gift_id);options.append(c)
	engine.enqueue_choice(p,{"kind":"r132_start","power_id":source_id,"slot_id":s.slot_id,"options":options,"remaining":[],"lock":{"round":lock_round} if lock_round>0 else {},"source_policy":policy.source_policy,"allowed_tiers":allowed_tiers,"origin_round":origin_round if origin_round>0 else int(engine.state.round),"offered_round":int(engine.state.round)})
	return true
static func last_end(engine,p: Dictionary) -> void:
	if engine.has_power(p,"BG26_HERO_104p") and int(engine.state.round)%3==0 and not p.hand.is_empty():
		engine.receive_card(p,original(engine,p,p.hand[0]),{"def_id":"BG26_HERO_104p"})
		engine.emit("UpbeatHarmonyResolved",int(p.id),{"round":engine.state.round})
	if engine.has_power(p,"TB_BaconShop_HP_014"):p.frozen=true
static func changed(engine,p: Dictionary) -> void:
	for s in p.power_slots:
		var root=str(engine.content.get_def(s.active_power_id).get("root_power_id",s.active_power_id))
		if root=="BG26_HERO_102p":s.active_power_id="BG26_HERO_102p2" if p.get("inge_health",false) else "BG26_HERO_102p"
		if root=="BG28_HERO_400p":s.active_power_id="BG28_HERO_400p2" if int(engine.state.round)<int(p.get("snake_ready_round",1)) else "BG28_HERO_400p"
		if s.active_power_id=="BG22_HERO_007p" and p.board.reduce(func(v,c):return v+engine.stats(c).x,0)>=30:
			s.active_power_id="BG22_HERO_007p2";engine.emit("HeroPowerTransformed",int(p.id),{"power_id":s.active_power_id,"slot_id":s.slot_id,"epoch":s.epoch})
static func bound(engine,p: Dictionary,s: Dictionary) -> void:
	if s.active_power_id=="BG20_HERO_202p" and not s.has("temporary_restore") and engine.Powers.receipt(engine,p,s,"storm_acquired"):
		discover_power(engine,p,"nguyen",int(s.slot_id),2)
	if s.active_power_id=="TB_BaconShop_HP_041":
		var pool=engine.state.enabled_tribes
		s.progress["rat_tribe"]=pool[engine.RNG.next(engine.state.streams,"effects",pool.size())]
		s.active_power_id="TB_BaconShop_HP_041"+engine.Demons.RAT_POWERS.get(s.progress.rat_tribe,"")
	if s.active_power_id=="TB_BaconShop_HP_036":s.progress["jar_damage"]=0
	changed(engine,p)
static func event(engine,event: Dictionary) -> void:
	if int(event.owner)<0 or int(event.owner)>=engine.state.players.size():return
	var p=engine.state.players[int(event.owner)]
	if not p.has("power_slots"):return
	if event.kind=="CardBought":
		for s in p.power_slots:
			if s.active_power_id!="BG20_HERO_280p5" or engine.content.get_def(event.payload.id).kind!="minion" or not engine.Powers.receipt(engine,p,s,str(event.seq)):continue
			var entry=data(engine,p,s)
			if int(entry.get("blade_reward_round",-1))==int(engine.state.round):continue
			if not s.progress.has("blade_buys"):s.progress["blade_buys"]=[]
			s.progress.blade_buys.append(event.payload.id)
			if s.progress.blade_buys.size()==3:
				var id=s.progress.blade_buys[engine.RNG.next(engine.state.streams,"effects",3)]
				entry["blade_reward_round"]=int(engine.state.round);s.progress.blade_buys=[]
				engine.receive_card(p,original(engine,p,{"def_id":id}),{"def_id":s.active_power_id})
	if event.kind=="CombatEnded":
		for player in engine.state.players:
			if not player.alive:continue
			for s in player.power_slots:
				if s.active_power_id=="BG21_HERO_000p" and engine.Powers.receipt(engine,player,s,"conviction:"+str(engine.state.round)):
					engine.enqueue_choice(player,{"kind":"r132_conviction","slot_id":s.slot_id,"epoch":s.epoch,"combat_round":int(engine.state.round),"options":["BG21_HERO_000p_t1","BG21_HERO_000_Buddyt","BG21_HERO_000_Buddyt2"].map(func(id):return {"def_id":id,"instance_id":-1,"modifiers":[],"extra_keywords":[],"gifts":[]})})
	if event.kind=="ShopRefreshed":frost_shop(engine,p)
static func frost_shop(engine,p: Dictionary) -> void:
	if not engine.has_power(p,"BG22_HERO_004p") or p.shop.size()>=7:return
	var pool=p.shop.filter(func(c):return engine.content.get_def(c.def_id).kind=="minion")
	if pool.is_empty():return
	var tier=pool.reduce(func(v,c):return maxi(v,int(engine.content.get_def(c.def_id).tier)),0);pool=pool.filter(func(c):return int(engine.content.get_def(c.def_id).tier)==tier)
	var target=pool[engine.RNG.next(engine.state.streams,"effects",pool.size())];var copy=full_copy(engine,p,target)
	target["frozen_card"]=true;copy["frozen_card"]=true;p.shop.append(copy)
	engine.emit("FrostShopCopied",int(p.id),{"source_instance":target.instance_id,"instance_id":copy.instance_id})
static func description(engine,p: Dictionary,slot_id: int) -> String:
	var old=engine.power_context.get(int(p.id),0)
	engine.power_context[int(p.id)]=slot_id
	var text=slot_description(engine,p,slot_id)
	engine.power_context[int(p.id)]=old
	return text
static func progress_text(text: String,status: String) -> String:
	return text+"\n"+status
static func _computed_slot_description(engine,p: Dictionary,slot_id: int) -> String:
	if engine.Powers.selected(engine,p,slot_id).get("active_power_id","")==engine.R135.POWER:return preload("res://ui/round135_presentation.gd").description(engine,p,slot_id)
	var s=engine.Powers.selected(engine,p,slot_id);var d=engine.content.get_def(s.active_power_id);var entry=data(engine,p,s);var text=str(d.get("text",""))

	var legacy=engine.Heroes7.description(engine,p)
	if legacy!="":text=legacy
	if engine.hero_handler(p)=="eudora":text=engine.Pirates.hero_description(engine,p)
	if engine.hero_handler(p) in ["snake","teron","sylvanas"]:text=preload("res://ui/beast_presentation.gd").hero(engine,p)
	if s.active_power_id=="BG21_HERO_000p":
		var v=entry.get("conviction",{"targets":1,"attack":1,"health":1});text=ExternalText.phrase("domain_rules_round132_powers.slot_description.ba641bb3b266", "说明待补充 · %d / %d / %d") % [int(v.targets),int(v.attack),int(v.health)]
	if s.active_power_id=="BG20_HERO_280p5":text=progress_text(text,ExternalText.phrase("domain_rules_round132_powers.slot_description.4e48b2a54fc6", "说明待补充") if int(entry.get("blade_reward_round",-1))==int(engine.state.round) else ExternalText.phrase("domain_rules_round132_powers.slot_description.e71cf0b58dc2", "说明待补充 · %d") % maxi(0,3-s.progress.get("blade_buys",[]).size()))
	if s.active_power_id=="BG21_HERO_020p":text=progress_text(text,ExternalText.phrase("domain_rules_round132_powers.slot_description.e71cf0b58dc2", "说明待补充 · %d") % maxi(0,3-s.progress.get("cookie_inputs",[]).size()))
	if s.active_power_id=="TB_BaconShop_HP_102":text=progress_text(text,ExternalText.phrase("domain_rules_round132_powers.slot_description.89f1110ecbb0", "说明待补充 · %d") % maxi(0,3-int(entry.get("game_used",0))))
	if s.active_power_id=="BG22_HERO_007p":text=progress_text(text,ExternalText.phrase("domain_rules_round132_powers.slot_description.a3da95a2ebc3", "说明待补充 · %d") % maxi(0,30-int(p.board.reduce(func(v,c):return v+engine.stats(c).x,0))))
	if s.active_power_id=="BG26_HERO_104p":text=progress_text(text,ExternalText.phrase("domain_rules_round132_powers.slot_description.1f847dcda572", "说明待补充") if int(engine.state.round)%3==0 else ExternalText.phrase("domain_rules_round132_powers.slot_description.c4bb2b3991f7", "说明待补充 · %d") % (3-int(engine.state.round)%3))
	if s.active_power_id in ["BG31_HERO_005p","TB_BaconShop_HP_046"] and int(entry.get("game_used",0))>0:text+=ExternalText.phrase("domain_rules_round132_powers.slot_description.6f02cb63a8a8", "说明待补充")
	if s.active_power_id=="BG32_HERO_002p":text=progress_text(text,ExternalText.phrase("domain_rules_round132_powers.slot_description.7aa9ae0a8e16", "说明待补充") if p.sessions.get("buttons",{}).get("resolved",false) else ExternalText.phrase("domain_rules_round132_powers.slot_description.50b425574a4a", "说明待补充") if int(engine.state.round)>=8 else ExternalText.phrase("domain_rules_round132_powers.slot_description.c4bb2b3991f7", "说明待补充 · %d") % (8-int(engine.state.round)))
	if s.active_power_id=="BG35_HERO_001p":text=progress_text(text,ExternalText.phrase("domain_rules_round132_powers.slot_description.449e98eb98ee", "说明待补充") if s.progress.has("genn_due") and not p.choices.any(func(choice):return choice.get("source","")=="genn" and int(choice.get("slot_id",-1))==int(s.slot_id)) else ExternalText.phrase("domain_rules_round132_powers.slot_description.db3519b0f3bf", "说明待补充") if entry.get("genn_started",false) else ExternalText.phrase("domain_rules_round132_powers.slot_description.5c9680e626fa", "说明待补充") if int(engine.state.round)>=4 else ExternalText.phrase("domain_rules_round132_powers.slot_description.c4bb2b3991f7", "说明待补充 · %d") % (4-int(engine.state.round)))
	if s.active_power_id=="BG36_HERO_101p":text=progress_text(text,ExternalText.phrase("domain_rules_round132_powers.slot_description.a615b1b72fd5", "说明待补充") if int(engine.state.round)>=7 else ExternalText.phrase("domain_rules_round132_powers.slot_description.c4bb2b3991f7", "说明待补充 · %d") % (7-int(engine.state.round)))
	if s.active_power_id=="BG36_HERO_105p":text=progress_text(text,ExternalText.phrase("domain_rules_round132_powers.slot_description.c4bb2b3991f7", "说明待补充 · %d") % (4-int(engine.state.round)%4))
	if s.active_power_id=="BG27_HERO_801p2":
		var debt=0
		for c in p.hand+p.board+p.pending_rewards:debt=maxi(debt,int(c.get("card_lock",{}).get("debt",0)))
		for choice in p.choices:debt=maxi(debt,int(choice.get("lock",{}).get("debt",0)))
		for due in p.get("hero_start_due",[]):debt=maxi(debt,int(due.get("lock",{}).get("debt",0)))
		text=progress_text(text,ExternalText.phrase("domain_rules_round132_powers.slot_description.e5cb0338129b", "说明待补充 · %d") % debt if debt>0 else ExternalText.phrase("domain_rules_round132_powers.slot_description.a615b1b72fd5", "说明待补充"))
	if s.active_power_id in ["TB_BaconShop_HP_041a","TB_BaconShop_HP_041c","TB_BaconShop_HP_041d","TB_BaconShop_HP_041g","TB_BaconShop_HP_041h","TB_BaconShop_HP_041i","TB_BaconShop_HP_041j","TB_BaconShop_HP_041k"]:text=ExternalText.phrase("domain_rules_round132_powers.slot_description.aaab0a99f01d", "说明待补充 · %s") % str(s.progress.get("rat_tribe",""))
	if s.active_power_id=="TB_BaconShop_HP_036":text=progress_text(text,ExternalText.phrase("domain_rules_round132_powers.slot_description.a3da95a2ebc3", "说明待补充 · %d") % maxi(0,150-int(s.progress.get("jar_damage",0))))
	if s.active_power_id=="BG20_HERO_242p":text=progress_text(text,ExternalText.phrase("domain_rules_round132_powers.slot_description.a16454078535", "说明待补充 · %d") % maxi(0,20-int(p.get("guff_progress",0))))
	if s.active_power_id==engine.R134.POWER:text=ExternalText.phrase("domain_rules_round132_powers.slot_description.c9e642a680f4", "说明待补充 · %d / %d") % [engine.R134.tier(int(engine.state.round)),4-int(engine.state.round)%4]
	if s.active_power_id==engine.R133.TICKETS:text+=ExternalText.phrase("domain_rules_round132_powers.slot_description.e6411cc205af", "说明待补充 · %d") % int(s.progress.get("tickets",0))
	if s.active_power_id==engine.R133.FLIGHT:
		var flight=s.progress.get("flight",{});text=ExternalText.phrase("domain_rules_round132_powers.slot_description.290048ce7fcf", "说明待补充") if flight.is_empty() else engine.content.get_def(flight.id).name+ExternalText.phrase("domain_rules_round132_powers.slot_description.5927fcdd3c78", "说明待补充 · %d") % int(flight.remaining)
	return str(d.get("name",ExternalText.phrase("domain_rules_round132_powers.slot_description.592f091121bb", "说明待补充")))+"\n"+text+ExternalText.phrase("domain_rules_round132_powers.slot_description.212a1a859cb7", "\n说明待补充 · %d / %d") % [cost(engine,p,s),engine.Powers.used(engine,p)]

static func description_parameters(engine,p: Dictionary,slot_id: int) -> Dictionary:
	var s=engine.Powers.selected(engine,p,slot_id);var entry=data(engine,p,s);var id=str(s.active_power_id);var round_number=int(engine.state.round)
	var result={"effective_cost":cost(engine,p,s),"used":int(entry.get("used",0)),"round":round_number,"progress":0,"threshold":0,"remaining":0,"tickets":int(s.progress.get("tickets",0)),"turns_remaining":0,"bound_name":"","ready":false}
	match id:
		"BG20_HERO_280p5":result.threshold=3;result.progress=3 if int(entry.get("blade_reward_round",-1))==round_number else s.progress.get("blade_buys",[]).size()
		"BG21_HERO_020p":result.threshold=3;result.progress=s.progress.get("cookie_inputs",[]).size()
		"TB_BaconShop_HP_102":result.threshold=3;result.progress=int(entry.get("game_used",0))
		"BG22_HERO_007p":result.threshold=30;result.progress=int(p.board.reduce(func(v,c):return v+engine.stats(c).x,0))
		"BG26_HERO_104p":result.threshold=3;result.progress=3 if round_number%3==0 else round_number%3
		"BG32_HERO_002p":result.threshold=8;result.progress=mini(8,round_number)
		"BG35_HERO_001p":result.threshold=4;result.progress=mini(4,round_number)
		"BG36_HERO_101p":result.threshold=7;result.progress=mini(7,round_number)
		"BG36_HERO_105p":result.threshold=4;result.progress=round_number%4
		"TB_BaconShop_HP_036":result.threshold=150;result.progress=int(s.progress.get("jar_damage",0))
		"BG20_HERO_242p":result.threshold=20;result.progress=int(p.get("guff_progress",0))
	if id==engine.R134.POWER:result.threshold=4;result.progress=round_number%4
	result.remaining=maxi(0,int(result.threshold)-int(result.progress));result.turns_remaining=result.remaining;result.ready=int(result.threshold)>0 and result.remaining==0
	if id==engine.R133.TICKETS:result.threshold=3;result.progress=result.tickets;result.remaining=maxi(0,3-int(result.tickets))
	var flight=s.progress.get("flight",{})
	if not flight.is_empty():result.turns_remaining=int(flight.remaining);result.remaining=result.turns_remaining;result.bound_name=str(engine.content.get_def(flight.id).name)
	return result

static func slot_description(engine,p: Dictionary,slot_id: int) -> String:
	return ExternalText.describe(engine.content.get_def(engine.Powers.selected(engine,p,slot_id).active_power_id), data(engine,p,engine.Powers.selected(engine,p,slot_id)), p, _computed_slot_description(engine,p,slot_id), "body", description_parameters(engine,p,slot_id))

# Committed sale tails survive choices/save-load. Candidate selection occurs only after
# sale effects, deaths and rewards settle; never during availability or rendering.
static func resume_devour(engine) -> void:
	if not engine.state.has("devour_tail"):return
	var tail=engine.state.devour_tail
	var p=engine.state.players[int(tail.owner)]
	if engine.state.has("confirmation") or engine.state.has("cast_tail") or engine.state.has("play_tail") or not engine.state.get("effect_queue",[]).is_empty() or not p.choices.is_empty() or engine.R134.pending(p):return
	engine.state.erase("devour_tail")
	var candidates=p.board.filter(func(c):return int(c.instance_id)!=int(tail.source_instance) and engine.content.get_def(c.def_id).kind=="minion") if p.alive else []
	var before=int(engine.state.streams.effects);var target_id=-1
	if not candidates.is_empty():
		var target=candidates[engine.RNG.next(engine.state.streams,"effects",candidates.size())]
		target_id=int(target.instance_id);engine.buff(target,int(tail.attack),int(tail.health))
	engine.emit("DevourResolved",int(p.id),{"source_instance":tail.source_instance,"attack":tail.attack,"health":tail.health,"candidate_instances":candidates.map(func(c):return c.instance_id),"target_instance":target_id,"effects_before":before,"effects_after":int(engine.state.streams.effects),"slot_id":tail.slot_id,"epoch":tail.epoch,"root_action_id":tail.root_action_id,"consumed_snapshot":tail.get("consumed_snapshot",{}).duplicate(true)})

# Old swallow choices were unpaid and had not sold anything. Cancel only that
# uncommitted intent, including its matching sale confirmation; user may reopen power.
static func migrate_devour(engine) -> void:
	for p in engine.state.players:
		var legacy=p.choices.filter(func(c):return c.get("kind","")=="r132_target" and c.get("op","")=="swallow")
		if legacy.is_empty():continue
		var held=engine.state.get("confirmation",{})
		if int(held.get("owner",-1))==int(p.id) and held.get("action","")=="sell" and held.get("resume",{}).get("command","") in ["choose","choose_target"] and legacy.any(func(c):return int(c.get("first_id",-1))==int(held.get("target_instance",-2))):
			engine.state.erase("confirmation");engine.state["confirmation_tickets"]={}
		p.choices=p.choices.filter(func(c):return c not in legacy)
		engine.emit("LegacyDevourChoiceCancelled",int(p.id),{"count":legacy.size(),"reason":"REOPEN_SINGLE_TARGET_POWER","committed":false})
