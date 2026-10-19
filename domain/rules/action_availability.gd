extends RefCounted

static func power(engine, player: Dictionary,slot_id: int=0) -> Dictionary:
	var old=engine.power_context.get(int(player.get("id",-1)),0)
	engine.power_context[int(player.get("id",-1))]=slot_id
	var result=selected_power(engine,player)
	engine.power_context[int(player.get("id",-1))]=old
	return result
static func selected_power(engine, player: Dictionary) -> Dictionary:
	if player.is_empty(): return {"available":false,"reason":"INVALID_PLAYER","targets":[]}
	if engine.state.phase!="recruit" or not player.alive: return {"available":false,"reason":"WRONG_PHASE","targets":[]}
	if not player.choices.is_empty(): return {"available":false,"reason":"MANDATORY_CHOICE","targets":[]}
	if engine.power_definition(player).get("id","")=="BG30_HERO_304p":return {"available":engine.R13Items.available(engine,player,"marin"),"reason":"" if engine.R13Items.available(engine,player,"marin") else "POWER_NOT_READY","targets":[],"cost":0}
	var op=engine.R136Slots.power_op(engine,player,int(engine.Powers.selected(engine,player).get("slot_id",0)))
	if op!="":return {"available":true,"reason":"","targets":[],"cost":0}
	var h=engine.power_definition(player)
	var handler=engine.hero_handler(player)
	if h.get("id","") in [engine.R134.POWER,engine.R135.POWER]:return {"available":false,"reason":"PASSIVE_POWER","targets":[],"cost":0}
	var r133=engine.R133.query(engine,player)
	if not r133.is_empty():return r133
	var r132=engine.R132.query(engine,player)
	if not r132.is_empty():return r132
	var round12=engine.Beasts.availability(engine,player)
	if not round12.is_empty():return round12
	var round11=engine.Fish.availability(engine,player)
	if not round11.is_empty():return round11
	var round10=engine.Demons.availability(engine,player)
	if not round10.is_empty():return round10
	var round9=engine.Pirates.power_availability(engine,player)
	if not round9.is_empty():return round9
	var round7=engine.Heroes7.availability(engine,player)
	if not round7.is_empty():return round7
	if handler in ["patchwerk","upgrade_coins","alakir"]: return {"available":false,"reason":"PASSIVE_POWER","targets":[]}
	if engine.power_used(player) or (handler=="golden" and engine.power_used(player,true)): return {"available":false,"reason":"POWER_ALREADY_USED","targets":[]}
	if int(player.coins)<engine.power_cost(player): return {"available":false,"reason":"NOT_ENOUGH_COINS","targets":[]}
	var targets=[]
	match handler:
		"xyrella":
			if player.hand.size()>=16: return {"available":false,"reason":"HAND_FULL","targets":[]}
			targets=_minion_ids(engine,player.shop)
		"reborn":
			
			targets=_minion_ids(engine,player.board)+_minion_ids(engine,player.shop)
		"golden": targets=_minion_ids(engine,player.board)
		"coin_cap","random_spell": pass
		_: return {"available":false,"reason":"POWER_NOT_IMPLEMENTED","targets":[]}
	if handler in ["xyrella","reborn","golden"] and targets.is_empty():
		return {"available":false,"reason":"NO_LEGAL_TARGET","targets":[]}
	if handler=="random_spell" and engine.random_power_spells(player).is_empty():
		return {"available":false,"reason":"NO_LEGAL_CANDIDATE","targets":[]}
	return {"available":true,"reason":"","targets":targets,"handler":handler,"cost":engine.power_cost(player)}

static func _minion_ids(engine, cards: Array) -> Array:
	var result=[]
	for card in cards:
		if engine.content.get_def(str(card.get("def_id",""))).get("kind","")=="minion": result.append(int(card.instance_id))
	return result

static func legal_power_target(engine, player: Dictionary, target_id: int, handler: String="") -> bool:
	var state=selected_power(engine,player)
	if not state.available: return false
	if handler.is_empty(): handler=str(state.get("handler",""))
	if int(target_id) not in state.targets: return false
	var card=engine.find_target(player,int(target_id))
	if card.is_empty(): return false
	if handler=="xyrella": return engine.find_index(player.shop,int(target_id))>=0
	if handler=="teron":return engine.find_index(player.board,int(target_id))>=0
	if handler=="hooktusk":return engine.find_index(player.board,int(target_id))>=0
	if handler=="golden": return engine.find_index(player.board,int(target_id))>=0
	return handler=="reborn" and (engine.find_index(player.board,int(target_id))>=0 or engine.find_index(player.shop,int(target_id))>=0)

static func fast_action(engine,player: Dictionary,zone: String,card: Dictionary,right_click: bool,level: int=1) -> Dictionary:
	if engine.content.get_def(card.def_id).get("unplayable",false):return {"manual":true,"reason":"CARD_UNPLAYABLE"}
	var id=int(card.get("instance_id",-1))
	if right_click and zone=="board": return {"kind":"sell","payload":{"instance_id":id,"right_click":true}}
	if zone!="hand": return {}
	var d=engine.play_definition(card)
	
	if d.kind=="spell" and not engine.Fast.classify(engine,player,card).reasons.is_empty():
		return {"noop":true} if right_click else {}
	if right_click and level==2:
		var classification=engine.Fast.classify(engine,player,card,d.kind=="minion")
		if not classification.reasons.is_empty():return {"noop":true}
		if classification.unknown_dynamic:return {"manual":true,"instance_id":id,"reason":"FAST_EFFECT_REQUIRES_MANUAL"}
	if d.get("kind","")=="minion" and right_click and level==2:return {"kind":"fast_play_sell","payload":{"instance_id":id}}
	if d.get("kind","")=="minion" and not right_click:
		if engine.requires_battlecry_target(d): return {"manual":true,"instance_id":id}
		return {"kind":"play","payload":{"instance_id":id,"index":player.board.size()}}
	if d.get("kind","")!="spell": return {}
	var targeted=not d.get("effects",[]).is_empty() and str(d.effects[0].get("target","none")) in ["minion","friendly_minion","friendly_undead"]
	if targeted:
		if player.board.is_empty(): return {"manual":true,"reason":"NO_FRIENDLY_ENDPOINT","instance_id":id,"right_click":right_click and level==2}
		var target=player.board[0] if not right_click else player.board[player.board.size()-1]
		return {"kind":"fast_play" if level==2 and right_click else "play","payload":{"instance_id":id,"target_id":int(target.instance_id),"right_click":right_click},"manual_on_reject":true,"instance_id":id,"endpoint":"left" if not right_click else "right"}
	if level==2 and right_click:return {"kind":"fast_play","payload":{"instance_id":id,"right_click":true}}
	if not right_click:return {"kind":"play","payload":{"instance_id":id}}
	return {"manual":true,"reason":"RIGHT_CLICK_CANCEL"}

static func action(engine, pid: int, kind: String, payload: Dictionary={}) -> Dictionary:
	return engine.preview_action(pid,kind,payload)
