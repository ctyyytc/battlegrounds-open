extends RefCounted


static func record(engine,p: Dictionary,targets: Array,value: Vector2i,source: String,duration: String,key: String) -> void:
	var current=p.shop.filter(func(c):return engine.content.get_def(c.def_id).kind=="minion" and not engine.Beasts.immune(engine,c)).map(func(c):return int(c.instance_id))
	var layers=p.get("shop_general_layers",[]).filter(func(m):return int(m.get("expires",2147483647))>int(engine.state.round) and m.get("targets",[]).any(func(id):return int(id) in current))
	if not targets.is_empty():
		layers.append({"scope":"shop_all","key":key,"targets":targets.duplicate(),"attack":value.x,"health":value.y,"source":source,"expires":int(engine.state.round)+1 if duration=="next_turn" else 2147483647})
	p["shop_general_layers"]=layers
static func current(engine,p: Dictionary) -> Vector2i:
	var targets=p.shop.filter(func(c):return engine.content.get_def(c.def_id).kind=="minion" and not engine.Beasts.immune(engine,c))
	var result=Vector2i.ZERO
	if targets.is_empty():return result
	for layer in p.get("shop_general_layers",[]):
		if layer.get("scope","")!="shop_all" or int(layer.get("expires",2147483647))<=int(engine.state.round):continue
		if targets.all(func(c):return layer.get("targets",[]).any(func(target):return int(target)==int(c.instance_id)) and c.modifiers.any(func(m):return m.get("shop_scope_key","")==layer.get("key","") and m.has("attack") and m.has("health"))):
			result+=Vector2i(int(layer.attack),int(layer.health))
	return result
