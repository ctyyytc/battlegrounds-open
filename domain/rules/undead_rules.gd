extends RefCounted
const RNG=preload("res://domain/rules/deterministic_rng.gd")
const Attributes=preload("res://domain/rules/spell_attributes.gd")

const HANDLERS={
	"knight_counter":["derived"],"combat_buff":["deathrattle"],"combat_reborn":["deathrattle"],
	"magnetic":["passive"],"destroy_copy":["battlecry"],"destroy_discover":["battlecry"],
	"plague_attack":["deathrattle"],"activate_destroy":["activate"],"banshee":["reborn"],
	"avenge_generate":["avenge"],"summon_tracked":["deathrattle"],"phantom":["reborn"],
	"spell_bonus":["deathrattle"],"avenge_give":["avenge"],"menagerie":["","deathrattle","rally"],
	"cast_tea":["targeted_spell"],"slaughter":[""],"discover_marked":[""],"destroy_generate":[""],
	"knight_reborn":["combat_start"],"heart":["friendly_death"],"discover_filtered":["obtain"],
	"first_deathrattle":["combat_start"],"summon_shield":["summoned"],"destroy_coins":["recruit_destroy"],
	"avenge_spell":["avenge"],"soul_jar":["combat_start"],"plague_copy":["recruit_destroy"],
	"knight_portrait":["friendly_death"],"reborn_copy":["reborn"]}
static func supports(d: Dictionary,e: Dictionary) -> bool:
	return d.kind in ["minion","spell","trinket"] and HANDLERS.has(e.get("handler","")) and e.get("trigger","") in HANDLERS[e.handler]
static func tribe(engine,c: Dictionary,t: String) -> bool:
	var types=engine.card_types(c)
	return t in types or "全部种族" in types
static func board(engine,p: Dictionary) -> Array:
	return engine.combat_context.boards[int(engine.combat_context.players.find(p))] if not engine.combat_context.is_empty() and p in engine.combat_context.players else p.board
static func board_player(engine,pid: int) -> Dictionary:
	for p in engine.combat_context.get("players",[]):
		if int(p.id)==pid: return p
	return engine.state.players[pid]
static func is_combat(engine) -> bool:
	return not engine.combat_context.is_empty()
static func add_global(engine,p: Dictionary,amount: int,health: int=0) -> void:
	p.undead_attack+=amount
	p["undead_health"]=int(p.get("undead_health",0))+health
	if is_combat(engine):
		for c in board(engine,p):
			if tribe(engine,c,"亡灵"):
				c.attack+=amount; c.health+=health; c.max_health+=health
				c["derived_attack"]=int(c.get("derived_attack",c.attack-amount))+amount
				c["derived_health"]=int(c.get("derived_health",c.max_health-health))+health
				engine.R135.stat_gain(engine,c,amount,health)
	engine.emit("UndeadAttackChanged",int(p.id),{"amount":amount,"health":health,"total":p.undead_attack,"total_health":p.undead_health})
static func local_buff(engine,c: Dictionary,a: int,h: int,permanent: bool=false) -> void:
	if engine.Beasts.immune(engine,c):return
	if is_combat(engine):
		var retained=engine.Gifts.count(engine,c,28)
		if retained>0:
			a*=1+retained;h*=1+retained;permanent=true
		c.attack+=a; c.health+=h; c.max_health+=h
		if permanent:
			var p=engine.state.players[int(c.owner)]
			var index=engine.find_index(p.board,int(c.instance_id))
			if index>=0 and not board_player(engine,int(c.owner)).get("is_ghost",false): engine.buff(p.board[index],a,h,"permanent","effect",false)
		engine.R135.stat_gain(engine,c,a,h)
		engine.R13Items.amalgam_gain(engine,c,a,h,true)
		engine.emit("CombatStatsChanged",int(c.owner),{"instance_id":c.instance_id,"attack":a,"health":h})
	else: engine.buff(c,a,h)
static func copy_base(engine,p: Dictionary,c: Dictionary,source: Dictionary={}) -> void:
	engine.receive_card(p,engine.make_card(engine.R13Items.original_id(engine,c),int(p.id)),source)
