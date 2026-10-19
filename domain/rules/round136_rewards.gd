extends RefCounted

const EVIDENCE="BG24_Reward_363"
const SCEPTER="BG27_Reward_812"
const LOOP="BG33_Reward_020"
const CONFLICTS=["BG30_MagicItem_973","BG30_MagicItem_423","BG30_MagicItem_841","BG30_MagicItem_998","BG32_MagicItem_366","BG35_MagicItem_930","BG35_MagicItem_755","BG36_MagicItem_830"]
const GIFTS={"BG24_Reward_718":"BG24_Reward_718t","BG24_Reward_719":"BG24_Reward_719t","BG27_Reward_504":"BG27_Reward_504t"}
static func supports(_d: Dictionary,e: Dictionary) -> bool:
	return e.get("handler","")=="round136" and e.get("op","") in ["reward","sack","hammer","accelerator"]
static func pair_legal(quest: String,reward: String) -> bool:
	return not (quest=="BG27_Quest_801" and reward==LOOP)
static func reward_legal(engine,p: Dictionary,id: String) -> bool:
	if id in engine.R135.config(engine).get("project_excluded_rewards",[]):return false
	if id=="BG33_Reward_011" and "鱼人" not in engine.state.enabled_tribes:return false
	if id==SCEPTER and p.trinkets.any(func(t):return t.id in CONFLICTS):return false
	return true
static func views(engine,p: Dictionary) -> Array:
	engine.R135.ensure(p);var result=[]
	if not p.r135 is Dictionary or not p.r135.get("slots") is Dictionary:return []
	for q in p.r135.slots.values():
		result.append(q)
		if q.get("status","")=="reward_active" and q.get("reward_id","")==EVIDENCE and q.has("child"):result.append(q.child)
	return result
static func scepter_reserved(engine,p: Dictionary) -> bool:
	return views(engine,p).any(func(q):return q.get("reward_id","")==SCEPTER and q.get("status","") in ["active","completion_pending","reward_active"] and engine.R135.valid_slot(engine,p,q))
static func bindings(engine,p: Dictionary,id: String) -> Array:
	if id==SCEPTER:return engine.state.enabled_tribes.filter(func(t):return not engine.R135.minions(engine,p,str(t)).is_empty())
	return []
static func grant(engine,p: Dictionary,q: Dictionary) -> void:
	var r=q.reward_state;var id=str(q.reward_id)
	if id==LOOP:
		var cycles=int(q.progress)/int(q.threshold)
		q.progress=int(q.progress)%int(q.threshold);r["completed_cycles"]=int(r.get("completed_cycles",0))+cycles
		r["cumulative_attack"]=int(r.completed_cycles)*2;r["cumulative_health"]=int(r.completed_cycles)
		engine.emit("IncantationCyclesGranted",int(p.id),{"quest_instance":q.instance,"cycles":cycles,"total":r.completed_cycles,"progress":q.progress})
	if id in ["BG33_Reward_014","BG33_Reward_015"] and not r.has("opportunity"):
		r["opportunity"]=engine.R136Slots.reward_opportunity(engine,p,q)
	if id=="BG24_Reward_350":engine.check_triples(p)
static func extra_cast(engine,p: Dictionary,spell: Dictionary) -> int:
	return engine.R135.active(engine,p,"BG28_Reward_501").size() if spell.get("played_from_hand",false) and spell.get("is_tavern_spell",false) and not spell.get("automatic",false) else 0
static func aura(engine,p: Dictionary) -> Vector2i:
	var result=Vector2i.ZERO
	for q in engine.R135.active(engine,p,LOOP):result+=Vector2i(int(q.reward_state.get("cumulative_attack",0)),int(q.reward_state.get("cumulative_health",0)))
	return result
