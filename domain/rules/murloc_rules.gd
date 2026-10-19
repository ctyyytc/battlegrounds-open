extends RefCounted
const RNG=preload("res://domain/rules/deterministic_rng.gd")
const U=preload("res://domain/rules/undead_rules.gd")
const OPS=["hand_scout","random_minion","hurt_hand","hand_summon","family","cost_spells","hand_grow","give","repeat_battlecry","left_hand","give_venom","highest_attack","parents","fish_spell","fish_discover","chorus","teach","low_play","conch","deep","suppress","special_shop","flippers","blessing","stir","brann","brann_type","collage","conch_portrait","warcry_free","book","typewriter","reflect","sinstone","memory","morgl","learned","flurgl","sneed","barov","guff"]
static func supports(_d: Dictionary,e: Dictionary) -> bool:
	return e.get("handler","")=="round11" and e.get("op","") in OPS+["murky"]
static func specs(engine,c: Dictionary,op: String) -> Array:
	return engine.content.get_def(c.get("def_id",c.get("id",""))).get("effects",[]).filter(func(e):return e.get("handler","")=="round11" and e.get("op","")==op)
static func has(engine,p: Dictionary,op: String) -> bool:
	return p.trinkets.any(func(c):return not specs(engine,c,op).is_empty())
static func pick(engine,a: Array) -> Variant:
	return null if a.is_empty() else a[RNG.next(engine.state.streams,"effects",a.size())]
static func hand(engine,p: Dictionary,tribe: String="") -> Array:
	return p.hand.filter(func(c):return engine.content.get_def(c.def_id).kind=="minion" and (tribe=="" or U.tribe(engine,c,tribe)))
static func left(engine,p: Dictionary,a: int,h: int,tribe: String="") -> void:
	var cards=hand(engine,p,tribe)
	if not cards.is_empty():engine.buff(cards[0],a,h)
static func fish_buff(engine,p: Dictionary,source: Dictionary,a: int,h: int,exclude: bool=false) -> void:
	for c in U.board(engine,p):
		if U.tribe(engine,c,"鱼人") and (not exclude or int(c.instance_id)!=int(source.get("instance_id",-1))):engine.buff(c,a,h)
	left(engine,p,a,h,"鱼人")
static func quota(engine,c: Dictionary,key: String,limit: int) -> int:
	return maxi(0,limit-(int(c.get(key+"_used",0)) if int(c.get(key+"_round",-1))==int(engine.state.round) else 0))
static func use_quota(engine,c: Dictionary,key: String) -> void:
	if int(c.get(key+"_round",-1))!=int(engine.state.round):c[key+"_round"]=int(engine.state.round);c[key+"_used"]=0
	c[key+"_used"]=int(c.get(key+"_used",0))+1
static func copy(engine,p: Dictionary,c: Dictionary,original: bool=false) -> Dictionary:
	var d=engine.content.get_def(c.def_id)
	if original:
		var id=engine.R13Items.original_id(engine,c)
		if engine.content.get_def(id).get("acquisition_policy","")=="structural_alias":id=c.def_id
		return engine.make_card(id,int(p.id))
	var result=c.duplicate(true);result.instance_id=int(engine.state.next_instance);engine.state.next_instance+=1
	result.pool_copies=0;result["attached_pool"]=[];result.erase("shop_price");result.erase("shop_price_source")
	engine.qualify_gold_copy(result,"murloc_copy")
	return result
static func generated(engine,p: Dictionary,c: Dictionary) -> void:
	if engine.content.get_def(c.def_id).get("base_id","")=="BG_LOE_077" and has(engine,p,"brann_type"):c["type_override"]=["鱼人","龙"]
static func played(engine,p: Dictionary,c: Dictionary) -> void:
	var d=engine.content.get_def(c.def_id)
	if d.get("base_id","") in ["BG35_140","BG35_141"]:
		p["family_played"]=int(p.get("family_played",0))+1;c["family_snapshot"]=int(p.family_played)
	if U.tribe(engine,c,"鱼人"):
		for held in hand(engine,p):
			for e in specs(engine,held,"hand_grow"):engine.buff(held,int(e.attack),int(e.health))
		for item in p.trinkets:
			if not specs(engine,item,"stir").is_empty():
				item["stir_progress"]=int(item.get("stir_progress",0))+1
				if int(item.stir_progress)>=5:item.stir_progress-=5;spells(engine,p,2,-1,item)
	if d.has("tier") and int(d.tier)>0 and int(d.tier)<=3:
		for listener in U.board(engine,p).duplicate():
			for e in specs(engine,listener,"low_play"):fish_buff(engine,p,listener,int(e.attack),int(e.health))
