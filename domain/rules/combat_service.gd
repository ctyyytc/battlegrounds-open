extends RefCounted
const ExternalText = preload("res://domain/resources/external_content.gd")
const RNG=preload("res://domain/rules/deterministic_rng.gd")
const Special=preload("res://domain/rules/special_rules.gd")
const Undead=preload("res://domain/rules/undead_rules.gd")
static func unit(engine,card: Dictionary) -> Dictionary:
	var result=card.duplicate(true)
	result.erase("fatal_damage_group")
	result.erase("rafaam_reserved_slots")
	engine.R133.strip(result)
	var stats=engine.stats(card,"combat_entry")
	result["attack"]=stats.x; result["health"]=stats.y; result["max_health"]=stats.y
	result["derived_attack"]=stats.x; result["derived_health"]=stats.y
	result.health-=int(card.get("recruit_damage",0))
	result["keywords"]=engine.keywords(card)
	result["shield"]="DIVINE_SHIELD" in result.keywords
	result["venom"]="VENOMOUS" in result.keywords
	result["poison"]="POISONOUS" in result.keywords
	result["immune_attacking"]=false
	for e in engine.content.get_def(card.def_id).effects:
		if e.handler=="attack_immune": result.immune_attacking=true
	return result
static func reborn(engine,dead: Dictionary) -> Dictionary:
	var enhanced=dead.enhanced_reborn_available
	var card=dead.duplicate(true) if enhanced else engine.make_card(dead.def_id,int(dead.owner),0)
	card.pool_copies=0; card.gold_route=""; card.enhanced_reborn_available=false; card.triple_receipt=false
	
	if not enhanced: card["reborn_base_health"]=1
	var result=unit(engine,card)
	if enhanced:
		var current=engine.stats(dead,"combat_entry")
		result.attack=int(dead.attack)+current.x-int(dead.get("derived_attack",current.x))
		result.max_health=int(dead.max_health)+current.y-int(dead.get("derived_health",current.y)); result.health=result.max_health
		result.keywords=dead.keywords.duplicate()
	result["reborn_consumed"]=true
	result.keywords.erase("REBORN")
	
	result.erase("tracked_rewards")
	result.extra_keywords.erase("REBORN")
	result.shield="DIVINE_SHIELD" in result.keywords
	result.venom="VENOMOUS" in result.keywords
	result["poison"]="POISONOUS" in result.keywords
	result.instance_id=int(engine.state.next_instance); engine.state.next_instance+=1
	return result
static func hit(attacker: Dictionary,target: Dictionary,damage: int,immune: bool) -> void:
	if immune or target.get("immune",false) or damage<=0: return
	if target.shield:
		if target.has("shield_budget"):
			target.shield_budget-=1
			if int(target.shield_budget)<=0: target.shield=false
		else: target.shield=false
		return
	var was_alive=int(target.health)>0
	target.health-=damage
	if attacker.get("poison",false):target.health=0
	if attacker.get("venom",false):
		target.health=0; attacker.venom=false
	if was_alive and int(target.health)<=0:target["killed_by"]=int(attacker.instance_id);target["killed_by_owner"]=int(attacker.get("owner",-1))
static func damage_group(engine) -> int:
	var ctx=engine.combat_context
	ctx["damage_group_seq"]=int(ctx.get("damage_group_seq",0))+1
	return int(ctx.damage_group_seq)
static func mark_fatal(source: Dictionary,target: Dictionary,group: int) -> void:
	if int(target.health)>0 or target.has("fatal_damage_group"):return
	if int(target.get("killed_by",-1))!=int(source.instance_id) or int(target.get("killed_by_owner",-1))!=int(source.get("owner",-2)):return
	target["fatal_damage_group"]=group
