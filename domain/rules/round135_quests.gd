extends RefCounted

const POWER="BG24_HERO_100p"
const PARTS=["BG24_Reward_715t","BG24_Reward_715t2","BG24_Reward_715t3","BG24_Reward_715t4"]
const DISCOVERIES=["triple","undead","tavern_spell","fish","demon_damage","tagged_minion","seedling","medivh","round8_discovery","pirate_spell","telescope","hooktusk","sylvanas","r13_seven","r13_gift","r13_globe","r13_factory","r13_hearth","r132_start","r132_cookie","r132_naga","r132_elise","r133_ticket_discovery","r133_flight_discovery","r134_spell","r134_prize"]
static func supports(_d: Dictionary,e: Dictionary) -> bool:
	return e.get("handler","")=="round135" and e.get("op","") in ["quest","reward","part","wind","purse"]
static func ensure(p: Dictionary) -> void:
	if not p.has("r135"):p["r135"]={"slots":{},"removed":[],"seq":0,"deliveries":[],"discoveries":{}}
static func config(engine) -> Dictionary:
	return engine.content.quest_config
static func owned(engine,p: Dictionary) -> bool:
	if not p.get("alive",true) or p.get("is_ghost",false):return false
	for local in engine.combat_context.get("players",[]):
		if int(local.id)==int(p.id) and local.get("is_ghost",false):return false
	return true
static func active(engine,p: Dictionary,reward: String) -> Array:
	ensure(p)
	if reward in config(engine).get("project_excluded_rewards",[]):return []
	if not owned(engine,p):return []
	return engine.R136.views(engine,p).filter(func(q):return (q.status=="reward_active" or q.get("reward_id","")==engine.R136.LOOP and q.status=="completion_pending") and q.get("reward_id","")==reward and valid_slot(engine,p,q))
static func has(engine,p: Dictionary,reward: String) -> bool:
	return not active(engine,p,reward).is_empty()
static func valid_slot(engine,p: Dictionary,q: Dictionary) -> bool:
	var slots=p.get("power_slots",[]).filter(func(s):return int(s.slot_id)==int(q.slot_id))
	var s={} if slots.is_empty() else slots[0]
	return not s.is_empty() and s.active_power_id==POWER and int(s.epoch)==int(q.epoch)
static func legal(engine,id: String) -> bool:
	var d=engine.content.get_def(id)
	return ready(engine,id) and engine.content.eligible(d,engine.state.enabled_tribes)
static func ready(engine,id: String,seen: Dictionary={}) -> bool:
	if seen.has(id):return true
	var d=engine.content.get_def(id)
	if d.is_empty() or not d.get("implemented",false):return false
	seen=seen.duplicate();seen[id]=true
	for dependency in config(engine).get("required_dependencies",{}).get(id,[]):
		if not ready(engine,str(dependency),seen):return false
	return true
static func minions(engine,p: Dictionary,tribe: String="") -> Array:
	return engine.generation_candidates(p,{"kind":"minion"}).filter(func(id):return ready(engine,id) and (tribe=="" or tribe in engine.content.get_def(id).card_types or "全部种族" in engine.content.get_def(id).card_types))
static func spells(engine,p: Dictionary) -> Array:
	return engine.R134.spells(engine,p).filter(func(id):return ready(engine,id))
static func bindings(engine,p: Dictionary,reward: String) -> Array:
	if reward==engine.R136.SCEPTER:return engine.R136.bindings(engine,p,reward)
	if config(engine).bound_pools.has(reward):return config(engine).bound_pools[reward].filter(func(id):return legal(engine,id))
	if reward=="BG28_Reward_510":return engine.R13Items.seven_pool(engine).filter(func(id):return legal(engine,id))
	if reward=="BG24_Reward_134":return engine.state.enabled_tribes.filter(func(t):return not minions(engine,p,str(t)).is_empty())
	return [""]
