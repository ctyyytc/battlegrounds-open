extends RefCounted
const U=preload("res://domain/rules/undead_rules.gd")
const RNG=preload("res://domain/rules/deterministic_rng.gd")
const OPS=["summon","beast_aura","beetle_growth","raptor","lobster","others","banana","random_beast","attack_aura","behemoth","rally_deathrattle","fishbait","shark","bait_reward","boon","mug","give","rivendare","babyfood","all_deathrattles","beetle_ring","duster","anklet","anklet_grow","left_deathrattles","cat","horn","lion_portrait","target_buff","trigger_deathrattle","sprout","onyxia","sylvanas","teron","snake"]
static func supports(_d: Dictionary,e: Dictionary) -> bool:
	return e.get("handler","")=="round12" and e.get("op","") in OPS
static func specs(engine,c: Dictionary,op: String) -> Array:
	return engine.Triggers.effects(engine,c).filter(func(e):return e.get("handler","")=="round12" and e.get("op","")==op) if c.has("def_id") else engine.content.get_def(c.get("id","")).get("effects",[]).filter(func(e):return e.get("handler","")=="round12" and e.get("op","")==op)
static func has(engine,p: Dictionary,op: String) -> bool:
	return p.trinkets.any(func(c):return not specs(engine,c,op).is_empty())
static func pick(engine,a: Array) -> Variant:
	return null if a.is_empty() else a[RNG.next(engine.state.streams,"effects",a.size())]
static func beast(engine,c: Dictionary) -> bool:
	return U.tribe(engine,c,"野兽")
static func beetle(engine,c: Dictionary) -> bool:
	return c.get("def_id","") in ["BG28_603t","BG28_603t_G"]
static func immune(engine,c: Dictionary) -> bool:
	return engine.content.get_def(c.get("def_id","")).get("immune_stat_gain",false)
static func battlefield(engine,p: Dictionary,c: Dictionary,purpose: String) -> bool:
	if purpose=="combat_entry":return true
	var id=int(c.get("instance_id",-1))
	if engine.find_index(p.hand,id)>=0 or engine.find_index(p.shop,id)>=0:return false
	return engine.find_index(U.board(engine,p),id)>=0 or (U.is_combat(engine) and c.has("derived_attack"))
static func goldrinn_aura(engine,p: Dictionary,c: Dictionary,purpose: String="current") -> Vector2i:
	if not beast(engine,c) or int(p.get("goldrinn_expires",-1))<=int(engine.state.round):return Vector2i.ZERO
	
	
	if not battlefield(engine,p,c,purpose):return Vector2i.ZERO
	return Vector2i(int(p.get("goldrinn_attack",0)),int(p.get("goldrinn_health",0)))
static func derived(engine,p: Dictionary,c: Dictionary,purpose: String="current") -> Vector2i:
	var v=Vector2i.ZERO
	if beetle(engine,c):v+=Vector2i(int(p.get("beetle_attack",0)),int(p.get("beetle_health",0)))
	if beast(engine,c):
		v+=goldrinn_aura(engine,p,c,purpose)
		if U.is_combat(engine) and battlefield(engine,p,c,purpose):v+=Vector2i(int(p.get("beast_combat_attack",0)),int(p.get("beast_combat_health",0)))
	return v
static func global_growth(engine,p: Dictionary,a: int,h: int,shared: bool) -> void:
	var ak="beetle_attack" if shared else "beast_combat_attack"
	var hk="beetle_health" if shared else "beast_combat_health"
	p[ak]=int(p.get(ak,0))+a;p[hk]=int(p.get(hk,0))+h
	if U.is_combat(engine):
		for c in U.board(engine,p):
			if (beetle(engine,c) if shared else beast(engine,c)) and not immune(engine,c):
				c.attack+=a;c.health+=h;c.max_health+=h
				c.derived_attack+=a;c.derived_health+=h
				engine.R135.stat_gain(engine,c,a,h)
	engine.emit("BeastSharedGrowth",int(p.id),{"beetle":shared,"attack":a,"health":h,"total_attack":p[ak],"total_health":p[hk]})