static func spells(engine,p: Dictionary,n: int,cost: int=-1,source: Dictionary={}) -> void:
	var options=engine.Naga.spell_pool(engine,p).filter(func(id):return cost<0 or int(engine.content.get_def(id).cost)==cost)
	for unused in n:
		var id=pick(engine,options)
		if id!=null:engine.receive_card(p,engine.make_card(id,int(p.id)),source)
static func bought(engine,p: Dictionary,c: Dictionary) -> void:
	var d=engine.content.get_def(c.def_id)
	if engine.has_power(p,"BG20_HERO_242p"):
		p["guff_progress"]=int(p.get("guff_progress",0))+int(d.get("tier",0))
		while int(p.guff_progress)>=20:
			p.guff_progress-=20
			var reward=engine.make_card("BG_TRIPLE_REWARD_R92",int(p.id));reward["reward_tier"]=mini(int(p.tier)+1,6)
			p["guff_rewards"]=int(p.get("guff_rewards",0))+1;reward["reward_key"]="guff:%d:%d" % [int(p.id),int(p.guff_rewards)]
			reward["reward_source"]={"def_id":p.hero_id,"owner":p.id};engine.receive_card(p,reward,engine.content.get_def(p.hero_id))
	if d.kind=="minion":
		for item in p.trinkets:
			for e in specs(engine,item,"typewriter"):
				if int(item.get("typewriter_used",0))<int(e.amount):item["typewriter_used"]=int(item.get("typewriter_used",0))+1;engine.receive_card(p,copy(engine,p,c),item)
			if d.effects.any(func(e):return e.get("trigger","")=="battlecry") and not specs(engine,item,"warcry_free").is_empty() and quota(engine,item,"warcry",2)>0:use_quota(engine,item,"warcry")
	if d.get("is_tavern_spell",false):
		for source in p.board.duplicate()+p.trinkets.duplicate():
			for e in specs(engine,source,"teach"):
				if quota(engine,source,"teach",int(e.amount))<=0:continue
				use_quota(engine,source,"teach")
				var apprentice=engine.make_card("BG33_890t",int(p.id));apprentice["learned_spell"]=d.id
				engine.receive_card(p,apprentice,engine.Acquisition.context(engine,source,"apprentice"))
static func purchase_cost(engine,p: Dictionary,c: Dictionary,normal: int) -> int:
	var d=engine.content.get_def(c.def_id)
	if d.kind=="minion" and p.get("r134",{}).get("buy_two",false) and normal>0:normal=2
	if d.kind=="minion" and d.effects.any(func(e):return e.get("trigger","")=="battlecry"):
		for item in p.trinkets:
			if not specs(engine,item,"warcry_free").is_empty() and quota(engine,item,"warcry",2)>0:return 0
	var result=0 if normal==0 else int(c.get("shop_price",normal))
	if d.get("is_tavern_spell",false):result=maxi(0,result-int(p.get("r134",{}).get("discount",0)))
	return result
static func leave_shop(c: Dictionary) -> void:
	c.erase("shop_price");c.erase("shop_price_source")
static func sold(engine,p: Dictionary) -> void:
	if not engine.has_power(p,"TB_BaconShop_HP_056"):return
	p["flurgl_sales"]=int(p.get("flurgl_sales",0))+1
	while int(p.flurgl_sales)>=5:
		p.flurgl_sales-=5;random_minion(engine,p,{"amount":1,"tribe":"鱼人"},{})
static func discovered(engine,p: Dictionary,c: Dictionary) -> void:
	for item in p.trinkets:
		if not specs(engine,item,"sinstone").is_empty() and quota(engine,item,"sinstone",2)>0:
			use_quota(engine,item,"sinstone");engine.receive_card(p,copy(engine,p,c),item)
