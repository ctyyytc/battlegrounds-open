extends RefCounted

static func base(effect: Dictionary) -> Vector2i:
	if effect.get("handler","")=="slaughter": return Vector2i(int(effect.get("amount",5)),0)
	return Vector2i(int(effect.get("attack",0)),int(effect.get("health",0)))
static func eligible(spell: Dictionary,effect: Dictionary) -> bool:
	var handler=str(effect.get("handler",""))
	if handler=="round11" and spell.get("id","")=="BG35_149":return spell.get("is_tavern_spell",false) and effect.get("op","")=="deep"
	if handler=="round10":return spell.get("is_tavern_spell",false) and effect.get("op","")=="perfect"
	if handler=="round6" and spell.get("id","")=="BG34_444":return effect.get("op","")=="refresh_growth"
	if handler=="round9":return spell.get("is_tavern_spell",false) and effect.get("op","") in ["pants","shop_growth","seafood","bounty_buff","left_buff","golden_buff","favor"]
	if handler=="round8":return spell.get("is_tavern_spell",false) and effect.get("op","") in ["target_buff","board_buff","random_buff","bread","time_delay","barrage"]
	if handler=="round7":return spell.get("is_tavern_spell",false) and effect.get("op","") in ["target_buff","board_spell","queen","tide","nature"]
	if handler=="slaughter": return true
	if handler=="shop_buff": return true
	if handler in ["buff","grow_self","menagerie"]:
		return spell.get("is_tavern_spell",false) and (handler=="menagerie" or base(effect)!=Vector2i.ZERO)
	return false
static func bonus(spell: Dictionary,effect: Dictionary,player: Dictionary) -> Vector2i:
	if not eligible(spell,effect): return Vector2i.ZERO
	return Vector2i(int(player.get("spell_bonus_attack",0))+int(spell.get("aura_attack",0)),int(player.get("spell_bonus_health",0))+int(spell.get("aura_health",0)))
static func value(spell: Dictionary,effect: Dictionary,player: Dictionary) -> Vector2i:
	return base(effect)+bonus(spell,effect,player)
