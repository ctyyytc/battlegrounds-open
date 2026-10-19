extends RefCounted

const POWER="TB_BaconShop_HP_106"
const TAG="BG30_MagicItem_707"
const TOME="BG35_MagicItem_812"
const TOKEN="BG35_MagicItem_812t"
const CAKE="BG30_MagicItem_994"
const WHEEL="TB_BaconShop_HERO_35_Buddy_"
const RESULTS=["t2","t3","t5","t6","t7","t8"]
const WEIGHTS=[19,19,19,5,19,19]
const IDS=["004","013","029","033","040","100","110","006","009","010","012","014","018","026","030","101","011","015","019","020","034","037","039","104","016","022","023","025","028","032","106"]
static func supports(_d: Dictionary,e: Dictionary) -> bool:
	return e.get("handler","")=="round134" and (e.get("op","") in [POWER,TAG,TOME,TOKEN,CAKE,"elder"] or e.get("op","").begins_with(WHEEL) or e.get("op","").trim_prefix("BGS_Treasures_") in IDS)
static func ensure(p: Dictionary) -> void:
	if not p.has("r134"):p["r134"]={"periods":{},"tasks":[],"wheel":[],"ui":[],"seq":0,"returns":[],"used_obtain":{}}
static func tier(round_number: int) -> int:
	return clampi(round_number/4,1,4)
static func key(engine,p: Dictionary,source: String) -> String:
	ensure(p);p.r134.seq+=1
	return "r134:%d:%s:%d" % [int(p.id),source,int(p.r134.seq)]
static func origin(engine,source: String,receipt: String="") -> Dictionary:
	var value=engine.Acquisition.context(engine,{"def_id":source},"darkmoon_prize")
	value["reward_receipt"]=receipt;return value
static func pool(engine,p: Dictionary,n: int) -> Array:
	var ids=[]
	for id in engine.content.definitions:
		var d=engine.content.get_def(id)
		if d.get("is_darkmoon_prize",false) and d.get("implemented",false) and not d.get("golden",false) and int(d.get("prize_tier",0))==n and engine.content.eligible(d,engine.state.enabled_tribes):ids.append(id)
	ids.sort();return ids
static func pick(engine,ids: Array) -> Variant:
	return null if ids.is_empty() else ids[engine.RNG.next(engine.state.streams,"effects",ids.size())]
static func give(engine,p: Dictionary,id: String,source: String,receipt: String="") -> void:
	engine.receive_card(p,engine.make_card(id,int(p.id)),origin(engine,source,receipt))
static func earn(engine,p: Dictionary,source: String,stages: Array,receipt: String="") -> void:
	ensure(p)
	if receipt=="":receipt=key(engine,p,source)
	if p.r134.tasks.any(func(t):return t.receipt==receipt):return
	p.r134.tasks.append({"receipt":receipt,"source":source,"created_round":int(engine.state.round),"stages":stages.duplicate(),"stage":0,"status":"pending"})
	engine.emit("PrizeEarned",int(p.id),{"receipt":receipt,"source":source,"locked_tiers":stages})
	advance_rewards(engine,p)
static func advance_rewards(engine,p: Dictionary) -> void:
	ensure(p);engine.R133.ensure(p)
	if not p.choices.is_empty():return
	for task in p.r134.tasks:
		if task.status=="done" or task.get("kind","")=="random_spells":continue
		var n=int(task.stages[task.stage]);var ids=pool(engine,p,n)
		if ids.is_empty():engine.R133.anomaly(engine,p,task.receipt,n,false);continue
		p.r133_anomalies.erase(task.receipt)
		var options=[];var candidates=ids.duplicate()
		while not candidates.is_empty() and options.size()<3:
			var id=candidates.pop_at(engine.RNG.next(engine.state.streams,"choice",candidates.size()))
			options.append(engine.make_card(id,int(p.id)))
		engine.enqueue_choice(p,{"kind":"r134_prize","tier":n,"options":options,"receipt":task.receipt,"stage":task.stage,"source":task.source})
		task.status="choice";return