static func increment(engine,p: Dictionary,c: Dictionary,key: String,amount: int=1) -> void:
	c[key]=int(c.get(key,0))+amount
	if U.is_combat(engine) and not p.get("is_ghost",false):
		var i=engine.find_index(p.board,int(c.get("instance_id",-1)))
		if i>=0:p.board[i][key]=c[key]
static func summon(engine,p: Dictionary,id: String,index: int=-1,taunt: bool=false,saved: Dictionary={},fixed_stats: int=-1) -> Dictionary:
	var board=U.board(engine,p)
	var cap=engine.capacity(board)
	if U.is_combat(engine):cap=int(engine.combat_context.capacities[engine.combat_context.players.find(p)])
	if board.size()>=cap:
		if "野兽" in engine.content.get_def(id).get("card_types",[]):anklet_growth(engine,p)
		engine.emit("SummonUnavailable",int(p.id),{"id":id,"reason":"BOARD_FULL"})
		return {}
	var c=engine.make_card(id,int(p.id)) if saved.is_empty() else saved.duplicate(true)
	if fixed_stats>=0:c["base_override"]={"attack":fixed_stats,"health":fixed_stats}
	if not saved.is_empty():
		c.instance_id=int(engine.state.next_instance);engine.state.next_instance+=1
		if U.is_combat(engine):
			var now=engine.stats(c,"combat_entry");c.attack+=now.x-int(c.derived_attack);c.max_health+=now.y-int(c.derived_health);c.health+=now.y-int(c.derived_health)
			c.derived_attack=now.x;c.derived_health=now.y
	elif U.is_combat(engine):c=engine.Combat.unit(engine,c)
	c.pool_copies=0
	if not c.get("r13_keep_route",false):c.gold_route=""
	c.erase("r13_keep_route");c.triple_receipt=false;c.erase("triple_reward_key")
	if taunt:engine.add_keyword(c,"TAUNT")
	if index<0:board.append(c)
	else:board.insert(mini(index,board.size()),c)
	if U.is_combat(engine):U.summoned(engine,p,c)
	else:summoned(engine,p,c)
	engine.Naga.recruit_entered(engine,p,c)
	engine.emit("MinionSummoned",int(p.id),{"instance_id":c.instance_id,"id":c.def_id,"origin":"round12"})
	return c
static func summoned(engine,p: Dictionary,c: Dictionary) -> void:
	if U.is_combat(engine) and engine.has_handler(p,"sprout"):engine.buff(c,1,2);engine.add_keyword(c,"TAUNT")
	if not beast(engine,c):return
	
	var listeners=U.board(engine,p).filter(func(v):return int(v.instance_id)!=int(c.instance_id)).duplicate()
	for source in listeners:
		for e in specs(engine,source,"behemoth"):
			engine.buff(c,3*int(e.scale)*(1+int(source.get("behemoth_count",0))),0)
			increment(engine,p,source,"behemoth_count")
		if U.is_combat(engine):
			for e in specs(engine,source,"banana"):engine.buff(c,int(c.attack)*(int(e.multiplier)-1),0)
	for item in p.trinkets:
		if U.is_combat(engine):
			for e in specs(engine,item,"banana"):engine.buff(c,int(c.attack)*(int(e.multiplier)-1),0)
		if not specs(engine,item,"duster").is_empty():
			item["duster_count"]=int(item.get("duster_count",0))+1
			if int(item.duster_count)>=6:item.duster_count-=6;random_beast(engine,p,1,item)
	anklet_growth(engine,p)
static func anklet_growth(engine,p: Dictionary) -> void:
	for item in p.trinkets:
		if not specs(engine,item,"anklet_grow").is_empty():
			item["anklet_count"]=int(item.get("anklet_count",0))+1
			if U.is_combat(engine):global_growth(engine,p,1,1,false)
static func random_beast(engine,p: Dictionary,n: int,source: Dictionary={}) -> void:
	U.random_cards(engine,p,{"tribe":"野兽","amount":n},source)