static func start_reward(engine,p: Dictionary,q: Dictionary) -> bool:
	var r=q.reward_state;var round_number=int(engine.state.round)
	if int(r.get("start_round",-1))==round_number:
		return not r.has("teaching_due")
	
	r["start_round"]=round_number;var part="start:"+str(round_number);var id=str(q.reward_id)
	if GIFTS.has(id):
		for i in (2 if id=="BG27_Reward_504" else 1):engine.R135.deliver(engine,p,q,GIFTS[id],part+":"+str(i))
	elif id=="BG28_Reward_509":
		var level=int(r.get("smelting_level",1));var targets=p.board.filter(func(c):return gold_target(engine,p,c) and int(engine.content.get_def(c.def_id).tier)==level)
		if not targets.is_empty():engine.Pirates.transform_gold(engine,targets[engine.RNG.next(engine.state.streams,"effects",targets.size())])
		r["smelting_level"]=mini(6,level+1)
	elif id=="BG28_Reward_514":
		
		for i in 5:engine.Yogg.trigger(engine,p,id,q.instance+":"+part+":"+str(i))
	elif id=="BG33_Reward_011":
		r["teaching_due"]={"part":part,"tier":int(p.tier),"pool":engine.R135.spells(engine,p)}
		teach(engine,p,q);return false
	else:engine.R135.legacy_start(engine,p,q,part)
	return true
static func teach(engine,p: Dictionary,q: Dictionary) -> void:
	var due=q.reward_state.teaching_due
	if p.choices.any(func(c):return c.kind=="r136_teach" and c.quest_instance==q.instance):return
	if due.pool.is_empty():due.pool=engine.R135.spells(engine,p).filter(func(id):return int(engine.content.get_def(id).tier)<=int(due.tier))
	if due.pool.is_empty():due["diagnostic"]="EMPTY_TEACHING_POOL";return
	var ids=engine.RNG.shuffle(due.pool,engine.state.streams,"choice").slice(0,3);var options=[]
	for id in ids:options.append(engine.make_card(id,int(p.id)))
	engine.enqueue_choice(p,{"kind":"r136_teach","quest_instance":q.instance,"slot_id":q.slot_id,"epoch":q.epoch,"part":due.part,"teaching_tier":due.tier,"options":options})
	q.reward_state.teaching_due["session_id"]=p.choices[-1].session_id
static func evidence_pool(engine,p: Dictionary,q: Dictionary) -> Array:
	return engine.R135.config(engine).ethereal_pool.filter(func(id):return id!=q.get("previous_selected_family","") and engine.R135.reward_legal(engine,p,id))
static func evidence_offer(engine,p: Dictionary,q: Dictionary) -> bool:
	if p.choices.any(func(c):return c.kind=="r136_evidence" and c.quest_instance==q.instance):return false
	var pool=evidence_pool(engine,p,q)
	if pool.size()<2:q.reward_state["diagnostic"]="INSUFFICIENT_ETHEREAL_FAMILIES";return false
	q.reward_state.erase("diagnostic");var options=[]
	for unused in 2:
		var id=pool.pop_at(engine.RNG.next(engine.state.streams,"choice",pool.size()));var domain=engine.R135.bindings(engine,p,id)
		options.append({"reward_id":id,"bound":domain[engine.RNG.next(engine.state.streams,"choice",domain.size())],"reward_state":{}})
	engine.enqueue_choice(p,{"kind":"r136_evidence","quest_instance":q.instance,"slot_id":q.slot_id,"epoch":q.epoch,"options":options})
	q.reward_state["selection_session"]=p.choices[-1].session_id
	return false
static func turn_start(engine,p: Dictionary) -> bool:
	engine.R135.ensure(p)
	for q in p.r135.slots.values():
		if q.status!="reward_active" or not engine.R135.valid_slot(engine,p,q):continue
		if q.reward_id!=EVIDENCE:
			if not start_reward(engine,p,q):
				if q.reward_state.has("teaching_due"):teach(engine,p,q)
				return false
			continue
		var r=q.reward_state
		if int(r.get("evidence_round",-1))!=int(engine.state.round):r["evidence_round"]=int(engine.state.round);r["phase"]="old_start"
		if r.phase=="done":continue
		if r.phase=="old_start":
			if q.has("child") and not start_reward(engine,p,q.child):
				if q.child.reward_state.has("teaching_due"):teach(engine,p,q.child)
				return false
			if not p.choices.is_empty():return false
			r.phase="select"
		if r.phase=="select":return evidence_offer(engine,p,q)
		if r.phase=="new_start":
			if not start_reward(engine,p,q.child):
				if q.child.reward_state.has("teaching_due"):teach(engine,p,q.child)
				return false
			r.phase="done"
	return true
static func find_quest(engine,p: Dictionary,instance: String) -> Dictionary:
	for q in views(engine,p):
		if q.instance==instance:return q
	return {}