static func reward_legal(engine,p: Dictionary,id: String) -> bool:
	if not engine.R136.reward_legal(engine,p,id) or not legal(engine,id) or bindings(engine,p,id).is_empty():return false
	if id in ["BG28_Reward_504","BG28_Reward_515"] and spells(engine,p).is_empty():return false
	if id=="BG33_Reward_012" and not legal(engine,"BG33_Reward_012t"):return false
	return true
static func quest_legal(engine,id: String) -> bool:
	return legal(engine,id) and (id!="BG24_Quest_151" or engine.state.enabled_tribes.size()>=2)
static func start(engine,p: Dictionary,s: Dictionary) -> bool:
	ensure(p)
	var slot_key=str(s.slot_id)
	if p.r135.slots.has(slot_key) and int(p.r135.slots[slot_key].epoch)==int(s.epoch):return true
	var rewards=config(engine).rewards.keys().filter(func(id):return reward_legal(engine,p,id))
	var quests=config(engine).quests.keys().filter(func(id):return quest_legal(engine,id))
	if rewards.size()<2 or quests.is_empty():
		p.r135["diagnostic"]="INSUFFICIENT_QUEST_REWARD_FAMILIES";return false
	p.r135.erase("diagnostic");var options=[];var first=""
	for unused in 2:
		var reward=rewards.pop_at(engine.RNG.next(engine.state.streams,"choice",rewards.size()))
		var candidates=quests.filter(func(id):return id!=first and engine.R136.pair_legal(id,reward))
		if candidates.is_empty():candidates=quests.filter(func(id):return engine.R136.pair_legal(id,reward))
		var quest=candidates[engine.RNG.next(engine.state.streams,"choice",candidates.size())];first=quest
		var domain=bindings(engine,p,reward);var bound=domain[engine.RNG.next(engine.state.streams,"choice",domain.size())]
		var tribes=[]
		if quest=="BG24_Quest_151":tribes=engine.RNG.shuffle(engine.state.enabled_tribes,engine.state.streams,"choice").slice(0,2)
		var tier=config(engine).rewards[reward].tier
		options.append({"quest_id":quest,"reward_id":reward,"tier":tier,"threshold":int(config(engine).quests[quest][tier]),"bound":bound,"bound_tribes":tribes,"rule_revision":int(engine.content.pack.rule_revision)})
	p.r135.seq+=1
	var q={"instance":"quest:%d:%d:%d:%d" % [int(p.id),int(s.slot_id),int(s.epoch),int(p.r135.seq)],"slot_id":s.slot_id,"epoch":s.epoch,"status":"offered","progress":0,"seen":{},"options":options,"grant_parts":{},"reward_state":{}}
	p.r135.slots[slot_key]=q
	engine.enqueue_choice(p,{"kind":"quest_offer","slot_id":s.slot_id,"epoch":s.epoch,"quest_instance":q.instance,"options":options,"rng_after":engine.state.streams.duplicate(true)})
	q["session_id"]=p.choices[-1].session_id;p.choices[-1].auto_policy="manual"
	return true
static func option_valid(engine,p: Dictionary,o: Dictionary) -> bool:
	if not config(engine).rewards.has(o.get("reward_id","")) or not config(engine).quests.has(o.get("quest_id","")):return false
	if not engine.R136.pair_legal(o.quest_id,o.reward_id) or not reward_legal(engine,p,o.reward_id) or not quest_legal(engine,o.quest_id):return false
	if o.tier!=config(engine).rewards[o.reward_id].tier or int(o.threshold)!=int(config(engine).quests[o.quest_id][o.tier]):return false
	if o.bound not in bindings(engine,p,o.reward_id):return false
	return o.quest_id!="BG24_Quest_151" or (o.bound_tribes.size()==2 and o.bound_tribes[0]!=o.bound_tribes[1] and o.bound_tribes.all(func(t):return t in engine.state.enabled_tribes))