static func cleanup(engine,boards: Array,capacities: Array,players: Array,side_order: int) -> Array:
	var ctx=engine.combat_context
	ctx["cleanup_depth"]=int(ctx.get("cleanup_depth",0))+1
	var feedback=_cleanup_batch(engine,boards,capacities,players,side_order)
	ctx.cleanup_depth-=1
	if int(ctx.cleanup_depth)>0 or ctx.get("draining_forager",false):return feedback
	ctx["draining_forager"]=true
	for unused in 128:
		
		if boards.any(func(team):return team.any(func(c):return int(c.health)<=0)):
			feedback.append_array(cleanup(engine,boards,capacities,players,side_order))
		feedback.append_array(engine.Beasts.drain_pending(engine))
		if boards.any(func(team):return team.any(func(c):return int(c.health)<=0)):continue
		var summoned=engine.Combat132.stable_one(engine)
		if summoned.is_empty():summoned=engine.Fish.forager_one(engine)
		if summoned.is_empty():
			ctx.draining_forager=false
			for player in players:engine.R135.safe(engine,player,true)
			return feedback
		feedback.append(summoned)
	ctx.draining_forager=false
	engine.emit("ForagerBudgetExceeded",0,{"remaining":ctx.get("forager_pending",[]).size()})
	return feedback
static func _cleanup_batch(engine,boards: Array,capacities: Array,players: Array,side_order: int) -> Array:
	var feedback=[]
	var deaths=[]
	for side in [side_order,1-side_order]:
		for index in boards[side].size():
			var c=boards[side][index]
			if int(c.health)<=0: deaths.append({"side":side,"index":index,"unit":c.duplicate(true)})
		boards[side]=boards[side].filter(func(c):return int(c.health)>0)
	engine.Combat132.reserve_deaths(engine,deaths)
	
	for death in deaths:
		var side=int(death.side); var c=death.unit
		var p=players[side]
		var spawned_instances=[]
		var reward_event_start=engine.events.size()
		feedback.append({"kind":"death","instance_id":c.instance_id,"def_id":c.def_id})
		engine.combat_context.deaths.append({"instance_id":c.instance_id,"owner":p.id,"def_id":c.def_id,"base_id":engine.content.get_def(c.def_id).get("base_id",c.def_id)})
		engine.emit("MinionDied",int(p.id),{"instance_id":c.instance_id,"id":c.def_id})
		engine.Combat132.death(engine,p,c)
		if Undead.tribe(engine,c,"机械"):
			if not p.has("mechanical_deaths"): p["mechanical_deaths"]=[]
			p.mechanical_deaths.append(engine.content.get_def(c.def_id).get("base_id",c.def_id))
		Undead.death(engine,p,c)
		var death_effects=engine.Triggers.expanded(engine,p,c,"deathrattle")
		if not death_effects.is_empty(): engine.count_trigger(p,"deathrattle",engine.Triggers.times(engine,p,"deathrattle"))
		spawned_instances.append_array(resolve_deathrattles(engine,p,c,boards,side,capacities,int(death.index),death_effects,feedback))
		for event in engine.events.slice(reward_event_start):
			if event.kind in ["CardGranted","RewardQueued"] and event.owner==int(p.id):
				feedback.append({"kind":"reward" if event.kind=="CardGranted" else "reward_queued","instance_id":int(event.payload.get("instance_id",-1)),"def_id":str(event.payload.get("id",""))})
		death["spawned_instances"]=spawned_instances
	
	
	for death in deaths:
		var side=int(death.side); var c=death.unit
		var p=players[side]
		if "REBORN" in c.keywords and boards[side].size()<int(capacities[side]):
			var child=reborn(engine,c)
			var insert_at=mini(int(death.index),boards[side].size())
			for spawned_id in death.get("spawned_instances",[]):
				var spawned_index=engine.find_index(boards[side],int(spawned_id))
				if spawned_index>=insert_at: insert_at=spawned_index+1
			boards[side].insert(insert_at,child)
			feedback.append({"kind":"reborn","instance_id":child.instance_id,"source":c.instance_id,"def_id":child.def_id})
			engine.emit("RebornResolved",int(p.id),{"instance_id":child.instance_id,"enhanced":c.enhanced_reborn_available})
			Undead.summoned(engine,p,child); Undead.reborn_event(engine,p,child)
	engine.Secrets133.redemption(engine,players,boards,capacities,deaths,feedback)
	
	for side in 2:
		var p=players[side]
		if boards[side].is_empty() and not p.get("soul_jar_stored",[]).is_empty():
			var stored=p.soul_jar_stored; p.soul_jar_stored=[]
			for saved in stored:
				if boards[side].size()>=int(capacities[side]): break
				var child=saved.duplicate(true); child.instance_id=int(engine.state.next_instance); engine.state.next_instance+=1
				child.health=child.max_health; child.pool_copies=0; boards[side].append(child)
				Undead.summoned(engine,p,child)
				feedback.append({"kind":"summon","instance_id":child.instance_id,"def_id":child.def_id})
				engine.emit("MinionSummoned",int(p.id),{"instance_id":child.instance_id,"origin":"soul_jar"})
	if boards.any(func(team):return team.any(func(c):return int(c.health)<=0)): feedback.append_array(cleanup(engine,boards,capacities,players,side_order))
	feedback.append_array(engine.Beasts.drain_pending(engine))
	return feedback