static func discover(engine,p: Dictionary,e: Dictionary,marked: bool=false,source: Dictionary={}) -> void:
	var pool=engine.discovery_candidates(p,e,source)
	if e.get("deathrattle",false): pool=pool.filter(func(id):return engine.content.get_def(id).effects.any(func(x):return x.get("trigger","")=="deathrattle"))
	engine.resolve_discovery(p,pool,"undead",int(e.get("amount",1)),source,marked)
static func random_cards(engine,p: Dictionary,e: Dictionary,source: Dictionary={}) -> void:
	var pool=engine.generation_candidates(p,e,source if not source.is_empty() else engine.effect_source)
	for unused in int(e.get("amount",1)):
		if pool.is_empty(): break
		var c=engine.make_card(pool[RNG.next(engine.state.streams,"effects",pool.size())],int(p.id))
		var result=engine.receive_card(p,c,source)
		if result!="burned" and not source.is_empty() and e.get("handler","")=="avenge_generate":
			if not source.has("tracked_rewards"): source["tracked_rewards"]=[]
			source.tracked_rewards.append(int(c.instance_id))
static func different_family(engine,source: Dictionary,target: Dictionary) -> bool:
	if source.is_empty() or target.is_empty(): return false
	var a=engine.content.get_def(source.def_id); var b=engine.content.get_def(target.def_id)
	return str(a.get("base_id",source.def_id))!=str(b.get("base_id",target.def_id))
static func valid_different_victim(engine,p: Dictionary,victim: Dictionary,source: Dictionary) -> bool:
	return valid_victim(engine,p,victim,source) and different_family(engine,source,victim)
static func valid_victim(engine,p: Dictionary,victim: Dictionary,source: Dictionary={}) -> bool:
	return not victim.is_empty() and engine.find_index(p.board,int(victim.instance_id))>=0 and tribe(engine,victim,"亡灵") and int(victim.instance_id)!=int(source.get("instance_id",-1))
static func recruit_destroy(engine,p: Dictionary,victim: Dictionary) -> bool:
	var index=engine.find_index(p.board,int(victim.get("instance_id",-1)))
	if index<0: return false
	if engine.Continuation.request(engine,p,victim,"destroy",{"kind":"recruit_destroy","instance_id":victim.instance_id}):return false
	var dead=p.board.pop_at(index)
	engine.emit("MinionDestroyed",int(p.id),{"instance_id":dead.instance_id,"id":dead.def_id,"phase":"recruit"})
	death(engine,p,dead)
	var death_specs=engine.Triggers.expanded(engine,p,dead,"deathrattle")
	if not death_specs.is_empty(): engine.count_trigger(p,"deathrattle",engine.Triggers.times(engine,p,"deathrattle"))
	for e in death_specs:
		if e.get("trigger","")!="deathrattle": continue
		engine.emit("DeathrattleTriggered",int(p.id),{"instance_id":dead.instance_id,"phase":"recruit"})
		if e.handler=="summon":
			for unused in int(e.amount):
				if p.board.size()>=engine.capacity(p.board): break
				var child=engine.make_card(e.id,int(p.id));p.board.insert(mini(index,p.board.size()),child)
				engine.Naga.recruit_entered(engine,p,child)
		else: engine.effect(p,e,dead)
	if "REBORN" in engine.keywords(dead) and p.board.size()<engine.capacity(p.board):
		var child=engine.recruit_reborn(dead)
		p.board.insert(mini(index,p.board.size()),child)
		engine.Naga.recruit_entered(engine,p,child)
		engine.emit("RebornResolved",int(p.id),{"instance_id":child.instance_id,"phase":"recruit"})
		reborn_event(engine,p,child)
	engine.return_pool(dead)
	for item in p.trinkets:
		for e in engine.content.get_def(item.id).effects:
			if e.get("trigger","")=="recruit_destroy":
				if e.handler=="destroy_coins": engine.gain_coins(p,int(e.amount))
				elif e.handler=="plague_copy" and engine.content.get_def(dead.def_id).get("base_id","")=="BG34_690": copy_base(engine,p,dead,item)
	return true
