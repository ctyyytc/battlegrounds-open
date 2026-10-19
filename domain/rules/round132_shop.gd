extends RefCounted
static func minions(engine,p: Dictionary,tier: int,exact: bool=false,all_types: bool=false) -> Array:
	return engine.content.pool("minion",engine.state.enabled_tribes).filter(func(id):return (int(engine.content.get_def(id).tier)==tier if exact else int(engine.content.get_def(id).tier)<=tier) and (not all_types or "全部种族" in engine.content.get_def(id).card_types))
static func available_stock(engine,p: Dictionary,id: String) -> int:
	var amount=int(engine.state.pool.get(id,0))
	for c in p.shop:
		if c.pool_base==id:amount+=int(c.pool_copies)
		for a in c.get("attached_pool",[]):
			if a.id==id:amount+=int(a.copies)
	return amount
static func possible(engine,p: Dictionary,policy: String) -> bool:
	if policy=="TB_BaconShop_HP_077":return not p.get("previous_recruit_board",[]).is_empty()
	if engine.Naga.spell_pool(engine,p).is_empty():return false
	if policy=="TB_BaconShop_HP_028":return minions(engine,p,mini(6,int(p.tier)+1),true).reduce(func(v,id):return v+available_stock(engine,p,id),0)>=2
	return true
static func draw(engine,p: Dictionary,ids: Array,stock: bool) -> Dictionary:
	var pool=[]
	for id in ids:
		for unused in (int(engine.state.pool.get(id,0)) if stock else 1):pool.append(id)
	if pool.is_empty():return {}
	var id=pool[engine.RNG.next(engine.state.streams,"shop"+str(p.id),pool.size())]
	if stock:engine.state.pool[id]-=1
	var c=engine.make_card(id,int(p.id),1 if stock else 0)
	if stock:
		if engine.Elementals.elemental(engine,c):engine.buff(c,int(p.get("nomi_attack",0)),int(p.get("nomi_health",0)),"permanent","nomi")
		engine.Pirates.growth(engine,p,c);engine.Demons.growth(engine,p,c)
	return c
static func refresh(engine,p: Dictionary,policy: String,target: Dictionary={}) -> String:
	if policy!="hamul_fallback" and not possible(engine,p,policy):return "NO_LEGAL_CANDIDATE"
	var old_shop=p.shop.duplicate(true)
	for c in p.shop:engine.return_pool(c)
	var result=[];var n=int(engine.content.rules.shop_sizes[int(p.tier)-1]);var spells=engine.Naga.spell_pool(engine,p)
	match policy:
		"BG34_HERO_001p":
			for unused in mini(7,n+1):
				var c=draw(engine,p,spells,false)
				if not c.is_empty():result.append(c)
		"TB_BaconShop_HP_028":
			for unused in 2:
				var c=draw(engine,p,minions(engine,p,mini(6,int(p.tier)+1),true),true)
				if c.is_empty():return "NO_LEGAL_CANDIDATE"
				c["toki_guarantee"]=true;result.append(c)
			for unused in maxi(0,n-2):
				var c=draw(engine,p,minions(engine,p,int(p.tier)),true)
				if not c.is_empty():result.push_front(c)
			var spell=draw(engine,p,spells,false)
			if not spell.is_empty():result.append(spell)
		"TB_BaconShop_HP_077":
			var copies=p.previous_recruit_board.duplicate()
			if copies.size()>7:copies=engine.RNG.shuffle(copies,engine.state.streams,"shop"+str(p.id)).slice(0,7)
			for c in copies:result.append(engine.R132.original(engine,p,c))
			if result.size()<7:
				var spell=draw(engine,p,spells,false)
				if not spell.is_empty():result.append(spell)
		"hamul_fallback":
			var ids=fallback_pool(engine,p)
			for unused in 7:
				var c=draw(engine,p,ids,true)
				if not c.is_empty():result.append(c)
		_:return "UNKNOWN_REFRESH_POLICY"
	if result.is_empty():return "NO_LEGAL_CANDIDATE"
	p.shop=result;p.frozen=false
	engine.emit("ShopRefreshed",int(p.id),{"special":policy,"old":old_shop.map(func(c):return c.instance_id),"new":result.map(func(c):return c.instance_id)})
	engine.trinket_effects(p,"refresh");engine.Elementals.refresh(engine,p);engine.Quilboar.refresh(engine,p)
	engine.Demons.sort_shop(engine,p)
	engine.R133.refreshed(engine,p)
	return ""
static func fallback_pool(engine,p: Dictionary) -> Array:
	return ["BG27_080"] if int(p.tier)<=3 else minions(engine,p,int(p.tier),false,true)
static func outside(engine,c: Dictionary) -> bool:
	return not c.is_empty() and not engine.card_types(c).is_empty() and engine.Naga.types(engine,c).is_empty()
