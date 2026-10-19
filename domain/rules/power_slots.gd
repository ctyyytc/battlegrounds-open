extends RefCounted

const FINITE=["BG31_HERO_005p","TB_BaconShop_HP_046","TB_BaconShop_HP_048","TB_BaconShop_HP_076","TB_BaconShop_HP_102"]
# Borrowed powers that still own work in the upcoming battle or its settlement.
# Recruit-only powers keep their existing end-of-recruit boundary (BR-86).
const COMBAT_BORROWS=["BG20_HERO_282p","BG21_HERO_000p","BG22_HERO_000p_Alt","BG22_HERO_001p","BG22_HERO_002p","BG22_HERO_003p","BG22_HERO_200p","BG25_HERO_103p","TB_BaconShop_HP_036","TB_BaconShop_HP_036t","TB_BaconShop_HP_053","TB_BaconShop_HP_069","TB_BaconShop_HP_080","TB_BaconShop_HP_086","TB_BaconShop_HP_107"]
# Start handlers and automatic shop-refresh passives must finish before Nguyen returns.
const START_BORROWS=["BG22_HERO_004p","BG24_HERO_204p","BG31_HERO_003p","BG23_HERO_305p","TB_BaconShop_HP_036t","TB_BaconShop_HP_038","TB_BaconShop_HP_039t","TB_BaconShop_HP_106","BG36_HERO_105p","BG32_HERO_002p"]
static func has_start_work(engine,s: Dictionary) -> bool:
	var id=str(s.active_power_id)
	return id in START_BORROWS or engine.content.get_def(id).get("effects",[]).any(func(e):return e.get("trigger","") in ["turn_start","obtain_and_start"])
const PROGRESS={"BG20_HERO_242p":["guff_progress"],"BG20_HERO_280p5":["blade_buys"],"BG21_HERO_020p":["cookie_inputs"],"TB_BaconShop_HP_048":["brann_buys"],"TB_BaconShop_HP_056":["flurgl_sales"],"TB_BaconShop_HP_074":["eudora_digs"],"TB_BaconShop_HP_088":["chen_plays"],"TB_BaconShop_HP_036":["jar_damage"],"BG25_HERO_103p":["teron_target"]}
static func validate(engine,p: Dictionary,enabled: Array=[]) -> String:
	var trinket_error=engine.R136Slots.validate(engine,p)
	if trinket_error!="":return trinket_error
	var r135_error=engine.R135.validate(engine,p,enabled)
	if r135_error!="":return r135_error
	var r134_error=engine.R134.validate(p)
	if r134_error!="":return r134_error
	var r133_error=engine.R133.validate(p)
	if r133_error!="":return r133_error
	if engine.content.get_def(str(p.get("hero_id",""))).get("kind","")!="hero":return "INVALID_SAVE_HERO"
	if not p.has("power_slots"):return ""
	if not p.power_slots is Array or p.power_slots.size()<1 or p.power_slots.size()>2:return "INVALID_SAVE_POWER_SLOTS"
	var seen=[]
	for s in p.power_slots:
		if not s is Dictionary or not s.get("progress") is Dictionary or int(s.get("epoch",0))<1 or int(s.get("slot_id",-1)) not in [0,1] or int(s.slot_id) in seen:return "INVALID_SAVE_POWER_SLOTS"
		seen.append(int(s.slot_id))
		for key in ["active_power_id","persistent_power_id"]:
			if engine.content.get_def(str(s.get(key,""))).get("kind","")!="hero_power":return "INVALID_SAVE_POWER_ID"
		if s.has("temporary_restore") and (not s.temporary_restore is Dictionary or engine.content.get_def(str(s.temporary_restore.get("power_id",""))).get("kind","")!="hero_power" or not s.temporary_restore.get("progress") is Dictionary):return "INVALID_SAVE_POWER_RESTORE"
	if not p.get("power_ledger",{}) is Dictionary or not p.get("identity_lost_limited",[]) is Array or not p.get("power_event_receipts",{}) is Dictionary:return "INVALID_SAVE_POWER_LEDGER"
	return ""
static func ensure(engine,p: Dictionary) -> void:
	if not p.has("power_slots"):
		var id=str(engine.content.get_def(p.hero_id).get("initial_power_id",""))
		p["power_slots"]=[slot(id,0)]
		var current=id
		if id=="TB_BaconShop_HP_036":
			p.power_slots[0].progress["jar_damage"]=int(p.get("jar_damage",0))
			if p.get("portal",false):p.power_slots[0].active_power_id="TB_BaconShop_HP_036t"
		if id=="TB_BaconShop_HP_041" and p.has("rat_tribe"):
			p.power_slots[0].progress["rat_tribe"]=p.rat_tribe;current=id+engine.Demons.RAT_POWERS.get(p.rat_tribe,"");p.power_slots[0].active_power_id=current
		p["power_ledger"]={current:{"round":int(engine.state.get("round",1)),"used":int(p.get("power_used",false)),"game_used":int(p.get("power_used_game",false))}}
	if not p.has("power_ledger"):p["power_ledger"]={}
	if not p.has("identity_lost_limited"):p["identity_lost_limited"]=[]
	if not p.has("power_event_receipts"):p["power_event_receipts"]={}
static func slot(id: String,index: int) -> Dictionary:
	return {"slot_id":index,"persistent_power_id":id,"active_power_id":id,"epoch":1,"progress":{}}
static func selected(engine,p: Dictionary,slot_id: int=-1) -> Dictionary:
	ensure(engine,p)
	var wanted=int(engine.power_context.get(int(p.id),0)) if slot_id<0 else slot_id
	for s in p.power_slots:
		if int(s.slot_id)==wanted:return s
	return {}
