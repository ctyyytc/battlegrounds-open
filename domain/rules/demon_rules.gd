extends RefCounted
const RNG=preload("res://domain/rules/deterministic_rng.gd")
const U=preload("res://domain/rules/undead_rules.gd")
const Attributes=preload("res://domain/rules/spell_attributes.gd")
const RAT="TB_BaconShop_HERO_12"
const JAR="TB_BaconShop_HERO_37"
const RAT_POWERS={"恶魔":"d","海盗":"g","元素":"h","野猪人":"i","纳迦":"j","亡灵":"k","鱼人":"c","野兽":"a"}
const OPS=["weaver","rewind","corrosion","prince","satyr","feed_window","feed_one","feed_token","mud","damage_discover","consume_end","demons_eat","give","tichondrius","shop_low","escape","spell_shop","spell_strength","void","eye","cheese","uzul","shield","gauntlet","portrait","life_demon","life_spell","bloodblade","claw","eat_spell","discover_tag","invoke","perfect","gold_eye","hamul","rat","jar"]
static func supports(_d: Dictionary,e: Dictionary) -> bool:
	return e.get("handler","")=="round10" and e.get("op","") in OPS
static func specs(engine,c: Dictionary,op: String) -> Array:
	var d=engine.content.get_def(c.get("def_id",c.get("id","")))
	return d.get("effects",[]).filter(func(e):return e.get("handler","")=="round10" and e.get("op","")==op)
static func has(engine,p: Dictionary,op: String) -> bool:
	return p.trinkets.any(func(c):return not specs(engine,c,op).is_empty())
static func pick(engine,a: Array) -> Variant:
	return null if a.is_empty() else a[RNG.next(engine.state.streams,"effects",a.size())]
static func power_id(engine,p: Dictionary) -> String:
	if engine.hero_handler(p) in ["rat","jar"]:return str(engine.power_definition(p).id)
	return ""
static func turn_start(engine,p: Dictionary) -> void:
	for s in p.power_slots:
		if str(s.active_power_id).begins_with("TB_BaconShop_HP_041"):
			var available=engine.state.enabled_tribes.filter(func(t):return t!=s.progress.get("rat_tribe",""))
			s.progress["rat_tribe"]=pick(engine,available);s.active_power_id="TB_BaconShop_HP_041"+RAT_POWERS.get(s.progress.rat_tribe,"")
			engine.emit("RatKingChanged",int(p.id),{"tribe":s.progress.rat_tribe,"power_id":s.active_power_id,"slot_id":s.slot_id})
	if engine.has_power(p,"TB_BaconShop_HP_036t"):portal_reward(engine,p,true)
static func portal_reward(engine,p: Dictionary,at_start: bool=false) -> void:
	if int(p.get("portal_reward_round",-1))==int(engine.state.round):return
	p["portal_reward_round"]=int(engine.state.round)
	U.random_cards(engine,p,{"tribe":"恶魔","amount":2},engine.Acquisition.context(engine,engine.content.get_def("TB_BaconShop_HP_036t"),"hero_start" if at_start else "ordinary"))
	engine.emit("PortalRewardIssued",int(p.id),{"round":engine.state.round})
static func damage_fact(engine,source: Dictionary,amount: int) -> void:
	if source.is_empty() or amount<=0:return
	var pid=int(source.get("owner",-1))
	if pid<0 or pid>=engine.state.players.size():return
	
	
	var p=U.board_player(engine,pid)
	engine.emit("MinionOrdinaryDamage",pid,{"instance_id":source.instance_id,"amount":amount})
	for s in p.power_slots:
		if s.active_power_id!="TB_BaconShop_HP_036":continue
		s.progress["jar_damage"]=int(s.progress.get("jar_damage",0))+amount
		if int(s.progress.jar_damage)>=150:
			s.active_power_id="TB_BaconShop_HP_036t";engine.emit("HeroPowerTransformed",pid,{"power_id":s.active_power_id,"slot_id":s.slot_id})
			if engine.state.phase=="recruit" and engine.combat_context.is_empty() and engine.resolution_phase!="turn_end":portal_reward(engine,p)
	if U.tribe(engine,source,"恶魔"):
		for c in U.board(engine,p).duplicate():
			if int(c.instance_id)==int(source.instance_id):continue
			for e in specs(engine,c,"satyr"):
				var n=int(e.amount);U.local_buff(engine,c,n,n,true)