static func resolve(engine,p: Dictionary,choice: Dictionary,index: int) -> String:
	if choice.kind!="quest_offer":return "UNHANDLED"
	ensure(p);var q=p.r135.slots.get(str(choice.slot_id),{})
	if q.is_empty() or not valid_slot(engine,p,q) or q.status!="offered" or q.instance!=choice.quest_instance or q.session_id!=choice.session_id:return "STALE_QUEST_OFFER"
	var o=choice.options[index]
	if o!=q.options[index] or not option_valid(engine,p,o):return "INVALID_QUEST_BINDING"
	q.merge(o,true);q.status="active";q.erase("options");p.choices.pop_front()
	engine.emit("QuestSelected",int(p.id),{"quest_instance":q.instance,"quest_id":q.quest_id,"reward_id":q.reward_id})
	return ""
static func loss(engine,p: Dictionary,s: Dictionary,id: String) -> void:
	if id!=POWER:return
	ensure(p);var q=p.r135.slots.get(str(s.slot_id),{})
	if q.is_empty():return
	p.choices=p.choices.filter(func(c):return c.get("quest_instance","")!=q.instance)
	if q.has("child"):q.child.status="removed";p.r135.removed.append(q.child.duplicate(true))
	q.status="removed";q.erase("seen");q.progress=0;p.r135.removed.append(q.duplicate(true));p.r135.slots.erase(str(s.slot_id))
static func progress(engine,p: Dictionary,q: Dictionary,n: int,key: String) -> void:
	var cyclic=q.get("reward_id","")==engine.R136.LOOP
	if (q.status!="active" and not (cyclic and q.status in ["reward_active","completion_pending"])) or q.seen.has(key) or n<=0:return
	q.seen[key]=true;q.progress=int(q.progress)+n if cyclic else mini(int(q.threshold),int(q.progress)+n)
	if int(q.progress)>=int(q.threshold):q.status="completion_pending";q["completion_root"]=engine.state.get("active_root",engine.cause);q["completed_seq"]=int(engine.state.event_seq)
static func gauge(engine,p: Dictionary) -> void:
	ensure(p)
	for q in p.r135.slots.values():
		if q.status!="active" or q.quest_id!="BG27_Quest_801" or not valid_slot(engine,p,q):continue
		var total=0
		for c in engine.Undead.board(engine,p):
			if int(c.get("health",1))>0:total+=int(c.attack) if c.has("attack") else engine.stats(c).x
		q.progress=mini(int(q.threshold),total)
		if total>=int(q.threshold):q.status="completion_pending";q["completed_seq"]=int(engine.state.event_seq);q["completion_root"]=engine.state.get("active_root",engine.cause)
static func event(engine,e: Dictionary) -> void:
	var pid=int(e.owner)
	if pid<0 or pid>=engine.state.players.size():return
	var p=engine.state.players[pid]
	ensure(p);var payload=e.payload;var kind=str(e.kind);var key="event:"+str(e.seq)
	if kind=="MinionDied" and not engine.combat_context.is_empty():
		for local in engine.combat_context.players:
			if int(local.id)==pid:continue
			var other=engine.state.players[int(local.id)]
			if not owned(engine,other):continue
			ensure(other)
			for q in other.r135.slots.values():
				if q.get("quest_id","")=="BG27_Quest_802" and valid_slot(engine,other,q):progress(engine,other,q,1,key)
	if not owned(engine,p):return
	for q in p.r135.slots.values():
		if (q.status!="active" and not (q.get("reward_id","")==engine.R136.LOOP and q.status in ["reward_active","completion_pending"])) or not valid_slot(engine,p,q):continue
		var n=0
		match str(q.quest_id):
			"BG24_Quest_114":
				if kind in ["MinionPlayedFromHand","MinionSummoned","RebornResolved"]:n=1
			"BG24_Quest_123":
				if kind=="QuestStatGain":n=1
			"BG24_Quest_124":
				if kind=="FriendlyDeathCounted":n=1
			"BG24_Quest_126":
				if kind=="CoinsSpent":n=int(payload.get("amount",0))
			"BG24_Quest_151":
				if kind=="CardBought" and payload.get("kind","")=="minion" and payload.get("types",[]).any(func(t):return t in q.bound_tribes or t=="全部种族"):n=1
			"BG24_Quest_311":
				if kind=="MinionPlayedFromHand" and payload.get("battlecry",false):n=1
			"BG24_Quest_313":
				if kind=="CardBought" and payload.get("kind","")=="minion":n=1
			"BG24_Quest_314":
				if kind=="HandEntered":n=1
			"BG24_Quest_352":
				if kind=="AttackResolved":n=1
			"BG28_Quest_500":
				if kind=="SpellResolved":n=1
		progress(engine,p,q,n,key)
	if kind=="FriendlyDeathCounted" and not engine.combat_context.is_empty():
		for id in ["BG28_Reward_504","BG33_Reward_004"]:
			for q in active(engine,p,id):
				var r=q.reward_state;var period=3 if id=="BG28_Reward_504" else 2
				r["deaths"]=int(r.get("deaths",0))+1
				if int(r.deaths)%period==0:
					if period==2:p.free_refresh+=1
					else:generate(engine,p,q,spells(engine,p),1,"avenge:"+key)
