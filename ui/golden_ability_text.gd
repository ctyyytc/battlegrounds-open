extends RefCounted
const ExternalText = preload("res://domain/resources/external_content.gd")
const Special=preload("res://domain/rules/special_rules.gd")
static func descriptions() -> Dictionary:
	return {
	"恶魔":ExternalText.phrase("golden_ability_text.206f925ff1a0", "说明待补充"),
	"元素":ExternalText.phrase("golden_ability_text.5471fb7bf51f", "说明待补充"),
	"龙":ExternalText.phrase("golden_ability_text.3972ea1fdb05", "说明待补充"),
	"亡灵":ExternalText.phrase("golden_ability_text.949895d3e679", "说明待补充"),
	"鱼人":ExternalText.phrase("ui_golden_ability_text.<module>.6096cdd96142", "说明待补充"),
	"野兽":ExternalText.phrase("golden_ability_text.845575856148", "说明待补充"),
	"野猪人":ExternalText.phrase("golden_ability_text.db1ff8d4a537", "说明待补充"),
	"海盗":ExternalText.phrase("golden_ability_text.019509a9a337", "说明待补充"),
	"纳迦":ExternalText.phrase("golden_ability_text.a77e3de0a836", "说明待补充")
}
static func describe(definition: Dictionary,card: Dictionary,enabled: Array,zone: String="") -> String:
	if card.has("type_override"):
		definition=definition.duplicate(true);definition.card_types=card.type_override
	var route=str(card.get("gold_route",""))
	if definition.get("base_id","")=="BG33_318" and route=="鱼人":return ExternalText.phrase("golden_ability_text.3114d517efa6", "说明待补充")
	if route!="": return ExternalText.phrase("golden_ability_text.c2b139bf0106", "说明待补充")+ExternalText.term(route)+"）\n"+descriptions().get(route,ExternalText.phrase("ui_golden_ability_text.describe.00478f051209", "说明待补充"))
	var routes=Special.eligible_routes(definition,enabled)
	if routes.is_empty(): return ""
	if not definition.get("implemented",false): return ExternalText.phrase("golden_ability_text.5c64f87e9afe", "说明待补充")
	if zone in ["board","combat"]: return ExternalText.phrase("golden_ability_text.6dd3f9371548", "说明待补充")
	var parts=[]
	for tribe in routes: parts.append(ExternalText.term(str(tribe))+"："+(ExternalText.phrase("golden_ability_text.cc4fb7585817", "说明待补充") if definition.get("base_id","")=="BG33_318" and tribe=="鱼人" else descriptions().get(tribe,ExternalText.phrase("ui_golden_ability_text.describe.00478f051209", "说明待补充"))))
	return ExternalText.phrase("golden_ability_text.93cc0f90eaa9", "说明待补充")+"\n".join(parts)+ExternalText.phrase("golden_ability_text.613b1d5fbef3", "说明待补充")
static func badge(definition: Dictionary,card: Dictionary,enabled: Array) -> String:
	if describe(definition,card,enabled)=="": return ""
	var route=str(card.get("gold_route",""))
	if route=="元素": return ExternalText.phrase("ui_golden_ability_text.badge.f61d4d996335", "说明待补充")
	return ExternalText.phrase("ui_golden_ability_text.badge.ff0e0e470257", "说明待补充")+(ExternalText.term(route) if route!="" else ExternalText.phrase("ui_golden_ability_text.badge.c6ec2c40dc18", "说明待补充"))