static func hurt_preview(p: Dictionary,amount: int) -> Dictionary:
	var effective=0 if amount<=0 or p.get("hero_immune",false) else amount
	var armor=mini(int(p.armor),effective)
	return {"amount":effective,"armor":armor,"health":effective-armor,"immune":bool(p.get("hero_immune",false))}
static func hurt(engine,p: Dictionary,amount: int,source: Dictionary={}) -> void:
	var damage=hurt_preview(p,amount)
	if int(damage.amount)<=0:return
	var before_health=int(p.health);var before_armor=int(p.armor)
	var armor_loss=int(damage.armor)
	p.armor-=armor_loss;p.health-=int(damage.health)
	engine.emit("HeroRecruitDamaged",int(p.id),{"amount":amount,"armor":armor_loss,"health":amount-armor_loss,"source_instance":source.get("instance_id",-1)})
	damage_fact(engine,source,amount)
	var rewind=false
	for c in p.board.duplicate():
		for e in specs(engine,c,"rewind"):
			rewind=true;var n=int(e.amount);engine.buff(c,n if has(engine,p,"portrait") else 0,n)
		for e in specs(engine,c,"corrosion"):
			rewind=true;var n=int(e.amount)
			p["corrosion_round"]=int(engine.state.round);p["corrosion_bonus"]=int(p.get("corrosion_bonus",0))+n
			grow_shop(engine,p,n,n,"next_turn","demon_corrosion")
		for e in specs(engine,c,"tichondrius"):
			for target in p.board:
				if U.tribe(engine,target,"恶魔"):engine.buff(target,int(e.amount),int(e.amount))
		for e in specs(engine,c,"cake_damage"):
			pass
		if engine.content.get_def(c.def_id).get("base_id","")=="BG36_733":
			c["cake_damage"]=int(c.get("cake_damage",0))+amount
			while int(c.cake_damage)>=4:
				c.cake_damage-=4
				for unused in (2 if engine.content.get_def(c.def_id).golden else 1):engine.receive_card(p,engine.make_card("BG28_607",int(p.id)),c)
	for item in p.trinkets:
		if not specs(engine,item,"void").is_empty():
			item["void_hits"]=int(item.get("void_hits",0))+1
			if int(item.void_hits)>=3:
				item.void_hits-=3;item["void_bonus"]=int(item.get("void_bonus",2))+2;grow_shop(engine,p,2,2,"permanent","void")
	if rewind:p.health=before_health;p.armor=before_armor;engine.emit("HeroDamageRewound",int(p.id),{"health":before_health,"armor":before_armor})
	
	if int(p.health)<=0:p.alive=false
static func payment(engine,p: Dictionary,d: Dictionary) -> Dictionary:
	for item in p.trinkets:
		if not specs(engine,item,"eye").is_empty() and int(item.get("eye_purchases",0))%4==3:return {"life":true,"item":item,"quota":"eye"}
	for item in p.trinkets:
		if int(item.get("life_round",-1))==int(engine.state.round) and int(item.get("life_used",0))>=1:continue
		if (d.kind=="minion" and ("恶魔" in d.card_types or "全部种族" in d.card_types) and not specs(engine,item,"life_demon").is_empty()) or (d.get("is_tavern_spell",false) and not specs(engine,item,"life_spell").is_empty()):return {"life":true,"item":item,"quota":"life"}
	return {"life":d.get("payment_resource","")=="health"}
static func bought(engine,p: Dictionary,plan: Dictionary) -> void:
	for item in p.trinkets:
		if not specs(engine,item,"eye").is_empty():item["eye_purchases"]=int(item.get("eye_purchases",0))+1
	if plan.get("quota","")=="life":plan.item["life_round"]=int(engine.state.round);plan.item["life_used"]=1
	if has(engine,p,"gauntlet"):fill_local(engine,p)
static func refresh_payment(engine,p: Dictionary,cost: int) -> Dictionary:
	if cost==0:return {"life":false}
	for c in p.board:
		for e in specs(engine,c,"prince"):
			if int(c.get("prince_round",-1))!=int(engine.state.round) or int(c.get("prince_used",0))<int(e.amount):return {"life":true,"card":c}
	return {"life":false}