static func stat_gain(engine,c: Dictionary,a: int,h: int) -> void:
	if a<=0 and h<=0:return
	var p=engine.state.players[int(c.owner)];var cards=engine.Undead.board(engine,p)+p.hand
	if engine.find_index(cards,int(c.instance_id))<0:return
	engine.emit("QuestStatGain",int(c.owner),{"instance_id":c.instance_id,"attack":a,"health":h})
static func safe(engine,p: Dictionary,combat: bool=false) -> void:
	ensure(p)
	if not owned(engine,p):return
	gauge(engine,p)
	if engine.draining_effects or not p.choices.is_empty() or engine.state.has("confirmation") or engine.state.has("cast_tail") or engine.state.has("play_tail") or not engine.state.get("effect_queue",[]).is_empty():return
	if not combat and (engine.settlement_depth>0 or engine.state.has("auto_chain")):return
	for q in engine.R136.views(engine,p):
		if q.status=="completion_pending" and valid_slot(engine,p,q):grant(engine,p,q)
		if q.status=="reward_active" and valid_slot(engine,p,q):
			for part in q.reward_state.get("unresolved",{}).keys():
				var pool=minions(engine,p,str(q.bound)) if q.reward_id=="BG24_Reward_134" else spells(engine,p) if q.reward_id in ["BG28_Reward_504","BG28_Reward_515"] else []
				if not pool.is_empty():generate(engine,p,q,pool,int(q.reward_state.unresolved[part].count),part)
	
	for q in p.r135.removed:
		for part in q.get("grant_parts",{}):
			var record=q.grant_parts[part]
			if not record.get("committed",false) and record.has("card"):deliver(engine,p,q,str(record.card.def_id),part)
static func origin(engine,q: Dictionary) -> Dictionary:
	return {"origin_kind":"quest_reward","producer_id":q.reward_id,"quest_instance":q.instance,"slot_id":q.slot_id,"epoch":q.epoch,"root_action_id":engine.cause}
static func deliver(engine,p: Dictionary,q: Dictionary,id: String,part: String) -> void:
	if q.grant_parts.has(part) and q.grant_parts[part].get("committed",false):return
	if not q.grant_parts.has(part):
		var card=engine.make_card(id,int(p.id));engine.Naga.generated(engine,p,card)
		card["quest_grant_receipt"]=q.instance+":"+part
		q.grant_parts[part]={"card":card,"committed":false}
	var record=q.grant_parts[part]
	if (p.hand+p.pending_rewards).any(func(c):return c.get("quest_grant_receipt","")==record.card.quest_grant_receipt):record.committed=true;return
	var result=engine.receive_card(p,record.card,origin(engine,q))
	if result in ["granted","queued"]:record.committed=true
