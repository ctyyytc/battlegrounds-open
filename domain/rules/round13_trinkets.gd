extends RefCounted
const ExternalText = preload("res://domain/resources/external_content.gd")
const U=preload("res://domain/rules/undead_rules.gd")
const RNG=preload("res://domain/rules/deterministic_rng.gd")
const OPS=["give","globe","cathedral","gold_supply","cube","stand","voucher","doll","clock","factory","map","rendle","wallet","unknown","lens","orb","seven_discover","gift_discover","locket","seven_random","hearth","candle","ghost","curator","safety","whistle","dagger","honey","ancient","golden","duplicate","iceblock","faceless","amalgam","marin"]
const RECURSIVE=["BG30_MagicItem_703","BG30_MagicItem_888","BG30_MagicItem_891","BG32_MagicItem_271","BG35_MagicItem_816","BG35_MagicItem_816t","BG35_MagicItem_818"]
const MARIN_BANNED=["BG30_MagicItem_888","BG30_MagicItem_891","BG32_MagicItem_271"]
static func supports(_d: Dictionary,e: Dictionary) -> bool:
	return e.get("handler","")=="round13_item" and e.get("op","") in OPS
static func has(engine,p: Dictionary,id: String) -> bool:
	return p.trinkets.any(func(v):return v.id==id)
static func available(engine,p: Dictionary,category: String) -> bool:
	return engine.R136Slots.available(engine,p,category)
static func old_available(engine,p: Dictionary,category: String) -> bool:
	if p.sessions.has(category):return not p.sessions[category].resolved
	if category=="marin":return engine.has_power(p,"BG30_HERO_304p") and int(engine.state.round)>=5
	if category=="buttons":return engine.has_power(p,"BG32_HERO_002p") and int(engine.state.round)>=8
	if category=="voucher":return p.has("voucher_source")
	return int(engine.state.round)>=(6 if category=="lesser" else int(p.get("greater_unlock",9)))
static func power_description(engine,p: Dictionary) -> String:
	return ExternalText.phrase("domain_rules_round13_trinkets.power_description.f1caa26bec23", "说明待补充 · %s") % (ExternalText.phrase("domain_rules_round13_trinkets.power_description.cd008a306777", "说明待补充") if p.sessions.has("marin") and p.sessions.marin.resolved else ExternalText.phrase("domain_rules_round13_trinkets.power_description.c1ca94e48e1c", "说明待补充") if int(engine.state.round)>=5 else ExternalText.phrase("domain_rules_round13_trinkets.power_description.7bd736c78358", "说明待补充 · %d") % (5-int(engine.state.round)))
static func item(engine,p: Dictionary,iid: int) -> Dictionary:
	for v in p.trinkets:
		if int(v.get("instance_id",-1))==iid:return v
	return {}
static func original_id(engine,c: Dictionary) -> String:
	var d=engine.content.get_def(c.def_id);var base=str(d.get("base_id",d.id))
	if base=="BG32_236":return "BG32_236_G"
	return base
static func seven_pool(engine,golden: bool=false) -> Array:
	var pool=[]
	for d in engine.content.definitions.values():
		if d.get("kind","")=="minion" and d.get("implemented",false) and int(d.get("tier",0))==7 and d.get("acquisition_policy","")=="seven_special_only" and d.get("golden",false)==golden and engine.content.eligible(d,engine.state.enabled_tribes):pool.append(d.id)
	pool.sort();return pool
static func allowed(engine,p: Dictionary,d: Dictionary) -> bool:
	if d.id in engine.R136.CONFLICTS and engine.R136.scepter_reserved(engine,p):return false
	if (engine.has_power(p,"BG30_HERO_304p") or engine.has_power(p,"BG32_HERO_002p")) and d.id in MARIN_BANNED:return false
	if d.id=="BG35_MagicItem_814" and int(p.tier)>=6:return false
	if d.id in MARIN_BANNED and p.trinkets.any(func(v):return v.id in MARIN_BANNED):return false
	return true
