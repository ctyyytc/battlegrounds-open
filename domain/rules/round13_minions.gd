extends RefCounted
const U=preload("res://domain/rules/undead_rules.gd")
const Gain=preload("res://domain/rules/elemental_gain.gd")
const OPS=["reclaimer","reclaim_summon","stone","last","sargeras","rai","sanders","kodo","jail","future","sea_copy"]
static func supports(_d: Dictionary,e: Dictionary) -> bool:
	return e.get("handler","")=="round13" and e.get("op","") in OPS
static func specs(engine,c: Dictionary,op: String) -> Array:
	return engine.Triggers.effects(engine,c).filter(func(e):return e.get("handler","")=="round13" and e.get("op","")==op)
static func bought(engine,p: Dictionary,c: Dictionary) -> void:
	if engine.content.get_def(c.def_id).kind!="minion":return
	for source in p.board.duplicate():
		for e in specs(engine,source,"stone"):
			if int(source.get("stone_round",-1))==int(engine.state.round):continue
			source["stone_round"]=int(engine.state.round)
			var v=Gain.from_source(engine,p,Vector2i(20,20),e,source);engine.buff(c,v.x,v.y)
			v=engine.stats(c)*(int(e.multiplier)-1);engine.buff(c,v.x,v.y)
static func summoned(engine,p: Dictionary,c: Dictionary) -> void:
	if not U.is_combat(engine):return
	for source in U.board(engine,p).duplicate():
		if int(source.instance_id)==int(c.instance_id):continue
		for e in specs(engine,source,"kodo"):
			if int(source.get("kodo_uses",0))>=3:continue
			source["kodo_uses"]=int(source.get("kodo_uses",0))+1
			U.local_buff(engine,c,int(source.attack)*int(e.multiplier),int(source.max_health)*int(e.multiplier))
static func valid_target(engine,p: Dictionary,d: Dictionary,target: Dictionary) -> bool:
	if d.effects.is_empty() or d.effects[0].get("op","")!="sea_copy":return true
	return not target.is_empty() and engine.find_index(p.shop,int(target.instance_id))>=0 and engine.content.get_def(target.def_id).kind=="minion" and engine.content.get_def(target.def_id).get("base_id",target.def_id)!="BG27_514"
static func jail_summon(engine,p: Dictionary,c: Dictionary,multiplier: int) -> Dictionary:
	var board=U.board(engine,p);var cap=int(engine.combat_context.capacities[engine.combat_context.players.find(p)])
	if board.size()>=cap:return {}
	var token=engine.make_card("PROJECT_R13_JAILBIRD_GOLEM",int(p.id));token["base_override"]={"attack":int(c.attack)*multiplier,"health":int(c.health)*multiplier}
	var child=engine.Combat.unit(engine,token);board.insert(board.find(c)+1,child);U.summoned(engine,p,child)
	engine.emit("JailGolemSummoned",int(p.id),{"instance_id":child.instance_id,"source":c.instance_id,"attack":child.attack,"health":child.max_health})
	return child
static func gold_target(engine,p: Dictionary,c: Dictionary) -> bool:
	var d=engine.content.get_def(c.def_id)
	return c in p.board and d.kind=="minion" and not d.get("golden",false) and int(d.get("tier",7))<=6 and d.get("golden_id","")!=""
static func golden(engine,p: Dictionary,c: Dictionary) -> void:
	if not gold_target(engine,p,c):return
	engine.Pirates.transform_gold(engine,c)
static func resolve_target(engine,p: Dictionary,choice: Dictionary,index: int) -> String:
	if index<0 or index>=choice.options.size():return "INVALID_OPTION"
	var id=int(choice.options[index].instance_id);var i=engine.find_index(p.board,id)
	if i<0 or not gold_target(engine,p,p.board[i]):return "INVALID_TARGET"
	golden(engine,p,p.board[i]);p.choices.pop_front();return ""
static func execute(engine,p: Dictionary,e: Dictionary,c: Dictionary) -> bool:
	if not supports({},e):return false
	var source=engine.effect_source;var board=U.board(engine,p);var target=engine.effect_target
	match str(e.op):
		"reclaimer":
			var i=board.find(c);var victims=[]
			for j in ([i-1,i+1] if e.golden else [i-1]):
				if j>=0 and j<board.size() and engine.content.get_def(board[j].def_id).get("base_id","")!="BG31_999":victims.append(board[j])
			c["reclaimed"]=victims.duplicate(true)
			for victim in victims:victim.health=0
		"reclaim_summon":
			var offset=0
			for saved in c.get("reclaimed",[]):
				var copy=saved.duplicate(true);copy["r13_keep_route"]=true
				engine.Beasts.summon(engine,p,copy.def_id,int(e.get("summon_index",-1))+offset,false,copy);offset+=1
		"last":
			for unused in int(e.amount):
				var chosen=[]
				for tribe in engine.state.enabled_tribes:
					# Recruit instances have no combat health field; they are live board cards.
					var candidates=board.filter(func(v):return int(v.get("health",1))>0 and int(v.instance_id) not in chosen and U.tribe(engine,v,tribe))
					var picked=engine.Naga.pick(engine,candidates)
					if picked==null:continue
					chosen.append(int(picked.instance_id));var gain=Vector2i(15,15)+Gain.extra(p)
					U.local_buff(engine,picked,gain.x,gain.y,true)
		"sargeras":
			p["shop_growth_attack"]=int(p.get("shop_growth_attack",0))+int(e.attack);p["shop_growth_health"]=int(p.get("shop_growth_health",0))+int(e.health)
			for v in p.shop:
				if engine.content.get_def(v.def_id).kind=="minion":engine.buff(v,int(e.attack),int(e.health),"permanent","sargeras")
		"rai":U.random_cards(engine,p,{"tier":6,"amount":e.amount},source)
		"sanders":
			if not gold_target(engine,p,target):return true
			golden(engine,p,target)
			for unused in range(1,int(e.amount)):
				var options=p.board.filter(func(v):return gold_target(engine,p,v)).duplicate(true)
				if not options.is_empty():engine.enqueue_choice(p,{"kind":"round13_gold_target","options":options,"source_instance":c.instance_id})
		"future":
			var held=p.hand.filter(func(v):return engine.content.get_def(v.def_id).kind=="minion")
			if not held.is_empty():
				var v=engine.stats(c)*int(e.multiplier);engine.buff(held[0],v.x,v.y)
		"sea_copy":
			if not valid_target(engine,p,engine.current_spell,target):return true
			for unused in int(e.amount):engine.receive_card(p,engine.Fish.copy(engine,p,target),source)
		"stone","kodo","jail":pass
	return true
