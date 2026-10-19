extends RefCounted
const RNG=preload("res://domain/rules/deterministic_rng.gd")
const U=preload("res://domain/rules/undead_rules.gd")
const Gain=preload("res://domain/rules/elemental_gain.gd")
const OPS=["elemental_bonus","nomi","refresh_growth","elemental_board","ball","sell_give","sell_discover","upgrade_effect","spell_discover","spell_choice","spell_strength","last_spell","consume_shop","activate_buff","activate_give","activate_steal","activate_next","activate_set","spend_wind","thunder","shop_aura","battlecry_multiplier","deathrattle_multiplier","end_multiplier","surprise","spell_aura","wildfire","remove_keywords","steal_attack","opening_damage","kill_killer","kangor","spellcraft","feeding","sell_coins","avalanche","self_buff","coins"]
static func supports(d: Dictionary,e: Dictionary) -> bool:
	return e.get("handler","")=="round6" and e.get("op","") in OPS
static func elemental(engine,c: Dictionary) -> bool:
	return U.tribe(engine,c,"元素")
static func bonus(engine,p: Dictionary,a: int,h: int) -> void:
	p.elemental_bonus_attack+=a;p.elemental_bonus_health+=h
	engine.emit("ElementalEffectStrengthChanged",int(p.id),{"attack":a,"health":h})
static func shop_aura(engine,p: Dictionary,a: int,h: int) -> void:
	p["nomi_attack"]=int(p.get("nomi_attack",0))+a;p["nomi_health"]=int(p.get("nomi_health",0))+h
	for c in p.shop:
		if elemental(engine,c): engine.buff(c,a,h,"permanent","nomi")
static func refresh(engine,p: Dictionary) -> void:
	var minions=p.shop.filter(func(c):return engine.content.get_def(c.def_id).kind=="minion")
	if minions.is_empty(): return
	var shared={}
	for growth in p.get("refresh_growth",[]):
		var grouped=str(growth.get("source_id","")) in ["BG34_865","BG34_865_G","BG34_444"]
		if grouped and shared.is_empty():shared=minions[RNG.next(engine.state.streams,"effects",minions.size())]
		var c=shared if grouped else minions[RNG.next(engine.state.streams,"effects",minions.size())]
		if engine.find_index(p.shop,int(c.instance_id))<0:
			engine.emit("RefreshGrowthSkipped",int(p.id),{"target_instance":c.instance_id});continue
		var value=Gain.value(engine.content.get_def(str(growth.get("source_id",""))),p,Vector2i(int(growth.attack),int(growth.health)))
		engine.buff(c,value.x,value.y,"permanent","refresh_growth")
		engine.emit("RefreshGrowthApplied",int(p.id),{"target_instance":c.instance_id,"source_id":growth.get("source_id",""),"attack":value.x,"health":value.y})
