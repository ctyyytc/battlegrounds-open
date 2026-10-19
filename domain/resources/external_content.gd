extends RefCounted
const PackStore=preload("res://domain/resources/resource_pack_store.gd")
# Local data only: typed base values and presentation; effects are never imported.
static var cached_pack: Dictionary = {}
static var pack_loaded: bool = false
static var pack_directory: String = ""
static var diagnostics: Array = []
static var schema_cache: Dictionary = {}

static func schema() -> Dictionary:
	if schema_cache.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://content/packs/resource_schema.json"))
		if parsed is Dictionary: schema_cache = parsed
	return schema_cache

static func reset() -> void:
	cached_pack = {}; pack_loaded = false; pack_directory = ""; diagnostics = []

static func integer_value(value: Variant, bounds: Array) -> bool:
	return (typeof(value) in [TYPE_INT, TYPE_FLOAT]) and is_finite(float(value)) and floor(float(value)) == float(value) and float(value) >= float(bounds[0]) and float(value) <= float(bounds[1])

static func placeholders(value: String) -> Array:
	var regex = RegEx.new(); regex.compile("\\{([A-Za-z_][A-Za-z0-9_.]*)\\}")
	var result: Array = []
	for found in regex.search_all(value): result.append(found.get_string(1))
	return result

static func template_valid(value: Variant, allowed: Array) -> bool:
	if not value is String: return false
	var remaining = value.replace("{{", "").replace("}}", "")
	var regex = RegEx.new(); regex.compile("\\{([A-Za-z_][A-Za-z0-9_.]*)\\}")
	for key in placeholders(remaining):
		if key not in allowed: return false
	remaining = regex.sub(remaining, "", true)
	return "{" not in remaining and "}" not in remaining

static func format_tokens(value: String) -> Array:
	var regex = RegEx.new(); regex.compile("%(?:[-+ #0]*[0-9]*(?:\\.[0-9]+)?[sdifxXoucCgGevV]|%)")
	var result: Array = []
	for found in regex.search_all(value): result.append(found.get_string())
	return result

static func formats_valid(value: String, expected: Array) -> bool:
	if format_tokens(value) != expected: return false
	if expected.is_empty(): return true
	var regex=RegEx.new();regex.compile("%(?:[-+ #0]*[0-9]*(?:\\.[0-9]+)?[sdifxXoucCgGevV]|%)")
	return "%" not in regex.sub(value,"",true)

static func validate_row(id: String, row: Variant, version: int) -> bool:
	var contract = schema().get("definitions", {}).get(id, {})
	if contract.is_empty() or not row is Dictionary: return false
	for field in row:
		if field not in contract.fields or (version == 1 and field not in ["name", "text"]): return false
		if field in ["name", "text"]:
			if not row[field] is String and not (version == 2 and field == "text" and row[field] == null): return false
		elif not integer_value(row[field], contract.fields[field].bounds): return false
	return true

static func configured_path() -> String:
	var fallback=str(ProjectSettings.get_setting("application/resources/external_pack_path","res://local_resources/pack.json"))
	var path=PackStore.active_path(fallback)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--resource-pack="):path=arg.trim_prefix("--resource-pack=")
	return path

static func command_line_override() -> bool:
	return Array(OS.get_cmdline_user_args()).any(func(arg):return arg.begins_with("--resource-pack="))

static func inspect_pack(path: String) -> Dictionary:
	var previous=[cached_pack,pack_loaded,pack_directory,diagnostics]
	reset();_read_pack(path)
	var result={"ok":not cached_pack.is_empty() and diagnostics.is_empty(),"path":path,"data":cached_pack.duplicate(true),"diagnostics":diagnostics.duplicate()}
	cached_pack=previous[0];pack_loaded=previous[1];pack_directory=previous[2];diagnostics=previous[3]
	return result

static func load_pack() -> Dictionary:
	if pack_loaded:return cached_pack
	return _read_pack(configured_path())

