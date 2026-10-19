extends RefCounted

static func perfect(engine,c: Dictionary,value: Vector2i) -> void:
	var previous=engine.stats(c)
	var retained=[]
	for modifier in c.modifiers:
		var layer=modifier.duplicate(true)
		layer.erase("attack");layer.erase("health")
		if layer.has("keyword") or layer.keys().any(func(k):return k not in ["duration","source"]):retained.append(layer)
	c.modifiers=retained
	c["base_override"]={"attack":value.x,"health":value.y}
	c.erase("reborn_base_health")
	c["gem_contributions"]=[]
	var delta=engine.stats(c)-previous;engine.R135.stat_gain(engine,c,delta.x,delta.y)
	engine.emit("AttributesReset",int(c.owner),{"instance_id":c.instance_id,"attack":value.x,"health":value.y,"policy":"BR-56 ordinary attributes and old target gem ledger; keywords/derived/aura retained"})