static func install(engine,p: Dictionary,id: String,slot: String,bound: String="",replace_iid: int=-1,power_owner: Dictionary={}) -> Dictionary:
	var d=engine.content.get_def(id)
	if not allowed(engine,p,d):return {}
	if power_owner.is_empty() and replace_iid>=0:power_owner=item(engine,p,replace_iid).get("power_owner",{}).duplicate(true)
	var result={"id":id,"size":d.size,"slot_size":slot,"bound_tribe":bound,"instance_id":int(engine.state.next_instance),"acquired_round":int(engine.state.round),"obtain_done":true}
	engine.state.next_instance+=1
	if not power_owner.is_empty():result["power_owner"]=power_owner.duplicate(true)
	if replace_iid>=0:
		var index=-1
		for i in p.trinkets.size():
			if int(p.trinkets[i].get("instance_id",-1))==replace_iid:index=i;break
		if index<0:return {}
		p.trinkets[index]=result
	else:p.trinkets.append(result)
	engine.emit("TrinketInstalled",int(p.id),{"id":id,"instance_id":result.instance_id,"slot":slot,"replaced":replace_iid})
	engine.trinket_effects(p,"obtain",{},result);return result
static func initialize(engine,p: Dictionary,c: Dictionary) -> void:
	if not c.has("instance_id"):c["instance_id"]=int(engine.state.next_instance);engine.state.next_instance+=1
	if not c.has("acquired_round"):c["acquired_round"]=int(engine.state.round)
static func cycle(engine,c: Dictionary,period: int,obtain: bool=false,initial: bool=false) -> bool:
	if obtain:c["next_round"]=int(engine.state.round)+period;return initial
	if int(engine.state.round)<int(c.get("next_round",int(engine.state.round)+period)):return false
	c["next_round"]=int(engine.state.round)+period;return true
static func free_discover(engine,p: Dictionary,c: Dictionary,kind: String,pool: Array,meta: Dictionary={}) -> void:
	if pool.is_empty():
		if not p.has("pending_special_discoveries"):p["pending_special_discoveries"]=[]
		p.pending_special_discoveries.append({"kind":kind,"source":c.duplicate(true),"meta":meta.duplicate(true)})
		engine.emit("SpecialDiscoveryPending",int(p.id),{"kind":kind,"source":c.instance_id});return
	var ids=RNG.shuffle(pool.duplicate(),engine.state.streams,"choice").slice(0,3);var cards=[]
	for id in ids:
		var card=engine.make_card(id,int(p.id));card["r13_meta"]=meta.duplicate(true);cards.append(card)
	engine.enqueue_choice(p,{"kind":kind,"options":cards,"source_instance":c.instance_id,"acquisition_source":engine.Acquisition.context(engine,c),"meta":meta})
	engine.emit("ChoiceOpened",int(p.id),{"kind":kind,"source_instance":c.instance_id,"count":cards.size()})
static func gifts(engine,p: Dictionary,c: Dictionary,tier: int,board_only: bool=false) -> void:
	var minions=[];var seen=[]
	var ids=p.board.map(func(v):return original_id(engine,v)) if board_only else seven_pool(engine) if tier==7 else engine.generation_candidates(p,{"tier":tier},{})
	for id in ids:
		if id not in seen:minions.append(engine.content.get_def(id));seen.append(id)
	var gift_defs=[]
	for d in engine.content.definitions.values():
		if d.kind=="dark_gift" and d.implemented:gift_defs.append({"id":int(d.numeric_id),"min_turn":d.min_turn,"max_turn":d.max_turn})
	var policy={"player":p,"enabled":engine.state.enabled_tribes,"tiers":range(1,8) if board_only else [tier],"special_free":true}
	var options=engine.Selection.Choices.gift_options(minions,gift_defs,int(engine.state.round),engine.state.enabled_tribes,[],engine.state.streams,policy)
	if options.is_empty():free_discover(engine,p,c,"r13_gift",[],{"tier":tier,"board_only":board_only});return
	var cards=[]
	for option in options:
		var card=engine.make_card(option.id,int(p.id));card["r13_gift_id"]=int(option.gift_id);cards.append(card)
	engine.enqueue_choice(p,{"kind":"r13_gift","options":cards,"source_instance":c.instance_id,"acquisition_source":engine.Acquisition.context(engine,c)})