static func mug_count(engine,p: Dictionary) -> int:
	return p.trinkets.filter(func(c):return not specs(engine,c,"mug").is_empty()).size()
static func draw_mug(engine,p: Dictionary) -> Dictionary:
	var tier=mini(6,int(p.tier)+1);var candidates=[]
	for id in engine.state.pool:
		if int(engine.content.get_def(id).tier)==tier:
			for unused in int(engine.state.pool[id]):candidates.append(id)
	if candidates.is_empty():return {}
	var id=candidates[RNG.next(engine.state.streams,"shop"+str(p.id),candidates.size())]
	engine.state.pool[id]-=1
	var c=engine.make_card(id,int(p.id),1);c["mug"]=true
	engine.Pirates.growth(engine,p,c);engine.Demons.growth(engine,p,c)
	return c
static func attack(engine,p: Dictionary,c: Dictionary) -> void:
	if not beast(engine,c):return
	for source in U.board(engine,p).filter(func(v):return int(v.get("health",1))>0).duplicate():
		for e in specs(engine,source,"attack_aura"):
			for target in U.board(engine,p):
				if beast(engine,target):engine.buff(target,int(e.attack),int(e.health))
	for item in p.trinkets:
		for e in specs(engine,item,"lion_portrait"):engine.buff(c,int(e.attack),int(e.health))
		if not specs(engine,item,"babyfood").is_empty():
			engine.buff(c,3*(1+int(item.get("babyfood_count",0))),0);item["babyfood_count"]=int(item.get("babyfood_count",0))+1
		if not specs(engine,item,"horn").is_empty() and engine.Triggers.effects(engine,c).any(func(e):return e.get("trigger","")=="rally"):p.free_refresh+=1
	engine.emit("BeastAttackTriggered",int(p.id),{"instance_id":c.instance_id})
static func after_attack(engine,p: Dictionary,c: Dictionary) -> void:
	for source in U.board(engine,p).filter(func(v):return int(v.get("health",1))>0).duplicate():
		for e in specs(engine,source,"beetle_growth"):
			if e.trigger=="after_attack":global_growth(engine,p,int(e.attack),int(e.health),true)
		if engine.Triggers.effects(engine,c).any(func(e):return e.get("trigger","")=="rally"):
			for e in specs(engine,source,"rally_deathrattle"):
				var candidates=U.board(engine,p).filter(func(v):return int(v.get("health",1))>0 and engine.Triggers.has_deathrattle(engine,v))
				if not candidates.is_empty():
					for unused in int(e.amount):trigger_deathrattle(engine,p,candidates[0])
static func trigger_deathrattle(engine,p: Dictionary,c: Dictionary) -> void:
	var es=engine.Triggers.expanded(engine,p,c,"deathrattle")
	if es.is_empty():return
	engine.count_trigger(p,"deathrattle",engine.Triggers.times(engine,p,"deathrattle"))
	if U.is_combat(engine):
		var side=engine.combat_context.players.find(p)
		engine.Combat.resolve_deathrattles(engine,p,c,engine.combat_context.boards,side,engine.combat_context.capacities,U.board(engine,p).find(c)+1,es,[],true)
	else:
		for e in es:
			engine.emit("DeathrattleTriggered",int(p.id),{"instance_id":c.instance_id,"destroyed":false})
			if e.get("handler","")=="summon":
				for i in int(e.amount):summon(engine,p,e.id,U.board(engine,p).find(c)+1+i)
			else:engine.effect(p,e,c,c)
static func death(engine,p: Dictionary,c: Dictionary) -> void:
	for item in p.trinkets:
		if not specs(engine,item,"cat").is_empty():
			item["cat_count"]=int(item.get("cat_count",0))+1
			if int(item.cat_count)>=7:item.cat_count-=7;random_beast(engine,p,1,item)
	if not U.is_combat(engine):return
	if engine.has_handler(p,"onyxia"):
		p["onyxia_avenge"]=int(p.get("onyxia_avenge",0))+1
		if int(p.onyxia_avenge)>=4:
			p.onyxia_avenge-=4
			var child=summon(engine,p,"BG22_HERO_305t")
			if not child.is_empty():
				engine.buff(child,int(p.get("onyxia_count",0)),int(p.get("onyxia_count",0)))
				engine.combat_context["immediate_attacks"].append({"side":engine.combat_context.players.find(p),"instance_id":child.instance_id})
			p["onyxia_count"]=int(p.get("onyxia_count",0))+1
