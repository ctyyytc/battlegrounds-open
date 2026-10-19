extends RefCounted
const ExternalText = preload("res://domain/resources/external_content.gd")
static func summary(d: Dictionary,c: Dictionary,round_number: int) -> String:
	match d.id:
		"BG30_MagicItem_891":
			if c.get("voucher_open",false) or round_number>=int(c.get("acquired_round",c.get("next_round",round_number+2)-2))+2:return "待选择 · 点击兑换"
		"BG30_MagicItem_434":return ExternalText.phrase("ui_round13_presentation.summary.9af3cb4cfc7c", "说明待补充") if c.get("cathedral_ready",false) else ExternalText.phrase("ui_round13_presentation.summary.71e9ebae56b5", "说明待补充")
		"BG30_MagicItem_435":return ExternalText.phrase("ui_round13_presentation.summary.7bd736c78358", "说明待补充 · %d") % int(c.get("supply_remaining",3))
		"BG32_MagicItem_366":return ExternalText.phrase("ui_round13_presentation.summary.2e8a4f0f1def", "说明待补充 · %d") % int(c.get("candle_remaining",2))
		"BG35_MagicItem_930":return ExternalText.phrase("round13_presentation.b9c3c7aa9a96", "说明待补充") if c.get("whistle_ready",false) else ExternalText.phrase("ui_round13_presentation.summary.7bae3f54bc28", "说明待补充")
		"BG35_MagicItem_818":return ExternalText.phrase("round13_presentation.3ac94541ba74", "说明待补充") if c.get("orb_ready",false) else ExternalText.phrase("ui_round13_presentation.summary.e0f6e3dc9036", "说明待补充")
		"BG36_MagicItem_371":return ExternalText.phrase("ui_round13_presentation.summary.5f4525665971", "说明待补充 · %d / %d") % [1+int(c.get("honey_growth",0)),1+int(c.get("honey_growth",0))]
		"BG32_MagicItem_428":
			if c.get("map_done",false):return ExternalText.phrase("ui_round13_presentation.summary.80897fd1c8a4", "说明待补充")
		"BG35_MagicItem_814":return ExternalText.phrase("ui_round13_presentation.summary.be7a95c8bb97", "说明待补充") if c.get("wallet_done",false) else ExternalText.phrase("ui_round13_presentation.summary.d254a1530208", "说明待补充")
		"BG32_MagicItem_361","BG32_MagicItem_361t":return ExternalText.phrase("ui_round13_presentation.summary.c1e5fb0479c7", "说明待补充")+str(c.get("factory_id",ExternalText.phrase("ui_round13_presentation.summary.8c7f2dc9417c", "说明待补充")))
	if c.has("next_round"):return ExternalText.phrase("ui_round13_presentation.summary.7bd736c78358", "说明待补充 · %d") % maxi(0,int(c.next_round)-round_number)
	return ""
static func item(d: Dictionary,c: Dictionary,p: Dictionary,round_number: int) -> String:
	return str(d.text)+"\n"+summary(d,c,round_number)
static func minion(engine,d: Dictionary,c: Dictionary,p: Dictionary,rich: bool=false) -> String:
	match d.get("base_id",d.id):
		"BG34_320":
			var a=int(p.get("elemental_bonus_attack",0));var h=int(p.get("elemental_bonus_health",0))
			var text=preload("res://ui/spell_presentation.gd")
			return ExternalText.phrase("round13_presentation.13d192e0ddba", "说明待补充 · %s / %s / %s") % [text.number(15,a,rich),text.number(15,h,rich),ExternalText.phrase("ui_round13_presentation.minion.b080bfcb0d4e", "说明待补充") if d.golden else ""]
		"BG34_322":return ExternalText.phrase("round13_presentation.610ee3b1697d", "说明待补充 · %s / %d") % [ExternalText.phrase("ui_round13_presentation.minion.ae0e48c82139", "说明待补充") if d.golden else "",maxi(0,3-int(c.get("kodo_uses",0)))]
		"BG34_950":return str(d.text)+(ExternalText.phrase("ui_round13_presentation.minion.3ab6d1e7df40", "\n说明待补充") if engine!=null and int(c.get("stone_round",-1))==int(engine.state.round) else ExternalText.phrase("ui_round13_presentation.minion.35db9fd7b9e3", "\n说明待补充"))
	return str(d.text)