static func retry_pending(engine,p: Dictionary) -> void:
	var pending=p.get("pending_special_discoveries",[]);p["pending_special_discoveries"]=[]
	for request in pending:
		if request.kind=="r13_gift":gifts(engine,p,request.source,int(request.meta.tier),request.meta.get("board_only",false))
		elif request.kind=="r13_globe":free_discover(engine,p,request.source,request.kind,engine.generation_candidates(p,{"tier":6},{}),request.meta)
		else:free_discover(engine,p,request.source,request.kind,seven_pool(engine,request.meta.get("golden",false)),request.meta)
static func selected(engine,p: Dictionary,choice: Dictionary,card: Dictionary) -> void:
	if card.has("r13_gift_id"):
		var gift_id=int(card.r13_gift_id)
		card.erase("r13_gift_id")
		engine.Gifts.acquire(engine,p,card,gift_id,"round13_special")
	if choice.kind=="r13_seven" and choice.meta.get("lock",false):card["locked_until_round"]=int(engine.state.round)+2
	if choice.kind=="r13_factory":
		var source=item(engine,p,int(choice.source_instance))
		if not source.is_empty():source["factory_id"]=card.def_id
	if choice.kind=="r13_hearth":preload("res://domain/rules/stat_reset.gd").perfect(engine,card,Vector2i(30,30))
static func special_choice(engine,p: Dictionary,choice: Dictionary,index: int) -> String:
	if index<0 or index>=choice.options.size():return "INVALID_OPTION"
	if choice.kind=="r13_replace":
		var source=item(engine,p,int(choice.source_instance))
		if source.is_empty():return "TRINKET_SOURCE_MISSING"
		var option=choice.options[index]
		if not allowed(engine,p,engine.content.get_def(option.def_id)) or not engine.R136Slots.owner_valid(engine,p,source.get("power_owner",{})):return "STALE_TRINKET_CANDIDATE"
		p.choices.pop_front()
		install(engine,p,option.def_id,str(source.slot_size),str(option.get("bound_tribe","")),int(source.instance_id));return ""
	if choice.kind=="r13_transform":
		var target=engine.find_target(p,int(choice.target_instance))
		if target.is_empty():return "TARGET_MISSING"
		var option=choice.options[index];var new_card=engine.make_card(option.def_id,int(p.id));new_card.instance_id=target.instance_id
		new_card.modifiers=target.modifiers.duplicate(true);new_card.gifts=target.gifts.duplicate(true);new_card.extra_keywords=target.extra_keywords.duplicate(true);new_card.pool_copies=0
		if target.has("gold_reward_excluded"):engine.exclude_gold_reward(new_card,str(target.gold_reward_excluded))
		engine.return_pool(target);target.clear();target.merge(new_card);p.choices.pop_front()
		engine.Naga.recruit_entered(engine,p,target);engine.check_triples(p);return ""
	return "UNKNOWN_R13_CHOICE"