static func grow_shop(engine,p: Dictionary,a: int,h: int,duration: String,origin: String) -> void:
	for c in p.shop:
		if engine.content.get_def(c.def_id).kind=="minion":engine.buff(c,a,h,duration,origin)
static func growth(engine,p: Dictionary,c: Dictionary) -> void:
	engine.R134.shop_growth(engine,p,c)
	if engine.content.get_def(c.def_id).kind!="minion":return
	for item in p.trinkets:
		if not specs(engine,item,"void").is_empty():var n=int(item.get("void_bonus",2));engine.buff(c,n,n,"permanent","void")
		if not specs(engine,item,"cheese").is_empty():var n=int(item.get("cheese_bonus",2));engine.buff(c,n,n,"permanent","cheese")
		if not specs(engine,item,"gauntlet").is_empty():engine.buff(c,3,3,"permanent","gauntlet")
	engine.buff(c,int(p.get("demon_shop_attack",0)),int(p.get("demon_shop_health",0)),"permanent","demon_shop")
	if int(engine.content.get_def(c.def_id).tier)<=3:engine.buff(c,int(p.get("demon_low_attack",0)),int(p.get("demon_low_health",0)),"permanent","demon_low")
	if int(p.get("corrosion_round",-1))==int(engine.state.round):var n=int(p.get("corrosion_bonus",0));engine.buff(c,n,n,"next_turn","demon_corrosion")
static func window(engine,p: Dictionary,n: int) -> void:
	if not p.has("fodder_windows"):p["fodder_windows"]=[]
	p.fodder_windows.append({"remaining":3,"amount":n})
	engine.emit("FodderWindowAdded",int(p.id),{"amount":n,"refreshes":3})
static func due(p: Dictionary) -> int:
	var n=int(p.get("fodder_overflow",0))+int(p.get("fodder_once",0))
	p["fodder_once"]=0
	for w in p.get("fodder_windows",[]):n+=int(w.amount);w.remaining-=1
	p["fodder_windows"]=p.get("fodder_windows",[]).filter(func(w):return int(w.remaining)>0)
	return n
static func draw_minion(engine,p: Dictionary,tribe: String="") -> Dictionary:
	var candidates=[]
	for id in engine.state.pool:
		var d=engine.content.get_def(id)
		if (engine.R13Items.has(engine,p,"BG30_MagicItem_998") and int(d.tier) in [1,2]) or (p.get("candle_drawing",false) and int(d.tier)!=6):continue
		if int(d.tier)>(6 if p.get("candle_drawing",false) else int(p.tier)) or (tribe!="" and not (tribe in d.card_types or "全部种族" in d.card_types)):continue
		for unused in int(engine.state.pool[id]):candidates.append(id)
	if candidates.is_empty():return {}
	var id=candidates[RNG.next(engine.state.streams,"shop"+str(p.id),candidates.size())]
	engine.state.pool[id]-=1
	var c=engine.make_card(id,int(p.id),1)
	if engine.Elementals.elemental(engine,c):engine.buff(c,int(p.get("nomi_attack",0)),int(p.get("nomi_health",0)),"permanent","nomi")
	engine.Pirates.growth(engine,p,c);growth(engine,p,c)
	return c
static func draw_spell(engine,p: Dictionary) -> Dictionary:
	var options=engine.content.pool("spell",engine.state.enabled_tribes).filter(func(id):return int(engine.content.get_def(id).tier)<=(6 if p.get("candle_drawing",false) else int(p.tier)) and (not p.get("candle_drawing",false) or int(engine.content.get_def(id).tier)==6) and (not engine.R13Items.has(engine,p,"BG30_MagicItem_998") or int(engine.content.get_def(id).tier) not in [1,2]))
	options=options.filter(func(id):return id not in engine.Pirates.BOUNTIES)+(["BOUNTY_FAMILY"] if options.any(func(id):return id in engine.Pirates.BOUNTIES) else [])
	if options.is_empty():return {}
	var id=options[RNG.next(engine.state.streams,"shop"+str(p.id),options.size())]
	if id=="BOUNTY_FAMILY":id=engine.Pirates.bounty_id(engine,p,"shop"+str(p.id))
	return engine.make_card(id,int(p.id))
static func bait(engine,p: Dictionary) -> Dictionary:
	for item in p.trinkets:
		if item.id=="BG30_MagicItem_973":return item
	return {}