static func resolve_deathrattles(engine,p: Dictionary,c: Dictionary,boards: Array,side: int,capacities: Array,index: int,death_effects: Array,feedback: Array,live_trigger: bool=false) -> Array:
	var spawned_instances=[]
	for e in death_effects:
		if e.get("trigger","")!="deathrattle": continue
		if e.get("handler","")=="round132_combat" and e.get("op","")=="phylactery":
			for target in boards[side]:engine.buff(target,int(c.attack),int(c.max_health))
			continue
		if live_trigger:
			var anchor=engine.find_index(boards[side],int(c.instance_id))
			if anchor>=0:index=anchor+1
		feedback.append({"kind":"deathrattle","instance_id":c.instance_id,"def_id":c.def_id})
		engine.emit("DeathrattleTriggered",int(p.id),{"instance_id":c.instance_id})
		if e.get("handler","") in ["round12","round13"]:
			var previous_ids=boards[side].map(func(v):return int(v.instance_id))
			var spec=e.duplicate(true);spec["summon_index"]=index
			engine.effect(p,spec,c,c)
			for child in boards[side]:
				if int(child.instance_id) not in previous_ids:
					spawned_instances.append(int(child.instance_id));feedback.append({"kind":"summon","instance_id":child.instance_id,"source":c.instance_id,"def_id":child.def_id})
			continue
		if e.get("handler","")=="round11" and e.get("op","")=="hand_summon":
			var spec=e.duplicate(true)
			if live_trigger:spec["summon_index"]=index
			spawned_instances.append_array(engine.Fish.summon_hand(engine,p,c,spec));continue
		if e.get("op","")=="kangor":
			var offset=0
			for id in p.get("mechanical_deaths",[]).slice(0,int(e.amount)):
				if boards[side].size()>=int(capacities[side]): break
				var token=unit(engine,engine.make_card(id,int(p.id)));boards[side].insert(mini(index+(offset if live_trigger else 0),boards[side].size()),token)
				offset+=1
				Undead.summoned(engine,p,token);spawned_instances.append(int(token.instance_id))
			continue
		if e.get("op","")=="kill_killer":
			for target in boards[1-side]:
				if int(target.instance_id)==int(c.get("killed_by",-1)): target.health=0
			continue
		if e.handler=="summon":
			for i in int(e.amount):
				if boards[side].size()>=int(capacities[side]): break
				var token=unit(engine,engine.make_card(e.id,int(p.id)))
				boards[side].insert(mini(index+i,boards[side].size()),token)
				spawned_instances.append(int(token.instance_id))
				Undead.summoned(engine,p,token)
				feedback.append({"kind":"summon","instance_id":token.instance_id,"source":c.instance_id,"def_id":token.def_id})
				engine.emit("MinionSummoned",int(p.id),{"instance_id":token.instance_id})
		elif e.handler=="summon_tracked":
			var offset=0
			for tracked_id in c.get("tracked_rewards",[]):
				var hand_index=engine.find_index(p.hand,int(tracked_id))
				if hand_index<0 or boards[side].size()>=int(capacities[side]): continue
				if engine.CardLock.locked(engine,p,p.hand[hand_index]):continue
				var token=unit(engine,p.hand[hand_index]); token.pool_copies=0
				
				token["hand_source_instance"]=token.instance_id; token.instance_id=int(engine.state.next_instance); engine.state.next_instance+=1
				boards[side].insert(mini(index+(offset if live_trigger else 0),boards[side].size()),token)
				offset+=1
				spawned_instances.append(int(token.instance_id)); Undead.summoned(engine,p,token)
				feedback.append({"kind":"summon","instance_id":token.instance_id,"source":c.instance_id,"def_id":token.def_id})
				engine.emit("MinionSummoned",int(p.id),{"instance_id":token.instance_id,"origin":"tracked_hand"})
		else: engine.effect(p,e,c)
	return spawned_instances
