extends RefCounted
static func consume(engine,p: Dictionary,secret: Dictionary) -> void:
	p.secrets.erase(secret)
	engine.emit("SecretConsumed",int(p.id),{"id":secret.id,"receipt":secret.receipt,"ghost":p.get("is_ghost",false)})
static func live_keywords(c: Dictionary) -> Array:
	var words=c.keywords.duplicate()
	if not c.get("shield",false):words.erase("DIVINE_SHIELD")
	if not c.get("venom",false):words.erase("VENOMOUS")
	return words
static func cluster(engine,p: Dictionary,target: Dictionary) -> Dictionary:
	var saved=engine.R132.full_copy(engine,p,target)
	engine.R133.strip(saved)
	for key in ["tracked_rewards","killed_by","killed_by_owner","acquisition_source","r133_reward","reward_tier","attached_pool","shield_budget","reborn_base_health"]:saved.erase(key)
	
	preload("res://domain/rules/stat_reset.gd").perfect(engine,saved,Vector2i(3,3))
	var words=live_keywords(target)
	saved.extra_keywords=words.duplicate();saved["removed_keywords"]=engine.content.get_def(saved.def_id).get("keywords",[]).filter(func(k):return k not in words)
	saved.modifiers=saved.modifiers.filter(func(m):return not m.has("keyword") or m.keyword in words)
	saved=engine.Combat.unit(engine,saved)
	saved.keywords=words;saved.shield="DIVINE_SHIELD" in words;saved.venom="VENOMOUS" in words
	saved["r13_keep_route"]=true
	return saved
static func attacked(engine,players: Array,boards: Array,capacities: Array,side: int,attacker: Dictionary,target: Dictionary) -> void:
	var defending=1-side;var p=players[defending]
	if attacker not in boards[side] or target not in boards[defending] or int(attacker.health)<=0 or int(target.health)<=0:return
	engine.R133.ensure(p)
	for secret in p.secrets.duplicate():
		if target not in boards[defending] or int(target.health)<=0:break
		if secret.id=="TB_Bacon_Secrets_07":
			if target.get("shield",false):continue
			consume(engine,p,secret);engine.add_keyword(target,"DIVINE_SHIELD");target.shield=true;target.erase("shield_budget")
		elif secret.id in ["TB_Bacon_Secrets_01","TB_Bacon_Secrets_15"]:
			if boards[defending].size()>=int(capacities[defending]):continue
			consume(engine,p,secret)
			if secret.id=="TB_Bacon_Secrets_01":engine.Beasts.summon(engine,p,"BG_EX1_170")
			else:engine.Beasts.summon(engine,p,target.def_id,-1,false,cluster(engine,p,target))
static func redemption(engine,players: Array,boards: Array,capacities: Array,deaths: Array,feedback: Array) -> void:
	for side in 2:
		var p=players[side];engine.R133.ensure(p)
		if boards[side].size()>=int(capacities[side]):continue
		var armed=p.secrets.filter(func(s):return s.id=="TB_Bacon_Secrets_10")
		if armed.is_empty():continue
		var eligible=deaths.filter(func(d):return int(d.side)==side and engine.content.get_def(d.unit.def_id).get("kind","")=="minion")
		if eligible.is_empty():continue
		var dead=eligible[0].unit;var card=engine.make_card(dead.def_id,int(p.id));card["reborn_base_health"]=1
		var saved=engine.Combat.unit(engine,card)
		consume(engine,p,armed[0])
		var child=engine.Beasts.summon(engine,p,dead.def_id,-1,false,saved)
		if not child.is_empty():feedback.append({"kind":"summon","instance_id":child.instance_id,"def_id":child.def_id,"origin":"redemption"})