static func generate(engine,p: Dictionary,q: Dictionary,pool: Array,n: int,part: String) -> void:
	if pool.is_empty():
		if not q.reward_state.has("unresolved"):q.reward_state["unresolved"]={}
		q.reward_state.unresolved[part]={"count":n,"reason":"EMPTY_LEGAL_QUEST_POOL"};return
	for i in n:
		var k=part+":"+str(i)
		if q.grant_parts.has(k):deliver(engine,p,q,str(q.grant_parts[k].card.def_id),k)
		else:deliver(engine,p,q,str(pool[engine.RNG.next(engine.state.streams,"effects",pool.size())]),k)
	if q.reward_state.has("unresolved"):q.reward_state.unresolved.erase(part)
static func initial_gift(engine,p: Dictionary,q: Dictionary) -> void:
	if q.reward_id in ["BG24_Reward_130","BG27_Reward_802","BG27_Reward_803","BG28_Reward_510"]:deliver(engine,p,q,str(q.bound),"bound")
static func grant(engine,p: Dictionary,q: Dictionary) -> void:
	var r=q.reward_state;var id=str(q.reward_id)
	if id=="BG33_Reward_012":
		if not q.grant_parts.has("cap"):engine.increase_coin_cap(p,5);q.grant_parts["cap"]={"committed":true}
		deliver(engine,p,q,"BG33_Reward_012t","purse")
	elif id in ["BG24_Reward_130","BG27_Reward_802","BG27_Reward_803","BG28_Reward_510"]:deliver(engine,p,q,str(q.bound),"bound")
	if q.grant_parts.values().any(func(part):return not part.get("committed",false)):return
	if not q.grant_parts.has("ability"):
		r["next_buff"]=2;r["next_coins"]=1;q.grant_parts["ability"]={"committed":true}
	q.status="reward_active";q["granted_round"]=int(engine.state.round)
	engine.R136.grant(engine,p,q)
	engine.emit("QuestCompleted",int(p.id),{"quest_instance":q.instance,"reward_id":id,"completion_seq":q.get("completed_seq",0)})
static func bought(engine,p: Dictionary,c: Dictionary,d: Dictionary) -> void:
	for q in active(engine,p,"BG24_Reward_306"):
		if d.kind=="minion":
			var n=int(q.reward_state.next_buff);engine.buff(c,n,n);q.reward_state.next_buff=n+2
	for q in active(engine,p,"BG28_Reward_506"):
		if int(q.reward_state.get("purchase_round",-1))==int(engine.state.round):continue
		q.reward_state["purchase_round"]=int(engine.state.round);copy_card(engine,p,q,c,"first:"+str(engine.state.round))
static func copy_card(engine,p: Dictionary,q: Dictionary,c: Dictionary,receipt: String) -> void:
	if q.grant_parts.has(receipt):return
	var copy=c.duplicate(true);copy.instance_id=int(engine.state.next_instance);engine.state.next_instance+=1;copy.pool_copies=0
	copy.erase("attached_pool");copy.erase("quest_grant_receipt")
	engine.qualify_gold_copy(copy,"quest_copy");copy["quest_copy_depth"]=1
	copy["quest_grant_receipt"]=q.instance+":"+receipt;q.grant_parts[receipt]={"card":copy,"committed":false}
	deliver(engine,p,q,str(copy.def_id),receipt)
static func discovered(engine,p: Dictionary,c: Dictionary,kind: String,receipt: String) -> void:
	if kind not in DISCOVERIES+["r136_locket"] or int(c.get("quest_copy_depth",0))>0:return
	var d=engine.content.get_def(c.def_id)
	if d.get("kind","") not in ["minion","spell"]:return
	ensure(p)
	if p.r135.discoveries.has(receipt):return
	p.r135.discoveries[receipt]=true
	for q in active(engine,p,"BG24_Reward_129"):copy_card(engine,p,q,c,"discovery:"+receipt)
static func turn_start(engine,p: Dictionary) -> bool:
	return engine.R136.turn_start(engine,p)
