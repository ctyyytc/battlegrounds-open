extends RefCounted
const RNG=preload("res://domain/rules/deterministic_rng.gd")
const U=preload("res://domain/rules/undead_rules.gd")
const MAGNETIC=["BG26_146","BG_DEEP_015","BG26_147","BG_BOT_911","BG32_172","BG35_341"]
const DEATHRATTLE_GIFTS=[3,20,24,26,39]
static func has_deathrattle(engine,c: Dictionary) -> bool:
	return engine.card_gifts(c).any(func(g):return int(g.id) in DEATHRATTLE_GIFTS)
static func count(engine,c: Dictionary,id: int) -> int:
	return engine.card_gifts(c).filter(func(g):return int(g.id)==id).size()
static func acquire(engine,p: Dictionary,c: Dictionary,id: int,source: String="regular_button") -> void:
	var gift={"id":id,"acquired_round":int(engine.state.round),"source":source,"progress":0}
	if id==2:
		gift["attack"]=3 if int(engine.state.round)>=5 else 2
		gift["health"]=4 if int(engine.state.round)>=5 else 3 if int(engine.state.round)==4 else 2
	c.gifts.append(gift)
	match id:
		1: engine.add_keyword(c,"DIVINE_SHIELD"); engine.add_keyword(c,"WINDFURY")
		5: engine.buff(c,5,5)
		10:
			var d=engine.content.get_def(c.def_id)
			if not d.golden and d.get("golden_id","")!="":
				c.def_id=d.golden_id;engine.qualify_gold(c,"gift10",true)
				engine.Naga.recruit_entered(engine,p,c)
		15: engine.add_keyword(c,"STEALTH")
		16:
			var clone=c.duplicate(true)
			clone.instance_id=int(engine.state.next_instance);engine.state.next_instance+=1
			clone.pool_copies=0;clone["attached_pool"]=[]
			engine.qualify_gold_copy(clone,"gift16_copy")
			engine.receive_card(p,clone,engine.Acquisition.context(engine,c,"ordinary"))
		24: engine.buff(c,10,0)
		26: engine.buff(c,0,10)
		27: engine.buff(c,4,4)
		38: c["all_tribes"]=true
		41: engine.add_keyword(c,"VENOMOUS")
		42: engine.add_keyword(c,"REBORN"); c["enhanced_reborn_available"]=true
		43: engine.buff(c,1000,0)
	engine.emit("DarkGiftAcquired",int(p.id),{"instance_id":c.instance_id,"gift":gift})
static func derived(engine,p: Dictionary,c: Dictionary) -> Vector2i:
	var result=Vector2i.ZERO
	for g in engine.card_gifts(c):
		var n=int(g.id)
		if n in [12,29]: result+=Vector2i.ONE*int(p.get("battlecry_count",0))*(2 if n==12 else 3)
		if n in [13,30]: result+=Vector2i.ONE*int(p.get("deathrattle_count",0))*(1 if n==13 else 2)
		if n in [14,32]: result+=Vector2i.ONE*int(p.tavern_spell_count)*(2 if n==14 else 3)
	return result
static func used(engine,p: Dictionary,played: Dictionary={},listeners: Variant=null) -> void:
	for c in p.board.duplicate():
		if int(c.instance_id)==int(played.get("instance_id",-1)):continue
		for g in (engine.card_gifts(c) if listeners==null else listeners.get(int(c.instance_id),[])):
			match int(g.id):
				6: engine.buff(c,3,0)
				7: engine.buff(c,0,3)
				33: engine.buff(c,2,2)
				40: engine.buff(c,4,4)
static func cards(engine,p: Dictionary,spec: Dictionary,c: Dictionary) -> void:
	U.random_cards(engine,p,spec,c)
static func end_one(engine,p: Dictionary,c: Dictionary,g: Dictionary) -> void:
	match int(g.id):
		2: engine.buff(c,int(g.get("attack",2)),int(g.get("health",2)))
		9,11:
			var elapsed=int(engine.state.round)-int(g.acquired_round)+1
			g["progress"]=elapsed%2
			if elapsed%2==0:
				if int(g.id)==11: U.copy_base(engine,p,c,c)
				else:
					var types=engine.card_types(c).filter(func(t):return t in engine.state.enabled_tribes)
					if not types.is_empty(): cards(engine,p,{"tribe":types[RNG.next(engine.state.streams,"effects",types.size())]},c)
		21:
			var pool=MAGNETIC.filter(func(id):return engine.content.get_def(id).get("implemented",false) and int(engine.content.get_def(id).tier)<=int(p.tier))
			if not pool.is_empty():
				var attached=engine.make_card(pool[RNG.next(engine.state.streams,"effects",pool.size())],int(p.id))
				engine.attach_magnetic(p,c,attached)
			else: engine.emit("EmptyMagneticPool",int(p.id),{"source_instance":c.instance_id,"tier":p.tier})
		25: engine.run_effects(p,c,"battlecry")
		27:
			g["progress"]=int(engine.state.round)-int(g.acquired_round)
			if int(g.progress)>=2 and not g.get("doubled",false):
				g["doubled"]=true
				var v=engine.stats(c); engine.buff(c,v.x,v.y)
