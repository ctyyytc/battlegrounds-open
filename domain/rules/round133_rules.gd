extends RefCounted
const FLIGHT="BG20_HERO_283p"
const ENHANCE="BG24_HERO_204p"
const MAGIC="TB_BaconShop_HP_020"
const TICKETS="TB_BaconShop_HP_101"
const TOKEN="TB_BaconShop_HP_101t2"
const ROOTS=[FLIGHT,ENHANCE,MAGIC,TICKETS]
const SECRETS=["TB_Bacon_Secrets_01","TB_Bacon_Secrets_15","TB_Bacon_Secrets_07","TB_Bacon_Secrets_10"]
const WORDS=["TAUNT","REBORN","WINDFURY","DIVINE_SHIELD","STEALTH","VENOMOUS"]
static func supports(d: Dictionary,e: Dictionary) -> bool:
	return e.get("handler","")=="round133" and (d.id in ROOTS or d.id==TOKEN or d.id in SECRETS or str(d.id).begins_with(FLIGHT+"_t") or d.kind=="hero" and e.get("op","") in ROOTS)
static func ensure(p: Dictionary) -> void:
	for key in ["r133_transfers","r133_rewards","r133_anomalies"]:
		if not p.has(key):p[key]={}
	for key in ["r133_tasks","secrets"]:
		if not p.has(key):p[key]=[]
static func validate(p: Dictionary) -> String:
	for key in ["r133_transfers","r133_rewards","r133_anomalies"]:
		if p.has(key) and not p[key] is Dictionary:return "INVALID_SAVE_R133_LEDGER"
	for key in ["r133_tasks","secrets"]:
		if p.has(key) and not p[key] is Array:return "INVALID_SAVE_R133_TASKS"
	var seen=[]
	for s in p.get("secrets",[]):
		if not s is Dictionary or s.get("id","") not in SECRETS or s.get("id","") in seen or str(s.get("receipt","")).is_empty():return "INVALID_SAVE_R133_SECRET"
		seen.append(s.id)
	return ""
static func ticket_slot(engine,p: Dictionary) -> Dictionary:
	for s in p.power_slots:
		if s.active_power_id==TICKETS:return s
	return {}
static func strip(c: Dictionary) -> void:
	for key in ["r133_offer","r133_roll","r133_ticket"]:c.erase(key)
static func loss(engine,p: Dictionary,s: Dictionary,id: String) -> void:
	if id==TICKETS:
		for c in p.shop:strip(c)
	if id in [FLIGHT,TICKETS]:s.progress={}
static func event(engine,fact: Dictionary) -> void:
	var pid=int(fact.owner)
	if pid<0 or pid>=engine.state.players.size():return
	var p=engine.state.players[pid];ensure(p)
	if fact.kind in ["HeroPowerBound","HeroPowerRestored"] and fact.payload.power_id==TICKETS:shop_sync(engine,p)
static func shop_sync(engine,p: Dictionary) -> void:
	ensure(p)
	var s=ticket_slot(engine,p)
	for c in p.shop:
		if s.is_empty():strip(c);continue
		if engine.content.get_def(c.def_id).kind not in ["minion","spell"]:continue
		var identity="%d:%d:%d" % [int(c.instance_id),int(s.slot_id),int(s.epoch)]
		if c.get("r133_offer","")==identity:continue
		strip(c);c["r133_offer"]=identity
		c["r133_roll"]=engine.RNG.next(engine.state.streams,"effects",100)
		c["r133_ticket"]=int(c.r133_roll)<24
		engine.emit("TicketOfferRolled",int(p.id),{"offer":identity,"instance_id":c.instance_id,"roll":c.r133_roll,"ticket":c.r133_ticket})
static func refreshed(engine,p: Dictionary) -> void:
	shop_sync(engine,p)
	if not engine.has_power(p,ENHANCE):return
	var results=[]
	for step in 2:
		var targets=p.shop.filter(func(c):return engine.content.get_def(c.def_id).kind=="minion" and not legal_words(engine,c).is_empty())
		if targets.is_empty():continue
		var c=targets[engine.RNG.next(engine.state.streams,"effects",targets.size())]
		var words=legal_words(engine,c);var word=words[engine.RNG.next(engine.state.streams,"effects",words.size())]
		engine.add_keyword(c,word);results.append({"instance_id":c.instance_id,"keyword":word,"step":step})
	engine.emit("EnhancementResolved",int(p.id),{"steps":results})
static func legal_words(engine,c: Dictionary) -> Array:
	var current=engine.keywords(c)
	return WORDS.filter(func(word):return word not in current and not (word=="WINDFURY" and "SUPER_WINDFURY" in current))
static func capture(engine,p: Dictionary,c: Dictionary) -> Dictionary:
	var s=ticket_slot(engine,p)
	if s.is_empty() or not c.get("r133_ticket",false):return {}
	if c.get("r133_offer","")!="%d:%d:%d" % [int(c.instance_id),int(s.slot_id),int(s.epoch)]:return {}
	return {"offer":str(c.get("r133_offer","")),"instance_id":c.instance_id,"slot_id":s.slot_id,"epoch":s.epoch,"ticket":true,"def_id":c.def_id,"shop_index":p.shop.find(c)}