static func fill_local(engine,p: Dictionary) -> void:
	while p.shop.size()<7:
		var minions=p.shop.filter(func(c):return engine.content.get_def(c.def_id).kind=="minion").size()
		var c=draw_minion(engine,p) if minions<6 else draw_spell(engine,p)
		if c.is_empty():break
		p.shop.append(c)
	sort_shop(engine,p)
	engine.R133.shop_sync(engine,p)
static func sort_shop(engine,p: Dictionary) -> void:
	p.shop=p.shop.filter(func(c):return engine.content.get_def(c.def_id).kind=="minion" and not c.get("bait",false) and not c.get("mug",false))+p.shop.filter(func(c):return engine.content.get_def(c.def_id).kind!="minion")+p.shop.filter(func(c):return c.get("mug",false))+p.shop.filter(func(c):return c.get("bait",false))
static func refill(engine,p: Dictionary,keep: bool,notify: bool=true,tribe: String="",preserve_individual: bool=false,reason: String="ordinary") -> bool:
	# Only automatic setup/start stock excludes new fodder. Keep refresh effects
	# and pending fodder counters independent of this stock-generation choice.
	var fodder_allowed=reason not in ["initial_setup","turn_start"]
	var requested_refresh=not keep
	var previous_instances=p.shop.map(func(c):return int(c.instance_id))
	if not keep:p["whistle_queue"]=[]
	var special=tribe!=""
	var bound={} if special else bait(engine,p)
	var mugs=0 if special else engine.Beasts.mug_count(engine,p)
	var extras=(2 if not bound.is_empty() else 0)+mugs
	var count=7 if special else mini(6-extras,6 if has(engine,p,"gauntlet") else int(engine.content.rules.shop_sizes[int(p.tier)-1]))
	var frost=p.shop.filter(func(c):return c.get("frozen_card",false)) if preserve_individual and not special else []
	if not keep and not frost.is_empty():
		for c in p.shop:
			if c not in frost:engine.return_pool(c)
		p.shop=frost;keep=true
		for c in frost:c.erase("frozen_card")
	if not keep and engine.has_power(p,"BG22_HERO_004p") and count+1>=7:count-=1
	if engine.has_power(p,"TB_BaconShop_HP_014"):count=maxi(0,count-1)
	if keep:
		if requested_refresh and notify and not special and fodder_allowed:
			var food=due(p);var room=maxi(0,count-p.shop.filter(func(c):return engine.content.get_def(c.def_id).kind=="minion").size());var shown=mini(room,food);p["fodder_overflow"]=food-shown
			for unused in shown:var c=engine.make_card("BG35_150t",int(p.id));growth(engine,p,c);p.shop.append(c)
		while p.shop.filter(func(c):return engine.content.get_def(c.def_id).kind=="minion" and not c.get("bait",false) and not c.get("mug",false)).size()<count and p.shop.size()<7:
			var c=draw_minion(engine,p,engine.R136.shop_tribe(engine,p))
			if c.is_empty():c=draw_minion(engine,p)
			if c.is_empty():break
			p.shop.append(c)
		if not p.shop.any(func(c):return engine.content.get_def(c.def_id).kind=="spell") and p.shop.size()<7:
			var c=draw_spell(engine,p)
			if not c.is_empty():p.shop.append(c)
	else:
		for c in p.shop:engine.return_pool(c)
		p.shop=[]
		var food=due(p) if notify and fodder_allowed else 0
		var shown=mini(count,food)
		if fodder_allowed:p["fodder_overflow"]=food-shown
		for i in count:
			var c=engine.make_card("BG35_150t",int(p.id)) if i<shown else draw_minion(engine,p,tribe if special else engine.R136.shop_tribe(engine,p))
			if c.is_empty():break
			if i<shown:growth(engine,p,c)
			p.shop.append(c)
		if not special:
			var spell=draw_spell(engine,p)
			if not spell.is_empty():p.shop.append(spell)
	if not bound.is_empty():
		while p.shop.filter(func(c):return c.get("bait",false)).size()<2 and p.shop.size()<7:
			var c=draw_minion(engine,p,bound.bound_tribe)
			if c.is_empty():break
			c["bait"]=true;p.shop.append(c)
	while p.shop.filter(func(c):return c.get("mug",false)).size()<mugs and p.shop.size()<7:
		var c=engine.Beasts.draw_mug(engine,p)
		if c.is_empty():break
		p.shop.append(c)
	p.frozen=false
	# Frozen stock can stay while new minions or spells enter. This refill is
	# one refresh, even when several slots are filled; unchanged stock is not.
	var refreshed=notify and (requested_refresh or p.shop.any(func(c):return int(c.instance_id) not in previous_instances))
	if refreshed:
		engine.emit("ShopRefreshed",int(p.id),{"special":"hamul" if special else "ordinary"})
		engine.trinket_effects(p,"refresh");engine.Elementals.refresh(engine,p);engine.Quilboar.refresh(engine,p)
		feed(engine,p)
	sort_shop(engine,p)
	if not special:engine.R134.spare_shop(engine,p)
	if refreshed:engine.R133.refreshed(engine,p)
	else:engine.R133.shop_sync(engine,p)
	return refreshed