static func execute(engine,p: Dictionary,e: Dictionary,c: Dictionary) -> bool:
	if e.get("handler","")!="round6": return false
	var a=int(e.get("attack",0));var h=int(e.get("health",0));var amount=int(e.get("amount",1))
	match str(e.get("op","")):
		"self_buff":
			var value=Gain.from_source(engine,p,Vector2i(a,h),e,c);U.local_buff(engine,c,value.x,value.y)
		"coins": engine.gain_coins(p,amount)
		"sell_coins":
			if p.get("last_combat_lost",false): engine.gain_coins(p,amount-1)
		"avalanche":
			var target=engine.effect_target
			if not target.is_empty():
				var snapshot=engine.sale_snapshot(target)
				if engine.sell_card(p,target):engine.transfer_sale_stats(p,snapshot,"avalanche")
		"elemental_bonus": bonus(engine,p,a,h)
		"nomi","shop_aura":
			for unused in amount:
				var value=Gain.from_source(engine,p,Vector2i(a,h),e,c);shop_aura(engine,p,value.x,value.y)
		"refresh_growth":
			if not p.has("refresh_growth"): p["refresh_growth"]=[]
			var fixed=preload("res://domain/rules/spell_attributes.gd").value(engine.current_spell,e,p) if engine.current_spell.get("id","")=="BG34_444" else Vector2i(a,h)
			for unused in amount: p.refresh_growth.append({"attack":fixed.x,"health":fixed.y,"source":c.get("instance_id",-1),"source_id":engine.effect_source.get("def_id",engine.effect_source.get("id",""))})
		"elemental_board":
			for unused in amount:
				var value=Gain.from_source(engine,p,Vector2i(a,h),e,c)
				for target in U.board(engine,p):
					if elemental(engine,target): U.local_buff(engine,target,value.x,value.y)
		"ball":
			var value=Gain.ball_parts(engine.content.get_def(c.def_id),p).total
			for target in p.board: engine.buff(target,value.x,value.y)
		"sell_give","activate_give":
			for unused in amount: engine.receive_card(p,engine.make_card(e.id,int(p.id)),engine.effect_source)
		"sell_discover": U.discover(engine,p,{"tier":int(c.get("discovery_tier",1)),"amount":amount},false,engine.effect_source)
		"upgrade_effect":
			var field=str(e.field);var old=int(c.get(field,int(e.get("initial",1))))
			c[field]=mini(old+amount,int(e.get("maximum",6)))
			engine.emit("EffectLevelIncreased",int(p.id),{"source_instance":c.instance_id,"field":field,"before":old,"after":c[field]})
		"spell_discover": spell_discover(engine,p,amount,engine.effect_source)
		"spell_choice":
			var options=[]
			for id in e.ids: options.append(engine.make_card(id,int(p.id)))
			engine.enqueue_choice(p,{"kind":"choose_one","options":options,"source":engine.effect_source.duplicate(true),"resolution_phase":engine.resolution_phase})
		"spell_strength":
			p["spell_bonus_attack"]=int(p.get("spell_bonus_attack",0))+a;p["spell_bonus_health"]=int(p.get("spell_bonus_health",0))+h
		"last_spell":
			if p.get("last_tavern_spell","")!="":
				for unused in amount: engine.receive_card(p,engine.make_card(p.last_tavern_spell,int(p.id)),engine.effect_source)
		"consume_shop": consume(engine,p,c,amount)
		"activate_buff":
			var value=Gain.from_source(engine,p,Vector2i(a,h),e,c);engine.buff(engine.effect_target,value.x,value.y)
		"activate_set":
			var target=engine.effect_target;var v=engine.stats(target);engine.buff(target,a-v.x,h-v.y)
		"activate_steal":
			for unused in amount:
				var pool=p.shop.filter(func(v):return engine.content.get_def(v.def_id).kind=="minion")
				if pool.is_empty(): break
				pool.sort_custom(func(x,y):return engine.stats(x).x>engine.stats(y).x)
				var card=pool[0];p.shop.erase(card);engine.receive_card(p,card,engine.effect_source)
		"activate_next": c["next_purchase_multiplier"]=amount
		"spend_wind":
			c["spend_progress"]=int(c.get("spend_progress",0))+int(e.get("spent",0))
			while int(c.spend_progress)>=7:
				c.spend_progress-=7
				for unused in amount: engine.cast(p,engine.content.get_def("BG34_444"),{})
		"thunder":
			c["thunder_progress"]=int(c.get("thunder_progress",0))+1
			if int(c.thunder_progress)>=3:
				c.thunder_progress=0;consume(engine,p,c,amount,false)
		"spellcraft":
			var spell=engine.make_card(e.id,int(p.id));spell["spellcraft_source"]=c.instance_id
			spell["permanent_spellcraft"]=engine.Gifts.count(engine,c,4)>0
			spell["spellcraft_source_snapshot"]={"instance_id":c.instance_id,"def_id":c.def_id,"permanent":spell.permanent_spellcraft}
			if e.get("scaling",false): spell["spellcraft_scale"]=1+int(floor(float(p.spell_count)/3.0))
			engine.receive_card(p,spell,engine.effect_source)
		"feeding":
			engine.Demons.window(engine,p,1)
		"battlecry_multiplier","deathrattle_multiplier","end_multiplier","surprise","spell_aura","wildfire","remove_keywords","steal_attack","opening_damage","kill_killer","kangor": pass
		_: return false
	return true
static func spell_discover(engine,p: Dictionary,amount: int,source: Dictionary) -> void:
	var pool=engine.content.pool("spell",engine.state.enabled_tribes).filter(func(id):return int(engine.content.get_def(id).tier)<=int(p.tier))
	engine.resolve_discovery(p,pool,"tavern_spell",amount,source)
static func consume(engine,p: Dictionary,c: Dictionary,multiplier: int,remove: bool=true) -> void:
	var pool=p.shop.filter(func(v):return engine.content.get_def(v.def_id).kind=="minion")
	if pool.is_empty(): return
	var highest=0
	for card in pool: highest=maxi(highest,engine.stats(card).y)
	pool=pool.filter(func(v):return engine.stats(v).y==highest)
	var eaten=pool[RNG.next(engine.state.streams,"effects",pool.size())]
	if remove:engine.Demons.consume(engine,p,c,eaten,multiplier);return
	var v=engine.stats(eaten)*multiplier;var value=Gain.from_source(engine,p,v,{},c);engine.buff(c,value.x,value.y)
	engine.emit("ShopStatsCopied",int(p.id),{"source_instance":c.instance_id,"target":eaten.instance_id,"attack":v.x,"health":v.y})

static func spent(engine,p: Dictionary,amount: int) -> void:
	if amount<=0: return
	engine.Naga.spent(engine,p,amount)
	engine.Pirates.spent(engine,p,amount)
	engine.emit("CoinsSpent",int(p.id),{"amount":amount})
	for c in p.board.duplicate():
		for e in engine.Triggers.effects(engine,c):
			if e.get("op","")=="spend_wind":
				var spec=e.duplicate(true);spec["spent"]=amount;engine.effect(p,spec,c)