static func _read_pack(path: String) -> Dictionary:
	pack_loaded=true
	if not FileAccess.file_exists(path): return cached_pack
	var parser = JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK or not parser.data is Dictionary:
		diagnostics.append("INVALID_RESOURCE_PACK"); return cached_pack
	var parsed: Dictionary = parser.data
	if not integer_value(parsed.get("schema_version", null), [1, 2]):
		diagnostics.append("UNSUPPORTED_RESOURCE_PACK"); return cached_pack
	var version = int(parsed.schema_version)
	var sections = ["definitions", "assets", "phrases", "templates", "ui", "terms"]
	for key in parsed:
		if key != "schema_version" and (key not in sections or (version == 1 and key not in ["definitions", "assets", "phrases"])):
			diagnostics.append("INVALID_SECTION:" + str(key)); return cached_pack
	for section in sections:
		if not parsed.get(section, {}) is Dictionary:
			diagnostics.append("INVALID_SECTION:" + section); return cached_pack
	pack_directory = path.get_base_dir()
	cached_pack = {"schema_version": version, "definitions": {}, "assets": {}, "phrases": {}, "templates": {}, "ui": {}, "terms": {}}
	for id in parsed.get("definitions", {}):
		var row = parsed.definitions[id]
		if validate_row(str(id), row, version): cached_pack.definitions[id] = row.duplicate(true)
		else: diagnostics.append("INVALID_DEFINITION:" + str(id))
	for key in parsed.get("assets", {}):
		if key not in schema().get("assets", []) or (not (version==2 and parsed.assets[key]==null) and asset_path(parsed.assets[key]).is_empty()):
			diagnostics.append("INVALID_ASSET:" + str(key))
		else: cached_pack.assets[key] = parsed.assets[key]
	for key in parsed.get("phrases", {}):
		var value = parsed.phrases[key]; var entry = schema().get("phrases", {}).get(key, {})
		if entry.is_empty() or not value is String or (value != "" and not formats_valid(value, entry.format_tokens)):
			diagnostics.append("INVALID_PHRASE:" + str(key))
		else: cached_pack.phrases[key] = value
	for key in parsed.get("templates", {}):
		var allowed = schema().get("templates", {}).get(key, null)
		if allowed is String: allowed = schema().get("parameter_sets", {}).get(allowed, null)
		if not allowed is Array or not template_valid(parsed.templates[key], allowed): diagnostics.append("INVALID_TEMPLATE:" + str(key))
		else: cached_pack.templates[key] = parsed.templates[key]
	for section in ["ui", "terms"]:
		for key in parsed.get(section, {}):
			var value = parsed[section][key]
			if key not in schema().get(section, {}) or not value is String or (value != "" and not formats_valid(value, schema()[section][key].format_tokens)):
				diagnostics.append("INVALID_" + section.to_upper() + ":" + str(key))
			else: cached_pack[section][key] = value
	return cached_pack

static func asset_path(value: Variant) -> String:
	if not value is String or value.is_empty(): return ""
	var relative: String = value.replace("\\", "/")
	if relative.is_absolute_path() or ":" in relative or ".." in relative.split("/"): return ""
	if relative.get_extension().to_lower() not in ["png", "jpg", "jpeg", "webp", "svg"]: return ""
	# Resolve symlinked files and each parent component before accepting a local image.
	var directory = pack_directory
	var components = relative.split("/", false)
	for index in components.size():
		var part = components[index]
		var access = DirAccess.open(directory)
		if access == null or access.is_link(part): return ""
		directory = directory.path_join(part)
	if not FileAccess.file_exists(directory): return ""
	return directory

static func apply(registry) -> void:
	var data = load_pack()
	for id in registry.definitions:
		var definition: Dictionary = registry.definitions[id]
		definition.name = str(id); definition.text = "说明待补充 · " + str(id)
		for field in schema().get("definitions", {}).get(id, {}).get("fields", {}):
			var field_contract = schema().definitions[id].fields[field]
			if field not in ["name", "text"]: definition[field] = int(field_contract.default)
		for field in data.get("definitions", {}).get(id, {}):
			var value = data.definitions[id][field]
			if field in ["name", "text"]:
				if field=="name" and value.strip_edges().is_empty():continue
				if field=="text" and data.get("schema_version",1)==1 and value.strip_edges().is_empty():continue
				definition[field] = "" if value == null else value
				if field == "text": definition["_external_text"] = true
			else: definition[field] = int(value)
	for key in data.get("assets", {}):
		var path = "" if data.assets[key]==null else asset_path(data.assets[key])
		if path.is_empty() and data.assets[key]!=null: continue
		if registry.assets.has(key): registry.assets[key].path = path
		if registry.ui_assets.has(key): registry.ui_assets[key].path = path