static func acquired(engine,p: Dictionary,c: Dictionary,fact: Dictionary={}) -> void:
	if fact.is_empty():fact=capture(engine,p,c)
	strip(c)
	if fact.is_empty():return
	ensure(p)
	var s=ticket_slot(engine,p)
	if s.is_empty() or int(s.epoch)!=int(fact.epoch) or p.r133_transfers.has(fact.offer):return
	p.r133_transfers[fact.offer]=true
	var n=int(s.progress.get("tickets",0))+1;var completed=n>=3
	s.progress["tickets"]=n%3
	engine.emit("TicketCollected",int(p.id),dict(fact,{"progress":n%3,"completed":completed}))
	if completed:
		var receipt="ticket:"+fact.offer
		var token=engine.make_card(TOKEN,int(p.id));token["reward_tier"]=int(p.tier);token["r133_reward"]=receipt
		grant(engine,p,token,receipt,"r133_ticket_token")
static func dict(base: Dictionary,extra: Dictionary) -> Dictionary:
	var result=base.duplicate(true);result.merge(extra,true);return result
static func grant(engine,p: Dictionary,c: Dictionary,receipt: String,kind: String) -> bool:
	ensure(p)
	if p.r133_rewards.has(receipt):return true
	
	p.r133_rewards[receipt]="committing"
	var source={"origin_kind":kind,"producer_id":TOKEN if kind.begins_with("r133_ticket") else FLIGHT,"reward_receipt":receipt,"root_action_id":engine.cause}
	var result=engine.receive_card(p,c,source)
	if result in ["granted","queued"]:p.r133_rewards[receipt]=result;return true
	p.r133_rewards.erase(receipt);return false
static func transfer_batch(engine,p: Dictionary,cards: Array,source: Dictionary) -> Array:
	
	
	var moved=[];var facts=[]
	for c in cards:
		if c not in p.shop:continue
		var fact=capture(engine,p,c);p.shop.erase(c);engine.Fish.leave_shop(c);strip(c)
		var result=engine.receive_card(p,c,source)
		if result in ["granted","queued"]:moved.append(c);facts.append({"card":c,"fact":fact})
	for entry in facts:acquired(engine,p,entry.card,entry.fact)
	return moved
static func query(engine,p: Dictionary) -> Dictionary:
	var s=engine.Powers.selected(engine,p);var id=str(s.get("active_power_id",""))
	if id not in ROOTS:return {}
	ensure(p)
	var reason=""
	if id in [ENHANCE,TICKETS]:reason="PASSIVE_POWER"
	elif id==FLIGHT and s.progress.has("flight"):reason="FLIGHT_IN_PROGRESS"
	elif id==MAGIC:
		if engine.Powers.used(engine,p)>0:reason="POWER_ALREADY_USED"
		elif secret_count(p)>=5 or SECRETS.all(func(v):return mounted(p,v)):reason="SECRET_LIMIT"
	return {"available":reason=="","reason":reason,"targets":[],"cost":0,"handler":id,"slot_id":s.slot_id,"epoch":s.epoch}
static func use(engine,p: Dictionary) -> String:
	var q=query(engine,p)
	if not q.get("available",false):return q.get("reason","POWER_NOT_IMPLEMENTED")
	var s=engine.Powers.selected(engine,p);var options=[]
	for id in ([FLIGHT+"_t1",FLIGHT+"_t2",FLIGHT+"_t3"] if q.handler==FLIGHT else SECRETS):
		options.append({"def_id":id,"instance_id":-1,"modifiers":[],"extra_keywords":[],"gifts":[]})
	engine.enqueue_choice(p,{"kind":"r133_route" if q.handler==FLIGHT else "r133_secret","slot_id":s.slot_id,"epoch":s.epoch,"options":options})
	return ""
static func option_error(engine,p: Dictionary,choice: Dictionary,index: int) -> String:
	var s=engine.Powers.selected(engine,p,int(choice.slot_id))
	if s.is_empty() or int(s.epoch)!=int(choice.epoch):return "STALE_POWER_EPOCH"
	var id=str(choice.options[index].def_id)
	if choice.kind=="r133_route":
		return "SAME_FLIGHT_ROUTE" if engine.Powers.ledger(engine,p,int(s.slot_id)).get("last_route","")==id else ""
	return "SECRET_ALREADY_MOUNTED" if mounted(p,id) else "SECRET_LIMIT" if secret_count(p)>=5 else ""
