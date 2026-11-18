extends RefCounted

# These effects award cards or a card discovery during the start-of-round batch.
const ITEM_HANDLERS=["give","generate"]
const ITEM_OPS=["give","globe","book","reflect","factory","lens","ball_portrait","bounty","lockbox","random_craft","random_choice","conch_portrait","seven_random","dagger","wind","parents","collage","gold_supply"]
const QUEST_GIVERS=["BG24_Reward_134","BG28_Reward_515","BG33_Reward_011"]
const MUKLA="TB_BaconShop_HP_038"
const CAT="TB_BaconShop_HP_080"

static func stamp(engine) -> int:
	var order=int(engine.state.next_instance)
	engine.state.next_instance+=1
	return order

static func item_effect(effect: Dictionary) -> bool:
	return effect.get("trigger","") in ["turn_start","obtain_and_start"] and (effect.get("handler","") in ITEM_HANDLERS or effect.get("op","") in ITEM_OPS)

static func power_receipt(slot: Dictionary) -> Dictionary:
	return {"slot_id":int(slot.slot_id),"epoch":int(slot.epoch),"power_id":str(slot.active_power_id),"order":int(slot.get("acquired_order",0))}

static func holds_power(p: Dictionary,slot: Dictionary) -> bool:
	var owner=power_receipt(slot)
	return p.get("post_battle_rewards",[]).any(func(reward):return reward.get("power_owner",{})==owner)

static func valid_battle(engine,p: Dictionary,reward: Dictionary) -> bool:
	if not p.alive or int(reward.get("battle_round",-1))!=int(engine.state.round)-1:return false
	var owner=reward.get("power_owner",{})
	if not owner.is_empty():return engine.R136Slots.owner_valid(engine,p,owner)
	var q=engine.R136.find_quest(engine,p,str(reward.get("quest_instance","")))
	return not q.is_empty() and q.get("reward_id","")=="BG27_Reward_806" and int(reward.get("epoch",-1))==int(q.epoch) and engine.R135.valid_slot(engine,p,q)

static func collect(engine,p: Dictionary) -> Array:
	var jobs=[]
	for reward in p.get("post_battle_rewards",[]):
		jobs.append({"kind":"battle","order":int(reward.get("source_order",0)),"reward":reward})
	p["post_battle_rewards"]=[]
	for item in p.trinkets:
		var d=engine.content.get_def(item.id)
		if d.effects.any(item_effect):
			jobs.append({"kind":"item","order":int(item.instance_id),"instance":int(item.instance_id)})
		if item.id==engine.R134.TAG:
			jobs.append({"kind":"prize_item","order":int(item.instance_id),"instance":int(item.instance_id)})
	for q in engine.R136.views(engine,p):
		if q.status=="reward_active" and engine.R135.valid_slot(engine,p,q) and (q.get("reward_id","") in QUEST_GIVERS or q.get("reward_id","") in engine.R136.GIFTS):
			jobs.append({"kind":"quest","order":int(q.get("acquired_order",0)),"quest":q.instance,"epoch":int(q.epoch)})
	for receiver in engine.state.players:
		if not receiver.alive:continue
		for slot in receiver.power_slots:
			var id=str(slot.active_power_id)
			if id==MUKLA or int(receiver.id)==int(p.id) and engine.R132.is_card_start(engine,p,slot):
				var entry=power_receipt(slot)
				entry.merge({"kind":"power","owner":int(receiver.id)})
				jobs.append(entry)
	for position in jobs.size():jobs[position]["position"]=position
	jobs.sort_custom(func(a,b):return int(a.order)<int(b.order) or int(a.order)==int(b.order) and int(a.position)<int(b.position))
	return jobs

static func resolve(engine,p: Dictionary,job: Dictionary) -> void:
	match str(job.kind):
		"battle":
			var reward=job.reward
			if not valid_battle(engine,p,reward):return
			if reward.kind=="cat_consolation":
				var victim=int(reward.get("eliminated_id",-1))
				if victim<0 or victim>=engine.state.players.size():return
				var eliminated=engine.state.players[victim]
				if eliminated.alive or int(eliminated.rank)<=0 or not eliminated.get("eliminated_board",[]).is_empty():return
				engine.receive_card(p,engine.make_card("TB_BaconShop_HP_080t",int(p.id)),{"def_id":CAT})
			else:p.choices.append(reward)
		"item","prize_item":
			var item=engine.R13Items.item(engine,p,int(job.instance))
			if item.is_empty():return
			if job.kind=="item":engine.trinket_effects(p,"turn_start",{},item,"card_rewards")
			else:engine.R134.start_prize_item(engine,p,item)
		"quest":
			var q=engine.R136.find_quest(engine,p,str(job.quest))
			if not q.is_empty() and q.status=="reward_active" and int(q.epoch)==int(job.epoch) and engine.R135.valid_slot(engine,p,q):
				engine.R136.start_reward(engine,p,q)
		"power":
			var owner=engine.state.players[int(job.owner)]
			if owner.alive and engine.R136Slots.owner_valid(engine,owner,job):
				engine.R132.card_start(engine,p,owner,engine.Powers.selected(engine,owner,int(job.slot_id)))

static func valid_cursor(cursor: Dictionary) -> bool:
	if not cursor.has("reward_jobs"):return not cursor.has("reward_index")
	var jobs=cursor.reward_jobs
	if not jobs is Array or int(cursor.get("stage",-1))!=1 or not cursor.has("reward_index"):return false
	if int(cursor.reward_index)<0 or int(cursor.reward_index)>jobs.size():return false
	for job in jobs:
		if not job is Dictionary:return false
		match job.get("kind",""):
			"battle":
				if not job.get("reward") is Dictionary:return false
			"item","prize_item":
				if int(job.get("instance",-1))<0:return false
			"quest":
				if str(job.get("quest",""))=="" or int(job.get("epoch",0))<1:return false
			"power":
				if int(job.get("owner",-1)) not in range(8) or int(job.get("slot_id",-1)) not in [0,1]:return false
			_:return false
	return true

static func advance(engine,p: Dictionary,cursor: Dictionary) -> bool:
	if not cursor.has("reward_jobs"):
		cursor["reward_jobs"]=collect(engine,p)
		cursor["reward_index"]=0
	while int(cursor.reward_index)<cursor.reward_jobs.size():
		if not engine.settle_start_choices(p):return false
		var job=cursor.reward_jobs[int(cursor.reward_index)]
		cursor.reward_index+=1
		resolve(engine,p,job)
	if not engine.settle_start_choices(p):return false
	cursor.erase("reward_jobs")
	cursor.erase("reward_index")
	cursor["rewards_settled"]=true
	return true