static func consume(engine,p: Dictionary,c: Dictionary,eaten: Dictionary,multiplier: int=1,take_keywords: bool=false,fill: bool=true) -> bool:
	if eaten.is_empty() or engine.find_index(p.shop,int(eaten.instance_id))<0 or engine.content.get_def(eaten.def_id).kind!="minion":return false
	var v=engine.stats(eaten)*multiplier
	var value=engine.Elementals.Gain.from_source(engine,p,v,{},c)
	engine.buff(c,value.x,value.y,"permanent","consume")
	if take_keywords:
		for k in engine.keywords(eaten):engine.add_keyword(c,k)
	if U.tribe(engine,c,"恶魔") and has(engine,p,"claw"):
		engine.buff(c,5,5,"permanent","claw")
		for k in engine.keywords(eaten):engine.add_keyword(c,k)
	p.shop.erase(eaten);engine.return_pool(eaten)
	engine.emit("ShopMinionConsumed",int(p.id),{"source_instance":c.instance_id,"target":eaten.instance_id,"attack":value.x,"health":value.y,"keywords":take_keywords,"consumed_snapshot":eaten.duplicate(true),"consumer_snapshot":c.duplicate(true)})
	if engine.content.get_def(c.def_id).get("base_id","")=="BG34_500":preload("res://domain/rules/elemental_trinkets.gd").consumed(engine,p,c,value)
	if fill and has(engine,p,"gauntlet"):fill_local(engine,p)
	return true
static func eat_random(engine,p: Dictionary,c: Dictionary,n: int,multiplier: int=1,keys: bool=false) -> void:
	var targets=p.shop.filter(func(v):return engine.content.get_def(v.def_id).kind=="minion").duplicate()
	for unused in mini(n,targets.size()):var eaten=targets.pop_at(RNG.next(engine.state.streams,"effects",targets.size()));consume(engine,p,c,eaten,multiplier,keys)
static func feed(engine,p: Dictionary) -> void:
	var demons=p.board.filter(func(c):return U.tribe(engine,c,"恶魔"))
	if demons.is_empty():return
	for food in p.shop.duplicate():
		if engine.content.get_def(food.def_id).get("base_id","")!="BG35_150t":continue
		var consumer=pick(engine,demons)
		if consume(engine,p,consumer,food,2 if engine.content.get_def(food.def_id).golden else 1,false,false):
			var replacement=draw_minion(engine,p)
			if not replacement.is_empty():p.shop.append(replacement)
	if has(engine,p,"gauntlet"):fill_local(engine,p)
	sort_shop(engine,p)
static func valid_target(engine,p: Dictionary,d: Dictionary,c: Dictionary) -> bool:
	if d.get("effects",[]).is_empty():return true
	var op=str(d.effects[0].get("op",""))
	if d.effects[0].get("handler","")!="round10":return true
	if op=="eat_spell":return not c.is_empty() and engine.find_index(p.board,int(c.instance_id))>=0 and U.tribe(engine,c,"恶魔")
	if op=="gold_eye":return not c.is_empty() and engine.find_index(p.board,int(c.instance_id))>=0 and int(engine.content.get_def(c.def_id).tier)<=4 and not engine.content.get_def(c.def_id).golden and engine.content.get_def(c.def_id).get("golden_id","")!=""
	if op=="hamul":
		if c.is_empty() or engine.card_types(c).is_empty():return false
		if engine.Shop132.outside(engine,c):return engine.Shop132.fallback_pool(engine,p).any(func(id):return engine.Shop132.available_stock(engine,p,id)>0)
		return true
	return true
