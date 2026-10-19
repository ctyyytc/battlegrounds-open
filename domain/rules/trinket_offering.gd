extends RefCounted
const RNG=preload("res://domain/rules/deterministic_rng.gd")
static var cached={}
static var last_diagnostics={}
static func policy() -> Dictionary:
	if cached.is_empty():cached=JSON.parse_string(FileAccess.get_file_as_string("res://content/packs/trinket_offering_policy.json"))
	return cached
static func metadata(id: String) -> Dictionary:return policy().rows.get(id,{"types":[],"offer_mode":"neutral","sample_weight":2})
static func context(engine,p: Dictionary,size_value: String) -> Dictionary:
	var threshold=int(policy().membership_threshold[size_value]);var counts={};var board_counts={};var no_type=0;var distinct=[]
	for tribe in engine.state.enabled_tribes:counts[tribe]=0;board_counts[tribe]=0
	for zone in ["hand","board"]:
		for c in p[zone]:
			if engine.content.get_def(c.def_id).kind!="minion":continue
			var types=engine.card_types(c)
			if types.is_empty():no_type+=1
			for tribe in engine.state.enabled_tribes:
				if tribe in types or "全部种族" in types:
					counts[tribe]+=1
					if zone=="board":board_counts[tribe]+=1
	for tribe in counts:
		if int(counts[tribe])>0:distinct.append(tribe)
	var in_types=[]
	for tribe in counts:
		if int(counts[tribe])>=threshold:in_types.append(tribe)
	var hero_types=policy().hero_types.get(str(p.hero_id),[]).duplicate()
	for slot in p.get("power_slots",[]):
		for hero in policy().hero_types:
			if engine.content.get_def(hero).get("initial_power_id","")==slot.active_power_id:hero_types.append_array(policy().hero_types[hero])
	for tribe in hero_types:
		if counts.has(tribe) and tribe not in in_types:in_types.append(tribe)
	if distinct.size()>=3:in_types.append("MENAGERIE")
	if no_type>=3:in_types.append("NONE")
	var main_candidates=[];var highest=-1;var highest_board=-1
	for tribe in in_types:
		if tribe in ["MENAGERIE","NONE"]:continue
		var total=int(counts[tribe]);var on_board=int(board_counts[tribe])
		if total>highest or total==highest and on_board>highest_board:highest=total;highest_board=on_board;main_candidates=[tribe]
		elif total==highest and on_board==highest_board:main_candidates.append(tribe)
	if no_type>=3 and no_type>highest:main_candidates=["NONE"]
	if main_candidates.is_empty() and "MENAGERIE" in in_types:main_candidates=["MENAGERIE"]
	return {"size":size_value,"threshold":threshold,"counts":counts,"board_counts":board_counts,"in_types":in_types,"main_candidates":main_candidates,"main_type":"","no_type_count":no_type,"distinct_types":distinct}
static func in_affinity(types: Array,ctx: Dictionary) -> bool:return types.any(func(t):return t in ctx.in_types)
static func condition(engine,p: Dictionary,rule: String) -> bool:
	match rule:
		"no_demon_lobby":return "恶魔" not in engine.state.enabled_tribes
		"under_five_minions":return (p.hand+p.board).filter(func(c):return engine.content.get_def(c.def_id).kind=="minion").size()<5
		"board_tier_three":return p.board.any(func(c):return int(engine.content.get_def(c.def_id).get("tier",0))==3)
		"health_under_sixteen":return int(p.health)+int(p.armor)<16
		"health_rewinder":return p.board.any(func(c):return not engine.Demons.specs(engine,c,"rewind").is_empty() or not engine.Demons.specs(engine,c,"corrosion").is_empty())
		"baller_sold":return int(p.get("ball_sold_count",0))>0
		"multiple_battlecries":return int(p.get("battlecry_count",0))>=2
	return true
static func eligible(engine,p: Dictionary,d: Dictionary,ctx: Dictionary) -> bool:
	var meta=metadata(d.id);var types=meta.types
	if not types.is_empty() and not types.any(func(t):return t in engine.state.enabled_tribes or t in ["MENAGERIE","NONE"]):return false
	if meta.offer_mode=="requires_in" and not in_affinity(types,ctx):return false
	if not condition(engine,p,str(meta.get("condition",""))):return false
	return true