static func random_replacement(engine,p: Dictionary,c: Dictionary,size: String,choose: bool) -> void:
	var pool=engine.content.pool("trinket",engine.state.enabled_tribes,false).filter(func(id):return id not in RECURSIVE and engine.content.get_def(id).size==size and allowed(engine,p,engine.content.get_def(id)))
	if pool.is_empty():engine.emit("TrinketReplacementUnavailable",int(p.id),{"instance_id":c.instance_id});return
	if choose:
		var options=[]
		for id in RNG.shuffle(pool,engine.state.streams,"choice").slice(0,2):options.append({"def_id":id,"instance_id":int(engine.state.next_instance),"owner":p.id,"modifiers":[],"gifts":[],"extra_keywords":[],"gold_route":"","pool_copies":0,"bound_tribe":engine.Special.preference(p.hand,p.board,engine.content.definitions,engine.state.enabled_tribes)})
		engine.enqueue_choice(p,{"kind":"r13_replace","source_instance":c.instance_id,"options":options})
	else:
		var id=engine.Naga.pick(engine,pool);install(engine,p,id,str(c.slot_size),str(c.get("bound_tribe","")),int(c.instance_id))
static func valid_target(engine,p: Dictionary,d: Dictionary,c: Dictionary) -> bool:
	if d.effects.is_empty() or d.effects[0].get("handler","")!="round13_item":return true
	match str(d.effects[0].op):
		"duplicate":return not c.is_empty() and int(engine.content.get_def(c.def_id).get("tier",7))<=3
		"golden":return not c.is_empty() and c in p.board and not engine.content.get_def(c.def_id).get("golden",false) and engine.content.get_def(c.def_id).get("golden_id","")!=""
		"ancient":return not c.is_empty() and int(engine.content.get_def(c.def_id).get("tier",7))<6 and not engine.generation_candidates(p,{"tier":int(engine.content.get_def(c.def_id).tier)+1},{}).is_empty()
	return true
static func extra_cast(engine,p: Dictionary,spell: Dictionary) -> int:
	if not spell.get("counts_player_cast",true):return 0
	var extra=0
	for c in p.trinkets:
		if c.id=="BG30_MagicItem_434" and c.get("cathedral_ready",false):c.cathedral_ready=false;extra+=1
	return extra
static func aura(engine,p: Dictionary) -> Vector2i:
	var v=Vector2i.ZERO
	for c in p.trinkets:
		if c.id=="BG36_MagicItem_371":v+=Vector2i.ONE*(1+int(c.get("honey_growth",0)))
	return v
static func after_spell(engine,p: Dictionary,spell: Dictionary,target: Dictionary,friendly_cast: bool=false) -> void:
	if not spell.get("counts_player_cast",true) or target.is_empty() or engine.content.get_def(target.def_id).kind!="minion":return
	for c in p.trinkets.duplicate():
		if c.id=="BG36_MagicItem_371":c["honey_growth"]=int(c.get("honey_growth",0))+1
		if c.id!="BG36_MagicItem_211" or not friendly_cast:continue
		var targets=U.board(engine,p).filter(func(v):return int(v.instance_id)!=int(target.instance_id) and engine.Naga.valid_target(engine,p,spell,v))
		var forwarded=engine.Naga.pick(engine,targets)
		if forwarded==null:continue
		var copy=spell.duplicate(true);copy["counts_player_cast"]=false;copy["cast_owner"]="trinket";copy["forward_instance"]=c.instance_id
		engine.emit("LocketForwarded",int(p.id),{"trinket":c.instance_id,"spell":spell.id,"target":forwarded.instance_id});engine.cast(p,copy,forwarded,0,0,false,1)
static func amalgam_gain(engine,c: Dictionary,a: int,h: int,combat: bool=false) -> void:
	if engine.content.get_def(c.def_id).get("base_id","")!="TB_BaconShop_HP_033t":return
	var p=U.board_player(engine,int(c.owner))
	for v in U.board(engine,p).duplicate():
		if v.def_id!="TB_BaconShop_HERO_33_Buddy_G" or int(v.instance_id)==int(c.instance_id):continue
		if combat:U.local_buff(engine,v,2*a,2*h)
		else:engine.buff(v,2*a,2*h)
static func battle_damage(engine,p: Dictionary,damage: int) -> bool:
	if int(p.get("iceblock_immune_round",-1))==int(engine.state.round):return true
	if p.get("iceblock",false) and damage-int(p.armor)>=int(p.health):
		p.iceblock=false;p["iceblock_immune_round"]=int(engine.state.round);engine.emit("IceBlockTriggered",int(p.id),{"damage":damage});return true
	return false