static func legacy_start(engine,p: Dictionary,q: Dictionary,part: String) -> void:
	var r=q.reward_state
	match str(q.reward_id):
		"BG24_Reward_134":generate(engine,p,q,minions(engine,p,str(q.bound)),2,part)
		"BG24_Reward_361":engine.gain_coins(p,int(r.next_coins));r.next_coins+=1
		"BG28_Reward_515":generate(engine,p,q,spells(engine,p),3,part)
		"BG33_Reward_013":
			var candidates=engine.R134.gold_targets(engine,p)
			if not candidates.is_empty():
				var top=0
				for c in candidates:top=maxi(top,int(engine.content.get_def(c.def_id).tier))
				candidates=candidates.filter(func(c):return int(engine.content.get_def(c.def_id).tier)==top)
				engine.Pirates.transform_gold(engine,candidates[engine.RNG.next(engine.state.streams,"effects",candidates.size())])
static func opening_entries(engine,p: Dictionary,side: int) -> Array:
	ensure(p);var result=[]
	for q in engine.R136.views(engine,p):
		if q.status!="reward_active" or not valid_slot(engine,p,q):continue
		q.reward_state["deaths"]=0
		if q.reward_id in ["BG24_Reward_109","BG24_Reward_111","BG33_Reward_003"]:result.append({"category":0,"side":side,"slot":q.slot_id,"order":1,"op":"quest135","quest":q})
	return result
static func combat_gold(engine,c: Dictionary,retain: bool=false) -> bool:
	var d=engine.content.get_def(c.def_id);var gid=str(d.get("golden_id",""))
	if d.get("golden",false) or not engine.content.definitions.has(gid):return false
	var before=engine.stats(c);var old_derived=Vector2i(int(c.get("derived_attack",0)),int(c.get("derived_health",0)))
	c.def_id=gid;engine.exclude_gold_reward(c,"quest_combat_gold")
	var after=engine.stats(c);var delta=after-before
	c.attack+=delta.x;c.health+=delta.y;c.max_health+=delta.y;c["derived_attack"]=old_derived.x+delta.x;c["derived_health"]=old_derived.y+delta.y
	for k in engine.keywords(c):engine.add_keyword(c,k)
	c.immune_attacking=engine.content.get_def(gid).effects.any(func(e):return e.handler=="attack_immune")
	
	if retain and c.get("r135_retain_form_eligible",false):
		var p=engine.state.players[int(c.owner)];var i=engine.find_index(p.board,int(c.instance_id))
		if i>=0:p.board[i].def_id=gid;engine.exclude_gold_reward(p.board[i],"retained_combat_gold")
	return true
static func opening(engine,p: Dictionary,q: Dictionary) -> void:
	var ctx=engine.combat_context;var side=ctx.players.find(p);var board=ctx.boards[side]
	var key="opening:"+str(engine.state.round)
	if q.reward_state.has(key):return
	q.reward_state[key]=true
	match str(q.reward_id):
		"BG24_Reward_109":
			var targets=[] if board.is_empty() else [board[0]] if board.size()==1 else [board[0],board[-1]]
			for c in targets:combat_gold(engine,c)
		"BG24_Reward_111":
			var candidates=board.filter(func(c):return int(c.health)>0)
			if board.size()>=int(ctx.capacities[side]) or candidates.is_empty():return
			var top=0
			for c in candidates:top=maxi(top,int(c.health))
			candidates=candidates.filter(func(c):return int(c.health)==top)
			var c=candidates[engine.RNG.next(engine.state.streams,"combat",candidates.size())];var saved=c.duplicate(true);saved["r13_keep_route"]=true
			engine.Beasts.summon(engine,p,c.def_id,-1,false,saved)
		"BG33_Reward_003":
			if board.is_empty():return
			engine.add_keyword(board[0],"DIVINE_SHIELD")
			ctx.immediate_attacks.append({"side":side,"instance_id":board[0].instance_id,"attack_count":2 if "WINDFURY" in board[0].keywords else 1,"origin":"quest_reward"})
static func after_battle(engine,p: Dictionary) -> void:
	if not owned(engine,p):return
	engine.R136.after_battle(engine,p)
	for q in active(engine,p,"BG24_Reward_138"):
		var deaths=engine.combat_context.deaths.filter(func(d):return int(d.owner)==int(p.id))
		if not deaths.is_empty():
			var id=engine.R13Items.original_id(engine,{"def_id":deaths[-1].def_id})
			deliver(engine,p,q,id,"battle:"+str(engine.state.round))
