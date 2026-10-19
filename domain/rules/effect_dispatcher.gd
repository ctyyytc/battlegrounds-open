extends RefCounted
"""Executes the generic recruit-time effect vocabulary against the existing MatchEngine services."""
const RNG=preload("res://domain/rules/deterministic_rng.gd")
const Attributes=preload("res://domain/rules/spell_attributes.gd")
const Gain=preload("res://domain/rules/elemental_gain.gd")

static func execute(engine, p: Dictionary, effect_spec: Dictionary, target: Dictionary) -> bool:
	if effect_spec.get("handler","")=="gift_deathrattle":
		engine.Gifts.death(engine,p,target);return true
	if effect_spec.get("handler","")=="round133" and effect_spec.get("op","")==engine.R133.TOKEN:
		engine.R133.token_play(engine,p,engine.effect_source);return true
	if engine.R136.execute(engine,p,effect_spec,target):return true
	if engine.R135.execute(engine,p,effect_spec,target):return true
	if engine.R134.execute(engine,p,effect_spec,target):return true
	if engine.R13Items.execute(engine,p,effect_spec,target):return true
	if engine.R13.execute(engine,p,effect_spec,target):return true
	if engine.Beasts.execute(engine,p,effect_spec,target):return true
	if engine.Fish.execute(engine,p,effect_spec,target):return true
	if engine.Demons.execute(engine,p,effect_spec,target):return true
	if engine.Pirates.execute(engine,p,effect_spec,target):return true
	if preload("res://domain/rules/quilboar_rules.gd").execute(engine,p,effect_spec,target):return true
	if preload("res://domain/rules/naga_rules.gd").execute(engine,p,effect_spec,target):return true
	if effect_spec.get("handler","")=="dark_gift":
		if target.is_empty():return false
		engine.Gifts.acquire(engine,p,target,int(effect_spec.numeric_id),"effect");return true
	if preload("res://domain/rules/elemental_trinkets.gd").execute(engine,p,effect_spec,target): return true
	if preload("res://domain/rules/elemental_rules.gd").execute(engine,p,effect_spec,target): return true
	if preload("res://domain/rules/undead_rules.gd").execute(engine,p,effect_spec,target): return true
	match str(effect_spec.get("handler","")):
		"grow_self","buff":
			if effect_spec.get("trigger","")=="battlecry" and effect_spec.get("target","") in ["minion","friendly_minion","friendly_undead"]: target=engine.effect_target
			if target.is_empty(): return false
			var value=Attributes.value(engine.current_spell,effect_spec,p)
			var duration="next_turn" if engine.current_spell.get("is_spellcraft",false) and not engine.current_spell.get("permanent_spellcraft",false) else "permanent"
			var scale=int(engine.current_spell.get("spellcraft_scale",1))
			for unused in int(effect_spec.get("repeat",1)):
				var gain=Gain.from_source(engine,p,value*scale,effect_spec)
				engine.buff(target,gain.x,gain.y,duration)
			if effect_spec.has("keyword"): engine.add_keyword(target,str(effect_spec.keyword),duration)
		"next_coins": p.next_coins+=int(effect_spec.amount)
		"coins": engine.gain_coins(p,int(effect_spec.amount))
		"coin_cap": engine.increase_coin_cap(p,int(effect_spec.get("amount",1)))
		"free_refresh": p.free_refresh+=int(effect_spec.amount)
		"undead_attack": preload("res://domain/rules/undead_rules.gd").add_global(engine,p,int(effect_spec.amount))
		"give":
			if not engine.content.definitions.has(str(effect_spec.get("id",""))): return false
			for i in int(effect_spec.amount): engine.receive_card(p,engine.make_card(str(effect_spec.id),int(p.id)),engine.effect_source)
		"generate":
			var options=engine.generation_candidates(p,effect_spec,engine.effect_source)
			if options.is_empty(): return true
			for i in int(effect_spec.get("amount",1)):
				engine.receive_card(p,engine.make_card(options[RNG.next(engine.state.streams,"effects",options.size())],int(p.id)),engine.effect_source)
		"upgrade_discount": p.upgrade_cost=maxi(0,int(p.upgrade_cost)-int(effect_spec.amount))
		"board_buff":
			for c in p.board:
				if not effect_spec.has("tribe") or effect_spec.tribe in engine.content.get_def(c.def_id).card_types or "全部种族" in engine.content.get_def(c.def_id).card_types:
					var gain=Gain.from_source(engine,p,Vector2i(int(effect_spec.get("attack",0)),int(effect_spec.get("health",0))),effect_spec);engine.buff(c,gain.x,gain.y)
		"hand_left_buff":
			for c in p.hand:
				if engine.content.get_def(c.def_id).kind=="minion":
					engine.buff(c,int(effect_spec.get("attack",0)),int(effect_spec.get("health",0))); break
		"shop_buff":
			var value=Attributes.value(engine.current_spell,effect_spec,p)
			var duration="next_turn" if engine.current_spell.get("is_spellcraft",false) and not engine.current_spell.get("permanent_spellcraft",false) else "permanent"
			var source=str(engine.current_spell.get("id",engine.effect_source.get("def_id","")))
			var key="shop_all:"+str(p.id)+":"+str(engine.state.event_seq)
			var targets=[]
			for c in p.shop:
				if engine.content.get_def(c.def_id).kind=="minion" and not engine.Beasts.immune(engine,c):
					engine.buff(c,value.x,value.y,duration,source)
					c.modifiers[-1]["shop_scope_key"]=key
					targets.append(int(c.instance_id))
					if not c.has("shop_general_once"):c["shop_general_once"]=[]
					c.shop_general_once.append({"attack":value.x,"health":value.y,"source":source,"scope":"shop_all","expires":int(engine.state.round)+1 if duration=="next_turn" else 2147483647})
			preload("res://domain/rules/shop_bonus.gd").record(engine,p,targets,value,source,duration,key)
		_: return false
	return true