static func button_refresh(engine,p: Dictionary) -> bool:
	var whistle=p.trinkets.filter(func(v):return v.id=="BG35_MagicItem_930" and v.get("whistle_ready",false))
	if not whistle.is_empty():
		whistle[0].whistle_ready=false
		for c in p.shop:engine.return_pool(c)
		p.shop=[];p["whistle_queue"]=[];p.frozen=false
		for c in p.board:
			var copy=engine.make_card(original_id(engine,c),int(p.id));copy["whistle_copy"]=true
			if p.shop.size()<7:p.shop.append(copy)
			else:p.whistle_queue.append(copy)
		engine.emit("ShopRefreshed",int(p.id),{"special":"whistle"});engine.trinket_effects(p,"refresh");engine.Elementals.refresh(engine,p);engine.Quilboar.refresh(engine,p);engine.R133.refreshed(engine,p);return true
	var candles=p.trinkets.filter(func(v):return v.id=="BG32_MagicItem_366" and int(v.get("candle_remaining",2))>0)
	if candles.is_empty():return false
	for c in candles:c["candle_remaining"]=int(c.get("candle_remaining",2))-1
	p["candle_drawing"]=true;engine.refill_shop(p,false);p.erase("candle_drawing");return true
static func bought(engine,p: Dictionary) -> void:
	if not p.get("whistle_queue",[]).is_empty() and p.shop.size()<7:
		p.shop.append(p.whistle_queue.pop_front());engine.emit("WhistleBackfill",int(p.id),{"remaining":p.whistle_queue.size()})
static func start_after(engine,p: Dictionary) -> void:
	retry_pending(engine,p);engine.R136Slots.cube_start(engine,p)