static func execute(engine,p: Dictionary,e: Dictionary,target: Dictionary) -> bool:
	if e.get("handler","")!="round135":return false
	match str(e.op):
		"part":engine.buff(target,5,5);engine.add_keyword(target,str(e.keyword))
		"wind":
			var duration="permanent" if engine.current_spell.get("permanent_spellcraft",false) or engine.current_spell.get("force_permanent",false) else "next_turn"
			for k in ["WINDFURY","DIVINE_SHIELD"]:engine.add_keyword(target,k,duration)
		"purse":engine.gain_coins(p,5)
		_:return false
	return true
static func validate(engine,p: Dictionary,enabled: Array=[]) -> String:
	var extra=engine.R136.validate(engine,p,enabled)
	if extra!="":return extra
	if not p.has("r135"):return ""
	if not p.r135 is Dictionary or not p.r135.get("slots") is Dictionary or not p.r135.get("removed") is Array or not p.r135.get("discoveries") is Dictionary:return "INVALID_QUEST_STATE"
	for q in p.r135.slots.values():
		if not q is Dictionary or q.get("status","") not in ["offered","active","completion_pending","reward_active"] or not q.get("grant_parts") is Dictionary or not q.get("reward_state") is Dictionary or not q.get("seen") is Dictionary or int(q.get("slot_id",-1)) not in [0,1]:return "INVALID_QUEST_STATE"
		var slot_valid=valid_slot(engine,p,q)
		var s=engine.Powers.selected(engine,p,int(q.slot_id))
		var restore=s.get("temporary_restore",{})
		if not slot_valid and not (restore.get("power_id","")==POWER and int(restore.get("epoch",-1))==int(q.epoch)):return "STALE_QUEST_EPOCH"
		var options=q.get("options",[]) if q.status=="offered" else [q]
		if options.size()!=(2 if q.status=="offered" else 1):return "INVALID_QUEST_BINDING"
		for o in options:
			if not o is Dictionary:return "INVALID_QUEST_BINDING"
			if not config(engine).quests.has(o.get("quest_id","")) or not config(engine).rewards.has(o.get("reward_id","")):return "INVALID_QUEST_BINDING"
			var tier=config(engine).rewards[o.reward_id].tier
			if not engine.R136.pair_legal(o.quest_id,o.reward_id):return "INVALID_QUEST_PAIR"
			if o.get("tier","")!=tier or int(o.get("threshold",-1))!=int(config(engine).quests[o.quest_id][tier]):return "INVALID_QUEST_THRESHOLD"
			if config(engine).bound_pools.has(o.reward_id) and o.get("bound","") not in config(engine).bound_pools[o.reward_id]:return "INVALID_QUEST_BINDING"
			if o.quest_id=="BG24_Quest_151" and (not o.get("bound_tribes") is Array or o.bound_tribes.size()!=2 or o.bound_tribes[0]==o.bound_tribes[1] or o.bound_tribes.any(func(t):return t not in enabled)):return "INVALID_QUEST_BINDING"
			if o.reward_id=="BG24_Reward_134" and o.get("bound","") not in enabled:return "INVALID_QUEST_BINDING"
			if config(engine).bound_pools.has(o.reward_id) or o.reward_id=="BG28_Reward_510":
				var d=engine.content.get_def(str(o.get("bound","")))
				if d.is_empty() or not d.get("implemented",false) or not engine.content.eligible(d,enabled):return "INVALID_QUEST_BINDING"
				if o.reward_id=="BG28_Reward_510" and (int(d.get("tier",0))!=7 or d.get("golden",false)):return "INVALID_QUEST_BINDING"
		if q.status!="offered" and (int(q.get("progress",-1))<0 or q.reward_id!=engine.R136.LOOP and int(q.progress)>int(q.threshold)):return "INVALID_QUEST_PROGRESS"
	return ""