static func death(engine,p: Dictionary,dead: Dictionary) -> void:
	engine.Beasts.death(engine,p,dead)
	engine.Quilboar.dead(engine,p,dead)
	engine.emit("FriendlyDeathCounted",int(p.id),{"instance_id":dead.instance_id,"id":dead.def_id,"phase":"combat" if is_combat(engine) else "recruit"})
	if engine.content.get_def(dead.def_id).get("base_id","")=="BG25_008":
		p["knight_deaths"]=int(p.get("knight_deaths",0))+1
		update_knights(engine,p,4,2,true)
	for item in p.trinkets:
		for e in engine.content.get_def(item.id).effects:
			if e.handler=="heart":
				item["death_progress"]=int(item.get("death_progress",0))+1
				if int(item.death_progress)>=int(e.threshold):
					item.death_progress=0; random_cards(engine,p,e,item)
				engine.emit("TrinketProgress",int(p.id),{"id":item.id,"remaining":int(e.threshold)-int(item.death_progress)})
			if e.handler=="knight_portrait" and tribe(engine,dead,"亡灵"):
				p["knight_extra_attack"]=int(p.get("knight_extra_attack",0))+int(e.attack)
				p["knight_extra_health"]=int(p.get("knight_extra_health",0))+int(e.health)
				update_knights(engine,p,int(e.attack),int(e.health),false)
	if not is_combat(engine): return
	for c in board(engine,p).duplicate():
		for e in engine.content.get_def(c.def_id).effects:
			if e.get("trigger","")=="avenge": avenge(engine,p,c,e)
	for item in p.trinkets:
		for e in engine.content.get_def(item.id).effects:
			if e.get("trigger","")=="avenge": avenge(engine,p,item,e)
static func update_knights(engine,p: Dictionary,a: int,h: int,scaled: bool) -> void:
	if not is_combat(engine): return
	for c in board(engine,p):
		var d=engine.content.get_def(c.def_id)
		if d.get("base_id","")=="BG25_008":
			var multiplier=2 if scaled and d.golden else 1
			local_buff(engine,c,a*multiplier,h*multiplier)
			c["derived_attack"]=int(c.get("derived_attack",c.attack-a*multiplier))+a*multiplier
			c["derived_health"]=int(c.get("derived_health",c.max_health-h*multiplier))+h*multiplier
static func avenge(engine,p: Dictionary,source: Dictionary,e: Dictionary) -> void:
	var key="avenge_"+str(e.handler)
	source[key]=int(source.get(key,0))+1
	if int(source[key])>=int(e.threshold):
		source[key]=0
		engine.emit("AvengeTriggered",int(p.id),{"source":source.get("instance_id",source.get("id","")),"handler":e.handler})
		if e.handler=="avenge_generate": random_cards(engine,p,e,source)
		elif e.handler=="avenge_give":
			for unused in int(e.amount): engine.receive_card(p,engine.make_card(e.id,int(p.id)),source)
		elif e.handler=="avenge_spell": spell_bonus(engine,p,int(e.attack),int(e.health))
		elif e.handler in ["round7","round8","round9","round12"]:engine.effect(p,e,source,source)
static func spell_bonus(engine,p: Dictionary,a: int,h: int) -> void:
	p["spell_bonus_attack"]=int(p.get("spell_bonus_attack",0))+a
	p["spell_bonus_health"]=int(p.get("spell_bonus_health",0))+h
	engine.emit("TavernSpellBonusChanged",int(p.id),{"attack":a,"health":h})
static func reborn_event(engine,p: Dictionary,child: Dictionary) -> void:
	for c in board(engine,p).duplicate():
		for e in engine.content.get_def(c.def_id).effects:
			if e.handler=="banshee":
				local_buff(engine,c,int(e.attack),int(e.health))
				if is_combat(engine):
					c.shield=true
					if "DIVINE_SHIELD" not in c.keywords: c.keywords.append("DIVINE_SHIELD")
				else: engine.add_keyword(c,"DIVINE_SHIELD")
			elif e.handler=="phantom":
				var a=int(child.get("attack",engine.stats(child).x))*int(e.amount)
				for target in reversed_board(engine,p):
					if tribe(engine,target,"亡灵"): local_buff(engine,target,a,a); break
	if not is_combat(engine): return
	for item in p.trinkets:
		for e in engine.content.get_def(item.id).effects:
			if e.handler=="reborn_copy" and int(item.get("combat_uses",0))<int(e.limit):
				item["combat_uses"]=int(item.get("combat_uses",0))+1; copy_base(engine,p,child,item)