static func execute(engine,p: Dictionary,e: Dictionary,c: Dictionary) -> bool:
	if not supports({},e):return false
	var source=engine.effect_source;var obtain=e.get("trigger","")=="obtain";var target=engine.effect_target
	if engine.content.get_def(source.get("id",source.get("def_id",""))).get("kind","")=="trinket":initialize(engine,p,source)
	match str(e.op):
		"give":engine.receive_card(p,engine.make_card(e.id,int(p.id)),source)
		"seven_random":
			var id=engine.Naga.pick(engine,seven_pool(engine))
			if id!=null:engine.receive_card(p,engine.make_card(id,int(p.id)),source)
		"seven_discover":free_discover(engine,p,source,"r13_seven",seven_pool(engine,e.golden),{"golden":e.golden,"lock":true})
		"gift_discover":gifts(engine,p,source,int(e.tier))
		"dagger":
			if cycle(engine,source,2,obtain,true):gifts(engine,p,source,7,true)
		"globe":
			if cycle(engine,source,2,obtain):
				engine.gain_coins(p,2)
				free_discover(engine,p,source,"r13_globe",engine.generation_candidates(p,{"tier":6},{}),{"tier":6})
		"gold_supply":
			if obtain:source["supply_remaining"]=3
			else:
				source["supply_remaining"]=int(source.get("supply_remaining",3))-1
				if int(source.supply_remaining)<=0:source.supply_remaining=3;engine.receive_card(p,engine.make_card("BG26_813t",int(p.id)),source)
		"factory":
			if source.has("factory_id"):engine.receive_card(p,engine.make_card(source.factory_id,int(p.id)),source)
			elif not p.choices.any(func(v):return v.kind=="r13_factory" and int(v.source_instance)==int(source.instance_id)):engine.resolve_discovery(p,engine.generation_candidates(p,{"tier":e.tier,"typed":true},{}).filter(func(id):return not engine.card_types({"def_id":id}).is_empty()),"r13_factory",1,source)
		"map":
			if not source.get("map_done",false) and cycle(engine,source,2,obtain):source["map_done"]=true;engine.gain_coins(p,10)
		"wallet":
			if not obtain and int(p.tier)==6 and not source.get("wallet_done",false):source["wallet_done"]=true;engine.gain_coins(p,12)
		"lens":
			if cycle(engine,source,2,obtain,true):engine.receive_card(p,engine.make_card("BG35_MagicItem_817t",int(p.id)),source)
		"hearth":engine.resolve_discovery(p,engine.generation_candidates(p,{"tier":6},{}),"r13_hearth",2,source)
		"doll":engine.gain_coins(p,2)
		"rendle":
			if not p.shop.is_empty():
				var highest=0
				for v in p.shop:highest=maxi(highest,int(engine.content.get_def(v.def_id).get("tier",0)))
				var stolen=engine.Naga.pick(engine,p.shop.filter(func(v):return int(engine.content.get_def(v.def_id).get("tier",0))==highest));p.shop.erase(stolen);engine.receive_card(p,stolen,source)
		"cathedral":source["cathedral_ready"]=true
		"honey":source["honey_growth"]=0
		"candle":source["candle_remaining"]=2
		"whistle":source["whistle_ready"]=true
		"safety":p["iceblock"]=true;engine.gain_coins(p,5)
		"iceblock":p["iceblock"]=true
		"curator":
			engine.receive_card(p,engine.make_card("TB_BaconShop_HERO_33_Buddy_G",int(p.id)),source)
			var card=engine.make_card("TB_BaconShop_HP_033t",int(p.id));card["base_override"]={"attack":10,"health":10};engine.receive_card(p,card,source)
		"duplicate":engine.receive_card(p,engine.make_card(original_id(engine,target),int(p.id)),source)
		"golden":engine.Pirates.transform_gold(engine,target)
		"ancient":
			var pool=engine.generation_candidates(p,{"tier":int(engine.content.get_def(target.def_id).tier)+1},{})
			engine.resolve_discovery(p,pool,"r13_transform",1,source);p.choices[-1]["target_instance"]=target.instance_id
		"faceless":
			if not target.is_empty():
				var id=int(c.instance_id);var copy=engine.Fish.copy(engine,p,target);copy.instance_id=id;engine.return_pool(c);c.clear();c.merge(copy)
				engine.Naga.recruit_entered(engine,p,c)
		"cube":
			engine.R136Slots.cube(engine,p,source);random_replacement(engine,p,source,"lesser",true)
		"unknown":engine.gain_coins(p,int(e.get("coins",0)));random_replacement(engine,p,source,e.size,false)
		"clock":engine.gain_coins(p,2);p["greater_unlock"]=mini(int(p.get("greater_unlock",9)),int(engine.state.round)+1)
		"voucher":
			if obtain:source["next_round"]=int(engine.state.round)+2
			engine.R136Slots.sync_vouchers(engine,p)
		"orb":
			engine.gain_coins(p,10);source["orb_ready"]=true;convert_greater(engine,p)
		"ghost","locket","stand","amalgam","marin":pass
	return true
static func convert_greater(engine,p: Dictionary) -> void:
	engine.R136Slots.adjust_orb(engine,p)
static func command(engine,p: Dictionary,kind: String,args: Dictionary) -> String:
	return engine.R136Slots.command(engine,p,kind,args)