static func numeric_hash(definitions: Dictionary) -> String:
	var values: Array = []; var ids = schema().get("definitions", {}).keys(); ids.sort()
	for id in ids:
		var fields = schema().definitions[id].fields.keys(); fields.sort()
		for field in fields:
			if field not in ["name", "text"]: values.append([id, field, int(definitions[id][field])])
	return JSON.stringify(values).sha256_text()

static func phrase(key: String, fallback: String) -> String:
	var value = load_pack().get("phrases", {}).get(key, "")
	return value if value is String and not value.is_empty() and formats_valid(value, format_tokens(fallback)) else fallback

static func ui(key: String, fallback: String) -> String:
	var value = load_pack().get("ui", {}).get(key, "")
	return value if value is String and not value.is_empty() and formats_valid(value, format_tokens(fallback)) else fallback

static func term(key: String, fallback: String = "") -> String:
	var value = str(load_pack().get("terms", {}).get(key, ""))
	return (key if fallback.is_empty() else fallback) if value.is_empty() else value

static func terms_list(values: Array) -> Array:
	return values.map(func(value):return term(str(value)))

static func number(value: Variant) -> int:
	return int(value) if typeof(value) in [TYPE_INT, TYPE_FLOAT] else 0

static func named(key: String, parameters: Dictionary, fallback: String) -> String:
	var value = str(load_pack().get("templates", {}).get(key, ""))
	if value.is_empty(): return fallback
	# Substitution is single-pass: braces in imported names cannot become new parameters.
	var regex = RegEx.new(); regex.compile("\\{([A-Za-z_][A-Za-z0-9_.]*)\\}")
	var text = value.replace("{{", "\u0001").replace("}}", "\u0002"); var output = ""; var cursor = 0
	for found in regex.search_all(text):
		var token = found.get_string(1)
		if not parameters.has(token): return fallback
		output += text.substr(cursor, found.get_start() - cursor) + str(parameters[token]); cursor = found.get_end()
	return (output + text.substr(cursor)).replace("\u0001", "{").replace("\u0002", "}")

static func flatten(parameters: Dictionary, prefix: String, source: Dictionary) -> void:
	for key in source:
		var value = source[key]
		if typeof(value) in [TYPE_INT, TYPE_FLOAT, TYPE_BOOL, TYPE_STRING]: parameters[prefix + str(key)] = value