static func reversed_board(engine,p: Dictionary) -> Array:
	var result=board(engine,p).duplicate(); result.reverse(); return result
static func summoned(engine,p: Dictionary,c: Dictionary) -> void:
	engine.R13.summoned(engine,p,c)
	engine.Beasts.summoned(engine,p,c)
	engine.automaton_summoned(p,c)
	for item in p.trinkets:
		for e in engine.content.get_def(item.id).effects:
			if e.handler=="summon_shield" and int(item.get("combat_uses",0))<int(e.limit):
				item["combat_uses"]=int(item.get("combat_uses",0))+1
				c.shield=true
				if "DIVINE_SHIELD" not in c.keywords: c.keywords.append("DIVINE_SHIELD")
static func assign_type(index: int,candidates: Array,types: Array,matched: Dictionary,seen: Dictionary) -> bool:
	for t in types[index]:
		if seen.has(t): continue
		seen[t]=true
		if not matched.has(t) or assign_type(int(matched[t]),candidates,types,matched,seen):
			matched[t]=index; return true
	return false
static func menagerie_targets(engine,p: Dictionary) -> Array:
	var candidates=RNG.shuffle(board(engine,p).duplicate(),engine.state.streams,"effects")
	var types=[]; var matched={}; var result=[]
	for c in candidates:
		var card_types=engine.card_types(c).duplicate()
		types.append(engine.state.enabled_tribes.duplicate() if "全部种族" in card_types else card_types)
	for i in candidates.size(): assign_type(i,candidates,types,matched,{})
	for i in matched.values():
		if candidates[int(i)] not in result: result.append(candidates[int(i)])
	return result
static func execute(engine,p: Dictionary,e: Dictionary,target: Dictionary) -> bool:
	if not HANDLERS.has(e.get("handler","")): return false
	match str(e.handler):
		"plague_attack": add_global(engine,p,int(e.amount)*(1 if is_combat(engine) else 2))
		"spell_bonus": spell_bonus(engine,p,int(e.attack),int(e.health))
		"combat_buff","combat_reborn":
			var candidates=board(engine,p).filter(func(c):return tribe(engine,c,e.tribe) and int(c.instance_id)!=int(target.get("instance_id",-1)) and (e.handler!="combat_reborn" or (different_family(engine,target,c) and "REBORN" not in c.get("keywords",engine.keywords(c)))))
			candidates=RNG.shuffle(candidates,engine.state.streams,"effects")
			for c in candidates.slice(0,int(e.amount)):
				if e.handler=="combat_buff": local_buff(engine,c,int(e.attack),int(e.health))
				elif is_combat(engine): c.keywords.append("REBORN")
				else: engine.add_keyword(c,"REBORN")
		"discover_marked","discover_filtered": discover(engine,p,e,e.handler=="discover_marked",engine.effect_source)
		"destroy_copy","destroy_discover":
			var victim=engine.effect_target
			if valid_victim(engine,p,victim,target) and recruit_destroy(engine,p,victim):
				if e.handler=="destroy_copy":
					for unused in int(e.amount): copy_base(engine,p,victim,target)
				else: discover(engine,p,e,false,target)
		"slaughter","destroy_generate":
			
			if e.handler=="slaughter":
				
				var value=Attributes.value(engine.current_spell,e,p)
				if valid_victim(engine,p,target) and recruit_destroy(engine,p,target): add_global(engine,p,value.x,value.y)
			else:
				if valid_victim(engine,p,target): recruit_destroy(engine,p,target)
				if engine.cast_destroy_succeeded: random_cards(engine,p,e)
		"menagerie":
			for unused in int(e.get("amount",1)):
				for c in menagerie_targets(engine,p):
					var value=Attributes.value(engine.current_spell,e,p)
					local_buff(engine,c,value.x,value.y,bool(e.get("permanent",false)))
		"cast_tea":
			for unused in int(e.amount): engine.cast(p,engine.content.get_def("BG28_888"),{})
		"summon_tracked": pass 
		_: pass 
	return true
