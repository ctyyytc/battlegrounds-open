extends RefCounted
"""Explicit map from content handlers to the runtime consumer that executes them."""

const CAPABILITIES := {
	"dark_gift": {"kinds":["dark_gift"],"triggers":[""],"consumer":"dark_gift_rules","target":"source_minion","params":["numeric_id"]},
	
	"grow_self": {"kinds":["minion"],"triggers":["minion_played","minion_sold","rally"],"consumer":"recruit_effect","target":"source_minion","params":["attack","health"]},
	"buff": {"kinds":["spell","trinket"],"triggers":["","spell_cast"],"consumer":"recruit_effect","target":"minion","params":["attack","health","keyword"]},
	"next_coins": {"kinds":["minion","spell"],"triggers":["battlecry",""],"consumer":"recruit_effect","target":"none","params":["amount"]},
	"coins": {"kinds":["spell","trinket"],"triggers":["","obtain"],"consumer":"recruit_effect","target":"none","params":["amount"]},
	"coin_cap": {"kinds":["hero","hero_power","spell","trinket"],"triggers":["","turn_end","obtain"],"consumer":"recruit_effect","target":"none","params":["amount"]},
	"free_refresh": {"kinds":["minion","spell","trinket"],"triggers":["battlecry","minion_played","obtain",""],"consumer":"recruit_effect","target":"none","params":["amount"]},
	"undead_attack": {"kinds":["minion","trinket"],"triggers":["battlecry","rally","turn_end","tavern_spell_cast"],"consumer":"recruit_effect","target":"none","params":["amount"]},
	"give": {"kinds":["minion","trinket","spell"],"triggers":["","battlecry","deathrattle","obtain","obtain_and_start"],"consumer":"recruit_effect","target":"none","params":["id","amount"]},
	"generate": {"kinds":["minion","spell","trinket"],"triggers":["battlecry","deathrattle","obtain","obtain_and_start",""],"consumer":"recruit_effect","target":"none","params":[]},
	"upgrade_discount": {"kinds":["trinket"],"triggers":["obtain_and_start","refresh"],"consumer":"recruit_effect","target":"none","params":["amount"]},
	"board_buff": {"kinds":["trinket"],"triggers":["tavern_spell_cast"],"consumer":"recruit_effect","target":"board","params":["attack","health","tribe"]},
	"hand_left_buff": {"kinds":["trinket"],"triggers":["minion_played"],"consumer":"recruit_effect","target":"hand_minion","params":["attack","health"]},
	"shop_buff": {"kinds":["spell"],"triggers":[""],"consumer":"recruit_effect","target":"shop","params":["attack","health"]},
	
	"xyrella": {"kinds":["hero","hero_power"],"triggers":[""],"consumer":"hero_power","target":"shop_minion","params":[]},
	"random_spell": {"kinds":["hero","hero_power"],"triggers":[""],"consumer":"hero_power","target":"none","params":[]},
	"golden": {"kinds":["hero","hero_power"],"triggers":[""],"consumer":"hero_power","target":"board_minion","params":[]},
	"reborn": {"kinds":["hero","hero_power"],"triggers":[""],"consumer":"hero_power","target":"friendly_minion","params":[]},
	"coin_cap_power": {"kinds":["hero","hero_power"],"triggers":[""],"consumer":"hero_power","target":"none","params":[]},
	"patchwerk": {"kinds":["hero","hero_power"],"triggers":[""],"consumer":"passive_power","target":"none","params":[]},
	"upgrade_coins": {"kinds":["hero","hero_power"],"triggers":[""],"consumer":"passive_power","target":"none","params":[]},
	"alakir": {"kinds":["hero","hero_power"],"triggers":[""],"consumer":"passive_power","target":"none","params":[]},
	
	"elemental_counter": {"kinds":["minion"],"triggers":["derived"],"consumer":"derived_stats","target":"self","params":[]},
	"extra_cast": {"kinds":["minion"],"triggers":["passive"],"consumer":"cast_rules","target":"none","params":["amount"]},
	"attack_immune": {"kinds":["minion"],"triggers":["passive"],"consumer":"combat_rules","target":"self","params":[]},
	"tribe_attack": {"kinds":["trinket"],"triggers":["aura"],"consumer":"derived_stats","target":"tribe","params":["tribe","amount"]},
	"summon": {"kinds":["minion"],"triggers":["deathrattle"],"consumer":"combat_effect","target":"none","params":["id","amount"]},
	
	"card_attack": {"kinds":["dark_gift"],"triggers":[""],"consumer":"dark_gift_rules","target":"none","params":[]},
	"combat_copy": {"kinds":["dark_gift"],"triggers":[""],"consumer":"dark_gift_rules","target":"none","params":[]},
	"death_refresh": {"kinds":["dark_gift"],"triggers":[""],"consumer":"dark_gift_rules","target":"none","params":[]},
	"death_spell": {"kinds":["dark_gift"],"triggers":[""],"consumer":"dark_gift_rules","target":"none","params":[]},
	"extra_copy": {"kinds":["dark_gift"],"triggers":[""],"consumer":"dark_gift_rules","target":"none","params":[]},
	"harpy": {"kinds":["dark_gift"],"triggers":[""],"consumer":"dark_gift_rules","target":"none","params":[]},
	"periodic_copy": {"kinds":["dark_gift"],"triggers":[""],"consumer":"dark_gift_rules","target":"none","params":[]},
	"half_attack_health": {"kinds":["trinket"],"triggers":["combat_start"],"consumer":"combat_effect","target":"board","params":[]},
}