static func resolve(engine,p: Dictionary,c: Dictionary,index: int) -> String:
	if c.kind not in ["r136_evidence","r136_teach","r136_locket"]:return "UNHANDLED"
	var q=find_quest(engine,p,c.quest_instance)
	if q.is_empty() or not engine.R135.valid_slot(engine,p,q) or int(c.epoch)!=int(q.epoch):return "STALE_REWARD_SOURCE"
	if c.kind=="r136_evidence":
		if q.reward_state.get("phase","")!="select" or q.reward_state.get("selection_session","")!=c.session_id:return "STALE_ETHEREAL_CHOICE"
		var o=c.options[index]
		if o.reward_id not in evidence_pool(engine,p,q) or o.bound not in engine.R135.bindings(engine,p,o.reward_id):return "INVALID_ETHEREAL_REWARD"
		if q.has("child"):
			q.child.status="removed";p.r135.removed.append(q.child.duplicate(true))
		var child={"instance":q.instance+":child:"+str(engine.state.round),"slot_id":q.slot_id,"epoch":q.epoch,"status":"reward_active","reward_id":o.reward_id,"bound":o.bound,"reward_state":{"next_buff":2,"next_coins":1,"smelting_level":1},"grant_parts":{},"granted_round":int(engine.state.round)}
		q["child"]=child;q["previous_selected_family"]=o.reward_id;q.reward_state.phase="new_start";p.choices.pop_front()
		engine.R135.initial_gift(engine,p,child);grant(engine,p,child)
		engine.emit("EtherealRewardSelected",int(p.id),{"reward_id":o.reward_id,"quest_instance":q.instance})
	elif c.kind=="r136_teach":
		var due=q.reward_state.get("teaching_due",{})
		if due.get("session_id","")!=c.session_id or c.options[index].def_id not in due.pool:return "STALE_TEACHING_CHOICE"
		var part=str(due.part)+":apprentice"
		if not q.grant_parts.has(part):
			var card=engine.make_card("BG33_890t",int(p.id));card["learned_spell"]=c.options[index].def_id;card["quest_grant_receipt"]=q.instance+":"+part
			q.grant_parts[part]={"card":card,"committed":false}
		engine.R135.deliver(engine,p,q,"BG33_890t",part);q.reward_state.erase("teaching_due");p.choices.pop_front()
	else:
		if int(c.battle_round)!=int(engine.state.round):return "STALE_LOCKET_BATTLE"
		var source=c.options[index];var copy=engine.R132.full_copy(engine,p,source)
		engine.receive_card(p,copy,engine.R135.origin(engine,q));p.choices.pop_front()
		engine.R135.discovered(engine,p,copy,"r136_locket",c.session_id)
	return ""
static func after_battle(engine,p: Dictionary) -> void:
	
	var snapshot=p.get("previous_recruit_board",[]).filter(func(c):return not engine.content.get_def(c.def_id).get("golden",false))
	for q in engine.R135.active(engine,p,"BG27_Reward_806"):
		var part="locket:"+str(engine.state.round)
		if q.grant_parts.has(part):continue
		q.grant_parts[part]={"committed":true}
		if snapshot.is_empty():continue
		engine.enqueue_choice(p,{"kind":"r136_locket","quest_instance":q.instance,"epoch":q.epoch,"battle_round":int(engine.state.round),"options":engine.RNG.shuffle(snapshot,engine.state.streams,"choice").slice(0,3).duplicate(true)})
static func gold_target(engine,p: Dictionary,c: Dictionary) -> bool:
	if c.is_empty() or c not in p.board:return false
	var d=engine.content.get_def(c.def_id);var g=engine.content.get_def(str(d.get("golden_id","")))
	return d.get("kind","")=="minion" and not d.get("golden",false) and g.get("implemented",false) and g.get("golden",false)
static func shop_tribe(engine,p: Dictionary) -> String:
	if p.get("candle_drawing",false):return ""
	for q in engine.R135.active(engine,p,SCEPTER):
		var tribe=str(q.bound)
		var count=p.shop.filter(func(c):return engine.content.get_def(c.def_id).kind=="minion" and (tribe in engine.card_types(c) or "全部种族" in engine.card_types(c))).size()
		if count<2:return tribe
	return ""
