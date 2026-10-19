extends RefCounted
const Registry=preload("res://domain/rules/content_registry.gd")
static func regular_tiers(turn: int) -> Array:
	if turn<3: return []
	if turn==3: return [2]
	if turn==4: return [2,3]
	if turn==5: return [3]
	if turn==6: return [3,4]
	if turn==7: return [4]
	if turn==8: return [4,5]
	if turn==9: return [4,5,6]
	return [5,6]
static func gift_ids(minion: Dictionary,gifts: Array,turn: int,enabled: Array,policy: Dictionary = {}) -> Array:
	var tiers=policy.get("tiers",regular_tiers(turn))
	if not int(minion.tier) in tiers or not Registry.eligible(minion,enabled): return []
	var result=[]
	var white=[]
	for id in minion.manual_gift_ids: white.append(int(id))
	for gift in gifts:
		if not int(gift.id) in white: continue
		if int(gift.id)==31 and int(minion.tier)==7:continue
		if int(gift.id)==39 and minion.get("base_id",minion.id)=="BG31_999":continue
		if not policy.get("ignore_windows",false):
			if turn<int(gift.min_turn): continue
			if gift.max_turn!=null and turn>int(gift.max_turn): continue
		if not gift_context(int(gift.id),policy,enabled):continue
		result.append(int(gift.id))
	return result
static func gift_context(id: int,policy: Dictionary,enabled: Array) -> bool:
	if id in [34,36] and "龙" in enabled:return false
	if id==7 and ("野猪人" in enabled or "纳迦" in enabled):return false
	var p=policy.get("player",{})
	if p.is_empty():return id not in [12,13,14,29,30,32]
	if id==21 and int(p.get("tier",1))<3:return false
	var counts=[int(p.get("battlecry_count",0)),int(p.get("deathrattle_count",0)),int(p.get("tavern_spell_count",0))]
	var index=0 if id in [12,29] else 1 if id in [13,30] else 2 if id in [14,32] else -1
	if index>=0:return counts[index]>0 and counts.all(func(n):return n<=counts[index])
	return true
static func preference(hand: Array,board: Array,defs: Dictionary,enabled: Array) -> String:
	var counts={}
	var board_counts={}
	for tribe in enabled: counts[tribe]=0; board_counts[tribe]=0
	for card in hand+board:
		var d=defs[card.def_id]
		if d.kind!="minion": continue
		for tribe in enabled:
			if tribe in card.get("type_override",d.card_types) or "全部种族" in card.get("type_override",d.card_types):
				counts[tribe]+=1
	for card in board:
		for tribe in enabled:
			if tribe in card.get("type_override",defs[card.def_id].card_types) or "全部种族" in card.get("type_override",defs[card.def_id].card_types): board_counts[tribe]+=1
	var best=[]
	var highest=0
	for tribe in enabled:
		if counts[tribe]>highest: best=[tribe]; highest=counts[tribe]
		elif counts[tribe]==highest and highest>0: best.append(tribe)
	if best.size()==1: return best[0]
	var tie=[]
	highest=0
	for tribe in best:
		if board_counts[tribe]>highest: tie=[tribe]; highest=board_counts[tribe]
		elif board_counts[tribe]==highest and highest>0: tie.append(tribe)
	return tie[0] if tie.size()==1 else ""
static func extra_casts(board: Array,defs: Dictionary,spell: Dictionary,friendly_target: bool) -> int:
	var extra=0
	for card in board:
		if spell.get("is_spellcraft",false) and not spell.get("naga_repeat_excluded",false) and card.get("gold_route","")=="纳迦": extra+=1
		if friendly_target:
			for e in defs[card.def_id].effects:
				if e.handler=="extra_cast": extra+=int(e.amount)
	return extra
static func capacity(board: Array) -> int:
	var n=7
	for card in board:
		if card.get("gold_route","")=="野兽": n+=1
	return mini(n,10)
static func eligible_routes(d: Dictionary,enabled: Array) -> Array:
	if not d.get("golden",false) or int(d.tier)<5 or "全部种族" in d.card_types: return []
	var result=[]
	for tribe in d.card_types:
		if tribe in enabled: result.append(tribe)
	return result
static func ice_stats(golden: bool,count: int,bonus_attack: int,bonus_health: int) -> Vector2i:
	var a=4 if golden else 2
	var h=2 if golden else 1
	return Vector2i(a,h)+count*ice_gain(golden,bonus_attack,bonus_health)
static func ice_gain(golden: bool,bonus_attack: int,bonus_health: int) -> Vector2i:
	return Vector2i((4 if golden else 2)+bonus_attack,(2 if golden else 1)+bonus_health)