static func describe(handler: String) -> Dictionary:
	return CAPABILITIES.get(handler, {})

static func supports(definition: Dictionary, effect: Dictionary) -> bool:
	if preload("res://domain/rules/round136_rewards.gd").supports(definition,effect):return true
	if preload("res://domain/rules/round135_quests.gd").supports(definition,effect):return true
	if preload("res://domain/rules/round134_prizes.gd").supports(definition,effect):return true
	if preload("res://domain/rules/round133_rules.gd").supports(definition,effect):return true
	if preload("res://domain/rules/round132_powers.gd").supports(definition,effect):return true
	if preload("res://domain/rules/round13_trinkets.gd").supports(definition,effect):return true
	if preload("res://domain/rules/round13_minions.gd").supports(definition,effect):return true
	if preload("res://domain/rules/beast_rules.gd").supports(definition,effect):return true
	if preload("res://domain/rules/murloc_rules.gd").supports(definition,effect):return true
	if preload("res://domain/rules/demon_rules.gd").supports(definition,effect):return true
	if preload("res://domain/rules/pirate_rules.gd").supports(definition,effect):return true
	if preload("res://domain/rules/quilboar_rules.gd").supports(definition,effect):return true
	if preload("res://domain/rules/naga_rules.gd").supports(definition,effect):return true
	if preload("res://domain/rules/round7_heroes.gd").supports(definition,effect):return true
	if definition.kind=="dark_gift" and effect.get("handler","")=="dark_gift": return int(effect.get("numeric_id",0)) in range(1,45)
	if definition.kind=="minion" and effect.get("handler","")=="automaton_counter": return effect.get("trigger","")=="derived"
	if preload("res://domain/rules/elemental_trinkets.gd").supports(definition,effect): return true
	if preload("res://domain/rules/elemental_rules.gd").supports(definition,effect): return true
	if preload("res://domain/rules/undead_rules.gd").supports(definition,effect): return true
	var handler=str(effect.get("handler", ""))
	var spec=describe(handler)
	if spec.is_empty() or str(spec.get("consumer", ""))=="unimplemented": return false
	if str(definition.get("kind", "")) not in spec.kinds: return false
	if str(effect.get("trigger", "")) not in spec.triggers: return false
	if handler=="coin_cap" and str(definition.get("kind", "")) in ["hero","hero_power"]: return str(effect.get("trigger",""))=="" and str(effect.get("target","none"))=="none"
	var target=str(effect.get("target", spec.target))
	if target not in [spec.target,"none"]: return false
	for key in spec.params:
		if not effect.has(key):
			
			if key in ["attack","health","keyword"]: continue
			return false
	if effect.has("amount"):
		if typeof(effect.amount) not in [TYPE_INT,TYPE_FLOAT] or float(effect.amount)<0 or floor(float(effect.amount))!=float(effect.amount): return false
	for key in ["attack","health"]:
		if effect.has(key) and typeof(effect[key]) not in [TYPE_INT,TYPE_FLOAT]: return false
	return true