static func availability(engine,p: Dictionary) -> Dictionary:
	if engine.hero_handler(p)=="jar":return {"available":false,"reason":"PASSIVE_POWER","targets":[]}
	if engine.hero_handler(p)!="rat":return {}
	var s=engine.Powers.selected(engine,p);var tribe=str(s.progress.get("rat_tribe",""))
	var options=engine.discovery_candidates(p,{"tribe":tribe},engine.power_definition(p))
	var reason="POWER_ALREADY_USED" if engine.power_used(p) else "NOT_ENOUGH_COINS" if int(p.coins)<2 else "NO_LEGAL_CANDIDATE" if options.is_empty() else ""
	return {"available":reason=="","reason":reason,"targets":[],"cost":2,"handler":"rat"}
static func use_power(engine,p: Dictionary) -> String:
	var tribe=str(engine.Powers.selected(engine,p).progress.get("rat_tribe",""))
	U.discover(engine,p,{"tribe":tribe,"amount":1},false,engine.power_definition(p))
	p.coins-=2;engine.consume_power(p);engine.Elementals.spent(engine,p,2);engine.emit("HeroPowerUsed",int(p.id),{"hero":p.hero_id,"power_id":power_id(engine,p)})
	return ""
static func activate_query(engine,p: Dictionary,c: Dictionary,mode: String) -> Dictionary:
	var es=engine.Triggers.effects(engine,c).filter(func(e):return e.get("handler","")=="round10" and e.get("trigger","")=="activate")
	if mode!="gold" and es.is_empty():return {}
	var cost=1 if mode=="gold" else int(es[0].cost)
	var round_key="demon_gold_round" if mode=="gold" else "demon_native_round"
	var targets=[]
	if mode=="gold":targets=[-1] if p.shop.any(func(v):return engine.content.get_def(v.def_id).kind=="minion") else []
	elif es[0].op=="demons_eat":targets=[-1] if p.board.any(func(v):return U.tribe(engine,v,"恶魔")) and p.shop.any(func(v):return engine.content.get_def(v.def_id).kind=="minion") else []
	else:targets=[-1]
	var reason="ALREADY_ACTIVATED" if int(c.get(round_key,-1))==int(engine.state.round) else "NOT_ENOUGH_COINS" if int(p.coins)<cost else "NO_LEGAL_TARGET" if targets.is_empty() else ""
	return {"available":reason=="","reason":reason,"targets":targets,"cost":cost,"mode":mode}
static func activate(engine,p: Dictionary,c: Dictionary,mode: String) -> String:
	var query=activate_query(engine,p,c,mode)
	if not query.available:return query.reason
	p.coins-=int(query.cost);c["demon_gold_round" if mode=="gold" else "demon_native_round"]=int(engine.state.round);engine.Elementals.spent(engine,p,int(query.cost))
	if mode=="gold":
		for eaten in p.shop.duplicate():consume(engine,p,c,eaten)
		engine.refill_shop(p,false)
	else:
		for e in engine.Triggers.effects(engine,c).filter(func(e):return e.get("handler","")=="round10" and e.get("trigger","")=="activate"):engine.effect(p,e,c,c)
	engine.emit("MinionActivated",int(p.id),{"instance_id":c.instance_id,"mode":mode});engine.drain_rewards(p)
	return ""
static func neighbors(engine,p: Dictionary,c: Dictionary) -> Array:
	var result=[];var i=p.board.find(c)
	for j in [i-1,i+1]:
		if j>=0 and j<p.board.size():result.append(p.board[j])
	return result