static func legacy_command(engine,p: Dictionary,kind: String,args: Dictionary) -> String:
	var category=str(args.get("category",""))
	if category not in ["lesser","greater","marin","voucher","buttons"]:return "INVALID_CHOICE_CATEGORY"
	if kind=="open_choice":
		if p.sessions.has(category) and not p.sessions[category].resolved:p.sessions[category].deferred=false;return ""
		if p.sessions.has(category) and p.sessions[category].resolved:return "TRINKET_ALREADY_OWNED"
		var unlock=6 if category=="lesser" else int(p.get("greater_unlock",9)) if category=="greater" else 5 if category=="marin" else 8 if category=="buttons" else 0
		if int(engine.state.round)<unlock:return "CHOICE_LOCKED"
		if category=="marin" and not engine.has_power(p,"BG30_HERO_304p"):return "INVALID_CHOICE_CATEGORY"
		if category=="buttons" and not engine.has_power(p,"BG32_HERO_002p"):return "INVALID_CHOICE_CATEGORY"
		if category=="voucher" and not p.has("voucher_source"):return "CHOICE_LOCKED"
		var size="lesser" if category in ["lesser","marin"] else "greater"
		if category not in ["marin","buttons"] and p.trinkets.any(func(v):return v.id=="BG35_MagicItem_818" and v.get("orb_ready",false)):size="lesser"
		var options=engine.Selection.generate(engine,p,size,[])
		if options.size()!=4:return "INSUFFICIENT_IMPLEMENTED_CANDIDATES"
		p.sessions[category]={"kind":category,"offered_size":size,"options":options,"created_round":engine.state.round,"refreshes":0,"revision":0,"resolved":false,"deferred":false}
		engine.Choices.paid_identity(engine,p,p.sessions[category])
		engine.emit("ChoiceOpened",int(p.id),{"kind":category,"options":options,"offered_size":size});return ""
	if not p.sessions.has(category) or p.sessions[category].resolved:return "NO_CHOICE"
	var session=p.sessions[category]
	if kind=="defer_choice":session.deferred=true;return ""
	if kind=="refresh_choice":
		var quota_kind="greater" if category in ["greater","voucher","buttons"] else "lesser"
		if not engine.Selection.Choices.refresh_allowed(quota_kind,int(session.refreshes),int(p.trinket_refreshes)):return "CHOICE_REFRESH_LIMIT"
		var cost=engine.Selection.Choices.refresh_cost(quota_kind,int(p.trinket_refreshes))
		if int(p.coins)<cost:return "NOT_ENOUGH_COINS"
		var options=engine.Selection.generate(engine,p,session.offered_size,session.options.map(func(v):return v.id))
		if options.size()!=4:return "INSUFFICIENT_IMPLEMENTED_CANDIDATES"
		p.coins-=cost;engine.Elementals.spent(engine,p,cost);session.options=options;session.refreshes+=1;session.revision+=1;p.trinket_refreshes+=1;return ""
	if kind!="resolve_choice":return "UNKNOWN_CHOICE_COMMAND"
	if (session.get("require_revision",false) or args.has("revision")) and int(args.get("revision",-1))!=int(session.revision):return "STALE_CHOICE"
	var index=int(args.get("index",-1))
	if index<0 or index>=session.options.size():return "INVALID_OPTION"
	var option=session.options[index]
	if args.has("option_id") and str(args.option_id)!=str(option.id):return "STALE_CHOICE"
	if not allowed(engine,p,engine.content.get_def(option.id)):return "STALE_TRINKET_CANDIDATE"
	if int(p.coins)<int(option.cost):return "NOT_ENOUGH_COINS"
	var old=-1;var slot=category
	if category=="voucher":
		old=int(p.voucher_source);var original=item(engine,p,old)
		if original.is_empty():return "TRINKET_SOURCE_MISSING"
		slot=str(original.slot_size)
	p.coins-=int(option.cost);engine.Elementals.spent(engine,p,int(option.cost));session.resolved=true;session.deferred=true
	for c in p.trinkets:
		if c.id=="BG35_MagicItem_818" and c.get("orb_ready",false):c.orb_ready=false
	var stands=p.trinkets.filter(func(v):return v.id=="BG30_MagicItem_888").duplicate()
	install(engine,p,option.id,slot,option.bound_tribe,old)
	if engine.content.get_def(option.id).size=="greater":
		for c in stands:install(engine,p,option.id,str(c.slot_size),option.bound_tribe,int(c.instance_id))
	engine.check_triples(p);engine.emit("ChoiceResolved",int(p.id),{"kind":category,"id":option.id});return ""