static func resolve(engine,p: Dictionary,choice: Dictionary,index: int) -> String:
	if choice.kind!="r134_prize":return "UNHANDLED"
	ensure(p)
	var found=p.r134.tasks.filter(func(t):return t.receipt==choice.receipt and t.status=="choice" and int(t.stage)==int(choice.stage))
	if found.size()!=1:return "STALE_PRIZE_REWARD"
	var task=found[0];var c=choice.options[index]
	if c.def_id not in pool(engine,p,int(choice.tier)):return "INVALID_PRIZE"
	var discovery_snapshot=c.duplicate(true)
	var result=engine.receive_card(p,c,origin(engine,task.source,task.receipt+":"+str(task.stage)))
	if result not in ["granted","queued"]:return "PRIZE_NOT_RECEIVED"
	engine.R135.discovered(engine,p,discovery_snapshot,str(choice.kind),str(choice.session_id))
	p.choices.pop_front();task.stage+=1;task.status="done" if int(task.stage)>=task.stages.size() else "pending"
	engine.emit("PrizeChosen",int(p.id),{"receipt":task.receipt,"id":c.def_id,"tier":choice.tier,"stage":choice.stage})
	advance_rewards(engine,p);return ""
static func minion_pool(engine,p: Dictionary,n: int) -> Array:
	if n==7:return engine.R13Items.seven_pool(engine).filter(func(id):return engine.content.eligible(engine.content.get_def(id),engine.state.enabled_tribes))
	return engine.discovery_candidates(p,{"tier":n}).filter(func(id):return int(engine.state.pool.get(id,0))>0)
static func spells(engine,p: Dictionary,n: int=-1,min_cost: int=0) -> Array:
	return engine.Naga.spell_pool(engine,p).filter(func(id):
		var d=engine.content.get_def(id)
		return d.get("is_tavern_spell",false) and (n<0 or int(d.tier)==n) and int(d.cost)>=min_cost)
static func gold_targets(engine,p: Dictionary) -> Array:
	return p.shop.filter(func(c):return engine.content.get_def(c.def_id).kind=="minion" and not engine.content.get_def(c.def_id).get("golden",false) and engine.content.definitions.has(engine.content.get_def(c.def_id).get("golden_id","")))
static func valid(engine,p: Dictionary,d: Dictionary,c: Dictionary) -> String:
	if not d.get("is_darkmoon_prize",false) and d.id!=TOKEN:return ""
	var suffix=str(d.id).trim_prefix("BGS_Treasures_")
	if d.id==TOKEN or suffix=="032":
		var tiers=[3] if d.id==TOKEN else [1,2,3]
		if tiers.any(func(n):return pool(engine,p,n).is_empty()):return "NO_LEGAL_CANDIDATE"
	if suffix in ["004","012","020"] and minion_pool(engine,p,1 if suffix=="004" else mini(7,int(p.tier)+1) if suffix=="020" else int(p.tier)).is_empty():return "NO_LEGAL_CANDIDATE"
	if suffix=="101" and spells(engine,p,int(p.tier)).is_empty():return "NO_LEGAL_CANDIDATE"
	if suffix=="100" and spells(engine,p,-1,2).is_empty():return "NO_LEGAL_CANDIDATE"
	if suffix=="011" and engine.R132.source_pool(engine,p,"identity").is_empty():return "NO_LEGAL_CANDIDATE"
	if suffix=="010" and p.get("previous_recruit_board",[]).is_empty():return "NO_LEGAL_CANDIDATE"
	if suffix=="037" and gold_targets(engine,p).is_empty():return "NO_LEGAL_TARGET"
	if suffix=="006" and p.shop.all(func(s):return replacement_pool(engine,p,s).is_empty()):return "NO_LEGAL_CANDIDATE"
	if suffix=="034" and (c.is_empty() or engine.content.get_def(c.def_id).get("golden",false)):return "NON_GOLDEN_FRIEND_REQUIRED"
	if suffix=="016" and not c.is_empty() and not engine.content.get_def(c.def_id).get("golden",false) and not engine.content.definitions.has(engine.content.get_def(c.def_id).get("golden_id","")):return "NO_LEGAL_TARGET"
	return ""
static func blocked(engine,p: Dictionary,c: Dictionary) -> bool:
	var d=engine.content.get_def(c.def_id)
	if valid(engine,p,d,{})!="NO_LEGAL_CANDIDATE":return false
	engine.R133.anomaly(engine,p,"manual-prize:"+str(c.instance_id),int(d.get("prize_tier",p.tier)),true)
	return true
static func replacement_pool(engine,p: Dictionary,c: Dictionary) -> Array:
	var d=engine.content.get_def(c.def_id);var n=mini(6,int(d.get("tier",1))+1)
	return engine.content.pool(str(d.kind),engine.state.enabled_tribes).filter(func(id):return int(engine.content.get_def(id).tier)==n and (d.kind!="minion" or int(engine.state.pool.get(id,0))>0))