static func initialize(engine,p: Dictionary) -> void:
	if engine.has_power(p,"BG21_HERO_030p") and not p.get("sneed_initialized",false):
		p["sneed_initialized"]=true;p.board.append(engine.make_card("BG21_HERO_030t",int(p.id)))
static func availability(engine,p: Dictionary) -> Dictionary:
	if engine.hero_handler(p) not in ["guff","sneed","flurgl","barov"]:return {}
	if engine.hero_handler(p)!="barov":return {"available":false,"reason":"PASSIVE_POWER","targets":[]}
	var targets=p.board.filter(func(c):return not engine.content.get_def(c.def_id).golden).map(func(c):return c.instance_id)
	var shop=p.shop.filter(func(c):return engine.content.get_def(c.def_id).kind=="minion")
	var reason="POWER_ALREADY_USED" if engine.power_used(p) else "NO_LEGAL_TARGET" if targets.is_empty() or shop.is_empty() else ""
	return {"available":reason=="","reason":reason,"targets":targets,"handler":"barov","cost":0}
static func power(engine,p: Dictionary,args: Dictionary) -> String:
	var q=availability(engine,p);var id=int(args.get("target_id",-1))
	if not q.available:return q.reason
	if id not in q.targets:return "NON_GOLDEN_FRIENDLY_REQUIRED"
	var options=p.shop.filter(func(c):return engine.content.get_def(c.def_id).kind=="minion")
	var incoming=pick(engine,options);var si=engine.find_index(p.shop,int(incoming.instance_id));var bi=engine.find_index(p.board,id)
	var outgoing=p.board[bi];leave_shop(incoming);leave_shop(outgoing)
	p.board[bi]=incoming;p.shop[si]=outgoing;engine.consume_power(p)
	engine.Naga.recruit_entered(engine,p,incoming)
	engine.emit("HeroPowerUsed",int(p.id),{"hero":p.hero_id,"outgoing":outgoing.instance_id,"incoming":incoming.instance_id})
	return ""
static func learned_definition(engine,c: Dictionary) -> Dictionary:
	var root=engine.content.get_def(c.def_id)
	if not c.has("learned_spell"):return root
	var learned=engine.content.get_def(c.learned_spell);root=root.duplicate(true)
	root["learned_spell"]=c.learned_spell
	if engine.Quilboar.choice(learned):
		root.effects=[learned.effects[0].duplicate(true)];root.effects[0].trigger="choice_play"
	else:
		root.effects=[{"handler":"round11","op":"learned","trigger":"battlecry","target":learned.effects[0].get("target","none")}]
	return root
static func learned_sale(engine,c: Dictionary) -> bool:
	return engine.content.get_def(c.get("def_id","")).get("base_id","")=="BG33_890t" and c.has("learned_spell") and engine.content.get_def(c.learned_spell).get("effects",[]).any(func(e):return e.get("op","") in ["avalanche","invoke"])
static func learned_sale_target(engine,p: Dictionary,c: Dictionary) -> int:
	var spell=engine.content.get_def(c.learned_spell)
	var target=engine.effect_target
	if not target.is_empty() and engine.Naga.valid_target(engine,p,spell,target):return int(target.instance_id)
	var options=(U.board(engine,p)+(p.shop if not U.is_combat(engine) else [])).filter(func(v):return engine.Naga.valid_target(engine,p,spell,v))
	var selected=pick(engine,options)
	return int(selected.instance_id) if selected!=null else -1
static func learned_sale_card(engine,p: Dictionary,id: int) -> Dictionary:
	for card in U.board(engine,p)+(p.shop if not U.is_combat(engine) else []):
		if int(card.instance_id)==id:return card
	return {}