static func boundary(engine,p: Dictionary,phase: String) -> void:
	var previous_phase=engine.resolution_phase;engine.resolution_phase=phase
	var repeats=engine.Triggers.times(engine,p,"turn_end") if phase=="turn_end" else 1
	for c in p.board.duplicate():
		if phase=="turn_start":
			for unused in count(engine,c,19):
				engine.run_effects(p,c,"turn_end",{},true,1)
				for g in engine.card_gifts(c):
					if int(g.id)!=19: end_one(engine,p,c,g)
		else:
			for unused in repeats:
				for g in engine.card_gifts(c): end_one(engine,p,c,g)
	engine.resolution_phase=previous_phase
static func rally(engine,p: Dictionary,c: Dictionary) -> void:
	for unused in count(engine,c,8):
		for i in 2: engine.receive_card(p,engine.make_card("BG20_GEM",int(p.id)),c)
	for unused in count(engine,c,22):engine.Demons.window(engine,p,1)
	for unused in count(engine,c,31):
		var counts={}
		for target in U.board(engine,p):
			if target.has("health") and int(target.health)<=0:continue
			for tribe in engine.state.enabled_tribes:
				if tribe in engine.card_types(target) or "全部种族" in engine.card_types(target):counts[tribe]=int(counts.get(tribe,0))+1
		var best=[];var highest=0
		for tribe in counts:
			if int(counts[tribe])>highest:highest=int(counts[tribe]);best=[tribe]
			elif int(counts[tribe])==highest:best.append(tribe)
		if not best.is_empty():cards(engine,p,{"tribe":best[RNG.next(engine.state.streams,"effects",best.size())]},c)
static func essence_pool(engine,p: Dictionary) -> Array:
	return engine.content.pool("spell",engine.state.enabled_tribes).filter(func(id):
		var d=engine.content.get_def(id)
		return d.get("is_tavern_spell",false) and int(d.tier)<=int(p.tier))
static func death(engine,p: Dictionary,c: Dictionary) -> void:
	var board=U.board(engine,p)
	for g in engine.card_gifts(c):
		match int(g.id):
			3: p.free_refresh+=2
			20:
				var pool=essence_pool(engine,p)
				if not pool.is_empty(): engine.receive_card(p,engine.make_card(pool[RNG.next(engine.state.streams,"effects",pool.size())],int(p.id)),c)
			24,26:
				if not board.is_empty():
					var target=board[RNG.next(engine.state.streams,"effects",board.size())]
					U.local_buff(engine,target,int(c.get("attack",engine.stats(c).x)) if int(g.id)==24 else 0,int(c.get("max_health",engine.stats(c).y)) if int(g.id)==26 else 0)
			39:
				if not engine.combat_context.is_empty() and board.size()<int(engine.combat_context.get("capacities",[7,7])[engine.combat_context.players.find(p)]):
					var token=engine.make_card("PROJECT_R6_GIFT39_GOLEM",int(p.id));var base=engine.stats(token)
					engine.buff(token,int(c.attack)-base.x,int(c.max_health)-base.y)
					var unit=preload("res://domain/rules/combat_service.gd").unit(engine,token);board.append(unit)
					engine.emit("MinionSummoned",int(p.id),{"instance_id":unit.instance_id,"source_instance":c.instance_id,"origin":"gift39_same_stats_only"})
static func opening(engine,p: Dictionary,c: Dictionary) -> void:
	for g in engine.card_gifts(c):
		match int(g.id):
			17: c["shield_budget"]=int(c.get("shield_budget",0))+3
			34:
				U.local_buff(engine,c,0,int(c.max_health))
			35: U.local_buff(engine,c,int(c.attack),0)
			36: U.local_buff(engine,c,2*int(c.attack),2*int(c.max_health))
			37:
				var board=U.board(engine,p);var index=board.find(c)
				if index>0:U.local_buff(engine,c,int(board[index-1].attack),0)
			44:
				c["immune_attacking"]=true
static func refresh(engine,p: Dictionary) -> void:
	engine.Demons.feed(engine,p)