static func discover_minion(engine,p: Dictionary,n: int,source: String) -> void:
	engine.resolve_discovery(p,minion_pool(engine,p,n),"r134_minion",1,origin(engine,source),false,n,n<7)
static func return_card(engine,p: Dictionary,c: Dictionary,source: String) -> void:
	p.board.erase(c)
	engine.receive_card(p,c,origin(engine,source))
	engine.emit("PrizeMinionReturned",int(p.id),{"id":c.def_id,"instance_id":c.instance_id})
static func execute(engine,p: Dictionary,e: Dictionary,c: Dictionary) -> bool:
	if e.get("handler","")!="round134":return false
	ensure(p);var op=str(e.op)
	if op=="elder":
		var board=engine.Undead.board(engine,p)
		for unused in (2 if engine.content.get_def(c.def_id).get("golden",false) else 1):
			if board.is_empty():break
			var a=int(board[0].attack) if board[0].has("attack") else engine.stats(board[0]).x
			var h=int(board[-1].health) if board[-1].has("health") else engine.stats(board[-1]).y
			engine.Undead.local_buff(engine,c,a,h,false)
			engine.emit("ElderOpening",int(p.id),{"instance_id":c.instance_id,"attack":a,"health":h})
		return true
	if op in [TAG,TOME,CAKE]:
		var item=engine.effect_source;var receipt="obtain:"+str(item.get("instance_id",-1))
		if p.r134.used_obtain.has(receipt):return true
		p.r134.used_obtain[receipt]=true;item["r134_due"]=int(engine.state.round)+(3 if op==TAG else 1)
		if op==TAG:earn(engine,p,op,[3],receipt)
		elif op==TOME:give(engine,p,TOKEN,op,receipt)
		else:wheel(engine,p,item)
		return true
	if op==TOKEN:
		if engine.current_spell.get("reward_cast_authorized",true):earn(engine,p,TOKEN,[3])
		return true
	if op==POWER or op.begins_with(WHEEL):return true
	var id=op.trim_prefix("BGS_Treasures_")
	match id:
		"004":discover_minion(engine,p,1,op)
		"012":discover_minion(engine,p,int(p.tier),op)
		"020":discover_minion(engine,p,mini(7,int(p.tier)+1),op)
		"013":
			p.r134["wine"]=int(p.r134.get("wine",0))+1
			for s in p.shop:shop_growth(engine,p,s)
		"029":p.r134["rolls"]=int(p.r134.get("rolls",0))+1
		"033":p.r134["extra"]=int(p.r134.get("extra",0))+1;spare_shop(engine,p,1)
		"040","019":
			for unused in (2 if id=="040" else 10):give(engine,p,"BG28_897",op)
		"100":give(engine,p,str(pick(engine,spells(engine,p,-1,2))),op)
		"110":p.spell_bonus_attack=int(p.get("spell_bonus_attack",0))+1;p.spell_bonus_health=int(p.get("spell_bonus_health",0))+1
		"006":
			for old in p.shop.duplicate():
				var ids=replacement_pool(engine,p,old)
				if ids.is_empty():continue
				var selected=str(pick(engine,ids));var is_minion=engine.content.get_def(selected).kind=="minion"
				if is_minion:engine.state.pool[selected]-=1
				var next=engine.make_card(selected,int(p.id),1 if is_minion else 0)
				engine.return_pool(old);p.shop[p.shop.find(old)]=next;engine.Demons.growth(engine,p,next)
			engine.R133.shop_sync(engine,p)
		"009":
			if not c.has("attached_effects"):c["attached_effects"]=[]
			c.attached_effects.append({"handler":"buff","trigger":"turn_end","attack":4,"health":4})
		"010":
			var options=[]
			for old in p.previous_recruit_board:
				options.append(engine.R132.original(engine,p,old))
			var chosen=[]
			while not options.is_empty() and chosen.size()<3:chosen.append(options.pop_at(engine.RNG.next(engine.state.streams,"choice",options.size())))
			engine.enqueue_choice(p,{"kind":"r134_copy","options":chosen,"acquisition_source":origin(engine,op)})
		"014":
			engine.gain_coins(p,1)
			var held=engine.current_spell.get("r134_card",{})
			if not held.is_empty() and not p.r134.returns.any(func(v):return int(v.card.instance_id)==int(held.instance_id)):p.r134.returns.append({"card":held,"round":int(engine.state.round)})
		"018":var a=engine.stats(c).x;engine.buff(c,a+4,0)
		"026":engine.add_keyword(c,"TAUNT");engine.buff(c,0,engine.stats(c).y)
		"030":p.r134["battlecry"]=int(p.r134.get("battlecry",0))+1
		"101":engine.resolve_discovery(p,spells(engine,p,int(p.tier)),"r134_spell",1,origin(engine,op),false,int(p.tier),false)
		"011":engine.R132.discover_power(engine,p,"identity",int(p.power_slots[-1].slot_id))
		"015":engine.buff(c,10,0);engine.add_keyword(c,"DIVINE_SHIELD")
		"034":engine.buff(c,6,6);return_card(engine,p,c,op)
		"037":engine.Pirates.transform_gold(engine,pick(engine,gold_targets(engine,p)))
		"039":engine.R133.transfer_batch(engine,p,p.shop.duplicate(),origin(engine,op));engine.refill_shop(p,false)
		"104":p.r134["discount"]=int(p.r134.get("discount",0))+1
		"016":
			if not engine.content.get_def(c.def_id).get("golden",false):engine.Pirates.transform_gold(engine,c)
			return_card(engine,p,c,op)
		"022":p.r134["buy_two"]=true
		"023":p.free_refresh+=5;p.r134["rolls"]=int(p.r134.get("rolls",0))+5
		"025":engine.gain_coins(p,12)
		"028":
			engine.buff(c,15,15)
			for word in ["DIVINE_SHIELD","WINDFURY"]:engine.add_keyword(c,word)
		"032":earn(engine,p,op,[1,2,3])
		"106":
			var receipt=key(engine,p,op);p.r134.tasks.append({"receipt":receipt,"source":op,"created_round":int(engine.state.round),"locked_tier":int(p.tier),"kind":"random_spells","remaining":10,"status":"pending","results":[]})
			advance_random(engine,p)
		_:return false
	engine.emit("PrizeEffectCommitted",int(p.id),{"id":op});return true