static func execute(engine,p: Dictionary,e: Dictionary,c: Dictionary) -> bool:
	if e.get("handler","")!="round10":return false
	var n=int(e.get("amount",1));var source=engine.effect_source
	match str(e.op):
		"weaver":
			for unused in n:hurt(engine,p,1,c);engine.buff(c,2,2)
		"feed_window":window(engine,p,n)
		"feed_one":p["fodder_once"]=int(p.get("fodder_once",0))+n
		"mud":
			if not engine.effect_target.is_empty():eat_random(engine,p,engine.effect_target,1,n)
		"damage_discover":
			var pool=engine.discovery_candidates(p,{"tribe":"恶魔"},source)
			engine.resolve_discovery(p,pool,"demon_damage",n,source)
		"consume_end":engine.Elementals.consume(engine,p,c,n)
		"demons_eat":
			var targets=p.shop.filter(func(v):return engine.content.get_def(v.def_id).kind=="minion").duplicate()
			for target in p.board.duplicate():
				if U.tribe(engine,target,"恶魔") and not targets.is_empty():
					var eaten=targets.pop_at(RNG.next(engine.state.streams,"effects",targets.size()))
					consume(engine,p,target,eaten,n)
		"give":
			for unused in n:engine.receive_card(p,engine.make_card(e.id,int(p.id)),source)
		"shop_low":
			p["demon_low_attack"]=int(p.get("demon_low_attack",0))+n;p["demon_low_health"]=int(p.get("demon_low_health",0))+n
			for v in p.shop:
				if engine.content.get_def(v.def_id).kind=="minion" and int(engine.content.get_def(v.def_id).tier)<=3:engine.buff(v,n,n,"permanent","demon_low")
		"escape":
			for v in p.shop:
				if engine.content.get_def(v.def_id).kind=="minion":engine.buff(v,n,n);engine.add_keyword(v,pick(engine,["TAUNT","DIVINE_SHIELD","WINDFURY"]))
		"spell_shop","bloodblade":
			p["demon_shop_attack"]=int(p.get("demon_shop_attack",0))+n;p["demon_shop_health"]=int(p.get("demon_shop_health",0))+n;grow_shop(engine,p,n,n,"permanent","demon_shop")
		"spell_strength":p["spell_bonus_attack"]=int(p.get("spell_bonus_attack",0))+n;p["spell_bonus_health"]=int(p.get("spell_bonus_health",0))+n
		"void":
			if e.get("trigger","")=="obtain":grow_shop(engine,p,2,2,"permanent","void")
		"cheese":
			if e.get("trigger","")=="obtain":grow_shop(engine,p,2,2,"permanent","cheese")
			else:
				source["cheese_refreshes"]=int(source.get("cheese_refreshes",0))+1
				if int(source.cheese_refreshes)>=4:source.cheese_refreshes-=4;source["cheese_bonus"]=int(source.get("cheese_bonus",2))+2;grow_shop(engine,p,2,2,"permanent","cheese")
		"uzul":
			var targets=p.board.filter(func(v):return v.instance_id!=c.instance_id and U.tribe(engine,v,"恶魔"));var consumer=pick(engine,targets)
			if consumer!=null:eat_random(engine,p,consumer,1)
		"gauntlet":grow_shop(engine,p,3,3,"permanent","gauntlet");fill_local(engine,p)
		"eat_spell":eat_random(engine,p,c,n,1,e.get("keywords",false))
		"discover_tag":
			var pool=engine.discovery_candidates(p,{},source).filter(func(id):return engine.content.get_def(id).get("mechanics",[]).has(e.tag) or engine.content.get_def(id).effects.any(func(v):return v.get("trigger","")==e.tag))
			engine.resolve_discovery(p,pool,"tagged_minion",1,source)
		"invoke":
			var v=engine.stats(c)
			if engine.sell_card(p,c):
				var target=pick(engine,p.board)
				if target!=null:engine.buff(target,v.x,v.y,"permanent","invoke")
		"perfect":
			var v=Attributes.value(engine.current_spell,e,p)
			preload("res://domain/rules/stat_reset.gd").perfect(engine,c,v)
		"gold_eye":
			if valid_target(engine,p,engine.current_spell,c):
				engine.Pirates.transform_gold(engine,c)
				c.erase("activated_round")
				c.erase("demon_native_round")
		"hamul":
			if engine.Shop132.outside(engine,c):engine.Shop132.refresh(engine,p,"hamul_fallback",c);return true
			var tribes=engine.Naga.types(engine,c)
			if not tribes.is_empty():refill(engine,p,false,true,pick(engine,tribes))
		"rewind","corrosion","prince","satyr","feed_token","tichondrius","eye","shield","portrait","life_demon","life_spell","claw","rat","jar":pass
		_:return false
	return true