static func resolve(engine,p: Dictionary,choice: Dictionary,index: int) -> String:
	if choice.kind not in ["r133_route","r133_secret"]:return "UNHANDLED"
	var error=option_error(engine,p,choice,index)
	if error!="":return error
	var s=engine.Powers.selected(engine,p,int(choice.slot_id));var id=str(choice.options[index].def_id)
	if choice.kind=="r133_route":
		var ledger=engine.Powers.ledger(engine,p,int(s.slot_id));ledger["last_route"]=id;ledger["flight_serial"]=int(ledger.get("flight_serial",0))+1
		s.progress["flight"]={"id":id,"remaining":int(id.right(1)),"advanced_round":int(engine.state.round),"receipt":"flight:%d:%d" % [int(p.id),int(ledger.flight_serial)]}
	else:
		p.secrets.append({"id":id,"receipt":"secret:%d:%d" % [int(p.id),int(engine.state.event_seq)]})
		var old=engine.power_context.get(int(p.id),0);engine.power_context[int(p.id)]=int(s.slot_id);engine.consume_power(p);engine.power_context[int(p.id)]=old
		engine.emit("SecretMounted",int(p.id),{"id":id})
	p.choices.pop_front();return ""
static func secret_count(p: Dictionary) -> int:
	return p.get("secrets",[]).size()+int(p.get("iceblock",false))
static func mounted(p: Dictionary,id: String) -> bool:
	return p.get("secrets",[]).any(func(s):return s.id==id)
static func candidates(engine,p: Dictionary,task: Dictionary) -> Array:
	if task.kind=="spell":return engine.Naga.spell_pool(engine,p).filter(func(id):return int(engine.content.get_def(id).get("cost",-1))==1 and int(engine.content.get_def(id).tier)<=int(task.tier))
	return engine.discovery_candidates(p,{"tier":int(task.tier)})
static func anomaly(engine,p: Dictionary,key: String,tier: int,manual: bool) -> void:
	ensure(p)
	if p.r133_anomalies.has(key):return
	p.r133_anomalies[key]={"tier":tier,"manual":manual,"shown":true,"closed":false}
	engine.emit("RewardAnomaly",int(p.id),{"receipt":key,"tier":tier,"reason":"NO_LEGAL_CANDIDATE","manual":manual})
static func token_empty(engine,p: Dictionary,c: Dictionary) -> bool:
	return c.def_id==TOKEN and candidates(engine,p,{"kind":"minion","tier":int(c.get("reward_tier",p.tier))}).is_empty()
static func token_blocked(engine,p: Dictionary,c: Dictionary) -> bool:
	if not token_empty(engine,p,c):return false
	anomaly(engine,p,str(c.r133_reward),int(c.reward_tier),true);return true
static func token_play(engine,p: Dictionary,c: Dictionary) -> void:
	var receipt=str(c.r133_reward);var tier=int(c.reward_tier)
	if p.r133_rewards.has(receipt+":used"):return
	p.r133_rewards[receipt+":used"]=true
	p.r133_anomalies.erase(receipt)
	engine.resolve_discovery(p,candidates(engine,p,{"kind":"minion","tier":tier}),"r133_ticket_discovery",1,{"origin_kind":"r133_ticket_discovery","producer_id":TOKEN,"reward_receipt":receipt},false,tier,false)
static func turn_start(engine,p: Dictionary) -> void:
	ensure(p)
	for s in p.power_slots:
		if s.active_power_id!=FLIGHT or not s.progress.has("flight"):continue
		var f=s.progress.flight
		if int(f.advanced_round)>=int(engine.state.round):continue
		f.advanced_round=int(engine.state.round);f.remaining-=1
		if int(f.remaining)>0:continue
		s.progress.erase("flight")
		if str(f.id).ends_with("2"):
			if not p.r133_rewards.has(f.receipt):engine.gain_coins(p,2);p.r133_rewards[f.receipt]="coins"
		else:p.r133_tasks.append({"receipt":f.receipt,"kind":"spell" if str(f.id).ends_with("1") else "minion","tier":int(p.tier)})
		engine.emit("FlightArrived",int(p.id),{"receipt":f.receipt,"tier":p.tier,"route":f.id})
	changed(engine,p)
static func changed(engine,p: Dictionary) -> void:
	ensure(p);shop_sync(engine,p)
	for c in p.hand+p.board:strip(c)
	for c in p.hand:
		if c.def_id==TOKEN and not token_empty(engine,p,c):p.r133_anomalies.erase(str(c.r133_reward))
	for task in p.r133_tasks.duplicate():
		if p.r133_rewards.has(task.receipt):p.r133_tasks.erase(task);continue
		var pool=candidates(engine,p,task)
		if pool.is_empty():anomaly(engine,p,task.receipt,int(task.tier),false);continue
		p.r133_anomalies.erase(task.receipt)
		if task.kind=="spell":
			var id=pool[engine.RNG.next(engine.state.streams,"effects",pool.size())]
			grant(engine,p,engine.make_card(id,int(p.id)),task.receipt,"r133_flight_spell")
		else:
			p.r133_rewards[task.receipt]="choice"
			engine.resolve_discovery(p,pool,"r133_flight_discovery",1,{"origin_kind":"r133_flight_discovery","producer_id":FLIGHT,"reward_receipt":task.receipt},false,int(task.tier),false)
		p.r133_tasks.erase(task)
static func anomaly_command(p: Dictionary,closed: bool) -> void:
	for value in p.get("r133_anomalies",{}).values():value.closed=closed
