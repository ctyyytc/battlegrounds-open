extends RefCounted
const RNG=preload("res://domain/rules/deterministic_rng.gd")
const U=preload("res://domain/rules/undead_rules.gd")
const OPS=["progress","waterwheel","ball_portrait","wind","double_highest","bottled_ice","magmaloc_portrait","bound_shop","bound_gold"]
static func supports(d: Dictionary,e: Dictionary) -> bool:
	return d.kind=="trinket" and e.get("handler","")=="elemental_trinket" and e.get("op","") in OPS
static func execute(engine,p: Dictionary,e: Dictionary,c: Dictionary) -> bool:
	if e.get("handler","")!="elemental_trinket": return false
	var item=engine.effect_source
	match str(e.op):
		"bound_shop":pass 
		"bound_gold":
			if not item.get("gold_used",false) and engine.content.get_def(c.def_id).kind=="minion" and U.tribe(engine,c,item.bound_tribe):
				var d=engine.content.get_def(c.def_id)
				if not d.golden and d.golden_id!="":engine.Pirates.transform_gold(engine,c)
				item["gold_used"]=true
		"progress":
			item["progress"]=int(item.get("progress",0))+1
			if int(item.progress)>=int(e.threshold):
				item.progress=0
				if e.has("id"): engine.receive_card(p,engine.make_card(e.id,int(p.id)),item)
				else: U.random_cards(engine,p,{"tribe":"元素"},item)
		"waterwheel":
			if int(item.get("water_round",0))!=int(engine.state.round): item["water_round"]=int(engine.state.round);item["water_uses"]=0
			if int(item.get("water_uses",0))<2:
				item["water_uses"]=int(item.get("water_uses",0))+1
				var pool=engine.content.pool("spell",engine.state.enabled_tribes)
				if not pool.is_empty(): engine.receive_card(p,engine.make_card(pool[RNG.next(engine.state.streams,"effects",pool.size())],int(p.id)),item)
		"ball_portrait": engine.receive_card(p,engine.make_card(["BG31_816","BG31_818"][RNG.next(engine.state.streams,"effects",2)],int(p.id)),item)
		"wind":
			for unused in int(e.amount): engine.cast(p,engine.content.get_def("BG34_444"),{})
		"double_highest":
			var pool=p.shop.filter(func(v):return engine.content.get_def(v.def_id).kind=="minion")
			if not pool.is_empty():
				var highest=0
				for v in pool: highest=maxi(highest,engine.stats(v).y)
				pool=pool.filter(func(v):return engine.stats(v).y==highest)
				var target=pool[RNG.next(engine.state.streams,"effects",pool.size())];var value=engine.stats(target);engine.buff(target,value.x,value.y)
		"bottled_ice","magmaloc_portrait": pass 
		_: return false
	return true
static func consumed(engine,p: Dictionary,c: Dictionary,value: Vector2i) -> void:
	for item in p.trinkets:
		if engine.content.get_def(item.id).effects.any(func(e):return e.get("op","")=="magmaloc_portrait"):
			var index=p.board.find(c)
			for ni in [index-1,index+1]:
				if ni>=0 and ni<p.board.size(): engine.buff(p.board[ni],value.x,value.y)
static func opening(engine,p: Dictionary,board: Array) -> void:
	for item in p.trinkets:
		if not engine.content.get_def(item.id).effects.any(func(e):return e.get("op","")=="bottled_ice"): continue
		var candidates=board.filter(func(c):return U.tribe(engine,c,"元素"))
		for unused in mini(2,candidates.size()):
			var c=candidates.pop_at(RNG.next(engine.state.streams,"combat",candidates.size()))
			if not c.has("attached_effects"): c["attached_effects"]=[]
			c.attached_effects.append({"handler":"summon","trigger":"deathrattle","id":"BG26_537","amount":1})