static func accelerator_pool(engine,p: Dictionary,c: Dictionary) -> Array:
	if c.is_empty() or c not in p.board+p.shop:return []
	var d=engine.content.get_def(c.def_id);var tier=int(d.get("tier",7))
	if d.get("kind","")!="minion" or tier>=7:return []
	return engine.Shop132.minions(engine,p,mini(6,tier+1),true).filter(func(id):return tier!=6 or engine.content.get_def(id).get("base_id",id)!=d.get("base_id",d.id))
static func valid_target(engine,p: Dictionary,d: Dictionary,c: Dictionary) -> bool:
	if d.get("effects",[]).is_empty() or d.effects[0].get("handler","")!="round136":return true
	match str(d.effects[0].op):
		"hammer":return gold_target(engine,p,c)
		"accelerator":return not accelerator_pool(engine,p,c).is_empty()
		"sack":
			if c.is_empty() or c not in p.board+p.shop:return false
			var t=engine.content.get_def(c.def_id)
			return not t.get("golden",false) and (t.kind=="minion" or c in p.shop and t.get("is_tavern_spell",false))
	return true
static func execute(engine,p: Dictionary,e: Dictionary,c: Dictionary) -> bool:
	if e.get("handler","")!="round136":return false
	match str(e.op):
		"sack":
			p.board.erase(c);p.shop.erase(c);engine.receive_card(p,c,{"origin_kind":"quest_reward","producer_id":"BG24_Reward_718t"})
		"hammer":
			var original=str(c.def_id);engine.Pirates.transform_gold(engine,c)
			c["temporary_gold"]={"original":original,"gold":c.def_id,"expires_round":int(engine.state.round)+1,"form_revision":c.get("form_revision",0)}
		"accelerator":
			var pool=accelerator_pool(engine,p,c);var id=pool[engine.RNG.next(engine.state.streams,"effects",pool.size())]
			var replacement=engine.make_card(id,int(p.id));replacement.instance_id=c.instance_id
			if c.has("bread_rewards"):replacement["bread_rewards"]=c.bread_rewards.duplicate(true)
			engine.return_pool(c);c.clear();c.merge(replacement)
			if c in p.shop:
				if engine.Elementals.elemental(engine,c):engine.buff(c,int(p.get("nomi_attack",0)),int(p.get("nomi_health",0)),"permanent","nomi")
				engine.Pirates.growth(engine,p,c);engine.Demons.growth(engine,p,c)
			engine.emit("CardTransformed",int(p.id),{"instance_id":c.instance_id,"id":id,"source":"accelerator"})
			engine.Naga.recruit_entered(engine,p,c)
		_:return false
	return true
static func revert(engine,p: Dictionary) -> void:
	for c in p.board+p.hand+p.shop+p.pending_rewards:
		if not c.has("temporary_gold"):continue
		var r=c.temporary_gold
		if int(r.expires_round)>int(engine.state.round):continue
		if c.def_id==r.gold and int(c.get("form_revision",0))==int(r.form_revision):
			c.def_id=r.original;engine.emit("TemporaryGoldReverted",int(p.id),{"instance_id":c.instance_id,"id":c.def_id})
		c.erase("temporary_gold")
static func validate(engine,p: Dictionary,enabled: Array) -> String:
	for q in views(engine,p):
		if not q is Dictionary or not q.get("reward_state",{}) is Dictionary:return "INVALID_REWARD_STATE"
		if q.get("reward_id","") in engine.R135.config(engine).get("project_excluded_rewards",[]):return "EXCLUDED_QUEST_REWARD"
		if not pair_legal(q.get("quest_id",""),q.get("reward_id","")):return "INVALID_QUEST_PAIR"
		var r=q.get("reward_state",{})
		if q.get("reward_id","")=="BG33_Reward_011" and "鱼人" not in enabled:return "INVALID_MURLOC_REWARD"
		if int(r.get("smelting_level",1)) not in range(1,7) or int(r.get("completed_cycles",0))<0:return "INVALID_REWARD_PROGRESS"
		if q.has("child"):
			if not q.child is Dictionary or q.child.get("reward_id","") not in engine.R135.config(engine).ethereal_pool or q.child.get("slot_id",-1)!=q.slot_id or q.child.get("epoch",-1)!=q.epoch:return "INVALID_ETHEREAL_STATE"
			if not q.child.get("grant_parts") is Dictionary or not q.child.get("reward_state") is Dictionary:return "INVALID_ETHEREAL_STATE"
	return ""
