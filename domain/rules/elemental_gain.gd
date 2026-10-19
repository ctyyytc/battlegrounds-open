extends RefCounted
static func extra(p: Dictionary) -> Vector2i:
	return Vector2i(int(p.get("elemental_bonus_attack",0)),int(p.get("elemental_bonus_health",0)))
static func applies(d: Dictionary,e: Dictionary={}) -> bool:
	return "元素" in d.get("card_types",[]) and e.get("op","")!="elemental_bonus"
static func value(d: Dictionary,p: Dictionary,base: Vector2i,e: Dictionary={}) -> Vector2i:
	return base+extra(p) if applies(d,e) else base
static func from_source(engine,p: Dictionary,base: Vector2i,e: Dictionary={},source: Dictionary={}) -> Vector2i:
	var c=source if not source.is_empty() else engine.effect_source
	return value(engine.content.get_def(str(c.get("def_id",c.get("id","")))),p,base,e)
static func ball_parts(d: Dictionary,p: Dictionary) -> Dictionary:
	var base=Vector2i(2,2) if d.get("base_id","")=="BG36_181" else Vector2i(1,0) if d.get("base_id","")=="BG31_816" else Vector2i(0,1)
	base*=2 if d.get("golden",false) else 1
	var history=base*int(p.get("ball_sold_count",0));var elemental=extra(p)
	return {"base":base,"history":history,"elemental":elemental,"total":base+history+elemental}