static func learn_cast(engine,p: Dictionary,c: Dictionary,spec: Dictionary={}) -> void:
	if not c.has("learned_spell"):return
	var spell=engine.content.get_def(c.learned_spell).duplicate(true)
	var target=engine.effect_target
	# The whole battlecry batch owns this identity, including saved effect tails.
	if learned_sale(engine,c) and spec.has("learned_sale_target"):
		target=learned_sale_card(engine,p,int(spec.learned_sale_target))
		if target.is_empty() or not engine.Naga.valid_target(engine,p,spell,target):
			engine.emit("AutomaticSpellUnavailable",int(p.id),{"id":spell.id,"reason":"LEARNED_SALE_TARGET_GONE"});return
	if not engine.committing_choice.is_empty():spell["selected_choice_ids"]=engine.committing_choice.get("selected_choice_ids",[])
	else:spell["automatic"]=true
	if engine.Quilboar.choice(spell):
		var choice=engine.Quilboar.automatic_choice(engine,p,spell,target);spell=choice.spell;target=choice.target
		for id in spell.get("selected_choice_ids",[]):
			if not engine.Naga.valid_target(engine,p,engine.content.get_def(id),target):engine.emit("AutomaticSpellUnavailable",int(p.id),{"id":spell.id,"reason":"NO_LEARNED_CHOICE_TARGET"});return
	elif engine.Quilboar.requires_target(spell) and (target.is_empty() or not engine.Naga.valid_target(engine,p,spell,target)):
		var options=(U.board(engine,p)+(p.shop if not U.is_combat(engine) else [])).filter(func(v):return engine.Naga.valid_target(engine,p,spell,v))
		var selected=pick(engine,options);target=selected if selected!=null else {}
	if not engine.Naga.valid_target(engine,p,spell,target):engine.emit("AutomaticSpellUnavailable",int(p.id),{"id":spell.id,"reason":"NO_LEARNED_TARGET"});return
	var prior=engine.effect_source;engine.effect_source=c;engine.cast(p,spell,target);engine.effect_source=prior
static func activate_query(engine,p: Dictionary,c: Dictionary) -> Dictionary:
	var es=engine.content.get_def(c.def_id).effects.filter(func(e):return e.get("handler","")=="round11" and e.get("trigger","")=="activate")
	if es.is_empty():return {}
	var targets=[]
	if es[0].op=="repeat_battlecry":targets=p.board.filter(func(v):return engine.Triggers.effects(engine,v).any(func(e):return e.get("trigger","")=="battlecry")).map(func(v):return v.instance_id)
	else:targets=[-1] if not engine.generation_candidates(p,es[0],c).is_empty() else []
	var reason="ALREADY_ACTIVATED" if int(c.get("activated_round",-1))==int(engine.state.round) else "NOT_ENOUGH_COINS" if int(p.coins)<int(es[0].cost) else "NO_LEGAL_TARGET" if targets.is_empty() else ""
	return {"available":reason=="","reason":reason,"targets":targets,"cost":es[0].cost}
static func activate(engine,p: Dictionary,c: Dictionary,args: Dictionary) -> String:
	var q=activate_query(engine,p,c)
	if not q.available:return q.reason
	var id=int(args.get("target_id",-1))
	if id not in q.targets:return "TARGET_REQUIRED"
	p.coins-=int(q.cost);c["activated_round"]=int(engine.state.round);engine.Elementals.spent(engine,p,int(q.cost))
	var target=engine.find_target(p,id)
	for e in specs(engine,c,"repeat_battlecry"):
		for unused in int(e.amount):engine.run_effects(p,target,"battlecry")
	for e in specs(engine,c,"random_minion"):random_minion(engine,p,e,c)
	engine.emit("MinionActivated",int(p.id),{"instance_id":c.instance_id});engine.drain_rewards(p);engine.check_triples(p)
	return ""
static func random_minion(engine,p: Dictionary,e: Dictionary,c: Dictionary) -> void:
	var options=engine.generation_candidates(p,e,c)
	for unused in int(e.get("amount",1)):
		var id=pick(engine,options)
		if id!=null:engine.receive_card(p,engine.make_card(id,int(p.id)),c)
