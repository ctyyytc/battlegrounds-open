extends RefCounted
const RNG=preload("res://domain/rules/deterministic_rng.gd")
const Special=preload("res://domain/rules/special_rules.gd")

static func trinket_options(candidates: Array,excluded: Array,preference: String,streams: Dictionary) -> Array:
	var eligible=[]
	for d in candidates:
		if d.id not in excluded: eligible.append(d)
	if eligible.size()<4: return []
	var result=[]
	for i in 4:
		var weighted=[]
		for j in eligible.size():
			weighted.append(j)
			if preference in eligible[j].get("associated_pool_tribes",[]): weighted.append(j)
		var index=weighted[RNG.next(streams,"choice",weighted.size())]
		result.append({"id":eligible[index].id,"cost":int(eligible[index].cost),"bound_tribe":preference})
		eligible.remove_at(index)
	return result
static func gift_options(minions: Array,gifts: Array,turn: int,enabled: Array,excluded: Array,streams: Dictionary,policy: Dictionary={}) -> Array:
	var legal=gift_candidates(minions,gifts,turn,enabled,excluded,policy)
	if legal.size()<3 and not policy.get("special_free",false): return []
	if legal.is_empty():return []
	var result=[]
	var chosen=[]
	var preference=str(policy.get("guaranteed_tribe","")) if turn>=6 else ""
	if preference!="":
		var preferred=legal.filter(func(m):return minions.any(func(d):return d.id==m.id and (preference in d.card_types or "全部种族" in d.card_types)))
		
		
		if preferred.is_empty():return []
		var guaranteed=preferred[RNG.next(streams,"choice",preferred.size())]
		chosen.append(guaranteed);legal.erase(guaranteed)
	for i in range(mini(3-chosen.size(),legal.size())):
		
		var index=RNG.next(streams,"choice",legal.size())
		var m=legal.pop_at(index)
		chosen.append(m)
	var lowest=99
	for m in chosen:
		var definition=minions.filter(func(d):return d.id==m.id)[0]
		lowest=mini(lowest,int(definition.tier))
	for m in chosen:
		var definition=minions.filter(func(d):return d.id==m.id)[0]
		
		if int(definition.tier)!=lowest:m.gifts.erase(10)
		if m.gifts.is_empty():return []
		result.append({"id":m.id,"gift_id":m.gifts[RNG.next(streams,"choice",m.gifts.size())]})
	return result
static func gift_candidates(minions: Array,gifts: Array,turn: int,enabled: Array,excluded: Array,policy: Dictionary={}) -> Array:
	var legal=[]
	var seen=[];var excluded_bases=[]
	for m in minions:
		if m.id in excluded:excluded_bases.append(m.get("base_id",m.id))
	for m in minions:
		var base=m.get("base_id",m.id)
		if m.id in excluded or base in excluded_bases or base in seen: continue
		var ids=Special.gift_ids(m,gifts,turn,enabled,policy)
		if not ids.is_empty(): legal.append({"id":m.id,"gifts":ids});seen.append(base)
	return legal
static func refresh_cost(kind: String,global_count: int) -> int:
	return (1 if kind=="gift" else 2)+global_count
static func refresh_allowed(kind: String,local_count: int,global_count: int) -> bool:
	return global_count<3 and local_count<(2 if kind=="greater" else 1)