# Keep the destroyed target's gap even when other minions die before space opens.
# Its deathrattle summons and Reborn already occupy the gap before this copy.
static func teron_summon_index(engine,p: Dictionary,entry: Dictionary) -> int:
	var board=U.board(engine,p)
	for instance_id in entry.get("right_instances",[]):
		var index=engine.find_index(board,int(instance_id))
		if index>=0:return index
	return board.size()
static func drain_pending(engine) -> Array:
	var feedback=[]
	if engine.combat_context.is_empty() or engine.combat_context.get("draining_pending",false):return feedback
	engine.combat_context["draining_pending"]=true
	for side in 2:
		var p=engine.combat_context.players[side];var pending=p.get("beast_pending",[])
		while not pending.is_empty() and U.board(engine,p).size()<int(engine.combat_context.capacities[side]):
			var entry=pending.pop_front()
			var child=summon(engine,p,entry.card.def_id,teron_summon_index(engine,p,entry),false,entry.card) if entry.kind=="teron" else summon(engine,p,"BG28_603t",-1,true)
			if not child.is_empty():feedback.append({"kind":"summon","instance_id":child.instance_id,"def_id":child.def_id,"origin":entry.kind})
	engine.combat_context["draining_pending"]=false
	return feedback
static func sylvanas_pool(engine,p: Dictionary) -> Array:
	var result=[]
	for death_record in p.get("last_battle_deaths",[]):
		var id=str(death_record.base_id)
		var d=engine.content.get_def(id)
		if d.get("kind","")=="minion" and d.get("implemented",false) and int(d.get("tier",7))<=6 and id not in result:result.append(id)
	return result
static func availability(engine,p: Dictionary) -> Dictionary:
	var op=engine.hero_handler(p)
	if op not in ["snake","teron","sylvanas","onyxia","sprout"]:return {}
	var targets=[];var reason=""
	if op in ["onyxia","sprout"]:reason="PASSIVE_POWER"
	elif op=="snake" and int(engine.state.round)<int(p.get("snake_ready_round",1)):reason="POWER_COOLDOWN"
	elif engine.power_used(p):reason="POWER_ALREADY_USED"
	elif int(p.coins)<int(engine.power_cost(p)):reason="NOT_ENOUGH_COINS"
	elif op=="sylvanas":
		if int(engine.state.round)<3:reason="POWER_LOCKED_UNTIL_TURN_3"
		elif sylvanas_pool(engine,p).is_empty():reason="NO_LEGAL_CANDIDATE"
	elif op=="teron":
		targets=p.board.map(func(c):return int(c.instance_id))
		if targets.is_empty():reason="NO_LEGAL_TARGET"
	return {"available":reason=="","reason":reason,"targets":targets,"cost":int(engine.power_cost(p)),"handler":op,"ready_round":int(p.get("snake_ready_round",1))}
static func power(engine,p: Dictionary,args: Dictionary) -> String:
	var q=availability(engine,p)
	if not q.available:return q.reason
	if q.handler=="teron" and int(args.get("target_id",-1)) not in q.targets:return "TARGET_REQUIRED"
	p.coins-=int(q.cost);engine.consume_power(p);engine.Elementals.spent(engine,p,int(q.cost))
	match q.handler:
		"snake":
			var n=1+RNG.next(engine.state.streams,"effects",6)
			p["snake_ready_round"]=int(engine.state.round)+n;p["snake_last_roll"]=n;engine.gain_coins(p,n)
			engine.emit("SnakeRolled",int(p.id),{"roll":n,"ready_round":p.snake_ready_round})
		"teron":p["teron_target"]=int(args.target_id)
		"sylvanas":engine.resolve_discovery(p,sylvanas_pool(engine,p),"sylvanas",1)
	return ""