static func special_shop(engine,p: Dictionary,mode: String) -> void:
	p["whistle_queue"]=[]
	for c in p.shop:engine.return_pool(c)
	p.shop=[];p.frozen=false
	var n=mini(7,int(engine.content.rules.shop_sizes[int(p.tier)-1])+1)
	if engine.Demons.has(engine,p,"gauntlet"):n=7
	for unused in n:
		var c={}
		if mode=="spell":c=engine.Demons.draw_spell(engine,p)
		else:
			var options=[]
			for id in engine.state.pool:
				var d=engine.content.get_def(id)
				if int(d.tier)<=int(p.tier) and (not engine.R13Items.has(engine,p,"BG30_MagicItem_998") or int(d.tier) not in [1,2]) and d.effects.any(func(e):return e.get("trigger","")=="battlecry"):
					for copy_no in int(engine.state.pool[id]):options.append(id)
			var id=pick(engine,options)
			if id!=null:
				engine.state.pool[id]-=1;c=engine.make_card(id,int(p.id),1)
				engine.Pirates.growth(engine,p,c);engine.Demons.growth(engine,p,c)
				c["shop_price"]=1;c["shop_price_source"]="BG35_MagicItem_755t"
		if c.is_empty():break
		p.shop.append(c)
	engine.emit("ShopRefreshed",int(p.id),{"special":mode})
	engine.trinket_effects(p,"refresh");engine.Elementals.refresh(engine,p);engine.Quilboar.refresh(engine,p)
	engine.R133.refreshed(engine,p)
static func damage_received(engine,p: Dictionary,c: Dictionary,damage: int) -> void:
	if damage<=0:return
	for e in specs(engine,c,"hurt_hand"):
		var target=pick(engine,hand(engine,p))
		if target!=null:engine.buff(target,int(e.attack),int(e.health))
static func spell_resolved(engine,p: Dictionary,target: Dictionary) -> void:
	if target.is_empty() or not U.tribe(engine,target,"鱼人"):return
	for c in U.board(engine,p).duplicate():
		for e in specs(engine,c,"fish_spell"):
			for held in hand(engine,p,"鱼人"):engine.buff(held,int(e.attack),int(e.health))
			for v in U.board(engine,p):
				if U.tribe(engine,v,"鱼人"):engine.buff(v,int(e.attack),int(e.health))
static func ranked(engine,p: Dictionary,dimension: String,tribe: String="",summon_only: bool=false) -> Array:
	var cards=hand(engine,p,tribe).duplicate()
	if summon_only:cards=cards.filter(func(c):return not engine.CardLock.locked(engine,p,c))
	
	cards.sort_custom(func(a,b):return (engine.stats(a).x if dimension=="attack" else engine.stats(a).y)>(engine.stats(b).x if dimension=="attack" else engine.stats(b).y))
	return cards
static func register_forager(engine,p: Dictionary,c: Dictionary,e: Dictionary) -> void:
	var ctx=engine.combat_context
	if not ctx.has("forager_pending"):ctx["forager_pending"]=[]
	ctx["forager_seq"]=int(ctx.get("forager_seq",0))+1
	var task={"id":ctx.forager_seq,"owner":p.id,"source":c.duplicate(true),"remaining":int(e.amount),"used":[],"effect":e.duplicate(true)}
	ctx.forager_pending.append(task)
	engine.emit("ForagerRegistered",int(p.id),{"task":task.id,"source_instance":c.instance_id,"remaining":task.remaining})
static func forager_one(engine) -> Dictionary:
	var ctx=engine.combat_context
	for task in ctx.get("forager_pending",[]).duplicate():
		var side=-1
		for i in ctx.players.size():
			if int(ctx.players[i].id)==int(task.owner):side=i;break
		if side<0:ctx.forager_pending.erase(task);continue
		var p=ctx.players[side];var board=ctx.boards[side]
		if board.size()>=int(ctx.capacities[side]):continue
		var cards=ranked(engine,p,"attack","鱼人",true).filter(func(c):return int(c.instance_id) not in task.used)
		if cards.is_empty():
			ctx.forager_pending.erase(task);engine.emit("ForagerNoCandidate",int(p.id),{"task":task.id,"remaining":task.remaining});continue
		var held=cards[0];task.used.append(int(held.instance_id));task.remaining-=1
		
		if int(task.remaining)<=0:ctx.forager_pending.erase(task)
		var clone=engine.Combat.unit(engine,held);clone.instance_id=int(engine.state.next_instance);engine.state.next_instance+=1
		clone.pool_copies=0;clone["attached_pool"]=[];engine.exclude_gold_reward(clone,"forager_combat_copy")
		clone["hand_source_instance"]=held.instance_id;board.append(clone)
		engine.emit("HandCombatCopy",int(p.id),{"source_instance":held.instance_id,"instance_id":clone.instance_id,"origin":task.source.def_id,"task":task.id,"remaining":task.remaining,"dimension":"attack"})
		U.summoned(engine,p,clone)
		return {"kind":"summon","instance_id":clone.instance_id,"def_id":clone.def_id,"source":task.source.instance_id,"hand_source_instance":held.instance_id,"origin":"forager","task":task.id}
	return {}