static func advance_random(engine,p: Dictionary) -> void:
	engine.R133.ensure(p)
	for task in p.r134.tasks:
		if task.get("kind","")!="random_spells" or task.status=="done":continue
		var ids=spells(engine,p).filter(func(id):return int(engine.content.get_def(id).tier)<=int(task.locked_tier))
		if ids.is_empty():engine.R133.anomaly(engine,p,task.receipt,int(task.locked_tier),false);continue
		p.r133_anomalies.erase(task.receipt)
		while int(task.remaining)>0:
			var id=str(pick(engine,ids));task.results.append(id);give(engine,p,id,task.source,task.receipt+":"+str(task.remaining));task.remaining-=1
		task.status="done"
static func shop_growth(engine,p: Dictionary,c: Dictionary) -> void:
	if engine.content.get_def(c.def_id).kind!="minion":return
	var amount=int(p.get("r134",{}).get("wine",0))-int(c.get("r134_wine",0))
	if amount>0:engine.buff(c,amount,amount,"permanent","darkmoon_wine");c["r134_wine"]=int(p.r134.wine)
static func spare_shop(engine,p: Dictionary,limit: int=7) -> void:
	ensure(p)
	var shown=p.shop.filter(func(c):return c.get("r134_extra",false)).size()
	for unused in mini(limit,mini(maxi(0,int(p.r134.get("extra",0))-shown),maxi(0,7-p.shop.size()))):
		var c=engine.Demons.draw_minion(engine,p)
		if c.is_empty():break
		c["r134_extra"]=true;engine.buff(c,2,2,"permanent","darkmoon_extra");p.shop.append(c)
static func start(engine,p: Dictionary) -> void:
	ensure(p);var r=int(engine.state.round)
	if int(p.r134.get("advanced_round",-1))==r:return
	p.r134["advanced_round"]=r;p.r134["discount"]=0;p.r134["battlecry"]=0
	p.free_refresh+=int(p.r134.get("rolls",0))
	if r%4==0 and engine.has_power(p,POWER) and not p.r134.periods.has(str(r)):
		p.r134.periods[str(r)]=true;earn(engine,p,POWER,[tier(r)],"hp106:%d:%d" % [int(p.id),r])
	for item in p.trinkets:
		if item.id not in [TAG,CAKE] or r<int(item.get("r134_due",r+1)):continue
		item.r134_due=r+(3 if item.id==TAG else 1)
		if item.id==TAG:earn(engine,p,TAG,[3],"tag:%d:%d" % [int(item.instance_id),r])
		else:wheel(engine,p,item)
	advance(engine,p)
