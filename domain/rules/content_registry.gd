extends RefCounted
const ExternalContent=preload("res://domain/resources/external_content.gd")
const Capabilities=preload("res://domain/rules/capability_registry.gd")
var pack: Dictionary
var definitions: Dictionary
var rules: Dictionary
var assets: Dictionary
var ui_assets: Dictionary={}
var hero_power_bindings: Dictionary={}
var trinket_bindings: Dictionary={}
var content_hash: String
var numeric_profile_hash: String
var power_sources: Dictionary={}
var quest_config: Dictionary={}
var errors: Array = []
var diagnostics: Array = []
func _init() -> void:
	var file = FileAccess.open("res://content/packs/catalog.json", FileAccess.READ)
	if file == null:
		errors.append("CATALOG_MISSING")
		return
	var raw = file.get_as_text()
	content_hash = raw.sha256_text()
	pack = JSON.parse_string(raw)
	definitions = pack.definitions
	rules = pack.rules
	assets = JSON.parse_string(FileAccess.get_file_as_string("res://content/packs/assets.json"))
	var ui_pack=JSON.parse_string(FileAccess.get_file_as_string("res://content/packs/ui_assets.json"))
	if ui_pack is Dictionary:
		for entry in ui_pack.get("assets",[]): ui_assets[str(entry.get("asset_key",""))]=entry
	hero_power_bindings=JSON.parse_string(FileAccess.get_file_as_string("res://content/packs/hero_power_ui_bindings.json"))
	trinket_bindings=JSON.parse_string(FileAccess.get_file_as_string("res://content/packs/trinket_ui_bindings.json"))
	if FileAccess.file_exists("res://content/packs/round132_sources.json"):power_sources=JSON.parse_string(FileAccess.get_file_as_string("res://content/packs/round132_sources.json"))
	quest_config=JSON.parse_string(FileAccess.get_file_as_string("res://content/packs/round135.json"))
	ExternalContent.apply(self)
	numeric_profile_hash=ExternalContent.numeric_hash(definitions)
	content_hash=(content_hash+":"+numeric_profile_hash).sha256_text()
	validate()
func validate() -> void:
	if int(pack.get("schema_version",0)) != 1: errors.append("UNSUPPORTED_SCHEMA")
	for id in definitions:
		var d = definitions[id]
		if d.id != id: errors.append("ID_MISMATCH:"+id)
		if d.kind == "minion":
			if int(d.health)<=0 or int(d.tier)<1 or int(d.tier)>7: errors.append("INVALID_STATS:"+id)
			if d.get("golden_id","") != "" and not definitions.has(d.golden_id): errors.append("MISSING_GOLDEN:"+id)
		if d.get("implemented",false):
			if d.has("cost") and int(d.cost)<0: errors.append("NEGATIVE_COST:"+id)
			for e in d.get("effects",[]):
				if e.has("amount") and (typeof(e.amount) not in [TYPE_INT,TYPE_FLOAT] or float(e.amount)<0 or floor(float(e.amount))!=float(e.amount)): errors.append("INVALID_AMOUNT:"+id+":"+str(e.get("handler","")))
				if e.has("id") and not definitions.has(str(e.id)): errors.append("MISSING_REFERENCE:"+id+":"+str(e.id))
				if not Capabilities.supports(d,e):
					var issue="UNSUPPORTED_CAPABILITY:"+id+":"+str(e.get("trigger","(none)"))+":"+str(e.get("handler",""))
					if d.kind=="dark_gift": diagnostics.append(issue)
					else: errors.append(issue)
func get_def(id: String) -> Dictionary:
	return definitions.get(id,{})
func pool(kind: String, enabled: Array, only_shop: bool = true) -> Array:
	var result = []
	for id in definitions:
		var d = definitions[id]
		if d.get("round132_excluded",false):continue
		if d.get("acquisition_policy","") in ["dependency_only","excluded_round6","excluded_round7","structural_alias","initial_power_only"]: continue
		
		
		if only_shop and d.kind=="spell" and d.get("generated_only",false): continue
		if only_shop and d.kind=="minion" and ((d.get("golden",false) and not d.get("unique_golden_shop",false)) or int(d.tier)>6): continue
		if d.kind == kind and d.implemented and (not only_shop or d.shop_pool) and eligible(d,enabled):
			result.append(id)
	result.sort()
	return result
static func eligible(d: Dictionary, enabled: Array) -> bool:
	var associated = d.get("associated_pool_tribes",[])
	if not associated.is_empty() and not intersects(associated,enabled): return false
	var card_types = d.get("card_types",[])
	return card_types.is_empty() or "全部种族" in card_types or intersects(card_types,enabled)
static func intersects(a: Array,b: Array) -> bool:
	for x in a:
		if x in b: return true
	return false
func art_path(id: String) -> String:
	for a in assets.values():
		if a.content_id == id and a.has("path"): return a.path
	return ""
func art_path_for_key(key: String) -> String:
	var entry=assets.get(key,{})
	return str(entry.get("path",""))
func hero_power_art(hero_id: String) -> String:
	var row=hero_power_binding(hero_id)
	return art_path_for_key(str(row.get("asset_key","")))
func hero_power_binding(hero_id: String) -> Dictionary:
	var definition=get_def(hero_id)
	var power_id=hero_id if definition.get("kind","")=="hero_power" else str(definition.get("initial_power_id",""))
	for row in hero_power_bindings.get("rows",[]):
		if str(row.get("content_id",""))==power_id:
			return row
	return {}
func trinket_binding(item_id: String) -> Dictionary:
	for row in trinket_bindings.get("rows",[]):
		if str(row.get("content_id",""))==item_id: return row
	return {}
func ui_asset(key: String) -> Dictionary:
	return ui_assets.get(key,{})