static func summon_hand(engine,p: Dictionary,c: Dictionary,e: Dictionary) -> Array:
	var cards=ranked(engine,p,str(e.get("dimension","attack")),str(e.get("tribe","")),true).slice(0,int(e.get("amount",1)))
	var board=U.board(engine,p);var side=engine.combat_context.players.find(p);var cap=int(engine.combat_context.capacities[side]);var result=[]
	for held in cards:
		if board.size()>=cap:break
		var clone=engine.Combat.unit(engine,held);clone.instance_id=int(engine.state.next_instance);engine.state.next_instance+=1
		clone.pool_copies=0;clone["attached_pool"]=[];clone.triple_receipt=false;clone["hand_source_instance"]=held.instance_id
		var m=int(e.get("scale",1));clone.attack*=m;clone.health*=m;clone.max_health*=m
		if e.get("shield",false):engine.add_keyword(clone,"DIVINE_SHIELD")
		var source_index=engine.find_index(board,int(c.get("instance_id",-1)))
		if e.has("summon_index"):board.insert(mini(int(e.summon_index)+result.size(),board.size()),clone)
		elif e.get("trigger","")=="rally" and source_index>=0:board.insert(source_index+1+result.size(),clone)
		else:board.append(clone)
		result.append(clone.instance_id);U.summoned(engine,p,clone)
		engine.emit("HandCombatCopy",int(p.id),{"source_instance":held.instance_id,"instance_id":clone.instance_id,"origin":c.get("def_id",""),"dimension":e.get("dimension","attack")})
	return result
static func opening(engine,p: Dictionary) -> void:
	var originals=U.board(engine,p).duplicate()
	for held in hand(engine,p):
		if engine.CardLock.locked(engine,p,held):continue
		for e in specs(engine,held,"hand_scout"):
			var side=engine.combat_context.players.find(p)
			if U.board(engine,p).size()>=int(engine.combat_context.capacities[side]):continue
			var clone=engine.Combat.unit(engine,held);clone.instance_id=int(engine.state.next_instance);engine.state.next_instance+=1
			clone.pool_copies=0;clone["attached_pool"]=[];clone.triple_receipt=false;clone["hand_source_instance"]=held.instance_id
			clone.attack*=int(e.amount);clone.health*=int(e.amount);clone.max_health*=int(e.amount)
			U.board(engine,p).append(clone);U.summoned(engine,p,clone)
			engine.emit("HandCombatCopy",int(p.id),{"source_instance":held.instance_id,"instance_id":clone.instance_id,"origin":"scout"})
	for c in originals:
		for e in engine.Triggers.effects(engine,c):
			if e.get("handler","")=="round11" and e.get("trigger","")=="combat_start":engine.effect(p,e,c,c)
static func suppress(engine,p: Dictionary,enemy: Array) -> void:
	for unused in int(p.get("suppress_count",0)):
		var c=pick(engine,enemy.filter(func(v):return int(v.health)>0))
		if c!=null:c.health=1;engine.emit("CombatHealthSet",int(p.id),{"target":c.instance_id,"health":1})
	p["suppress_count"]=0
static func attack_kill(engine,p: Dictionary,c: Dictionary,victim: Dictionary) -> void:
	if int(victim.health)>0:return
	for e in specs(engine,c,"morgl"):
		var target=pick(engine,hand(engine,p))
		if target!=null:engine.buff(target,int(victim.attack)*int(e.amount),int(victim.max_health)*int(e.amount))