static func frame(boards: Array,message: String,players: Array=[],engine=null) -> Dictionary:
	var snapshot={"left":boards[0].duplicate(true),"right":boards[1].duplicate(true),"message":message}
	if engine!=null:snapshot["event_seq"]=int(engine.state.event_seq)
	if players.size()==2:
		snapshot["player_views"]={}
		for p in players:
			snapshot.player_views[str(p.id)]={"beetle_attack":int(p.get("beetle_attack",0)),"beetle_health":int(p.get("beetle_health",0)),"lobster_count":int(p.get("lobster_count",0))}
		snapshot["hands"]={"left":players[0].hand.duplicate(true),"right":players[1].hand.duplicate(true),"left_pending":players[0].pending_rewards.duplicate(true),"right_pending":players[1].pending_rewards.duplicate(true)}
	return snapshot
static func fight(engine,a: Dictionary,b: Dictionary) -> Dictionary:
	var players=[a,b]
	var boards=[[],[]]
	var capacities=[Special.capacity(a.board),Special.capacity(b.board)]
	engine.combat_context={"players":players,"boards":boards,"capacities":capacities,"deaths":[],"immediate_attacks":[]}
	for side in 2:
		players[side]["soul_jar_stored"]=[];players[side]["mechanical_deaths"]=[]
		players[side]["beast_combat_attack"]=0;players[side]["beast_combat_health"]=0
		for item in players[side].trinkets:
			item["combat_uses"]=0;item["combat_used"]=false
			for e in engine.content.get_def(item.id).effects:
				if e.get("trigger","")=="avenge":item["avenge_"+str(e.handler)]=0
		for card in players[side].board:boards[side].append(unit(engine,card))
	var opening_feedback=preload("res://domain/rules/combat_opening.gd").run(engine)
	var frames=[frame(boards,ExternalText.phrase("domain_rules_combat_service.fight.e52d47819a7b", "说明待补充 · %d / %d") % capacities,players,engine)]
	if not opening_feedback.is_empty():
		frames[0]["opening_feedback"]=opening_feedback
		frames[0].message+=ExternalText.phrase("domain_rules_combat_service.fight.57f47d9107e9", "说明待补充")
	engine.emit("CombatStarted",int(a.id),{"opponent":b.id,"capacities":capacities})
	var side=0 if boards[0].size()>boards[1].size() else 1
	if boards[0].size()==boards[1].size(): side=RNG.next(engine.state.streams,"combat",2)
	var cursors=[0,0]
	var strikes=0
	var stalled=0
	var target_stalls=0
	while not boards[0].is_empty() and not boards[1].is_empty() and strikes<500:
		var immediate={}
		var ordinary_side=side
		while not engine.combat_context.immediate_attacks.is_empty():
			var pending=engine.combat_context.immediate_attacks.pop_front()
			var found=engine.find_index(boards[int(pending.side)],int(pending.instance_id))
			if found>=0:immediate=pending;side=int(pending.side);break
		var eligible=[]
		for c in boards[side]:
			if int(c.attack)>0: eligible.append(c)
		if eligible.is_empty():
			stalled+=1
			if stalled>=2: break
			side=1-side; continue
		stalled=0
		var index=engine.find_index(boards[side],int(immediate.instance_id)) if not immediate.is_empty() else int(cursors[side])%boards[side].size()
		var searched=0
		while int(boards[side][index].attack)<=0 and searched<boards[side].size():
			index=(index+1)%boards[side].size(); searched+=1
		var strikes_before=strikes
		var attacker=boards[side][index]
		var attacks=int(immediate.get("attack_count",1)) if not immediate.is_empty() else 2 if "WINDFURY" in attacker.keywords else 1
		if not immediate.is_empty():engine.emit("ImmediateAttackStarted",int(attacker.owner),{"attacker":attacker.instance_id,"attack_count":attacks,"target_id":immediate.get("target_id",-1),"origin":immediate.get("origin","legacy")})
		if immediate.is_empty():cursors[side]=index+1
		for repeat_index in attacks:
			if attacker not in boards[side] or boards[1-side].is_empty(): break
			var taunts=[]; var targets=[]
			for target in boards[1-side]:
				if "STEALTH" in target.keywords: continue
				targets.append(target)
				if "TAUNT" in target.keywords: taunts.append(target)
			if not immediate.has("target_id") and not taunts.is_empty(): targets=taunts
			if targets.is_empty(): break
			var forced=targets.filter(func(c):return int(c.instance_id)==int(immediate.get("target_id",-1)))
			if immediate.has("target_id") and forced.is_empty():break
			var target=forced[0] if not forced.is_empty() else targets[RNG.next(engine.state.streams,"combat",targets.size())]
			attacker.keywords.erase("STEALTH")
			engine.Beasts.attack(engine,players[side],attacker)
			engine.Quilboar.friendly_attack(engine,players[side],attacker)
			for e in engine.Triggers.effects(engine,attacker):
				if e.get("op","")=="remove_keywords": target.keywords.erase("REBORN");target.keywords.erase("TAUNT")
				if e.get("op","")=="steal_attack": Undead.local_buff(engine,attacker,int(target.attack)*int(e.amount),0)
			for e in engine.Triggers.effects(engine,attacker):
				if e.get("trigger","")=="rally" and e.handler=="grow_self":
					attacker.attack+=int(e.attack); attacker.health+=int(e.health); attacker.max_health+=int(e.health)
					engine.R135.stat_gain(engine,attacker,int(e.attack),int(e.health))
					engine.emit("RallyTriggered",int(attacker.owner),{"instance_id":attacker.instance_id})
				elif e.get("trigger","")=="rally":
					engine.effect(players[side],e,attacker)
					engine.emit("RallyTriggered",int(attacker.owner),{"instance_id":attacker.instance_id})
			engine.Gifts.rally(engine,players[side],attacker)
			for e in engine.R13.specs(engine,attacker,"jail"):
				var child=engine.R13.jail_summon(engine,players[side],attacker,int(e.multiplier))
				if not child.is_empty():
					engine.Beasts.attack(engine,players[side],child);engine.Quilboar.friendly_attack(engine,players[side],child)
					frames.append(strike(engine,players,boards,capacities,side,child,target));strikes+=1
			if attacker not in boards[side] or target not in boards[1-side] or int(attacker.health)<=0 or int(attacker.attack)<=0 or int(target.health)<=0:
				engine.emit("AttackCancelledAfterGolem",int(attacker.owner),{"attacker":attacker.instance_id,"original_target":target.instance_id});continue
			frames.append(strike(engine,players,boards,capacities,side,attacker,target,repeat_index,attacks));strikes+=1
		if strikes==strikes_before: target_stalls+=1
		else: target_stalls=0
		if target_stalls>=2: break
		var still_index=boards[side].find(attacker)
		if immediate.is_empty():
			cursors[side]=still_index+1 if still_index>=0 else index
			side=1-side
		else:side=ordinary_side
	var winner=-1
	if not boards[0].is_empty() and boards[1].is_empty(): winner=0
	elif boards[0].is_empty() and not boards[1].is_empty(): winner=1
	var damage=0
	if winner>=0:
		damage=int(players[winner].tier)
		for c in boards[winner]: damage+=int(c.get("damage_star",engine.content.get_def(c.def_id).tier))
	if strikes>=500: engine.emit("TechnicalDraw",int(a.id),{"reason":"attack_budget","seed":engine.state.seed})
	for p in players: engine.drain_rewards(p)
	for p in players:
		if not p.get("is_ghost",false):p["last_battle_deaths"]=engine.combat_context.deaths.duplicate(true)
		engine.Combat132.after_battle(engine,p)
		engine.R135.after_battle(engine,p)
		p["beast_combat_attack"]=0;p["beast_combat_health"]=0;p["beast_pending"]=[]
	engine.combat_context={}
	return {"a":a.id,"b":b.id,"winner":winner,"damage":damage,"attacks":strikes,"frames":frames,"capacity":capacities,"technical_draw":strikes>=500}