static func end(engine,p: Dictionary) -> void:
	ensure(p)
	for entry in p.r134.returns.duplicate():
		if int(entry.round)>int(engine.state.round):continue
		engine.receive_card(p,entry.card,origin(engine,"BGS_Treasures_014"));p.r134.returns.erase(entry)
static func wheel(engine,p: Dictionary,source: Dictionary) -> void:
	ensure(p);var roll=engine.RNG.next(engine.state.streams,"effects",100);var sum=0;var selected=""
	for i in RESULTS.size():
		sum+=int(WEIGHTS[i])
		if roll<sum:selected=WHEEL+RESULTS[i];break
	var task={"receipt":key(engine,p,CAKE),"source_instance":source.get("instance_id",-1),"created_round":int(engine.state.round),"locked_tier":tier(int(engine.state.round)),"result_id":selected,"roll":roll,"phase":"pending","step":0,"steps":[],"ui_phase":"spin","ui_elapsed":0.0,"read":false}
	p.r134.wheel.append(task);engine.emit("WheelResultLocked",int(p.id),task.duplicate(true))
static func wheel_step(engine,p: Dictionary,t: Dictionary) -> void:
	var op=str(t.result_id).trim_prefix(WHEEL);var fact={"step":t.step,"targets":[],"id":t.result_id}
	match op:
		"t2":
			var ids=pool(engine,p,int(t.locked_tier))
			if ids.is_empty():t["blocked"]=true;engine.R133.anomaly(engine,p,t.receipt,int(t.locked_tier),false);return
			t["blocked"]=false
			p.r133_anomalies.erase(t.receipt)
			var id=str(pick(engine,ids));fact["prize_id"]=id;give(engine,p,id,t.result_id,t.receipt+":"+str(t.step));t.phase="done" if int(t.step)==1 else "pending"
		"t3":
			if p.board.size()>1:
				var receiver=pick(engine,p.board);var giver=pick(engine,p.board.filter(func(c):return c!=receiver));var value=engine.stats(giver)
				engine.buff(receiver,value.x,value.y);fact.targets=[receiver.instance_id,giver.instance_id];fact["attack"]=value.x;fact["health"]=value.y
			t.phase="done"
		"t5":
			if not p.board.is_empty():
				for c in p.shop.duplicate():
					if engine.content.get_def(c.def_id).kind!="minion":continue
					var receiver=pick(engine,p.board);var value=engine.stats(c);fact.targets.append({"from":c.instance_id,"to":receiver.instance_id,"attack":value.x,"health":value.y})
					engine.buff(receiver,value.x,value.y);p.shop.erase(c);engine.return_pool(c)
			engine.refill_shop(p,false);t.phase="done"
		"t6":
			var targets=p.board+p.shop.filter(func(c):return engine.content.get_def(c.def_id).kind=="minion")
			var at=engine.RNG.next(engine.state.streams,"effects",targets.size()+2)
			if at>=targets.size():fact["stop"]="hero" if at==targets.size() else "bartender";t.phase="done"
			else:var c=targets[at];engine.buff(c,10,10);fact.targets=[c.instance_id];fact["attack"]=10;fact["health"]=10
		"t7":
			var targets=gold_targets(engine,p)
			if not targets.is_empty():var c=pick(engine,targets);engine.Pirates.transform_gold(engine,c);fact.targets=[c.instance_id]
			t.phase="done"
		"t8":
			var receipt=str(t.receipt)
			var event_start=engine.events.size()
			fact["cast"]=engine.Yogg.trigger(engine,p,t.result_id,"wheel:"+receipt+":"+str(t.step))
			
			t=p.r134.wheel.filter(func(v):return v.receipt==receipt)[0]
			fact["spells"]=[]
			for event in engine.events.slice(event_start):
				if event.kind=="SpellResolved":fact.spells.append({"id":event.payload.id,"name":engine.content.get_def(event.payload.id).name,"target":event.payload.get("target",{})})
			t.phase="done" if int(t.step)>=3 else "pending"
	fact["target_names"]=[]
	for selected in fact.targets:
		var iid=int(selected.get("to",-1)) if selected is Dictionary else int(selected)
		var target=engine.find_target(p,iid)
		if not target.is_empty():fact.target_names.append(str(engine.content.get_def(target.def_id).name))
	t.steps.append(fact);t.step+=1;engine.emit("WheelStepCommitted",int(p.id),dict(fact,{"receipt":t.receipt}))
	if t.phase=="done":engine.emit("WheelCompleted",int(p.id),{"receipt":t.receipt,"result_id":t.result_id})