static func execute(engine,p: Dictionary,e: Dictionary,c: Dictionary) -> bool:
	if not supports({},e):return false
	var source=engine.effect_source
	match str(e.op):
		"give":
			for unused in int(e.amount):engine.receive_card(p,engine.make_card(e.id,int(p.id)),source)
		"random_minion":random_minion(engine,p,e,c)
		"family":
			var n=maxi(1,int(p.get("family_played",0)))
			fish_buff(engine,p,c,int(e.attack)*n,int(e.health)*n,true)
		"cost_spells":spells(engine,p,int(e.amount),int(e.cost),source)
		"left_hand":left(engine,p,int(e.attack),int(e.health))
		"give_venom":
			var options=U.board(engine,p).filter(func(v):return int(v.instance_id)!=int(c.instance_id) and U.tribe(engine,v,"鱼人") and not v.get("venom",false))
			for unused in mini(int(e.amount),options.size()):var target=pick(engine,options);options.erase(target);engine.add_keyword(target,"VENOMOUS")
		"parents":
			var parents=["BG35_140","BG35_141"] if e.get("both",false) else [pick(engine,["BG35_140","BG35_141"])]
			for id in parents:engine.receive_card(p,engine.make_card(id,int(p.id)),source)
		"fish_discover":
			if U.board(engine,p).any(func(v):return int(v.instance_id)!=int(c.instance_id) and U.tribe(engine,v,"鱼人")):
				engine.resolve_discovery(p,engine.discovery_candidates(p,{"tribe":"鱼人"},c),"fish",int(e.amount),c)
		"hand_summon":
			if e.get("defer_until_space",false) and U.is_combat(engine):register_forager(engine,p,c,e);return true
			if U.is_combat(engine):summon_hand(engine,p,c,e)
		"highest_attack":
			var options=ranked(engine,p,"attack")
			if not options.is_empty():engine.buff(c,engine.stats(options[0]).x*int(e.amount),0)
		"chorus":
			var v=Vector2i.ZERO
			for held in hand(engine,p):v+=engine.stats(held)
			engine.buff(c,v.x*int(e.amount),v.y*int(e.amount))
		"conch":
			var options=engine.generation_candidates(p,{"tribe":"鱼人"},source);var id=pick(engine,options)
			if id!=null:
				engine.receive_card(p,engine.make_card(id,int(p.id)));engine.receive_card(p,engine.make_card(id,int(p.id)))
		"deep":
			var v=preload("res://domain/rules/spell_attributes.gd").value(engine.current_spell,e,p)
			engine.buff(c,v.x,v.y)
			for target in U.board(engine,p):
				if U.tribe(engine,target,"鱼人"):engine.buff(target,v.x,v.y)
		"suppress":p["suppress_count"]=int(p.get("suppress_count",0))+1
		"special_shop":special_shop(engine,p,e.mode)
		"flippers":
			left(engine,p,int(e.amount),int(e.amount))
			if not U.board(engine,p).is_empty():engine.buff(U.board(engine,p)[0],int(e.amount),int(e.amount))
		"murky":
			for target in U.board(engine,p).slice(0,2):engine.buff(target,1+int(p.get("battlecry_count",0)),2+2*int(p.get("battlecry_count",0)))
		"brann":
			for card in p.board+p.hand+p.shop+p.pending_rewards:generated(engine,p,card)
			engine.receive_card(p,engine.make_card("BG_LOE_077",int(p.id)),source)
			random_minion(engine,p,{"battlecry":true,"amount":1},source)
		"collage":
			var spell=engine.make_card("BG35_MagicItem_755t",int(p.id));spell["spellcraft_expires_round"]=int(engine.state.round)+1;engine.receive_card(p,spell,source)
		"conch_portrait":
			if e.trigger=="obtain":source["conch_due"]=int(engine.state.round)+2;engine.receive_card(p,engine.make_card("BG28_601",int(p.id)),source)
			elif int(engine.state.round)>=int(source.get("conch_due",0)):source["conch_due"]=int(engine.state.round)+2;engine.receive_card(p,engine.make_card("BG28_601",int(p.id)),source)
		"book":engine.resolve_discovery(p,engine.Naga.spell_pool(engine,p),"medivh",int(e.amount),source)
		"reflect":
			var target=pick(engine,U.board(engine,p))
			if target!=null:engine.receive_card(p,copy(engine,p,target,true),source)
		"memory":
			var id=str(p.get("last_tavern_spell",""))
			if id!="":
				for unused in int(e.amount):engine.receive_card(p,engine.make_card(id,int(p.id)),source)
		"learned":learn_cast(engine,p,c,e)
		_:pass
	return true