static func strike(engine,players: Array,boards: Array,capacities: Array,side: int,attacker: Dictionary,target: Dictionary,repeat_index: int=0,attacks: int=1) -> Dictionary:
	engine.Secrets133.attacked(engine,players,boards,capacities,side,attacker,target)
	
	var before=frame(boards,"",players,engine)
	var attacker_damage=int(attacker.attack)
	var target_damage=int(target.attack)
	var target_health=int(target.health);var shield_before=bool(target.shield)
	var before_target_health=int(target.health);var before_attacker_health=int(attacker.health)
	var attacker_shield=bool(attacker.shield)
	var cleaves=engine.Triggers.effects(engine,attacker).any(func(e):return e.get("op","")=="cleave")
	var cleave_venom=cleaves and bool(attacker.get("venom",false))
	var venom_used=false
	var strike_group=damage_group(engine)
	
	var primary_source=attacker
	if cleave_venom:primary_source={"venom":true,"poison":attacker.get("poison",false),"instance_id":attacker.instance_id,"owner":attacker.owner}
	hit(primary_source,target,attacker_damage,false)
	if cleave_venom:venom_used=not primary_source.venom
	mark_fatal(attacker,target,strike_group)
	hit(target,attacker,target_damage,attacker.immune_attacking)
	mark_fatal(target,attacker,strike_group)
	engine.Fish.damage_received(engine,players[1-side],target,attacker_damage if not shield_before and attacker_damage>0 else 0)
	engine.Fish.damage_received(engine,players[side],attacker,target_damage if not attacker_shield and not attacker.immune_attacking and target_damage>0 else 0)
	engine.Fish.attack_kill(engine,players[side],attacker,target)
	engine.Pirates.damaged(engine,attacker,attacker_damage if int(target.health)<before_target_health else 0)
	engine.Demons.damage_fact(engine,attacker,attacker_damage if not shield_before and attacker_damage>0 else 0)
	engine.Pirates.damaged(engine,target,target_damage if int(attacker.health)<before_attacker_health else 0)
	engine.Demons.damage_fact(engine,target,target_damage if not attacker_shield and not attacker.immune_attacking and target_damage>0 else 0)
	if cleaves:
		var ti=boards[1-side].find(target)
		for ni in [ti-1,ti+1]:
			if ni>=0 and ni<boards[1-side].size():
				var neighbor=boards[1-side][ni];var nh=int(neighbor.health)
				var splash_source={"venom":cleave_venom,"poison":attacker.get("poison",false),"instance_id":attacker.instance_id,"owner":attacker.owner}
				hit(splash_source,neighbor,attacker_damage,false);mark_fatal(splash_source,neighbor,strike_group)
				if cleave_venom and not splash_source.venom:venom_used=true
				engine.Pirates.damaged(engine,attacker,attacker_damage if int(neighbor.health)<nh else 0)
				engine.Demons.damage_fact(engine,attacker,attacker_damage if int(neighbor.health)<nh else 0)
				engine.Fish.damage_received(engine,players[1-side],neighbor,attacker_damage if int(neighbor.health)<nh else 0)
	if venom_used:attacker.venom=false
	for e in engine.Triggers.effects(engine,attacker):
		if e.get("op","")!="wildfire" or int(target.health)>0 or shield_before: continue
		var ti=boards[1-side].find(target);var neighbors=[]
		for ni in [ti-1,ti+1]:
			if ni>=0 and ni<boards[1-side].size(): neighbors.append(boards[1-side][ni])
		if int(e.amount)==1 and neighbors.size()>1: neighbors=[neighbors[RNG.next(engine.state.streams,"combat",neighbors.size())]]
		var overflow_group=damage_group(engine)
		for neighbor in neighbors:
			var health_before=int(neighbor.health);var splash=maxi(0,attacker_damage-target_health)
			var splash_source={"venom":false,"instance_id":attacker.instance_id,"owner":attacker.owner}
			hit(splash_source,neighbor,splash,false);mark_fatal(splash_source,neighbor,overflow_group)
			engine.Demons.damage_fact(engine,attacker,splash if int(neighbor.health)<health_before else 0)
			engine.Fish.damage_received(engine,players[1-side],neighbor,splash if int(neighbor.health)<health_before else 0)
	var message="%s → %s" % [engine.content.get_def(attacker.def_id).name,engine.content.get_def(target.def_id).name]
	engine.emit("AttackResolved",int(attacker.owner),{"attacker":attacker.instance_id,"target":target.instance_id,"damage":attacker_damage})
	var damaged=frame(boards,"",players,engine)
	engine.Beasts.after_attack(engine,players[side],attacker)
	var feedback=cleanup(engine,boards,capacities,players,side)
	var result_frame=frame(boards,message,players,engine)
	result_frame["presentation"]={"before":before,"damaged":damaged,"attacker":attacker.instance_id,"target":target.instance_id,"strike":repeat_index+1,"strikes":attacks,"feedback":feedback}
	return result_frame