static func active(engine,p: Dictionary) -> Array:
	ensure(engine,p)
	return p.power_slots.map(func(s):return str(s.active_power_id))
static func owns(engine,p: Dictionary,id: String) -> bool:
	return id in active(engine,p)
static func definition(engine,p: Dictionary,slot_id: int=-1) -> Dictionary:
	var s=selected(engine,p,slot_id)
	return {} if s.is_empty() else engine.content.get_def(s.active_power_id)
static func handler(engine,p: Dictionary,slot_id: int=-1) -> String:
	var d=definition(engine,p,slot_id)
	var es=d.get("effects",[])
	if es.is_empty():return ""
	var e=es[0]
	return str(e.get("op","")) if e.get("handler","") in ["round12","round10","round11","round13_item","round132","round133","round134"] else str(e.get("handler",""))
static func has_handler(engine,p: Dictionary,value: String) -> bool:
	ensure(engine,p)
	return p.power_slots.any(func(s):return handler(engine,p,int(s.slot_id))==value)
static func ledger(engine,p: Dictionary,slot_id: int=-1) -> Dictionary:
	var s=selected(engine,p,slot_id)
	if s.is_empty():return {}
	var id=str(s.persistent_power_id) if s.get("temporary_restore",{}).is_empty() else str(s.active_power_id)
	if str(s.active_power_id).begins_with("TB_BaconShop_HP_041"):id=str(s.active_power_id)
	if not p.power_ledger.has(id):p.power_ledger[id]={"round":int(engine.state.round),"used":0,"game_used":0}
	var entry=p.power_ledger[id]
	if int(entry.round)!=int(engine.state.round):entry.round=int(engine.state.round);entry.used=0
	return entry
static func used(engine,p: Dictionary,whole_game: bool=false) -> int:
	var entry=ledger(engine,p)
	return int(entry.get("game_used" if whole_game else "used",0))
static func consume(engine,p: Dictionary,whole_game: bool=false) -> void:
	var entry=ledger(engine,p)
	entry.used=int(entry.get("used",0))+1
	if whole_game:entry.game_used=int(entry.get("game_used",0))+1
	
	p.power_used=int(entry.used)>0;p.power_used_game=int(entry.get("game_used",0))>0
static func loss(engine,p: Dictionary,s: Dictionary,id: String) -> void:
	engine.R136Slots.loss(engine,p,s)
	engine.R135.loss(engine,p,s,id)
	engine.R133.loss(engine,p,s,id)
	if id=="BG28_HERO_800p":p.erase("tavern_bought")
	if id in FINITE and id not in p.identity_lost_limited:p.identity_lost_limited.append(id)
	for key in PROGRESS.get(id,[]):p.erase(key)
	if id=="BG22_HERO_000p_Alt" and s.progress.has("ammo"):engine.return_pool(s.progress.ammo.card)
	s.progress={}
	engine.emit("HeroPowerLost",int(p.id),{"power_id":id,"slot_id":s.slot_id,"epoch":s.epoch})
static func replace(engine,p: Dictionary,index: int,id: String,temporary: bool=false) -> String:
	ensure(engine,p)
	var d=engine.content.get_def(id)
	if d.get("kind","")!="hero_power":return "INVALID_POWER"
	var s=selected(engine,p,index)
	if s.is_empty():return "INVALID_POWER_SLOT"
	var old=str(s.active_power_id)
	if temporary:
		engine.R136Slots.suspend(engine,p,s)
		if old in [engine.R133.FLIGHT,engine.R133.TICKETS]:engine.R133.loss(engine,p,s,old)
		s["temporary_restore"]={"power_id":s.active_power_id,"progress":s.progress.duplicate(true),"epoch":s.epoch}
	else:
		loss(engine,p,s,old)
		if s.has("temporary_restore"):
			var prior=s.duplicate(true);prior.epoch=s.temporary_restore.epoch
			loss(engine,p,prior,str(s.persistent_power_id))
		s.erase("temporary_restore");s.persistent_power_id=id
	s.active_power_id=id;s.epoch+=1;s.progress={}
	engine.emit("HeroPowerBound",int(p.id),{"power_id":id,"previous":old,"slot_id":index,"epoch":s.epoch,"temporary":temporary})
	engine.R132.bound(engine,p,s)
	engine.R136Slots.sync(engine,p)
	return ""
static func restore_temporary(engine,p: Dictionary,boundary: String="all") -> void:
	ensure(engine,p)
	for s in p.power_slots:
		if not s.has("temporary_restore"):continue
		if boundary=="recruit_end" and str(s.active_power_id) in COMBAT_BORROWS:continue
		if p.alive and boundary in ["recruit_end","before_start"] and has_start_work(engine,s):continue
		var restore=s.temporary_restore.duplicate(true)
		loss(engine,p,s,str(s.active_power_id))
		s.active_power_id=str(restore.power_id);s.progress=restore.progress;s.epoch+=1;s.erase("temporary_restore")
		engine.R136Slots.restore(engine,p,s,int(restore.epoch))
		engine.emit("HeroPowerRestored",int(p.id),{"power_id":s.active_power_id,"slot_id":s.slot_id,"epoch":s.epoch})
static func receipt(engine,p: Dictionary,s: Dictionary,event_id: String) -> bool:
	var key="%d:%d:%s" % [int(s.slot_id),int(s.epoch),event_id]
	if p.power_event_receipts.has(key):return false
	p.power_event_receipts[key]=true
	return true