static func dict(a: Dictionary,b: Dictionary) -> Dictionary:
	var result=a.duplicate(true);result.merge(b,true);return result
static func advance(engine,p: Dictionary,budget: int=1,retry_blocked: bool=true) -> void:
	ensure(p);engine.R133.ensure(p)
	if retry_blocked:advance_random(engine,p)
	for c in p.hand:
		var receipt="manual-prize:"+str(c.instance_id)
		if p.r133_anomalies.has(receipt) and valid(engine,p,engine.content.get_def(c.def_id),{})!="NO_LEGAL_CANDIDATE":p.r133_anomalies.erase(receipt)
	for task in p.r134.wheel:
		if task.phase=="done":continue
		if task.get("blocked",false) and not retry_blocked:continue
		for unused in budget:
			var old=int(task.step);wheel_step(engine,p,task)
			if task.phase=="done" or int(task.step)==old:break
		break
	if retry_blocked:advance_rewards(engine,p)
static func pending(p: Dictionary) -> bool:
	return p.get("r134",{}).get("wheel",[]).any(func(t):return t.phase!="done" and not t.get("blocked",false))
static func sale_blocked(p: Dictionary) -> bool:
	
	return p.get("r134",{}).get("wheel",[]).any(func(t):return t.phase!="done" or float(t.get("ui_elapsed",0))<6.2)
static func presenting(p: Dictionary) -> Dictionary:
	for task in p.get("r134",{}).get("wheel",[]):
		if task.phase!="done" or float(task.get("ui_elapsed",0))<6.2:return task
	return {}
static func presentation_tick(p: Dictionary,delta: float,paused: bool,reduced: bool) -> void:
	if paused:return
	var task=presenting(p)
	if task.is_empty():return
	task.ui_elapsed=6.2 if reduced or task.get("skip_requested",false) else minf(6.2,float(task.ui_elapsed)+maxf(0,delta))
static func skip_animation(p: Dictionary,receipt: String) -> String:
	for task in p.get("r134",{}).get("wheel",[]):
		if task.receipt==receipt:
			task["skip_requested"]=true;task.ui_elapsed=6.2
			return ""
	return "UNKNOWN_WHEEL_TASK"
static func validate(p: Dictionary) -> String:
	if not p.has("r134"):return ""
	if not p.r134 is Dictionary:return "INVALID_R134_STATE"
	for field in ["tasks","wheel","ui","returns"]:
		if not p.r134.get(field) is Array:return "INVALID_R134_LIST"
	for field in ["periods","used_obtain"]:
		if not p.r134.get(field) is Dictionary:return "INVALID_R134_LEDGER"
	var seen=[]
	for task in p.r134.tasks:
		if not task is Dictionary or str(task.get("receipt","")).is_empty() or task.receipt in seen or task.get("status","") not in ["pending","choice","done"]:return "INVALID_PRIZE_TASK"
		seen.append(task.receipt)
		if task.get("kind","")=="random_spells":
			if int(task.get("remaining",-1)) not in range(0,11) or not task.get("results") is Array:return "INVALID_PRIZE_TASK"
		elif not task.get("stages") is Array or task.stages.is_empty() or int(task.get("stage",-1))<0 or int(task.stage)>task.stages.size() or task.stages.any(func(n):return int(n) not in range(1,5)):return "INVALID_PRIZE_TASK"
	seen=[]
	for t in p.r134.get("wheel",[]):
		if not t is Dictionary or str(t.get("receipt","")).is_empty() or t.receipt in seen:return "INVALID_WHEEL_RECEIPT"
		seen.append(t.receipt)
		if str(t.get("result_id","")).trim_prefix(WHEEL) not in RESULTS or int(t.get("step",-1))<0 or int(t.get("locked_tier",0)) not in range(1,5) or not t.get("steps") is Array:return "INVALID_WHEEL_TASK"
		if int(t.step)!=t.steps.size() or t.get("phase","") not in ["pending","done"] or not t.get("read") is bool or not is_finite(float(t.get("ui_elapsed",-1))) or float(t.get("ui_elapsed",-1))<0:return "INVALID_WHEEL_PROGRESS"
		if t.has("skip_requested") and not t.skip_requested is bool:return "INVALID_WHEEL_PROGRESS"
	return ""