static func activate_query(engine,p: Dictionary,c: Dictionary) -> Dictionary:
	if specs(engine,c,"fishbait").is_empty():return {}
	var reason="ALREADY_ACTIVATED" if int(c.get("activated_round",-1))==int(engine.state.round) else "NOT_ENOUGH_COINS" if int(p.coins)<2 else "NO_LEGAL_TARGET" if p.shop.is_empty() else ""
	return {"available":reason=="","reason":reason,"cost":2,"targets":p.shop.map(func(v):return int(v.instance_id))}
static func activate(engine,p: Dictionary,c: Dictionary,args: Dictionary) -> String:
	var q=activate_query(engine,p,c)
	if not q.available:return q.reason
	var i=engine.find_index(p.shop,int(args.get("target_id",-1)))
	if i<0:return "TARGET_REQUIRED"
	p.coins-=2;c["activated_round"]=int(engine.state.round);engine.Elementals.spent(engine,p,2)
	engine.retire_pool_unit(p.shop[i],"lionfish");p.shop[i]=engine.make_card("BG36_205_G" if engine.content.get_def(c.def_id).golden else "BG36_205",int(p.id))
	p.shop[i]["fishbait_origin"]="lionfish"
	recruit_attack(engine,p,p.shop[i]);return ""
static func recruit_attack(engine,p: Dictionary,bait: Dictionary) -> void:
	var candidates=p.board.filter(func(c):return beast(engine,c))
	if candidates.is_empty():return
	var c=candidates[0]
	if engine.stats(c).x<=0:return
	attack(engine,p,c)
	engine.run_effects(p,c,"rally");engine.Gifts.rally(engine,p,c)
	var damage=engine.stats(c).x
	if damage>0:
		var bait_slot=p.shop.find(bait)
		p.shop.erase(bait);engine.emit("MinionDied",int(p.id),{"instance_id":bait.instance_id,"id":bait.def_id,"faction":"shop","phase":"recruit"})
		engine.count_trigger(p,"deathrattle",engine.Triggers.times(engine,p,"deathrattle"))
		for unused in engine.Triggers.times(engine,p,"deathrattle"):
			engine.buff(c,10 if engine.content.get_def(bait.def_id).golden else 5,10 if engine.content.get_def(bait.def_id).golden else 5)
			engine.emit("DeathrattleTriggered",int(p.id),{"instance_id":bait.instance_id,"faction":"shop"})
		engine.Pirates.damaged(engine,c,damage);engine.Demons.damage_fact(engine,c,damage)
		var origin=str(bait.get("fishbait_origin","legacy_unknown"))
		if origin=="legacy_unknown":engine.emit("FishbaitOriginUnknown",int(p.id),{"instance_id":bait.instance_id,"policy":"retain_legacy_replacement"})
		if origin!="lionfish":
			var replacement=engine.Demons.draw_minion(engine,p)
			if not replacement.is_empty():p.shop.insert(mini(bait_slot,p.shop.size()),replacement);engine.Demons.sort_shop(engine,p)
	engine.emit("AttackResolved",int(p.id),{"attacker":c.instance_id,"target":bait.instance_id,"damage":damage,"phase":"recruit"})
	after_attack(engine,p,c)
static func valid_target(engine,p: Dictionary,d: Dictionary,c: Dictionary) -> bool:
	if d.effects.is_empty() or d.effects[0].get("handler","")!="round12":return true
	var e=d.effects[0]
	if e.op=="target_buff":return not c.is_empty() and beast(engine,c)
	if e.op=="trigger_deathrattle":return not c.is_empty() and engine.find_index(p.board,int(c.instance_id))>=0 and engine.Triggers.has_deathrattle(engine,c)
	return true
