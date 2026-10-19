extends RefCounted
static func opening_entries(engine,p: Dictionary,side: int) -> Array:
	var result=[];var board=engine.combat_context.boards[side]
	for s in p.power_slots:
		var id=str(s.active_power_id);s.progress["combat_used"]=false
		if id in ["TB_BaconShop_HP_069","BG20_HERO_282p","BG22_HERO_001p"]:
			result.append({"category":0,"side":side,"slot":s.slot_id,"order":0,"op":"hero132","power_id":id,"epoch":s.epoch,"endpoints":([board[0].instance_id,board[-1].instance_id] if not board.is_empty() else [])})
	return result
static func opening(engine,p: Dictionary,entry: Dictionary) -> void:
	var ctx=engine.combat_context;var side=int(entry.side);var board=ctx.boards[side];var s=engine.Powers.selected(engine,p,int(entry.slot))
	if s.is_empty() or int(s.epoch)!=int(entry.epoch):return
	match str(entry.power_id):
		"TB_BaconShop_HP_069":
			var seen=[]
			for id in entry.endpoints:
				if id in seen:continue
				seen.append(id);var i=engine.find_index(board,int(id))
				if i<0:continue
				engine.buff(board[i],2,1);ctx.immediate_attacks.append({"side":side,"instance_id":id,"attack_count":1,"origin":"illidan"})
		"BG20_HERO_282p":
			if board.is_empty():return
			var low=board.reduce(func(v,c):return mini(v,int(c.attack)),2147483647)
			var pool=board.filter(func(c):return int(c.attack)==low);var target=pool[engine.RNG.next(engine.state.streams,"combat",pool.size())]
			if not target.has("attached_effects"):target["attached_effects"]=[]
			target.attached_effects.append({"handler":"round132_combat","op":"phylactery","trigger":"deathrattle"})
		"BG22_HERO_001p":
			match str(s.progress.get("element_id","")):
				"BG22_HERO_001p_t1":
					var pool=board.duplicate()
					for unused in mini(4,pool.size()):
						var c=pool.pop_at(engine.RNG.next(engine.state.streams,"combat",pool.size()))
						if not c.has("attached_effects"):c["attached_effects"]=[]
						c.attached_effects.append({"handler":"summon","trigger":"deathrattle","id":"BG22_HERO_001p_t1et","amount":1})
				"BG22_HERO_001p_t2":
					if not board.is_empty():engine.buff(board[0],int(board[0].attack),0)
				"BG22_HERO_001p_t3":
					if not board.is_empty():engine.add_keyword(board[-1],"DIVINE_SHIELD");engine.add_keyword(board[-1],"TAUNT")
				"BG22_HERO_001p_t4":
					var pool=ctx.boards[1-side].duplicate()
					for unused in mini(5,pool.size()):
						var c=pool.pop_at(engine.RNG.next(engine.state.streams,"combat",pool.size()));engine.Combat.hit({"instance_id":-1,"owner":p.id,"venom":false},c,1,false)
static func stable_one(engine) -> Dictionary:
	var ctx=engine.combat_context
	if ctx.is_empty() or int(ctx.get("cleanup_depth",0))>0:return {}
	for side in 2:
		var p=ctx.players[side];var board=ctx.boards[side]
		for s in p.power_slots:
			if board.size()>=int(ctx.capacities[side]):break
			var id=str(s.active_power_id);var child={}
			if id=="BG22_HERO_000p_Alt":
				var ammo=s.progress.get("ammo",{})
				if ammo.is_empty() or ammo.get("consumed",false) or int(ammo.epoch)!=int(s.epoch) or ctx.boards[1-side].is_empty():continue
				var targets=ctx.boards[1-side].filter(func(c):return int(c.health)>0 and "STEALTH" not in c.keywords)
				if targets.is_empty():continue
				var target=targets[engine.RNG.next(engine.state.streams,"combat",targets.size())]
				var saved=engine.Combat.unit(engine,ammo.card);saved["r13_keep_route"]=true
				ammo.consumed=true;child=engine.Beasts.summon(engine,p,ammo.card.def_id,-1,false,saved)
				if child.is_empty():ammo.consumed=false;continue
				child.pool_copies=0;child["attached_pool"]=[]
				ctx.immediate_attacks.append({"side":side,"instance_id":child.instance_id,"target_id":target.instance_id,"attack_count":1,"origin":"tavish","epoch":s.epoch})
				engine.emit("TavishFired",int(p.id),{"instance_id":child.instance_id,"target_id":target.instance_id,"slot_id":s.slot_id,"epoch":s.epoch})
			elif id in ["BG22_HERO_002p","BG22_HERO_003p"] and int(engine.state.round)>=7 and not s.progress.get("combat_used",false) and not board.is_empty():
				var key="attack" if id=="BG22_HERO_002p" else "health";var top=board.reduce(func(v,c):return maxi(v,int(c[key])),-2147483648)
				var pool=board.filter(func(c):return int(c[key])==top);var target=pool[engine.RNG.next(engine.state.streams,"combat",pool.size())]
				var saved=target.duplicate(true);saved["r13_keep_route"]=true;child=engine.Beasts.summon(engine,p,target.def_id,-1,false,saved)
				if child.is_empty():continue
				child.pool_copies=0;child["attached_pool"]=[];s.progress.combat_used=true
				engine.emit("HighestStatHeroCopied",int(p.id),{"power_id":id,"source_instance":target.instance_id,"instance_id":child.instance_id,"slot_id":s.slot_id,"value":top})
			if not child.is_empty():return {"kind":"summon","instance_id":child.instance_id,"def_id":child.def_id,"origin":id}
	return {}
static func reserve_deaths(engine,deaths: Array) -> void:
	
	
	var players=engine.combat_context.players
	for side in 2:
		var killer=players[1-side]
		var candidates=deaths.filter(func(d):return int(d.side)==side and int(d.unit.get("killed_by_owner",-1))==int(killer.id))
		if candidates.is_empty():continue
		candidates.sort_custom(func(a,b):
			var first=int(a.unit.get("fatal_damage_group",2147483647));var second=int(b.unit.get("fatal_damage_group",2147483647))
			return first<second if first!=second else int(a.index)<int(b.index))
		for s in killer.power_slots:
			if s.active_power_id!="TB_BaconShop_HP_053" or not s.progress.get("rafaam_ready",false):continue
			s.progress.rafaam_ready=false
			var c=candidates[0].unit
			if not c.has("rafaam_reserved_slots"):c["rafaam_reserved_slots"]=[]
			c.rafaam_reserved_slots.append(int(s.slot_id))
static func death(engine,p: Dictionary,c: Dictionary) -> void:
	var ctx=engine.combat_context;var side=ctx.players.find(p)
	if side<0:return
	var killer=ctx.players[1-side]
	if int(c.get("killed_by_owner",-1))!=int(killer.id):return
	for s in killer.power_slots:
		if s.active_power_id=="TB_BaconShop_HP_053" and int(s.slot_id) in c.get("rafaam_reserved_slots",[]):
			c.rafaam_reserved_slots.erase(int(s.slot_id))
			engine.receive_card(killer,engine.R132.original(engine,killer,c),{"def_id":s.active_power_id})
static func after_battle(engine,p: Dictionary) -> void:
	for s in p.power_slots:
		s.progress.erase("rafaam_ready")
		var ammo=s.progress.get("ammo",{})
		if not ammo.is_empty():
			engine.return_pool(ammo.card);s.progress.erase("ammo")