static func parameters(d: Dictionary, c: Dictionary = {}, p: Dictionary = {}, extra: Dictionary = {}) -> Dictionary:
	var result = {"content_id": d.get("id", ""), "name": d.get("name", ""), "base_attack": number(d.get("attack", 0)), "base_health": number(d.get("health", 0)), "base_cost": number(d.get("cost", d.get("power_cost", 0))), "attack": number(c.get("attack", d.get("attack", 0))), "health": number(c.get("health", d.get("health", 0))), "effective_cost": number(d.get("cost", d.get("power_cost", 0))), "tier": number(d.get("tier", 0)), "round": number(extra.get("round",p.get("presentation_round", p.get("round", 0)))), "remaining": 0, "progress": number(c.get("progress", 0)), "threshold": 0, "used": 0, "limit": 0, "player_coins": number(p.get("coins", 0)), "effect_values": "", "status": "", "generated": "", "detail": "", "bound_tribe": str(c.get("bound_tribe", ""))}
	flatten(result, "card.", c); flatten(result, "player.", p)
	var effects: Array = []
	for i in d.get("effects", []).size():
		var e: Dictionary = d.effects[i]; flatten(result, "effect." + str(i) + ".", e)
		var numbers: Array = []
		for key in e:
			if typeof(e[key]) in [TYPE_INT, TYPE_FLOAT]: numbers.append(str(key) + "=" + str(e[key]))
		if not numbers.is_empty(): effects.append("#" + str(i) + " " + ", ".join(numbers))
		var progress_keys = {"spend_wind":"spend_progress", "thunder":"thunder_progress", "fel":"fel_progress", "earring":"gem_progress", "ink":"avenge_round8", "heart":"death_progress", "progress":"progress", "spend_buff":"pirate_spent", "spend_box":"pirate_spent", "spend_bounty":"pirate_spent", "sand":"progress", "mortar":"progress", "rune":"progress", "wand":"progress", "spellbook":"progress", "beetle_ring":"avenge_round12", "duster":"duster_count", "cat":"cat_count", "waterwheel":"water_uses", "summon_shield":"combat_uses", "reborn_copy":"combat_uses", "avenge_spell":"avenge_avenge_spell"}
		var op = str(e.get("op", e.get("handler", "")))
		var limit = int(e.get("threshold", 7 if op in ["spend_wind", "cat"] else 3 if op == "thunder" else 6 if op == "duster" else 2 if op == "waterwheel" else 4 if op == "avenge_spell" else e.get("limit", 0)))
		if progress_keys.has(op):
			result.progress = int(c.get(progress_keys[op], 0)) if op != "waterwheel" or int(c.get("water_round",0)) == int(result.round) else 0; result.threshold = limit; result.remaining = maxi(0, limit - int(result.progress))
	result.effect_values = "; ".join(effects)
	for key in extra: result[key] = extra[key]
	var status: Array = []
	if int(result.threshold)>0: status.append(ui("status.progress", "进度 %d/%d · 剩余 %d") % [int(result.progress),int(result.threshold),int(result.remaining)])
	if d.get("kind", "") in ["spell", "hero_power", "trinket"]: status.append(ui("status.cost", "费用 %d") % int(result.effective_cost))
	if d.get("kind", "")=="minion": status.append(ui("status.stats", "属性 %d/%d") % [int(result.attack),int(result.health)])
	if int(result.used)>0: status.append(ui("status.used", "已用 %d 次") % int(result.used))
	if not str(result.bound_tribe).is_empty(): status.append(term(str(result.bound_tribe)))
	if not str(result.detail).is_empty(): status.append(str(result.detail))
	result.status = ui("status.values", "状态 · %s") % ", ".join(status)
	result.status = named("content." + str(d.get("id", "")) + ".status", result, result.status)
	return result

# Resource descriptions may use these legacy tribe tokens outside a template.
# Resolve only the instance binding, after generated/template text is composed.
static func bound_tribe_text(value: String, tribe: String) -> String:
	if tribe.is_empty(): return value
	var regex = RegEx.new(); regex.compile("(?<!\\{)\\{(种族|关联种族|bound_tribe)\\}(?!\\})")
	var matches = regex.search_all(value); matches.reverse()
	for found in matches:
		value = value.left(found.get_start()) + term(tribe) + value.substr(found.get_end())
	return value
static func describe(d: Dictionary, c: Dictionary, p: Dictionary, computed: String, channel: String = "body", extra: Dictionary = {}) -> String:
	var params = parameters(d, c, p, extra); params.generated = computed
	var key = "content." + str(d.get("id", "")) + "." + channel
	var value = named(key, params, "")
	if value.is_empty(): value = str(d.text) if d.get("_external_text", false) else computed
	if value.is_empty(): value = "说明待补充 · " + str(d.get("id", ""))
	# Keep computed dynamic data even with an imported static description.
	var template = str(load_pack().get("templates", {}).get(key, ""))
	if d.get("_external_text", false) and template.is_empty() and computed != str(d.text) and not computed.is_empty():
		# Existing calculation branches remain visible even for a static imported body.
		value = computed if computed.begins_with(str(d.text)) else value + "\n" + computed
	if "status" not in placeholders(template): value += "\n" + str(params.status)
	return bound_tribe_text(value, str(params.bound_tribe))