static func execute(engine,p: Dictionary,e: Dictionary,c: Dictionary) -> bool:
	if not supports({},e):return false
	var source=engine.effect_source
	match str(e.op):
		"summon":
			for i in int(e.amount):summon(engine,p,e.id,int(e.get("summon_index",U.board(engine,p).find(source)+1))+i)
		"beetle_growth":global_growth(engine,p,int(e.attack),int(e.health),true)
		"beast_aura":
			if U.is_combat(engine):global_growth(engine,p,int(e.attack),int(e.health),false)
			else:
				p["goldrinn_attack"]=int(p.get("goldrinn_attack",0))+int(e.attack);p["goldrinn_health"]=int(p.get("goldrinn_health",0))+int(e.health)
				p["goldrinn_expires"]=int(engine.state.round)+1
				engine.emit("RecruitBeastAura",int(p.id),{"attack":p.goldrinn_attack,"health":p.goldrinn_health,"expires":p.goldrinn_expires})
		"lobster":
			var n=1+int(p.get("lobster_count",0));p["lobster_count"]=n
			var target=pick(engine,U.board(engine,p).filter(func(v):return beast(engine,v) and int(v.get("health",1))>0))
			if target!=null:
				engine.buff(target,2*int(e.scale)*n,int(e.scale)*n)
		"raptor":
			var pool=engine.generation_candidates(p,{"tribe":"野兽"},source)
			var id=pick(engine,pool)
			if id!=null:
				if e.golden:id=engine.content.get_def(id).golden_id
				summon(engine,p,id,int(e.get("summon_index",U.board(engine,p).find(source)+1)),false,{},int(e.stats))
		"others":
			for target in U.board(engine,p):
				if int(target.instance_id)!=int(source.get("instance_id",c.get("instance_id",-1))):engine.buff(target,int(e.attack),int(e.health))
		"random_beast":random_beast(engine,p,int(e.amount),source)
		"bait_reward":
			for player in engine.combat_context.get("players",[]):
				for target in U.board(engine,player):
					if int(target.instance_id)==int(c.get("killed_by",-1)):engine.buff(target,int(e.amount),int(e.amount))
		"boon":
			if not p.has("beetle_boons"):p["beetle_boons"]=[]
			p.beetle_boons.append(int(e.amount))
		"shark":
			engine.refill_shop(p,false)
			var normal=p.shop.filter(func(v):return engine.content.get_def(v.def_id).kind=="minion" and not v.get("bait",false) and not v.get("mug",false))
			var bait=engine.make_card("BG36_205_G" if e.golden else "BG36_205",int(p.id))
			bait["fishbait_origin"]="shark"
			if not normal.is_empty():var i=p.shop.find(normal[0]);engine.return_pool(normal[0]);p.shop[i]=bait
			elif p.shop.size()<7:p.shop.append(bait)
			else:return true
			recruit_attack(engine,p,bait)
		"give":
			for unused in int(e.amount):engine.receive_card(p,engine.make_card(e.id,int(p.id)),source)
		"target_buff":
			var amount=preload("res://domain/rules/spell_attributes.gd").value(engine.current_spell,e,p)
			var duration="next_turn" if engine.current_spell.get("is_spellcraft",false) and not engine.current_spell.get("permanent_spellcraft",false) else "permanent"
			engine.buff(c,amount.x,amount.y,duration);engine.add_keyword(c,e.keyword,duration)
		"trigger_deathrattle":trigger_deathrattle(engine,p,c)
		"beetle_ring":
			for unused in int(e.amount):summon(engine,p,"BG28_603t",-1,true)
		"rivendare":
			for target in U.board(engine,p):
				if engine.content.get_def(target.def_id).get("base_id","")=="BG25_354":engine.buff(target,0,int(target.max_health))
		"all_deathrattles":
			for target in U.board(engine,p).duplicate():trigger_deathrattle(engine,p,target)
		"left_deathrattles":
			var targets=U.board(engine,p).filter(func(v):return engine.Triggers.has_deathrattle(engine,v)).slice(0,int(e.amount))
			for target in targets:trigger_deathrattle(engine,p,target)
		"anklet":global_growth(engine,p,1+int(source.get("anklet_count",0)),1+int(source.get("anklet_count",0)),false)
	return true