static func quote(d: Dictionary,ctx: Dictionary) -> Dictionary:
	var meta=metadata(d.id);var discount=0
	if meta.offer_mode=="pivot" and not in_affinity(meta.types,ctx):discount=int(policy().pivot_discount)
	var final_cost=maxi(int(policy().min_price),int(d.cost)-discount)
	return {"id":d.id,"base_cost":int(d.cost),"cost":final_cost,"pivot_discount":int(d.cost)-final_cost,"pivot_discount_limit":discount,"bound_tribe":str(ctx.main_type) if ctx.main_type in ctx.counts else "","offering_types":meta.types.duplicate(),"offering_group":meta.get("exclusive_group",""),"sample_weight":int(meta.sample_weight),"policy_revision":policy().policy_revision}
static func compatible(option: Dictionary,selected: Array,ctx: Dictionary) -> bool:
	for prior in selected:
		if prior.id==option.id:return false
		if "MENAGERIE" in option.offering_types and "MENAGERIE" in prior.offering_types:return false
		if option.offering_group!="" and option.offering_group==prior.offering_group:return false
		for tribe in option.offering_types:
			if tribe!=ctx.main_type and tribe in prior.offering_types:return false
	return true
static func neutral(o: Dictionary) -> bool:return o.offering_types.is_empty()
static func main_match(o: Dictionary,ctx: Dictionary) -> bool:
	return neutral(o) if ctx.main_type=="NONE" else ctx.main_type in o.offering_types
static func search(pool: Array,chosen: Array,ctx: Dictionary,requirements: Dictionary) -> Array:
	var need_main=requirements.main and not chosen.any(func(o):return main_match(o,ctx))
	var need_neutral=requirements.neutral and not chosen.any(func(o):return neutral(o))
	var need_cheap=requirements.cheap and not chosen.any(func(o):return int(o.cost)<=2)
	if chosen.size()==4:return chosen if not need_main and not need_neutral and not need_cheap else []
	var candidates=pool.filter(func(o):return compatible(o,chosen,ctx) and (main_match(o,ctx) if need_main else neutral(o) if need_neutral else int(o.cost)<=2 if need_cheap else true))
	for option in candidates:
		var found=search(pool,chosen+[option],ctx,requirements)
		if found.size()==4:return found
	return []
static func generate(engine,p: Dictionary,size_value: String,excluded: Array) -> Array:
	var previous_choice=engine.state.streams.choice
	var ctx=context(engine,p,size_value)
	if not ctx.main_candidates.is_empty():ctx.main_type=ctx.main_candidates[RNG.next(engine.state.streams,"choice",ctx.main_candidates.size())] if ctx.main_candidates.size()>1 else ctx.main_candidates[0]
	var candidates=[];var owned=p.trinkets.map(func(t):return t.id)
	for d in engine.content.definitions.values():
		if d.kind!="trinket" or d.size!=size_value or not d.implemented or d.get("round132_excluded",false) or d.get("acquisition_policy","") in ["dependency_only","excluded_round6","excluded_round7","structural_alias","initial_power_only"]:continue
		if d.id in owned or d.id in excluded or not engine.R13Items.allowed(engine,p,d) or not eligible(engine,p,d,ctx):continue
		candidates.append(quote(d,ctx))
	if candidates.size()<4:
		last_diagnostics={"reason":"fewer_than_four_eligible","context":ctx,"eligible":candidates.size()};engine.state.streams.choice=previous_choice;return []
	candidates.sort_custom(func(a,b):return a.id<b.id)
	var ordered=[]
	while not candidates.is_empty():
		var total=0
		for option in candidates:total+=int(option.sample_weight)
		var roll=RNG.next(engine.state.streams,"choice",total);var index=0
		for i in candidates.size():
			roll-=int(candidates[i].sample_weight)
			if roll<0:index=i;break
		ordered.append(candidates.pop_at(index))
	var requirements={"main":ctx.main_type!="" and ordered.any(func(o):return main_match(o,ctx)),"neutral":ordered.any(func(o):return neutral(o)),"cheap":ordered.any(func(o):return int(o.cost)<=2)}
	var result=search(ordered,[],ctx,requirements)
	ctx["unavailable_guarantees"]=[]
	for requirement in requirements:
		if not requirements[requirement]:ctx.unavailable_guarantees.append(requirement+":no_eligible_candidate")
	last_diagnostics={"reason":"ok" if result.size()==4 else "incompatible_constraints","context":ctx,"eligible":ordered.size(),"guarantees":requirements}
	if result.is_empty():engine.state.streams.choice=previous_choice;return []
	# Randomize display positions after constraints, keeping quote/context frozen.
	result=RNG.shuffle(result,engine.state.streams,"choice")
	for option in result:option["offering_context"]=ctx.duplicate(true);option["guarantees"]=requirements.duplicate(true)
	return result
