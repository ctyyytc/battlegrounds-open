extends RefCounted
const U=preload("res://domain/rules/undead_rules.gd")
static func run(engine) -> Array:
	var ctx=engine.combat_context;var queue=[];var feedback=[]
	
	for side in 2:
		var p=ctx.players[side];p["beast_combat_attack"]=0;p["beast_combat_health"]=0
		p["beast_pending"]=[];p["onyxia_avenge"]=0
		queue.append_array(engine.Combat132.opening_entries(engine,p,side))
		queue.append_array(engine.R135.opening_entries(engine,p,side))
		for power_slot in p.power_slots:
			var op=engine.Powers.handler(engine,p,int(power_slot.slot_id))
			if op in ["alakir","teron"]:
				var saved={}
				var i=engine.find_index(ctx.boards[side],int(p.get("teron_target",-1)))
				if i>=0:saved=ctx.boards[side][i].duplicate(true)
				queue.append({"category":0,"side":side,"slot":power_slot.slot_id,"order":0,"op":op,"card":saved})
		for slot in p.trinkets.size():
			var item=p.trinkets[slot];var es=engine.content.get_def(item.id).effects
			for order in es.size():
				var e=es[order]
				if e.get("trigger","")=="combat_start" and e.handler!="first_deathrattle":queue.append({"category":1,"side":side,"slot":slot,"order":order,"op":"trinket","effect":e,"source":item})
		if int(p.get("suppress_count",0))>0:queue.append({"category":2,"side":side,"slot":0,"order":0,"op":"suppress"})
		for slot in p.get("beetle_boons",[]).size():queue.append({"category":2,"side":side,"slot":slot+1,"order":0,"op":"boon","amount":p.beetle_boons[slot]})
		p["beetle_boons"]=[]
		for slot in ctx.boards[side].size():
			var c=ctx.boards[side][slot]
			queue.append({"category":3,"side":side,"slot":slot,"order":-1,"op":"gifts","source":c})
			var es=engine.Triggers.effects(engine,c)
			for order in es.size():
				var e=es[order]
				if e.get("trigger","")=="combat_start" or e.get("op","")=="opening_damage":queue.append({"category":3,"side":side,"slot":slot,"order":order,"op":"minion","effect":e,"source":c})
		for slot in p.hand.size():
			var c=p.hand[slot]
			if engine.CardLock.locked(engine,p,c):continue
			for e in engine.Fish.specs(engine,c,"hand_scout"):queue.append({"category":3,"side":side,"slot":ctx.boards[side].size()+slot,"order":0,"op":"scout","source":c,"effect":e})
	queue.sort_custom(func(a,b):
		for key in ["category","side","slot","order"]:
			if int(a[key])!=int(b[key]):return int(a[key])<int(b[key])
		return false)
	for entry in queue:
		var side=int(entry.side);var p=ctx.players[side];var board=ctx.boards[side]
		if entry.op in ["minion","gifts"] and entry.source not in board:continue
		engine.emit("CombatOpeningOrdered",int(p.id),{"category":entry.category,"side":side,"slot":entry.slot,"order":entry.order,"op":entry.op})
		match str(entry.op):
			"quest135":engine.R135.opening(engine,p,entry.quest)
			"hero132":engine.Combat132.opening(engine,p,entry)
			"alakir":
				if not board.is_empty():
					for k in ["WINDFURY","DIVINE_SHIELD","TAUNT"]:engine.add_keyword(board[0],k)
			"teron":
				if not entry.card.is_empty():
					var i=engine.find_index(board,int(entry.card.instance_id))
					if i>=0:
						p.beast_pending.append({"kind":"teron","card":entry.card,"right_instances":board.slice(i+1).map(func(c):return int(c.instance_id))});board[i].health=0
						feedback.append_array(engine.Combat.cleanup(engine,ctx.boards,ctx.capacities,ctx.players,side))
			"boon":
				for unused in int(entry.amount):p.beast_pending.append({"kind":"boon"})
				feedback.append_array(engine.Beasts.drain_pending(engine))
			"suppress":engine.Fish.suppress(engine,p,ctx.boards[1-side])
			"trinket":
				var e=entry.effect
				if e.handler=="half_attack_health":
					for c in board:engine.buff(c,0,int(floor(float(c.attack)/2.0)))
				elif e.handler=="knight_reborn":
					for c in board:
						if engine.content.get_def(c.def_id).get("base_id","")=="BG25_008":engine.add_keyword(c,"TAUNT");engine.add_keyword(c,"REBORN")
				elif e.get("op","")=="bottled_ice":
					var candidates=board.filter(func(c):return U.tribe(engine,c,"元素"))
					for unused in mini(2,candidates.size()):
						var c=candidates.pop_at(engine.RNG.next(engine.state.streams,"combat",candidates.size()))
						if not c.has("attached_effects"):c["attached_effects"]=[]
						c.attached_effects.append({"handler":"summon","trigger":"deathrattle","id":"BG26_537","amount":1})
				elif e.handler=="soul_jar":
					if board.size()>=3:
						p.soul_jar_stored=board.slice(0,3).duplicate(true)
						for c in board.slice(0,3):c.health=0
						feedback.append_array(engine.Combat.cleanup(engine,ctx.boards,ctx.capacities,ctx.players,side))
				else:engine.effect(p,e,{},entry.source)
			"gifts":
				var c=entry.source;engine.Gifts.opening(engine,p,c)
				for unused in engine.Gifts.count(engine,c,23):
					engine.Beasts.summon(engine,p,c.def_id,board.find(c)+1,false,c)
				for unused in engine.Gifts.count(engine,c,18):engine.Beasts.trigger_deathrattle(engine,p,c)
			"scout":
				if board.size()<int(ctx.capacities[side]):
					var c=engine.Combat.unit(engine,entry.source);c.attack*=int(entry.effect.amount);c.health*=int(entry.effect.amount);c.max_health*=int(entry.effect.amount)
					engine.Beasts.summon(engine,p,c.def_id,-1,false,c)
			"minion":
				var e=entry.effect;var c=entry.source
				if e.get("op","")=="opening_damage":
					for unused in int(e.amount):
						var group=engine.Combat.damage_group(engine)
						var venom_target={}
						if c.get("venom",false):
							for target_side in [1-side,side]:
								var legal=ctx.boards[target_side].filter(func(t):return int(t.instance_id)!=int(c.instance_id) and int(t.health)>0 and not t.shield and not t.get("immune",false))
								if not legal.is_empty():venom_target=legal[0];break
						for team in ctx.boards:
							for target in team:
								if int(target.instance_id)!=int(c.instance_id) and int(target.health)>0:
									var damage_source={"venom":c.get("venom",false) and target==venom_target,"instance_id":c.instance_id,"owner":c.owner}
									var unshielded=not target.shield and not target.get("immune",false);engine.Combat.hit(damage_source,target,3,false);engine.Combat.mark_fatal(damage_source,target,group)
									if target==venom_target and not damage_source.venom:c.venom=false
									if unshielded:engine.Demons.damage_fact(engine,c,3);engine.Fish.damage_received(engine,U.board_player(engine,int(target.owner)),target,3)
						engine.emit("OpeningDamageResolved",int(p.id),{"source_instance":c.instance_id,"damage_group":group,"venom_target":venom_target.get("instance_id",-1),"venom_remaining":c.get("venom",false)})
				else:engine.effect(p,e,c,c)
		feedback.append_array(engine.Combat.cleanup(engine,ctx.boards,ctx.capacities,ctx.players,side))
	return feedback
